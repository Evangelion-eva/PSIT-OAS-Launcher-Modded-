@echo off
cd /d "%~dp0"

:: Launch OAS
start "" "PSITOAS.exe"

:: Small delay then launch the screenshot overlay (truly hidden - no window flash)
timeout /t 1 /noredraw >nul
start "" /b wscript.exe "%~dp0run_hidden.vbs"
