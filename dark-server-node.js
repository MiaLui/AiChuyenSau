/**
 * Node.js proxy server
 * - HTTP proxy on port 8889 (for Kingfall app)
 * - WebSocket server on port 9998 (for Studio/browser)
 *
 * Usage:
 *  npm install ws node-fetch
 *  node dark-server-node.js
 */

const http = require('http');
const { URLSearchParams } = require('url');
const WebSocket = require('ws');
// prefer global fetch (Node >=18); fallback to node-fetch if not present
const fetch = global.fetch || require('node-fetch');

const HTTP_PORT = 8889;
const WS_PORT = 9998;
const TARGET_DOMAIN = 'generativelanguage.googleapis.com'; // change if needed

// Simple logger
const Logger = {
  output(...msgs) {
    const t = new Date().toLocaleTimeString('zh-CN', { hour12: false });
    const ms = String(new Date().getMilliseconds()).padStart(3, '0');
    console.log(`[${t}.${ms}]`, ...msgs);
  }
};

// Keep track of connected WS clients
const wsClients = new Set();

/**
 * Broadcast JSON to all connected WS clients
 */
function broadcast(obj) {
  const s = JSON.stringify(obj);
  for (const ws of wsClients) {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(s);
    }
  }
}

/**
 * Stream a fetch Response both to HTTP response (res) and to WS client(s).
 * If 'targetWs' is provided, stream chunk messages only to that WS. Otherwise broadcast.
 */
async function streamResponseToHttpAndWs(response, res, operationId, targetWs = null) {
  // prepare header map
  const headerMap = {};
  response.headers && response.headers.forEach && response.headers.forEach((v, k) => {
    headerMap[k] = v;
  });

  // send response headers to HTTP client
  res.writeHead(response.status, headerMap);

  // send response_headers event to WS(s)
  const headerMessage = {
    request_id: operationId,
    event_type: 'response_headers',
    status: response.status,
    headers: headerMap
  };
  if (targetWs) {
    if (targetWs.readyState === WebSocket.OPEN) targetWs.send(JSON.stringify(headerMessage));
  } else {
    broadcast(headerMessage);
  }
  Logger.output('[StreamHandler] response headers sent');

  // If response has no body, end
  if (!response.body) {
    res.end();
    const endMsg = { request_id: operationId, event_type: 'stream_close' };
    targetWs ? targetWs.send(JSON.stringify(endMsg)) : broadcast(endMsg);
    return;
  }

  // Node.js Readable stream: attach data/end/error
  response.body.on('data', (chunk) => {
    try {
      // write chunk back to HTTP client
      res.write(chunk);
    } catch (e) {
      Logger.output('[StreamHandler] error writing to http client:', e.message);
    }

    // send chunk event to ws (stringify as text)
    const chunkMsg = {
      request_id: operationId,
      event_type: 'chunk',
      // assume text; if binary needed, use base64: chunk.toString('base64') and mark it
      data: chunk.toString()
    };

    try {
      if (targetWs) {
        if (targetWs.readyState === WebSocket.OPEN) targetWs.send(JSON.stringify(chunkMsg));
      } else {
        broadcast(chunkMsg);
      }
    } catch (e) {
      Logger.output('[StreamHandler] error sending chunk to ws:', e.message);
    }
  });

  response.body.on('end', () => {
    try { res.end(); } catch (e) {}
    const endMsg = { request_id: operationId, event_type: 'stream_close' };
    if (targetWs) {
      if (targetWs.readyState === WebSocket.OPEN) targetWs.send(JSON.stringify(endMsg));
    } else {
      broadcast(endMsg);
    }
    Logger.output('[StreamHandler] stream ended');
  });

  response.body.on('error', (err) => {
    Logger.output('[StreamHandler] stream error:', err.message);
    try { res.end(); } catch (e) {}
    const errMsg = { request_id: operationId, event_type: 'error', status: 500, message: err.message };
    if (targetWs && targetWs.readyState === WebSocket.OPEN) {
      targetWs.send(JSON.stringify(errMsg));
    } else {
      broadcast(errMsg);
    }
  });
}

/**
 * Forward an incoming HTTP request to the real API and stream results.
 * requestUrl will be the path+query from the incoming request (eg: /v1/...)
 */
async function handleHttpProxy(req, res) {
  try {
    const operationId = `${Date.now()}-${Math.floor(Math.random() * 10000)}`;
    Logger.output('[HTTP] incoming', req.method, req.url);

    // collect body if present
    const chunks = [];
    req.on('data', chunk => chunks.push(chunk));
    await new Promise((resolve) => req.on('end', resolve));
    const bodyBuffer = Buffer.concat(chunks);
    const bodyString = bodyBuffer.length ? bodyBuffer.toString() : undefined;

    // Build URL to real target
    const path = req.url || '/';
    const targetUrl = `https://${TARGET_DOMAIN}${path}`;

    // Build headers: copy from incoming but remove forbidden
    const incomingHeaders = { ...req.headers };
    const forbidden = ['host', 'connection', 'content-length', 'origin', 'referer'];
    forbidden.forEach(h => delete incomingHeaders[h]);

    const fetchOptions = {
      method: req.method,
      headers: incomingHeaders,
      body: ['GET', 'HEAD'].includes(req.method) ? undefined : bodyString
    };

    Logger.output('[HTTP] forward to', targetUrl);
    const response = await fetch(targetUrl, fetchOptions);

    await streamResponseToHttpAndWs(response, res, operationId, null /* broadcast to all ws */);
  } catch (err) {
    Logger.output('[HTTP] proxy error:', err.message);
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: err.message }));
  }
}

/**
 * Start HTTP proxy server
 */
function startHttpServer() {
  const server = http.createServer((req, res) => {
    // health check path shortcut
    if (req.url === '/__health') {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('ok');
      return;
    }
    handleHttpProxy(req, res);
  });

  server.listen(HTTP_PORT, '127.0.0.1', () => {
    Logger.output(`HTTP proxy running at http://127.0.0.1:${HTTP_PORT}`);
  });
}

/**
 * Start WebSocket server
 * - On message from a WS client: expect JSON requestSpec { method, path, headers, query_params, body, request_id }
 *   then proxy the request and stream response back to that WS only.
 */
function startWsServer() {
  const wss = new WebSocket.Server({ port: WS_PORT });
  wss.on('connection', (ws, req) => {
    wsClients.add(ws);
    Logger.output('WS client connected from', req.socket.remoteAddress);
    ws.send(JSON.stringify({ event: 'connected', msg: 'Welcome to proxy WS' }));

    ws.on('message', async (msg) => {
      let requestSpec;
      try {
        requestSpec = JSON.parse(msg.toString());
      } catch (_) {
        ws.send(JSON.stringify({ event: 'error', message: 'Invalid JSON' }));
        return;
      }

      // expected requestSpec shape: { method, path, headers, query_params, body, request_id }
      const opId = requestSpec.request_id || (`ws-${Date.now()}-${Math.floor(Math.random()*10000)}`);
      Logger.output('[WS] received requestSpec', requestSpec.method, requestSpec.path);

      try {
        // construct target URL
        const pathSegment = requestSpec.path.startsWith('/') ? requestSpec.path : `/${requestSpec.path || ''}`;
        const query = requestSpec.query_params ? ('?' + new URLSearchParams(requestSpec.query_params).toString()) : '';
        const url = `https://${TARGET_DOMAIN}${pathSegment}${query}`;

        // headers sanitize
        const headers = { ...(requestSpec.headers || {}) };
        ['host', 'connection', 'content-length', 'origin', 'referer'].forEach(h => delete headers[h]);

        const fetchOptions = {
          method: requestSpec.method || 'GET',
          headers,
          body: ['GET', 'HEAD'].includes(requestSpec.method) ? undefined : requestSpec.body
        };

        const response = await fetch(url, fetchOptions);
        // stream only to this ws
        await streamResponseToHttpAndWs(response, {
          writeHead: () => {}, // dummy: we don't have an HTTP response object for WS-initiated requests
          write: () => {},     // dummy
          end: () => {}        // dummy
        }, opId, ws);

      } catch (err) {
        Logger.output('[WS] request error:', err.message);
        ws.send(JSON.stringify({ request_id: opId, event_type: 'error', status: 500, message: err.message }));
      }
    });

    ws.on('close', () => {
      wsClients.delete(ws);
      Logger.output('WS client disconnected');
    });
  });

  wss.on('listening', () => {
    Logger.output(`WebSocket server running at ws://127.0.0.1:${WS_PORT}`);
  });
}

// Start both servers
startHttpServer();
startWsServer();
