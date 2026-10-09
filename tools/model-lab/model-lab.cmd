@echo off
rem model-lab - the front door on Windows. Uses the py launcher when it works, else python.
py -3 -c "import sys" >nul 2>&1
if %ERRORLEVEL%==0 (
  py -3 "%~dp0model_lab.py" %*
) else (
  python "%~dp0model_lab.py" %*
)
exit /b %ERRORLEVEL%
