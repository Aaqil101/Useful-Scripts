@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0download_youtube_videos.ps1" %*
set "code=%ERRORLEVEL%"
rem Keep the window open on failure, so a double-click run shows the error.
if not "%code%"=="0" pause
exit /b %code%
