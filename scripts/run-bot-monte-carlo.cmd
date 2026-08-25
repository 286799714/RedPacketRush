@echo off
setlocal
title Red Packet Rush - Bot Monte Carlo

set "RESULT=1"
set "SERVER_DIR=%~dp0..\server"

if not exist "%SERVER_DIR%\package.json" (
    echo ERROR: The server directory could not be found.
    goto :finish
)

where npm >nul 2>&1
if errorlevel 1 (
    echo ERROR: npm was not found. Install Node.js 22 or newer first.
    goto :finish
)

pushd "%SERVER_DIR%"
if errorlevel 1 (
    echo ERROR: The server directory could not be opened.
    goto :finish
)
set "PUSHED_SERVER=1"

if not exist "node_modules\.bin\mocha.cmd" (
    echo Server dependencies are missing. Running npm ci...
    call npm ci
    if errorlevel 1 (
        echo.
        echo ERROR: Dependency installation failed.
        goto :finish
    )
)

echo.
echo Running 1,000 seeded Matches with two Bots of each strategy...
echo.
call npm test -- --grep "Bot strategy Monte Carlo"
set "RESULT=%ERRORLEVEL%"

echo.
if "%RESULT%"=="0" (
    echo PASS: The Monte Carlo results are shown above.
) else (
    echo FAIL: The Monte Carlo test exited with code %RESULT%.
)

:finish
if defined PUSHED_SERVER popd
echo.
echo Press any key to close this window.
pause >nul
endlocal & exit /b %RESULT%
