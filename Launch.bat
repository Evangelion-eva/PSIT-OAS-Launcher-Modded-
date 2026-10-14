@echo off
cd /d "%~dp0"

:: Launch overlay hidden (three dots)
start "" wscript.exe "%~dp0run_hidden.vbs"
