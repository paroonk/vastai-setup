@echo off
setlocal
rem Uploads the private folders next to this script to a Vast.ai instance.
rem   upload-to-vast.bat PORT HOST      (from the instance's SSH button: ssh -p PORT root@HOST)

if "%~2"=="" (
  echo Usage: upload-to-vast.bat PORT HOST
  echo Example: upload-to-vast.bat 12345 ssh5.vast.ai
  exit /b 1
)
set "PORT=%~1"
set "HOST=%~2"
set "REMOTE=/workspace/vastai-setup-private"

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"

ssh -p %PORT% root@%HOST% "mkdir -p %REMOTE%"
if errorlevel 1 goto :failed

set "SENT=0"
for %%F in (comfyui-obvpm-pro-extensions refmods) do (
  if exist "%SRC%\%%F" (
    echo uploading %%F
    scp -P %PORT% -r "%SRC%\%%F" root@%HOST%:%REMOTE%/
    if errorlevel 1 goto :failed
    set "SENT=1"
  ) else (
    echo skipped: %%F is not next to this script
  )
)

echo.
echo Uploaded to %REMOTE%. On the instance run provisioning again, then: supervisorctl restart comfyui
exit /b 0

:failed
echo Upload failed.
exit /b 1
