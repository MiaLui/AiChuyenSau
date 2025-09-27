@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

:: ===== Config =====
set "REPO_URL=https://github.com/MiaLui/AiChuyenSau.git"
set "BRANCH=code"
set "DEST=%~1"
if not defined DEST set "DEST=AiChuyenSau"

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

:: ===== Clone only branch 'code' (quiet) =====
if exist "%DEST%\.git" (
  echo %[O]% Phát hiện thư mục "%DEST%".
) else if exist "%DEST%" (
  echo %[W]% Thư mục "%DEST%" tồn tại nhưng không phải repo git.
) else (
  echo %[I]% Tạo mới "%DEST%"...
  git clone --quiet --single-branch -b "%BRANCH%" "%REPO_URL%" "%DEST%" >nul 2>nul
  if errorlevel 1 (
    echo %[E]% Tạo mới thất bại.
    goto :EOF
  )
  echo %[O]% Hoàn tất.
)

:: ===== Ensure checked out to 'code' & sync (quiet) =====
if exist "%DEST%\.git" (
  pushd "%DEST%"
    git remote set-url origin "%REPO_URL%" >nul 2>nul
    git fetch --quiet origin "%BRANCH%" >nul 2>nul

    git rev-parse --verify "%BRANCH%" >nul 2>nul
    if errorlevel 1 (
      git checkout -q -b "%BRANCH%" "origin/%BRANCH%" >nul 2>nul || (
        echo %[E]% Không thể checkout nhánh "%BRANCH%".
        popd & goto :EOF
      )
    ) else (
      git checkout -q "%BRANCH%" >nul 2>nul || (
        echo %[E]% Không thể chuyển sang nhánh "%BRANCH%".
        popd & goto :EOF
      )
      git branch --set-upstream-to="origin/%BRANCH%" "%BRANCH%" >nul 2>nul
      git pull --quiet --ff-only >nul 2>nul
    )
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
