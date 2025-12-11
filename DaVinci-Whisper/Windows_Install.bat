@echo off
chcp 65001 >nul

:: 1. Check for Administrator privileges, and if not present, try to restart with elevation.
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo.
    echo [INFO] Requesting Administrator privileges, please click "Yes" in the UAC prompt...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

setlocal enabledelayedExpansion

rem ======== Variables (modify as needed) ========
set "PYTHON=python"
set "SCRIPT_NAME=DaVinci Whisper"
set "UTILITY_DIR=C:\ProgramData\Blackmagic Design\DaVinci Resolve\Fusion\Scripts\Utility"
set "WHEEL_DIR=C:\ProgramData\Blackmagic Design\DaVinci Resolve\Fusion\HB\%SCRIPT_NAME%\wheel"
set "TARGET_DIR=C:\ProgramData\Blackmagic Design\DaVinci Resolve\Fusion\HB\%SCRIPT_NAME%\Lib"
rem All required packages
set "PACKAGES=faster-whisper==1.1.1 requests regex"
rem Official and mirror indexes
set "PIP_OFFICIAL=https://pypi.org/simple"
set "PIP_MIRROR=https://pypi.tuna.tsinghua.edu.cn/simple"
rem =============================================

echo.
echo [%DATE% %TIME%] Starting download and offline installation of dependencies
echo ------------------------------------------------------------

rem 2. Move local "%SCRIPT_NAME%" folder to Resolve Utility scripts directory
set "SOURCE_DIR=%~dp0%SCRIPT_NAME%"
if not exist "%UTILITY_DIR%" (
    echo [%DATE% %TIME%] Creating Utility scripts directory: "%UTILITY_DIR%"
    mkdir "%UTILITY_DIR%"
) else (
    echo [%DATE% %TIME%] Utility scripts directory already exists: "%UTILITY_DIR%"
)

if exist "%SOURCE_DIR%" (
    rem If the target folder exists, delete it first to ensure a clean copy (overwrite).
    if exist "%UTILITY_DIR%\%SCRIPT_NAME%" (
        echo [%DATE% %TIME%] Target folder exists, removing old version: "%UTILITY_DIR%\%SCRIPT_NAME%"
        rmdir /s /q "%UTILITY_DIR%\%SCRIPT_NAME%"
    )
    
    echo [%DATE% %TIME%] Copying "%SOURCE_DIR%" to "%UTILITY_DIR%\%SCRIPT_NAME%"
    xcopy "%SOURCE_DIR%" "%UTILITY_DIR%\%SCRIPT_NAME%\" /E /I /Y >nul
    if errorlevel 1 (
        echo [%DATE% %TIME%] ERROR: Failed to copy folder. Please try copying it manually.
    ) else (
        echo [%DATE% %TIME%] SUCCESS: Folder copied to Utility scripts.
    )
) else (
    echo [%DATE% %TIME%] WARNING: Source folder not found next to this script: "%SOURCE_DIR%"
)

rem 3. Create wheel directory if it does not exist
if exist "%WHEEL_DIR%" (
    echo [%DATE% %TIME%] Wheel download directory exists, cleaning: "%WHEEL_DIR%"
    rmdir /s /q "%WHEEL_DIR%"
)
echo [%DATE% %TIME%] Creating wheel download directory: "%WHEEL_DIR%"
mkdir "%WHEEL_DIR%"

rem 4. Clear pip cache to avoid potential corruption
echo [%DATE% %TIME%] Clearing pip cache
python -m pip cache purge --disable-pip-version-check

rem 5. Region detection (timezone). Use mirror first if China Standard Time
set "PRIMARY_INDEX=%PIP_OFFICIAL%"
set "SECONDARY_INDEX=%PIP_MIRROR%"
for /f "delims=" %%A in ('2^>nul tzutil /g') do set "TZ_NAME=%%A"
if /I "!TZ_NAME!"=="China Standard Time" (
    set "PRIMARY_INDEX=%PIP_MIRROR%"
    set "SECONDARY_INDEX=%PIP_OFFICIAL%"
    echo [%DATE% %TIME%] Region CN detected by timezone. Using mirror first: !PRIMARY_INDEX!
) else (
    echo [%DATE% %TIME%] Region not CN by timezone. Using official first: !PRIMARY_INDEX!
)

echo.
echo [%DATE% %TIME%] Attempting to download from: !PRIMARY_INDEX!
python -m pip download %PACKAGES% --dest "%WHEEL_DIR%" --only-binary=:all: ^
    --no-cache-dir -i "!PRIMARY_INDEX!" --retries 3 --timeout 30
if errorlevel 1 (
    echo [%DATE% %TIME%] WARNING: Primary index failed. Trying secondary: !SECONDARY_INDEX!
    python -m pip download %PACKAGES% --dest "%WHEEL_DIR%" --only-binary=:all: ^
        --no-cache-dir -i "!SECONDARY_INDEX!" --retries 3 --timeout 30
    if errorlevel 1 (
        echo [%DATE% %TIME%] ERROR: Failed to download packages from both indexes. Check your network or package names.
        pause & exit /b 1
    ) else (
        echo [%DATE% %TIME%] SUCCESS: Packages downloaded via secondary index to "%WHEEL_DIR%"
    )
) else (
    echo [%DATE% %TIME%] SUCCESS: Packages downloaded via primary index to "%WHEEL_DIR%"
)

rem 6. Create target installation directory if it does not exist
if exist "%TARGET_DIR%" (
    echo [%DATE% %TIME%] Target installation directory exists, cleaning: "%TARGET_DIR%"
    rmdir /s /q "%TARGET_DIR%"
)
echo [%DATE% %TIME%] Creating target installation directory: "%TARGET_DIR%"
mkdir "%TARGET_DIR%"

rem 7. Perform offline installation of all packages
echo.
echo [%DATE% %TIME%] Installing packages offline into: "%TARGET_DIR%"
python -m pip install %PACKAGES% --no-index --find-links "%WHEEL_DIR%" ^
    --target "%TARGET_DIR%" --upgrade --disable-pip-version-check
if errorlevel 1 (
    echo [%DATE% %TIME%] ERROR: Offline installation failed. Please review the errors above.
    pause & exit /b 1
)

rem 8. Set folder permissions for user access (NEWLY ADDED SECTION)
echo.
echo [%DATE% %TIME%] Setting permissions to allow standard user access...

echo [%DATE% %TIME%] Applying permissions to library directory: "%TARGET_DIR%"
icacls "%TARGET_DIR%" /inheritance:e /grant Users:(RX) /grant "Authenticated Users":(M) /T /C >nul
if errorlevel 1 (
    echo [%DATE% %TIME%] WARNING: Failed to set all permissions on "%TARGET_DIR%".
) else (
    echo [%DATE% %TIME%] SUCCESS: Permissions set on library directory.
)

echo [%DATE% %TIME%] Applying permissions to script directory: "%UTILITY_DIR%\%SCRIPT_NAME%"
icacls "%UTILITY_DIR%\%SCRIPT_NAME%" /inheritance:e /grant Users:(RX) /grant "Authenticated Users":(M) /T /C >nul
if errorlevel 1 (
    echo [%DATE% %TIME%] WARNING: Failed to set all permissions on "%UTILITY_DIR%\%SCRIPT_NAME%".
) else (
    echo [%DATE% %TIME%] SUCCESS: Permissions set on script directory.
)

echo.
echo [%DATE% %TIME%] SUCCESS: All packages have been installed and configured successfully!
echo ------------------------------------------------------------
pause
endlocal
