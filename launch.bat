@echo off
echo ============================================================
echo  Odysseus Launcher
echo ============================================================
echo.
echo  On FIRST launch you will be asked to set your admin
echo  username and password (with a confirmation prompt).
echo.
echo  >> READ CAREFULLY BEFORE CONTINUING:
echo     - Choose a strong password you will remember.
echo     - You will be asked to TYPE it twice to confirm.
echo     - This account is required to log in to Odysseus.
echo     - Once set, it is saved in data\auth.json and the
echo       prompt will NOT appear again on future launches.
echo.
echo  Press ENTER to continue, or close this window (X) to cancel.
echo ============================================================
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch-windows.ps1" %*
pause
