# ComfyUI Manager

Setup and operations for ComfyUI on macOS with Apple Silicon, bundled model management and persistent LaunchAgent control.

## What It Does

- **Install** ComfyUI + Miniconda + torch/MPS on Apple Silicon
- **Manage models** from CivitAI, HuggingFace, direct URLs
- **Run as service** via macOS LaunchAgent (background, auto-restart)
- **Control** via `make` commands (start/stop/logs/status)

## Quick Start

```bash
# Configure paths and keys
cp .env.example .env
nano .env  # Set COMFY_DIR, CIVITAI_API_KEY if needed

# Install ComfyUI
./install-comfyui.sh

# Render and install the LaunchAgent plist from config/
make install-plist

# Load LaunchAgent (runs at login, starts on demand)
make load

# Access UI
open http://127.0.0.1:8188
```

## Installation

Requires: macOS 11+, Apple Silicon (M1/M2/M3/M4), ~30GB disk.

```bash
./install-comfyui.sh
```

Does:
1. Install Homebrew, Miniconda, git
2. Clone ComfyUI repo, init conda env (Python 3.12)
3. Install PyTorch + MPS backend
4. Create model directories
5. Install ComfyUI-Manager plugin
6. Write `~/run-comfyui.sh` launcher

Output: ComfyUI at `$COMFY_DIR` (default: `~/Dev/AI/ComfyUI`).

Then run `make install-plist` to render `config/com.local.run-comfyui.plist.template`
into `~/Library/LaunchAgents/com.local.run-comfyui.plist` before `make load`.

## Configuration

`.env` file sets:

```bash
COMFY_DIR              # Installation path
CONDA_ENV              # Conda environment name
PYTHON_VERSION         # Python version (3.12 default)
LISTEN_ADDRESS         # Server bind address (0.0.0.0 for LAN)
LISTEN_PORT            # Port (8188 default)
LOG_DIR                # Log output path
DOWNLOAD_DIR           # Model cache directory
CIVITAI_API_KEY        # Optional, for restricted models
```

Source `config.sh` in scripts to load these vars.

## Usage

### Launch Service

```bash
make load      # Load plist, start ComfyUI
make start     # Kick service if already loaded
make restart   # Stop and start
make stop      # Stop and unload
make unload    # Unload plist
```

Service runs in background. Set to auto-launch on login.

### Monitor

```bash
make status       # Show launchd status
make logs         # Tail stdout
make errors       # Tail stderr
make logs-all     # Tail both
make check-port   # What's on :8188
```

### Manual Run

```bash
~/run-comfyui.sh   # Or: conda activate comfy && cd $COMFY_DIR && python main.py
```

Access at `http://127.0.0.1:8188` (or LAN IP if bound to 0.0.0.0).

## Model Management

```bash
./download-models.sh -t <type> -u <url> [-n <name>]
```

### Types

- `checkpoint` — Stable Diffusion checkpoints
- `lora` — LoRA adapters
- `vae` — VAE models
- `controlnet` — ControlNet weights
- `embedding` — Embeddings
- `upscale` — Upscale models

### Sources

**CivitAI model page:**
```bash
./download-models.sh -t checkpoint -u https://civitai.com/models/112902/dreamshaper-xl
```

**CivitAI direct URL:**
```bash
./download-models.sh -t checkpoint -u "https://civitai.com/api/download/models/354657?fileId=282807" -n dreamshaper.safetensors
```

**HuggingFace:**
```bash
./download-models.sh -t lora -u stabilityai/control-lora-canny -n canny.safetensors
```

**Direct URL:**
```bash
./download-models.sh -t checkpoint -u https://example.com/model.safetensors
```

**Batch from stdin:**
```bash
cat << EOF | ./download-models.sh --batch
checkpoint https://civitai.com/models/112902/dreamshaper-xl
lora https://civitai.com/models/456789/some-lora
vae stabilityai/control-lora-canny
EOF
```

Models download to `$COMFY_DIR/models/<type>/`.

## File Structure

```
comfyui-manager/
  .env                    # Local config (git-ignored)
  .env.example            # Config template
  config.sh               # Env loader (source this)
  Makefile                # Service control commands
  install-comfyui.sh      # One-time setup
  download-models.sh      # Model downloader
  run-comfyui             # Wrapper script
  config/                 # LaunchAgent plist template
```

## Troubleshooting

**MPS not available?**
```bash
python -c "import torch; print(torch.backends.mps.is_available())"
```
If false: update macOS and PyTorch. M1 requires Monterey 12.3+.

**Port 8188 in use?**
```bash
make check-port
lsof -nP -iTCP:8188 -sTCP:LISTEN
```

**LaunchAgent not starting?**
```bash
make install-plist  # (re)render the plist from config/ if it's missing or stale
make validate-plist
launchctl print gui/$(id -u)/com.local.run-comfyui
```

**Conda not found after shell restart?**
```bash
conda init zsh  # Re-initialize shell
```

**Model download fails?**
- CivitAI requires API key for some models: set `CIVITAI_API_KEY` in `.env`
- Check disk space: `df -h`
- HuggingFace token: `huggingface-cli login` if needed

**Out of memory?**
ComfyUI on M-series Macs uses unified memory (RAM). Reduce batch size or resolution in UI.

## Requirements Met

- ✅ Runs ComfyUI headless or with UI
- ✅ Automatic model download from major sources
- ✅ Persistent background service (LaunchAgent)
- ✅ Log access and monitoring
- ✅ Configuration via .env
- ✅ Apple Silicon optimized (MPS)
