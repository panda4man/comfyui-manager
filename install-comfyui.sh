#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/config.sh"

ENV_NAME="$CONDA_ENV"

echo "Installing ComfyUI for Apple Silicon macOS..."

if ! command -v brew >/dev/null 2>&1; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if ! command -v git >/dev/null 2>&1; then
  brew install git
fi

if ! command -v conda >/dev/null 2>&1; then
  brew install --cask miniconda
  echo "Miniconda installed. Initializing shell..."
  "$HOME/miniconda3/bin/conda" init zsh || true
  export PATH="$HOME/miniconda3/bin:$PATH"
fi

mkdir -p "$(dirname "$COMFY_DIR")"

if [ ! -d "$COMFY_DIR/.git" ]; then
  git clone https://github.com/comfyanonymous/ComfyUI.git
else
  cd "$COMFY_DIR"
  git pull
fi

source "$(conda info --base)/etc/profile.d/conda.sh"

if ! conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
  conda create -y -n "$ENV_NAME" python="$PYTHON_VERSION"
fi

conda activate "$ENV_NAME"

cd "$COMFY_DIR"

python -m pip install --upgrade pip setuptools wheel
pip install --upgrade torch torchvision torchaudio
pip install -r requirements.txt

mkdir -p \
  models/checkpoints \
  models/vae \
  models/clip \
  models/unet \
  models/loras \
  models/controlnet \
  models/upscale_models \
  input \
  output \
  custom_nodes

cd custom_nodes

if [ ! -d "ComfyUI-Manager/.git" ]; then
  git clone https://github.com/ltdrdata/ComfyUI-Manager.git
else
  cd ComfyUI-Manager
  git pull
  cd ..
fi

cat > "$HOME/run-comfyui.sh" <<EOF
#!/usr/bin/env bash
source "\$(conda info --base)/etc/profile.d/conda.sh"
conda activate "$ENV_NAME"
cd "$COMFY_DIR"
python main.py
EOF

chmod +x "$HOME/run-comfyui.sh"

echo ""
echo "ComfyUI install complete."
echo ""
echo "Run it with:"
echo "  ~/run-comfyui.sh"
echo ""
echo "Then open:"
echo "  http://127.0.0.1:8188"
echo ""
echo "MPS check:"
python - <<'PY'
import torch
print("MPS available:", torch.backends.mps.is_available())
PY
