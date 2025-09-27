@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

:: ===== Config =====
set "REPO_URL=https://github.com/MiaLui/AiChuyenSau.git"
set "BRANCH=%~1"
set "DEST=%~2"

:: ===== Log helpers =====
set "[I]=[INFO]"
set "[O]=[ OK ]"
set "[W]=[WARN]"
set "[E]=[ERR ]"

:: ===== Open webpage every run =====
start "" "https://ai.studio/apps/drive/1-eIAQJpWJrzTZvuDDigJoQ4H5sUbDDC_"
echo %[I]% Đã mở trang Web

:: ===== Ensure Git =====
where git >nul 2>nul
if errorlevel 1 (
  echo %[I]% Git chưa có. Đang thử cài qua winget...
  where winget >nul 2>nul
  if errorlevel 1 (
    echo %[E]% Không có git và cũng không có winget. Vui lòng cài Git for Windows rồi chạy lại:
    echo       https://git-scm.com/download/win
    goto :EOF
  )
  winget install --id Git.Git -e --source winget -h --accept-package-agreements --accept-source-agreements
  if errorlevel 1 (
    echo %[E]% Cài Git bằng winget thất bại. Hãy cài thủ công rồi chạy lại.
    goto :EOF
  )
  set "PATH=%ProgramFiles%\Git\cmd;%ProgramFiles(x86)%\Git\cmd;%PATH%"
)
where git >nul 2>nul || (echo %[E]% Không tìm thấy git. Dừng.& goto :EOF)
for /f "usebackq tokens=* delims=" %%G in (`git --version`) do set "GIT_VER=%%G"
echo %[O]% Đã có %GIT_VER%

:: ===== Decide DEST =====
if not defined DEST set "DEST=AiChuyenSau"

:: ===== Clone if needed (skip if exists) =====
if exist "%DEST%\.git" (
  echo %[O]% Phát hiện repo trong "%DEST%".
) else if exist "%DEST%" (
  echo %[W]% Thư mục "%DEST%" tồn tại nhưng không phải repo git.
) else (
  echo %[I]% Clone %REPO_URL%  ->  "%DEST%"
  if defined BRANCH (
    git clone --recursive -b "%BRANCH%" "%REPO_URL%" "%DEST%" || (echo %[E]% Tạo mới thất bại.& goto :EOF)
  ) else (
    git clone --recursive "%REPO_URL%" "%DEST%" || (echo %[E]% Tạo mới thất bại.& goto :EOF)
  )
  echo %[O]% Hoàn tất.
)

:: ===== Optional: checkout & pull if BRANCH specified =====
if defined BRANCH if exist "%DEST%\.git" (
  echo %[I]% Đồng bộ "%BRANCH%"...
  pushd "%DEST%"
    git fetch --all --quiet
    git rev-parse --verify "%BRANCH%" >nul 2>nul
    if errorlevel 1 (
      git checkout -b "%BRANCH%" "origin/%BRANCH%" || git checkout "%BRANCH%"
    ) else (
      git checkout "%BRANCH%" >nul 2>nul
    )
    git pull --ff-only
  popd
)

:: ===== Run ai.bat only =====
pushd "%DEST%"
if not exist "ai.bat" (
  echo %[E]% Không tìm thấy "ai.bat" trong:
  cd
  dir /b
  popd
  exit /b 1
)

echo %[I]% Chạy ai.bat ...
call "ai.bat"
set "ERRLVL=%ERRORLEVEL%"
popd
exit /b %ERRLVL%
