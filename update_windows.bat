@echo off
setlocal
title Update Odysseus Docker Deployment

pushd "%~dp0" >nul

echo =========================================
echo Updating Odysseus Docker deployment
echo =========================================
echo.

where git >nul 2>nul
if errorlevel 1 (
  echo [!] Git was not found on PATH.
  rem Try common Git for Windows install locations and add to PATH for this session
  if exist "%ProgramFiles%\Git\cmd\git.exe" (
    set "GIT_DIR=%ProgramFiles%\Git\cmd"
    set "PATH=%GIT_DIR%;%PATH%"
  ) else if exist "%ProgramFiles(x86)%\Git\cmd\git.exe" (
    set "GIT_DIR=%ProgramFiles(x86)%\Git\cmd"
    set "PATH=%GIT_DIR%;%PATH%"
  ) else if exist "%LocalAppData%\Programs\Git\cmd\git.exe" (
    set "GIT_DIR=%LocalAppData%\Programs\Git\cmd"
    set "PATH=%GIT_DIR%;%PATH%"
  ) else (
    echo     Install Git for Windows, then run this script again.
    goto :fail
  )
  rem Re-check for git after probing common locations
  where git >nul 2>nul
  if errorlevel 1 (
    echo [!] Still could not find Git after probing common locations.
    echo     Install Git for Windows or add it to PATH, then run this script again.
    goto :fail
  )
)

where docker >nul 2>nul
if errorlevel 1 (
  echo [!] Docker was not found on PATH.
  echo     Start Docker Desktop, then run this script again.
  goto :fail
)

docker compose version >nul 2>nul
if errorlevel 1 (
  echo [!] Docker Compose is not available.
  echo     Update Docker Desktop, then run this script again.
  goto :fail
)

echo [+] Pulling latest code...
git pull --ff-only
if errorlevel 1 goto :fail

echo.
echo [+] Rebuilding and restarting containers...
docker compose up -d --build
if errorlevel 1 goto :fail

echo.
echo [+] Removing dangling Docker images...
docker image prune -f
if errorlevel 1 goto :fail

echo.
echo =========================================
echo Update completed successfully.
echo =========================================
goto :done

:fail
echo.
echo Update failed. Check the message above and try again.

:done
popd >nul
pause
