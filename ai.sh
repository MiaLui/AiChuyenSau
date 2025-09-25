#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

JS_FILE="${1:-dark-server-node.js}"

info()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m[ OK ]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()   { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }
qrun() {
  local desc="$1"; shift; [ "${1:-}" = "--" ] && shift || true
  info "$desc"
  if "$@" >/dev/null 2>&1; then
    ok "$desc hoàn tất."
  else
    warn "$desc gặp lỗi, thử lại để xem log chi tiết:"
    "$@"
  fi
}

install_node() {
  info "Node.js chưa có. Đang cài đặt…"

  # Termux (Android)
  if [ -n "${PREFIX-}" ] && [ -d "${PREFIX}/bin" ] && uname -a | grep -qi termux; then
    qrun "Cập nhật Termux pkg" -- pkg update -y
    qrun "Cài Node.js (Termux)" -- pkg install -y nodejs
    return
  fi

  # Debian/Ubuntu
  if have apt-get; then
    qrun "apt-get update" -- sudo apt-get update -y -qq
    qrun "Cài Node.js + npm (apt)" -- sudo apt-get install -y -qq nodejs npm
    return
  fi
  # Fedora
  if have dnf; then
    qrun "Cài Node.js (dnf)" -- sudo dnf -y -q install nodejs npm
    return
  fi
  # RHEL/CentOS
  if have yum; then
    qrun "Cài Node.js (yum)" -- sudo yum -y -q install nodejs npm
    return
  fi
  # Arch/Manjaro
  if have pacman; then
    qrun "Cài Node.js + npm (pacman)" -- sudo pacman -Sy --noconfirm nodejs npm
    return
  fi
  # openSUSE
  if have zypper; then
    qrun "zypper refresh" -- sudo zypper -q refresh
    qrun "Cài Node.js + npm (zypper)" -- sudo zypper -y -q install nodejs npm
    return
  fi

  # macOS
  if [ "$(uname -s)" = "Darwin" ]; then
    if have brew; then
      qrun "Homebrew update" -- brew update
      qrun "Cài Node (brew)" -- brew install node
      return
    elif have port; then
      qrun "MacPorts selfupdate" -- sudo port -q selfupdate
      qrun "Cài Node (MacPorts)" -- sudo port -q install nodejs
      return
    fi
  fi

  # Windows via Git-Bash/MSYS
  if have powershell.exe; then
    if have winget; then
      qrun "Cài Node LTS (winget)" -- winget install -e --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
      return
    fi
    if have choco; then
      qrun "Cài Node LTS (Chocolatey)" -- choco install nodejs-lts -y
      return
    fi
  fi

  if have nvm; then
    qrun "Cài Node LTS (nvm)" -- bash -lc 'nvm install --lts && nvm use --lts'
    return
  fi

  err "Không tìm được cách cài Node.js tự động. Hãy cài thủ công rồi chạy lại."
  exit 1
}

ensure_npm_and_deps() {
  if ! have npm; then
    warn "npm không có trong PATH → cài kèm theo Node (nếu cần)…"
    install_node
    if ! have npm; then
      err "Không tìm thấy npm sau khi cài."
      exit 1
    fi
  fi

  if [ ! -f package.json ]; then
    info "Không thấy package.json → tạo mới"
    if ! npm init -y >/dev/null 2>&1; then
      warn "npm init -y gặp lỗi, thử lại để xem log:"
      npm init -y
    else
      ok "Đã tạo package.json"
    fi
  fi

  missing=()
  npm ls ws --depth=0 >/dev/null 2>&1 || missing+=("ws")
  npm ls node-fetch --depth=0 >/dev/null 2>&1 || missing+=("node-fetch")

  if [ "${#missing[@]}" -gt 0 ]; then
    qrun "Cài dependencies: ${missing[*]}" -- npm install --silent "${missing[@]}"
  else
    ok "Dependencies (ws, node-fetch) đã có."
  fi
}

if [ ! -f "$JS_FILE" ]; then
  err "Không tìm thấy file: $JS_FILE"
  err "Dùng: $0 [path/to/your-file.js]"
  exit 2
fi

if ! have node; then
  install_node
fi

if ! have node; then
  err "Cài đặt Node.js thất bại (node không có trong PATH)."
  exit 3
fi
ok "Node.js $(node -v) sẵn sàng."

ensure_npm_and_deps

info "Chạy: node \"$JS_FILE\""
exec node "$JS_FILE"
