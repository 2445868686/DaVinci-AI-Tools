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
rem Binary packages (have prebuilt wheels)
set "BINARY_PACKAGES=faster-whisper==1.1.1 requests regex"
rem Pure Python packages (no prebuilt wheel, need source install)
set "PURE_PYTHON_PACKAGES=jieba"
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
    rem If the target folder exists, remove contents except model folder
    if exist "%UTILITY_DIR%\%SCRIPT_NAME%" (
        echo [%DATE% %TIME%] Target folder exists, updating while preserving model folder...
        for /d %%d in ("%UTILITY_DIR%\%SCRIPT_NAME%\*") do if /I not "%%~nxd"=="model" rmdir /s /q "%%d" 2>nul
        for %%f in ("%UTILITY_DIR%\%SCRIPT_NAME%\*.*") do del /q "%%f" 2>nul
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
if not exist "%WHEEL_DIR%" (
    echo [%DATE% %TIME%] Creating wheel download directory: "%WHEEL_DIR%"
    mkdir "%WHEEL_DIR%"
) else (
    echo [%DATE% %TIME%] Wheel download directory already exists: "%WHEEL_DIR%"
)

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
echo [%DATE% %TIME%] Downloading binary packages from: !PRIMARY_INDEX!
python -m pip download %BINARY_PACKAGES% --dest "%WHEEL_DIR%" --only-binary=:all: ^
    --no-cache-dir -i "!PRIMARY_INDEX!" --retries 3 --timeout 30
if errorlevel 1 (
    echo [%DATE% %TIME%] WARNING: Primary index failed for binary packages. Trying secondary: !SECONDARY_INDEX!
    python -m pip download %BINARY_PACKAGES% --dest "%WHEEL_DIR%" --only-binary=:all: ^
        --no-cache-dir -i "!SECONDARY_INDEX!" --retries 3 --timeout 30
    if errorlevel 1 (
        echo [%DATE% %TIME%] ERROR: Failed to download binary packages from both indexes.
        pause & exit /b 1
    ) else (
        echo [%DATE% %TIME%] SUCCESS: Binary packages downloaded via secondary index.
    )
) else (
    echo [%DATE% %TIME%] SUCCESS: Binary packages downloaded via primary index.
)

rem Download pure Python packages (jieba) with --prefer-binary to avoid source builds
echo.
echo [%DATE% %TIME%] Downloading pure Python packages (jieba) from: !PRIMARY_INDEX!
python -m pip download %PURE_PYTHON_PACKAGES% --dest "%WHEEL_DIR%" --prefer-binary ^
    --no-cache-dir -i "!PRIMARY_INDEX!" --retries 3 --timeout 30
if errorlevel 1 (
    echo [%DATE% %TIME%] WARNING: Primary index failed for jieba. Trying secondary: !SECONDARY_INDEX!
    python -m pip download %PURE_PYTHON_PACKAGES% --dest "%WHEEL_DIR%" --prefer-binary ^
        --no-cache-dir -i "!SECONDARY_INDEX!" --retries 3 --timeout 30
    if errorlevel 1 (
        echo [%DATE% %TIME%] WARNING: jieba download failed. Will attempt online install later.
    ) else (
        echo [%DATE% %TIME%] SUCCESS: jieba downloaded via secondary index.
    )
) else (
    echo [%DATE% %TIME%] SUCCESS: jieba downloaded via primary index.
)

rem Download build dependencies (wheel, setuptools) for source packages that need them
echo.
echo [%DATE% %TIME%] Downloading build dependencies (wheel, setuptools)
python -m pip download wheel setuptools --dest "%WHEEL_DIR%" --prefer-binary ^
    --no-cache-dir -i "!PRIMARY_INDEX!" --retries 3 --timeout 30
if errorlevel 1 (
    python -m pip download wheel setuptools --dest "%WHEEL_DIR%" --prefer-binary ^
        --no-cache-dir -i "!SECONDARY_INDEX!" --retries 3 --timeout 30
)

rem 6. Create target installation directory if it does not exist
if not exist "%TARGET_DIR%" (
    echo [%DATE% %TIME%] Creating target installation directory: "%TARGET_DIR%"
    mkdir "%TARGET_DIR%"
) else (
    echo [%DATE% %TIME%] Target installation directory already exists: "%TARGET_DIR%"
)

rem 7. Perform offline installation of all packages
echo.
echo [%DATE% %TIME%] Installing packages offline into: "%TARGET_DIR%"
python -m pip install %BINARY_PACKAGES% %PURE_PYTHON_PACKAGES% --no-index --find-links "%WHEEL_DIR%" ^
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
