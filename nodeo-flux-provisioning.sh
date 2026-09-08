#!/bin/bash
# Nodeo provisioning script for ai-dock/comfyui — v2 (FLUX + Qwen)
# Fixes over v1: (A) AI-Dock native NODES=() + provisioning_get_nodes convention
# so custom nodes install at the correct point in the boot sequence, BEFORE
# ComfyUI starts; (B) robust ComfyUI path detection (/opt vs /workspace); plus a
# safe supervisorctl-based restart at the end as a belt-and-suspenders guard.
#
# Root cause of v1 failure: UnetLoaderGGUF "not found" (HTTP 400) — custom nodes
# were cloned into a path ComfyUI never scanned and/or after ComfyUI had already
# started, so they never registered. This version installs them the ai-dock way.
#
# HF_TOKEN is read from container ENV for gated model downloads. Custom node
# repos are public and need no token.

set -u

# ----------------------------------------------------------------------------
# (B) Resolve the real ComfyUI directory. ai-dock images vary: /opt vs /workspace.
# ----------------------------------------------------------------------------
COMFYUI_DIR=""
for c in "/opt/ComfyUI" "${WORKSPACE:-/workspace}/ComfyUI" "/workspace/ComfyUI" "$HOME/ComfyUI"; do
    if [[ -d "$c" ]]; then COMFYUI_DIR="$c"; break; fi
done
if [[ -z "$COMFYUI_DIR" ]]; then
    # Fall back to the documented default; mkdir will create the tree.
    COMFYUI_DIR="/opt/ComfyUI"
fi
echo "[provision] Using ComfyUI dir: $COMFYUI_DIR"

MODELS_DIR="${COMFYUI_DIR}/models"
NODES_DIR="${COMFYUI_DIR}/custom_nodes"

# ----------------------------------------------------------------------------
# (A) CUSTOM NODES — ai-dock native convention.
#   ComfyUI-GGUF       -> UnetLoaderGGUF        (all Qwen edit workflows)
#   rgthree-comfy      -> Image Comparer, Label (1ref graph only, harmless elsewhere)
#   ControlAltAI-Nodes -> FluxResolutionNode    (Combine 2 / Combine 3)
# ----------------------------------------------------------------------------
NODES=(
  "https://github.com/city96/ComfyUI-GGUF"
  "https://github.com/rgthree/rgthree-comfy"
  "https://github.com/gseth/ControlAltAI-Nodes"
)

# ----------------------------------------------------------------------------
# MODELS
# ----------------------------------------------------------------------------

# --- FLUX (existing, character generation) ---
UNET_MODELS=(
  "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors"
)
VAE_MODELS=(
  "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors"
)
CLIP_MODELS=(
  "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"
  "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors"
)
IPADAPTER_MODELS=(
  "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors"
  "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors"
)
CLIP_VISION_URL="https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors"
CLIP_VISION_FILENAME="CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors"

# --- Qwen-Image-Edit (scene image generation) ---
QWEN_DIFFUSION_MODELS=(
  "https://huggingface.co/QuantStack/Qwen-Image-Edit-GGUF/resolve/main/Qwen_Image_Edit-Q8_0.gguf"
)
QWEN_CLIP_MODELS=(
  "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"
)
QWEN_VAE_MODELS=(
  "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors"
)
QWEN_LORA_MODELS=(
  "https://huggingface.co/lightx2v/Qwen-Image-Lightning/resolve/main/Qwen-Image-Edit-Lightning-8steps-V1.0.safetensors"
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header

    # (A) Nodes FIRST — must be present before ComfyUI imports them.
    provisioning_get_nodes

    # Models
    provisioning_get_models "${MODELS_DIR}/unet"              "${UNET_MODELS[@]}"
    provisioning_get_models "${MODELS_DIR}/vae"               "${VAE_MODELS[@]}"
    provisioning_get_models "${MODELS_DIR}/clip"              "${CLIP_MODELS[@]}"
    provisioning_get_models "${MODELS_DIR}/ipadapter"         "${IPADAPTER_MODELS[@]}"
    provisioning_get_renamed_model "${MODELS_DIR}/clip_vision" "$CLIP_VISION_URL" "$CLIP_VISION_FILENAME"
    provisioning_get_models "${MODELS_DIR}/diffusion_models"  "${QWEN_DIFFUSION_MODELS[@]}"
    provisioning_get_models "${MODELS_DIR}/clip"              "${QWEN_CLIP_MODELS[@]}"
    provisioning_get_models "${MODELS_DIR}/vae"               "${QWEN_VAE_MODELS[@]}"
    provisioning_get_models "${MODELS_DIR}/loras"             "${QWEN_LORA_MODELS[@]}"

    provisioning_verify
    provisioning_restart_comfyui   # belt-and-suspenders; safe no-op if already loaded
    provisioning_print_end
}

# --- (A) ai-dock native node install: clone + pip install requirements ---
function provisioning_get_nodes() {
    mkdir -p "$NODES_DIR"
    printf "\n=== Installing %s custom node(s) into %s ===\n" "${#NODES[@]}" "$NODES_DIR"
    for repo in "${NODES[@]}"; do
        local name
        name="$(basename "$repo")"
        local path="${NODES_DIR}/${name}"
        local requirements="${path}/requirements.txt"
        if [[ -d "$path" ]]; then
            printf "Updating node: %s\n" "$name"
            ( cd "$path" && git pull --ff-only ) || printf "  (pull failed, keeping existing)\n"
        else
            printf "Cloning node: %s\n" "$name"
            git clone --recursive "$repo" "$path" || { printf "  !!! CLONE FAILED: %s\n" "$repo"; continue; }
        fi
        if [[ -f "$requirements" ]]; then
            printf "  Installing requirements for %s...\n" "$name"
            pip install --no-cache-dir -r "$requirements" || \
                printf "  !!! pip install -r failed for %s\n" "$name"
        fi
    done

    # Explicit dependency installs — do NOT rely solely on each node's
    # requirements.txt. ComfyUI-GGUF imports the `gguf` package at load time;
    # if it's missing the node IMPORT FAILS and UnetLoaderGGUF is unavailable
    # (this was the v2 failure: ModuleNotFoundError: No module named 'gguf').
    printf "  Installing explicit node dependencies (gguf)...\n"
    pip install --no-cache-dir "gguf>=0.13.0" || \
        printf "  !!! pip install gguf FAILED — UnetLoaderGGUF will not load\n"

    printf "=== Custom nodes done ===\n\n"
}

function provisioning_get_models() {
    if [[ -z ${2:-} ]]; then return 0; fi
    dir="$1"; mkdir -p "$dir"; shift
    arr=("$@")
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_get_renamed_model() {
    dir="$1"; url="$2"; filename="$3"; mkdir -p "$dir"
    dest_path="${dir}/${filename}"
    if [[ -f "$dest_path" ]]; then printf "Skipping (exists): %s\n" "$dest_path"; return 0; fi
    printf "Downloading (renamed): %s -> %s\n" "${url}" "${dest_path}"
    if [[ -n "${HF_TOKEN:-}" && "$url" == *"huggingface.co"* ]]; then
        wget -q --header="Authorization: Bearer $HF_TOKEN" --show-progress -e dotbytes="4M" -O "$dest_path" "$url"
    else
        wget -q --show-progress -e dotbytes="4M" -O "$dest_path" "$url"
    fi
}

function provisioning_download() {
    if [[ -n "${HF_TOKEN:-}" && "$1" == *"huggingface.co"* ]]; then
        wget -qnc --header="Authorization: Bearer $HF_TOKEN" --content-disposition --show-progress -e dotbytes="4M" -P "$2" "$1"
    else
        wget -qnc --content-disposition --show-progress -e dotbytes="4M" -P "$2" "$1"
    fi
}

function provisioning_print_header() {
    printf "\n###################################################\n# Nodeo: provisioning FLUX + Qwen-Image-Edit (v2)  #\n###################################################\n\n"
}

function provisioning_print_end() {
    printf "\nNodeo provisioning complete.\n\n"
}

function provisioning_verify() {
    printf "\n=== Verifying models ===\n"
    local missing=0
    for f in \
        "${MODELS_DIR}/unet/flux1-dev.safetensors" \
        "${MODELS_DIR}/vae/ae.safetensors" \
        "${MODELS_DIR}/clip/clip_l.safetensors" \
        "${MODELS_DIR}/clip/t5xxl_fp16.safetensors" \
        "${MODELS_DIR}/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors" \
        "${MODELS_DIR}/diffusion_models/Qwen_Image_Edit-Q8_0.gguf" \
        "${MODELS_DIR}/clip/qwen_2.5_vl_7b_fp8_scaled.safetensors" \
        "${MODELS_DIR}/vae/qwen_image_vae.safetensors" \
        "${MODELS_DIR}/loras/Qwen-Image-Edit-Lightning-8steps-V1.0.safetensors"
    do
        if [[ -f "$f" ]]; then printf "  OK      %s\n" "$f"
        else printf "  MISSING %s\n" "$f"; missing=$((missing+1)); fi
    done

    printf "\n=== Verifying custom nodes (in %s) ===\n" "$NODES_DIR"
    for name in "ComfyUI-GGUF" "rgthree-comfy" "ControlAltAI-Nodes"; do
        # Consider a node present only if its dir exists AND has python files.
        if [[ -d "${NODES_DIR}/${name}" ]] && compgen -G "${NODES_DIR}/${name}/*.py" > /dev/null; then
            printf "  OK      custom_nodes/%s\n" "$name"
        else
            printf "  MISSING custom_nodes/%s (ComfyUI will 400 on its nodes)\n" "$name"; missing=$((missing+1))
        fi
    done

    if [[ $missing -gt 0 ]]; then
        printf "\n!!! %s item(s) MISSING — expect failures !!!\n\n" "$missing"
    else
        printf "\nAll models and custom nodes present.\n\n"
    fi
}

# Safe restart via supervisor so newly-installed nodes are imported, without
# racing ai-dock's process manager. Auto-detects the service name; no-ops safely
# if supervisor isn't controlling comfyui on this image.
function provisioning_restart_comfyui() {
    printf "\n=== Restarting ComfyUI so new nodes register ===\n"
    if ! command -v supervisorctl >/dev/null 2>&1; then
        printf "  supervisorctl not found — skipping restart (ai-dock will start ComfyUI normally).\n"
        return 0
    fi
    # Find a supervisor program whose name looks like comfyui.
    local svc
    svc="$(supervisorctl status 2>/dev/null | awk '{print $1}' | grep -i comfy | head -n1)"
    if [[ -z "$svc" ]]; then
        printf "  No comfyui supervisor service found — skipping (first start will load nodes).\n"
        return 0
    fi
    printf "  Restarting supervisor service: %s\n" "$svc"
    supervisorctl restart "$svc" || printf "  (restart returned non-zero; first boot may already be loading nodes)\n"
}

provisioning_start
