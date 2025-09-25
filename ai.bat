@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

rem =========================
rem Random bright console color (bg=0)
rem =========================
set "colors=2 3 6 7 B E"
set "i=0"
for %%c in (%colors%) do (
  set /a i+=1
  set "color[!i!]=%%c"
)
set "max=!i!"
set /a pick=(%random% %% max) + 1
set "PICKCOLOR=!color[%pick%]!"
if defined PICKCOLOR color 0!PICKCOLOR!

cd /d "%~dp0"

set "ESC="
for /F "delims=" %%a in ('echo prompt $E^| cmd') do set "ESC=%%a"
if not defined ESC set "ESC="

set "B=%ESC%[1m"
set "N=%ESC%[0m"
set "C_INFO=%ESC%[1;34m"
set "C_OK=%ESC%[1;32m"
set "C_WARN=%ESC%[1;33m"
set "C_ERR=%ESC%[1;31m"

set "JS_FILE=%~1"
if not defined JS_FILE set "JS_FILE=dark-server-node.js"

call :info Kiểm tra File: "%JS_FILE%"
if not exist "%JS_FILE%" (
  call :err Không tìm thấy File: "%JS_FILE%"
  echo Hãy dùng: %~nx0 [path\to\your-file.js]
  goto :end_pause
)

call :info Kiểm tra: Node.js
call :resolve_node
if errorlevel 1 (
  call :warn Node.js chưa có. Bắt đầu cài đặt...
  call :install_node_windows
  if errorlevel 1 (
    call :err Cài đặt Node.js thất bại - không thể tiếp tục.
    goto :end_pause
  )
  call :resolve_node
  if errorlevel 1 (
    call :err Không tìm thấy node.exe sau khi cài đặt.
    goto :end_pause
  )
)

for /f "delims=" %%v in ('"%NODE_EXE%" -v 2^>nul') do set "NODE_VER=%%v"
if defined NODE_VER ( call :ok Đã có Node.js !NODE_VER! ) else ( call :ok Đã có Node.js )

call :have npm
if errorlevel 1 (
  set "PATH=%~dp0;%PATH%"
  for %%D in ("%ProgramFiles%\nodejs" "%ProgramFiles(x86)%\nodejs") do (
    if exist "%%~fD\npm.cmd" set "PATH=%%~fD;%PATH%"
  )
  call :have npm
  if errorlevel 1 (
    call :err Không tìm thấy npm.
    goto :end_pause
  )
)

if not exist "package.json" (
  call :info Không tìm thấy package.json → tạo mới
  call npm init -y 1>nul 2>nul
  if errorlevel 1 (
    call :warn npm init -y gặp lỗi, thử lại để xem log:
    call npm init -y
    if errorlevel 1 (
      call :err Tạo package.json thất bại.
      goto :end_pause
    )
  ) else (
    call :ok Đã tạo package.json
  )
)

set "MISSING="
call npm ls ws --depth=0 1>nul 2>nul
if errorlevel 1 set "MISSING=ws"

call npm ls node-fetch --depth=0 1>nul 2>nul
if errorlevel 1 (
  if defined MISSING (set "MISSING=%MISSING% node-fetch") else set "MISSING=node-fetch"
)

if defined MISSING (
  call :info Cài dependencies: %MISSING%
  call npm install %MISSING% --silent 1>nul 2>nul
  if errorlevel 1 (
    call :warn Cài dependencies gặp lỗi, thử lại để xem log:
    call npm install %MISSING%
    if errorlevel 1 (
      call :err Cài dependencies thất bại.
      goto :end_pause
    )
  ) else (
    call :ok Cài dependencies hoàn tất.
  )
) else (
  call :ok Dependencies: ws, node-fetch đã có.
)

echo.
call :info Chạy: "%JS_FILE%"
echo.

set "RC=0"
"%NODE_EXE%" "%JS_FILE%"
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" (
  call :ok Tiến trình Node đã kết thúc
) else (
  call :err Node kết thúc với mã lỗi %RC%.
)

goto :end_pause

:have
where %~1 >nul 2>nul
exit /b %ERRORLEVEL%

:resolve_node
set "NODE_EXE="
for /f "delims=" %%p in ('where node 2^>nul') do (
  if exist "%%~fp" (
    set "NODE_EXE=%%~fp"
    goto :res_ok
  )
)
if exist "%ProgramFiles%\nodejs\node.exe" set "NODE_EXE=%ProgramFiles%\nodejs\node.exe"
if not defined NODE_EXE if exist "%ProgramFiles(x86)%\nodejs\node.exe" set "NODE_EXE=%ProgramFiles(x86)%\nodejs\node.exe"
if defined NODE_EXE goto :res_ok

set "PATH=%ProgramFiles%\nodejs;%ProgramFiles(x86)%\nodejs;%PATH%"
for /f "delims=" %%p in ('where node 2^>nul') do (
  if exist "%%~fp" (
    set "NODE_EXE=%%~fp"
    goto :res_ok
  )
)

exit /b 1
:res_ok
exit /b 0

:install_node_windows
set "GOTNODE=0"

call :have winget
if not errorlevel 1 (
  call :info Đang cài Node.js - winget
  winget install -e --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements 1>nul 2>nul
)

call :resolve_node
if not errorlevel 1 (
  set "GOTNODE=1"
  call :ok Cài đặt Node.js hoàn tất - winget
  goto :inst_done
)

call :have choco
if not errorlevel 1 (
  call :info Đang cài Node.js - Chocolatey
  choco install nodejs-lts -y 1>nul 2>nul
)

call :resolve_node
if not errorlevel 1 (
  set "GOTNODE=1"
  call :ok Cài đặt Node.js hoàn tất - choco
  goto :inst_done
)

call :info Đang cài Node.js - MSI
set "NODE_MSI_URL=https://nodejs.org/dist/v22.11.0/node-v22.11.0-x64.msi"
set "NODE_MSI=%TEMP%\node_setup.msi"

powershell -NoProfile -ExecutionPolicy Bypass ^
  "try { Invoke-WebRequest -Uri '%NODE_MSI_URL%' -OutFile '%NODE_MSI%' -UseBasicParsing } catch { exit 2 }"
if errorlevel 2 (
  call :err Tải bộ cài Node.js MSI thất bại.
  exit /b 1
)

start /wait "" msiexec /i "%NODE_MSI%" /qn /norestart
del /q "%NODE_MSI%" 2>nul

call :resolve_node
if not errorlevel 1 (
  set "GOTNODE=1"
  call :ok Cài đặt Node.js hoàn tất - MSI
)

:inst_done
if "%GOTNODE%"=="1" (
  for %%D in ("%ProgramFiles%\nodejs" "%ProgramFiles(x86)%\nodejs") do (
    if exist "%%~fD\node.exe" set "PATH=%%~fD;%PATH%"
  )
  exit /b 0
)

call :err Không thể cài Node.js tự động. Hãy cài thủ công rồi chạy lại.
exit /b 1

:info
echo %C_INFO%[INFO]%N% %*
exit /b 0

:ok
echo %C_OK%[ OK ]%N% %*
exit /b 0

:warn
echo %C_WARN%[WARN]%N% %*
exit /b 0

:err
echo %C_ERR%[ERR ]%N% %*
exit /b 0

:end_pause
echo.
if not defined NO_PAUSE pause
exit /b %RC%
