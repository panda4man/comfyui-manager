#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/config.sh"

type=""
url=""
name=""

get_model_dir() {
  case "$1" in
    checkpoint) echo "models/checkpoints" ;;
    lora) echo "models/loras" ;;
    vae) echo "models/vae" ;;
    controlnet) echo "models/controlnet" ;;
    embedding) echo "embeddings" ;;
    upscale) echo "models/upscale_models" ;;
    *) return 1 ;;
  esac
}

usage() {
  cat << EOF
Usage: $0 -t <type> -u <url> [-n <name>]

Options:
  -t, --type      Model type: checkpoint, lora, vae, controlnet, embedding, upscale
  -u, --url       Direct download URL or HuggingFace path (user/repo/file)
  -n, --name      Custom filename (optional, auto-detected if not provided)
  -h, --help      Show this help

Examples:
  # Direct URL
  $0 -t checkpoint -u https://example.com/model.safetensors

  # HuggingFace
  $0 -t lora -u stabilityai/control-lora-canny -n canny.safetensors

  # CivitAI model page (auto-scrapes for download URL)
  $0 -t checkpoint -u https://civitai.com/models/112902/dreamshaper-xl

  # CivitAI direct download URL
  $0 -t checkpoint -u https://civitai.com/api/download/models/354657?fileId=282807

  # Batch download via stdin
  echo "checkpoint https://civitai.com/models/112902/dreamshaper-xl
lora https://civitai.com/models/456789/some-lora
vae stabilityai/control-lora-canny" | $0 --batch

EOF
  exit 1
}

# Convert HF path to direct URL
hf_to_url() {
  local path="$1"
  if [[ "$path" =~ ^https:// ]]; then
    echo "$path"
  else
    echo "https://huggingface.co/$path/resolve/main"
  fi
}

# Handle CivitAI URLs
civitai_to_url() {
  local url="$1"

  # Already a direct download URL
  if [[ "$url" =~ civitai.com/api/download ]]; then
    echo "$url"
    return 0
  fi

  # CivitAI model page → fetch from API
  if [[ "$url" =~ civitai.com/models/([0-9]+) ]]; then
    local model_id="${BASH_REMATCH[1]}"
    echo "Fetching CivitAI model info..." >&2

    # Use CivitAI API to get latest model version's download URL
    local download_url
    if command -v jq >/dev/null 2>&1; then
      download_url=$(curl -fsSL "https://civitai.com/api/v1/models/$model_id" 2>/dev/null | jq -r '.modelVersions[0].downloadUrl' 2>/dev/null)
    else
      # Fallback without jq: grep for downloadUrl field
      download_url=$(curl -fsSL "https://civitai.com/api/v1/models/$model_id" 2>/dev/null | grep -oP '"downloadUrl":"[^"]*' | head -1 | cut -d'"' -f4)
    fi

    if [[ -n "$download_url" && "$download_url" != "null" ]]; then
      echo "$download_url"
      return 0
    fi

    echo "Error: Could not fetch download URL from CivitAI API for model $model_id" >&2
    return 1
  fi

  # Not a CivitAI URL, pass through
  echo "$url"
}

download_model() {
  local type="$1"
  local url="$2"
  local custom_name="${3:-}"

  local model_subdir
  model_subdir=$(get_model_dir "$type") || {
    echo "Error: Unknown model type '$type'. Valid: checkpoint lora vae controlnet embedding upscale"
    return 1
  }

  local target_dir="$COMFY_DIR/$model_subdir"

  if [[ ! -d "$target_dir" ]]; then
    echo "Creating directory: $target_dir"
    mkdir -p "$target_dir"
  fi

  # Handle different sources
  local is_civitai=false
  if [[ "$url" =~ civitai ]]; then
    is_civitai=true
    url=$(civitai_to_url "$url") || return 1
  elif [[ ! "$url" =~ ^https:// ]]; then
    url=$(hf_to_url "$url")
  fi

  # Determine filename for non-CivitAI sources
  local filename="$custom_name"
  if [[ -z "$filename" && "$is_civitai" != "true" ]]; then
    filename=$(basename "${url%\?*}" | sed 's/%20/ /g')
  fi

  if [[ -z "$filename" && "$is_civitai" != "true" ]]; then
    echo "Error: Could not determine filename from URL: $url"
    return 1
  fi

  local filepath="$target_dir/$filename"

  echo "Downloading from: $(echo "$url" | sed 's|^https://||' | cut -d'/' -f1)"
  echo "  Type: $type"
  echo "  Destination: $target_dir/"

  # Create target dir
  mkdir -p "$DOWNLOAD_DIR" "$target_dir"

  # Download with progress
  local downloaded=false

  if command -v curl >/dev/null 2>&1; then
    if [[ "$is_civitai" == "true" ]]; then
      # For CivitAI: use -J with -O to get filename from Content-Disposition header
      # Add Authorization header if API key provided
      local curl_opts=(-fL -# -J -O)
      if [[ -n "$CIVITAI_API_KEY" ]]; then
        curl_opts+=(-H "Authorization: Bearer $CIVITAI_API_KEY")
      fi
      (cd "$target_dir" && curl "${curl_opts[@]}" "$url")
      if [[ $? -eq 0 ]]; then
        downloaded=true
      fi
    else
      # For other sources: use provided/detected filename
      if curl -fL -# -o "$filepath" -C - "$url"; then
        downloaded=true
      fi
    fi
  fi

  if [[ "$downloaded" != "true" ]] && command -v wget >/dev/null 2>&1; then
    if wget --show-progress -O "$filepath" "$url"; then
      downloaded=true
    fi
  fi

  # For CivitAI, find the downloaded file (should be .safetensors)
  if [[ "$is_civitai" == "true" && "$downloaded" == "true" ]]; then
    # Find the most recently modified file (the one we just downloaded)
    filepath=$(find "$target_dir" -type f ! -name ".*" -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1)
    if [[ -z "$filepath" ]]; then
      echo "✗ Failed to locate downloaded file in $target_dir"
      return 1
    fi
    filename=$(basename "$filepath")
  fi

  if [[ "$downloaded" == "true" ]]; then
    echo "✓ Downloaded: $filename"
    return 0
  else
    echo "✗ Failed to download: $filename"
    rm -f "$filepath"
    return 1
  fi
}

# Check dependencies
if ! command -v curl >/dev/null && ! command -v wget >/dev/null; then
  echo "Error: curl or wget required"
  exit 1
fi

if [[ $# -eq 0 ]]; then
  usage
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--type)
      type="$2"
      shift 2
      ;;
    -u|--url)
      url="$2"
      shift 2
      ;;
    -n|--name)
      name="$2"
      shift 2
      ;;
    --batch)
      # Read from stdin: type url [name]
      while read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        read -r type url name <<< "$line" || { type="$url"; url="$name"; name=""; }
        download_model "$type" "$url" "$name" || true
      done
      exit 0
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

if [[ -z "${type:-}" || -z "${url:-}" ]]; then
  echo "Error: -t and -u required"
  usage
fi

download_model "$type" "$url" "${name:-}"
