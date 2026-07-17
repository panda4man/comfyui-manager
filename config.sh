#!/usr/bin/env bash
# Common configuration loader for all scripts
# Source this file at the start of any script: source "$(dirname "$0")/config.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env if it exists, otherwise use defaults
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  set -a
  source "$SCRIPT_DIR/.env"
  set +a
fi

# Set defaults if not already defined
: "${COMFY_DIR:=$HOME/Dev/AI/ComfyUI}"
: "${CONDA_ENV:=comfy}"
: "${PYTHON_VERSION:=3.12}"
: "${LISTEN_ADDRESS:=0.0.0.0}"
: "${LISTEN_PORT:=8188}"
: "${LOG_DIR:=$HOME/Library/Logs}"
: "${LOG_FILE:=$LOG_DIR/comfyui.log}"
: "${ERROR_LOG_FILE:=$LOG_DIR/comfyui.error.log}"
: "${DOWNLOAD_DIR:=$HOME/.cache/comfy-downloads}"

# Set additional defaults
: "${CIVITAI_API_KEY:=}"

# Export for child processes
export COMFY_DIR CONDA_ENV PYTHON_VERSION LISTEN_ADDRESS LISTEN_PORT
export LOG_DIR LOG_FILE ERROR_LOG_FILE DOWNLOAD_DIR SCRIPT_DIR CIVITAI_API_KEY
