#!/usr/bin/env bash
set -euo pipefail
# Request administrator privileges
if [ "$EUID" -ne 0 ]; then
  echo "Requesting administrator privileges. Please enter your password:"
  exec sudo "$0" "$@"
  exit
fi
# ===== Variables =====
PYTHON=python3
SCRIPT_NAME="DaVinci TTS"

UTILITY_DIR="/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility"

WHEEL_DIR="/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/HB/$SCRIPT_NAME/wheel"
TARGET_DIR="/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/HB/$SCRIPT_NAME/Lib"
PACKAGES=(
  "requests" 
  "azure-cognitiveservices-speech" 
  "edge-tts" 
  "pypinyin"
)

# Official and mirror PyPI indexes
PIP_OFFICIAL="https://pypi.org/simple"
PIP_MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple"

# ===== Region detection (prefer mirror in CN) =====
read_user_default() {
  local key="$1"
  local val=""
  if [[ -n "${SUDO_USER-}" ]]; then
    val=$(sudo -u "$SUDO_USER" defaults read -g "$key" 2>/dev/null || true)
  else
    val=$(defaults read -g "$key" 2>/dev/null || true)
  fi
  echo "$val"
}

is_china_region() {
  local locale langs tz country
  locale="$(read_user_default AppleLocale)"
  langs="$(read_user_default AppleLanguages)"
  if [[ "$locale" == *"zh_CN"* || "$locale" == *"Hans_CN"* ]]; then
    return 0
  fi
  if [[ "$langs" == *"zh-Hans"* || "$langs" == *"zh_CN"* ]]; then
    return 0
  fi
  if command -v systemsetup >/dev/null 2>&1; then
    tz="$(systemsetup -gettimezone 2>/dev/null | awk -F': ' '{print $2}')"
    if [[ "$tz" == "Asia/Shanghai" || "$tz" == "Asia/Urumqi" ]]; then
      return 0
    fi
  fi
  if command -v curl >/dev/null 2>&1; then
    country="$(
      curl -m 2 -s https://ipinfo.io/country 2>/dev/null || \
      curl -m 2 -s https://ifconfig.co/country-iso 2>/dev/null || true
    )"
    country="${country//[$'\r\n\t ']}"
    if [[ "$country" == "CN" ]]; then
      return 0
    fi
  fi
  return 1
}

# ===== Logging =====
# Usage: log LEVEL "message"
# LEVEL: INFO, WARN, ERROR, SUCCESS
log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$ts][$level] $msg"
}

log INFO "Starting offline download and installation of dependencies."

# Step 1: Copy local script folder into Resolve Utility
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/$SCRIPT_NAME"
log INFO "Ensuring Utility scripts directory: $UTILITY_DIR"
mkdir -p "$UTILITY_DIR"
if [ -d "$SOURCE_DIR" ]; then
  if [ -d "$UTILITY_DIR/$SCRIPT_NAME" ]; then
    log INFO "Target exists: $UTILITY_DIR/$SCRIPT_NAME. Overwriting..."
    rm -rf "$UTILITY_DIR/$SCRIPT_NAME"
  fi
  log INFO "Copying \"$SOURCE_DIR\" to \"$UTILITY_DIR/$SCRIPT_NAME\""
  if ditto "$SOURCE_DIR" "$UTILITY_DIR/$SCRIPT_NAME"; then
    log SUCCESS "Folder copied to Utility scripts."
  else
    log ERROR "Failed to copy folder. Please copy it manually."
  fi
else
  log WARN "Source folder not found next to this script: $SOURCE_DIR"
fi

# Step 2: Prepare wheel download directory
log INFO "Preparing wheel download directory: $WHEEL_DIR"
mkdir -p "$WHEEL_DIR"

# Step 3: Clear pip cache (optional)
log INFO "Clearing pip cache..."
$PYTHON -m pip cache purge >/dev/null 2>&1 || log WARN "pip cache purge failed or already empty."

# Step 4: Download packages and dependencies
PRIMARY_INDEX="$PIP_OFFICIAL"; SECONDARY_INDEX="$PIP_MIRROR"
if is_china_region; then
  PRIMARY_INDEX="$PIP_MIRROR"; SECONDARY_INDEX="$PIP_OFFICIAL"
  log INFO "Region CN detected. Using mirror first: $PRIMARY_INDEX"
else
  log INFO "Region not CN. Using official first: $PRIMARY_INDEX"
fi

if $PYTHON -m pip download "${PACKAGES[@]}" \
    --dest "$WHEEL_DIR" \
    --only-binary=:all: \
    --use-feature=fast-deps \
    --no-cache-dir \
    --progress-bar=on \
    -i "$PRIMARY_INDEX"; then
  log SUCCESS "Download succeeded using primary index."
else
  log WARN "Primary index failed. Trying secondary: $SECONDARY_INDEX ..."
  if $PYTHON -m pip download "${PACKAGES[@]}" \
      --dest "$WHEEL_DIR" \
      --only-binary=:all: \
      --use-feature=fast-deps \
      --no-cache-dir \
      --progress-bar=on \
      -i "$SECONDARY_INDEX"; then
    log SUCCESS "Download succeeded using secondary index."
  else
    log ERROR "Download failed from both indexes. Please check your network."
    exit 1
  fi
fi

# Step 5: Create target directory & fix ownership
log INFO "Preparing target installation directory: $TARGET_DIR"
sudo mkdir -p "$TARGET_DIR"
sudo chown -R "$(whoami)" "$TARGET_DIR"
log SUCCESS "Target directory ready and owned by $(whoami)."

# Step 6: Offline install specified packages and dependencies
log INFO "Installing specified packages offline..."
if $PYTHON -m pip install "${PACKAGES[@]}" \
     --no-index \
     --find-links "$WHEEL_DIR" \
     --target "$TARGET_DIR"; then
  log SUCCESS "Successfully installed specified packages and their dependencies."
else
  log ERROR "Offline installation of specified packages failed. Please check wheels and permissions."
  exit 1
fi

# Step 7: Summary
log INFO "Installation process completed. Please verify modules in $TARGET_DIR."
log SUCCESS "All done."
