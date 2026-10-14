@echo off
setlocal
rem Copies the private folders next to this script into a local ComfyUI.
rem   copy-to-comfyui.bat [path to the ComfyUI folder that holds custom_nodes and models]

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"

set "COMFY=%~1"
if not defined COMFY if exist "%SRC%\..\ComfyUI\custom_nodes" set "COMFY=%SRC%\..\ComfyUI"
if not defined COMFY if exist "F:\ComfyUI\ComfyUI\custom_nodes" set "COMFY=F:\ComfyUI\ComfyUI"
if not defined COMFY (
  echo ComfyUI folder not found. Run: copy-to-comfyui.bat "D:\path\to\ComfyUI"
  exit /b 1
)
if not exist "%COMFY%\custom_nodes" (
  echo "%COMFY%" has no custom_nodes folder.
  exit /b 1
)
echo ComfyUI: %COMFY%

rem node: replace the old copy (mirror)
call :copy_dir "comfyui-obvpm-pro-extensions" "%COMFY%\custom_nodes\comfyui-obvpm-pro-extensions" /MIR /XD __pycache__
if errorlevel 1 goto :failed

rem refmods: merge, so your other mods in models\refmods are kept
call :copy_dir "refmods" "%COMFY%\models\refmods" /E
if errorlevel 1 goto :failed

echo.
echo Done. Restart ComfyUI.
exit /b 0

:copy_dir
if not exist "%SRC%\%~1" (
  echo skipped: %~1 is not next to this script
  exit /b 0
)
echo %~1 -^> %~2
robocopy "%SRC%\%~1" "%~2" %3 %4 %5 /NFL /NDL /NJH /NJS /NP >nul
if %ERRORLEVEL% GEQ 8 exit /b 1
exit /b 0

:failed
echo Copy failed.
exit /b 1
