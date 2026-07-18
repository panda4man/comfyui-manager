#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/config.sh"

type=""
url=""
name=""

# Populated as a side effect of civitai_to_url() when jq is available.
# Reset at the top of download_model() so nothing leaks across --batch entries.
CIVITAI_SHA256=""
CIVITAI_FILENAME=""
CIVITAI_SIZE_KB=""

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

    local api_response
    api_response=$(curl -fsSL "https://civitai.com/api/v1/models/$model_id" 2>/dev/null)

    # Use CivitAI API to get latest model version's download URL
    local download_url
    if command -v jq >/dev/null 2>&1; then
      download_url=$(echo "$api_response" | jq -r '.modelVersions[0].downloadUrl' 2>/dev/null || true)

      # Prefer the file flagged primary, fall back to the first file listed
      local file_json
      file_json=$(echo "$api_response" | jq -c '.modelVersions[0].files[]? | select(.primary == true)' 2>/dev/null || true)
      if [[ -z "$file_json" ]]; then
        file_json=$(echo "$api_response" | jq -c '.modelVersions[0].files[0]?' 2>/dev/null || true)
      fi

      if [[ -n "$file_json" && "$file_json" != "null" ]]; then
        CIVITAI_SHA256=$(echo "$file_json" | jq -r '.hashes.SHA256 // empty' 2>/dev/null || true)
        CIVITAI_FILENAME=$(echo "$file_json" | jq -r '.name // empty' 2>/dev/null || true)
        CIVITAI_SIZE_KB=$(echo "$file_json" | jq -r '.sizeKB // empty' 2>/dev/null || true)
      fi
    else
      # Fallback without jq: grep for downloadUrl field.
      # CIVITAI_SHA256/CIVITAI_FILENAME/CIVITAI_SIZE_KB stay empty; callers
      # (checksum verification, dedup, disk-space check) degrade gracefully.
      download_url=$(echo "$api_response" | grep -oP '"downloadUrl":"[^"]*' | head -1 | cut -d'"' -f4)
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

# Verify a downloaded file's SHA256 against an expected hash (case-insensitive).
# If no expected hash is known, this is a no-op success (degrade gracefully).
verify_checksum() {
  local file="$1"
  local expected_sha256="$2"

  if [[ -z "$expected_sha256" ]]; then
    echo "No checksum available, skipping verification"
    return 0
  fi

  local actual_sha256
  actual_sha256=$(shasum -a 256 "$file" | awk '{print $1}')

  local actual_lc expected_lc
  actual_lc=$(echo "$actual_sha256" | tr '[:upper:]' '[:lower:]')
  expected_lc=$(echo "$expected_sha256" | tr '[:upper:]' '[:lower:]')

  if [[ "$actual_lc" != "$expected_lc" ]]; then
    echo "✗ Checksum mismatch for $file"
    echo "  Expected: $expected_sha256"
    echo "  Actual:   $actual_sha256"
    return 1
  fi

  echo "✓ Checksum verified"
  return 0
}

# Ensure there is enough free space in $dir for a download of roughly
# $needed_kb (KB). If $needed_kb is unknown, fall back to a static floor
# (2GB). A ~10% safety margin is always added on top.
check_disk_space() {
  local dir="$1"
  local needed_kb="${2:-}"

  # Normalize a possible float (e.g. CivitAI sizeKB) to an integer.
  needed_kb="${needed_kb%%.*}"

  local floor_kb=2097152 # 2GB, used when the size can't be determined
  if [[ -z "$needed_kb" || ! "$needed_kb" =~ ^[0-9]+$ ]]; then
    needed_kb=$floor_kb
  fi

  local available_kb
  available_kb=$(df -Pk "$dir" | awk 'NR==2 {print $4}')

  local needed_with_margin=$(( needed_kb + needed_kb / 10 ))

  if (( available_kb < needed_with_margin )); then
    local avail_mb needed_mb
    avail_mb=$(( available_kb / 1024 ))
    needed_mb=$(( needed_with_margin / 1024 ))
    echo "✗ Not enough disk space in $dir (available: ${avail_mb}MB, required: ~${needed_mb}MB)" >&2
    return 1
  fi

  return 0
}

download_model() {
  # Reset CivitAI globals so a stale value can't leak between --batch entries.
  CIVITAI_SHA256=""
  CIVITAI_FILENAME=""
  CIVITAI_SIZE_KB=""

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

  # Dedup: skip if we already have this file.
  if [[ "$is_civitai" != "true" ]]; then
    if [[ -f "$filepath" ]]; then
      echo "✓ Already exists: $filename (skipping)"
      return 0
    fi
  elif [[ -n "$CIVITAI_FILENAME" ]]; then
    # CivitAI filename is normally only known post-download; the API lookup
    # in civitai_to_url() gives us it early when jq is available.
    local civitai_candidate="$target_dir/$CIVITAI_FILENAME"
    if [[ -f "$civitai_candidate" ]]; then
      echo "✓ Already exists: $CIVITAI_FILENAME (skipping)"
      return 0
    fi
  fi

  echo "Downloading from: $(echo "$url" | sed 's|^https://||' | cut -d'/' -f1)"
  echo "  Type: $type"
  echo "  Destination: $target_dir/"

  # Create target dir
  mkdir -p "$DOWNLOAD_DIR" "$target_dir"

  # Disk-space guard: abort this download (not the whole batch) if there
  # isn't enough room, with a ~10% safety margin.
  local needed_kb=""
  if [[ "$is_civitai" == "true" ]]; then
    needed_kb="$CIVITAI_SIZE_KB"
  else
    local content_length_bytes
    content_length_bytes=$(curl -sIL "$url" 2>/dev/null | awk '/[Cc]ontent-[Ll]ength/{print $2}' | tail -1 | tr -d '\r\n')
    if [[ "$content_length_bytes" =~ ^[0-9]+$ ]]; then
      needed_kb=$(( content_length_bytes / 1024 ))
    fi
  fi

  if ! check_disk_space "$target_dir" "$needed_kb"; then
    return 1
  fi

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
    if ! verify_checksum "$filepath" "$CIVITAI_SHA256"; then
      rm -f "$filepath"
      return 1
    fi
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
        # Quote-aware tokenizing (so a quoted name/url with spaces survives)
        # without eval, which would execute $()/backticks in the input.
        # (Uses a read loop rather than mapfile/readarray: this repo targets
        # stock macOS bash, which is 3.2 and predates those bash-4 builtins.)
        _fields=()
        while IFS= read -r _field; do
          _fields+=("$_field")
        done < <(printf '%s\n' "$line" | xargs -n1 2>/dev/null)
        type="${_fields[0]:-}"; url="${_fields[1]:-}"; name="${_fields[2]:-}"
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
