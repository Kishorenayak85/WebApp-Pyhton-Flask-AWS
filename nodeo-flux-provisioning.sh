#!/bin/bash
# Nodeo provisioning script for ai-dock/comfyui
# Provisions BOTH:
#   - FLUX.1-dev + IP-Adapter (character generation path, existing)
#   - Qwen-Image-Edit + custom nodes (scene image generation, NEW)
# Sourced automatically by init.sh via PROVISIONING_SCRIPT
# HF_TOKEN is read automatically by AI-Dock's download mechanism for models;
# custom nodes are public git repos and need no token.

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

# --- Qwen-Image-Edit (NEW, scene image generation) ---
# GGUF unet goes in diffusion_models (NOT unet) — UnetLoaderGGUF looks there.
QWEN_DIFFUSION_MODELS=(
  "https://huggingface.co/QuantStack/Qwen-Image-Edit-GGUF/resolve/main/Qwen_Image_Edit-Q8_0.gguf"
)

# Qwen text encoder -> models/clip. Shares the clip dir with FLUX encoders; different filename, no conflict.
QWEN_CLIP_MODELS=(
  "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"
)

# Qwen VAE -> models/vae. Different filename from FLUX ae.safetensors, no conflict.
QWEN_VAE_MODELS=(
  "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors"
)

QWEN_LORA_MODELS=(
  "https://huggingface.co/lightx2v/Qwen-Image-Lightning/resolve/main/Qwen-Image-Edit-Lightning-8steps-V1.0.safetensors"
)

# ----------------------------------------------------------------------------
# CUSTOM NODES (NEW — required by the Qwen edit workflows)
#   ComfyUI-GGUF      -> UnetLoaderGGUF          (all Qwen edit workflows)
#   rgthree-comfy     -> Image Comparer, Label   (preview/QoL nodes in the graphs)
#   ControlAltAI_Nodes-> FluxResolutionNode      (Combine 2 / Combine 3 only)
# ----------------------------------------------------------------------------
CUSTOM_NODES=(
  "https://github.com/city96/ComfyUI-GGUF"
  "https://github.com/rgthree/rgthree-comfy"
  "https://github.com/gseth/ControlAltAI-Nodes"
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

COMFYUI_DIR="/workspace/ComfyUI"

function provisioning_start() {
    provisioning_print_header

    # --- FLUX models ---
    provisioning_get_models "${COMFYUI_DIR}/models/unet"       "${UNET_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/vae"        "${VAE_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/clip"       "${CLIP_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/ipadapter"  "${IPADAPTER_MODELS[@]}"
    provisioning_get_renamed_model "${COMFYUI_DIR}/models/clip_vision" "$CLIP_VISION_URL" "$CLIP_VISION_FILENAME"

    # --- Qwen models ---
    provisioning_get_models "${COMFYUI_DIR}/models/diffusion_models" "${QWEN_DIFFUSION_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/clip"             "${QWEN_CLIP_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/vae"              "${QWEN_VAE_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/loras"            "${QWEN_LORA_MODELS[@]}"

    # --- Custom nodes (must come before ComfyUI starts) ---
    provisioning_get_custom_nodes

    provisioning_verify
    provisioning_print_end
}

function provisioning_get_models() {
    if [[ -z $2 ]]; then return 1; fi
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_get_renamed_model() {
    dir="$1"; url="$2"; filename="$3"
    mkdir -p "$dir"
    dest_path="${dir}/${filename}"
    if [[ -f "$dest_path" ]]; then
        printf "Skipping (already exists): %s\n" "$dest_path"
        return 0
    fi
    printf "Downloading (renamed): %s -> %s\n" "${url}" "${dest_path}"
    if [[ -n "$HF_TOKEN" && "$url" == *"huggingface.co"* ]]; then
        wget -q --header="Authorization: Bearer $HF_TOKEN" \
             --show-progress -e dotbytes="4M" -O "$dest_path" "$url"
    else
        wget -q --show-progress -e dotbytes="4M" -O "$dest_path" "$url"
    fi
}

# Clone each custom node repo and install its Python requirements.
# Idempotent: if the dir exists, pull latest instead of re-cloning.
function provisioning_get_custom_nodes() {
    local nodes_dir="${COMFYUI_DIR}/custom_nodes"
    mkdir -p "$nodes_dir"
    printf "\n=== Installing %s custom node(s) ===\n" "${#CUSTOM_NODES[@]}"
    for repo in "${CUSTOM_NODES[@]}"; do
        local name
        name="$(basename "$repo")"
        local target="${nodes_dir}/${name}"
        if [[ -d "$target" ]]; then
            printf "Updating existing custom node: %s\n" "$name"
            git -C "$target" pull --ff-only || printf "  (pull failed, keeping existing checkout)\n"
        else
            printf "Cloning custom node: %s\n" "$name"
            git clone --depth 1 "$repo" "$target" || { printf "  !!! clone FAILED: %s\n" "$repo"; continue; }
        fi
        # Install requirements if present
        if [[ -f "${target}/requirements.txt" ]]; then
            printf "  Installing requirements for %s...\n" "$name"
            pip install --no-cache-dir -r "${target}/requirements.txt" || \
                printf "  !!! pip install failed for %s (node may still work)\n" "$name"
        fi
    done
    printf "=== Custom node installation done ===\n\n"
}

function provisioning_print_header() {
    printf "\n###################################################\n# Nodeo: provisioning FLUX + Qwen-Image-Edit       #\n###################################################\n\n"
}

function provisioning_print_end() {
    printf "\nNodeo provisioning complete: ComfyUI will start now\n\n"
}

function provisioning_verify() {
    printf "\n=== Verifying downloads ===\n"
    local missing=0
    for f in \
        "${COMFYUI_DIR}/models/unet/flux1-dev.safetensors" \
        "${COMFYUI_DIR}/models/vae/ae.safetensors" \
        "${COMFYUI_DIR}/models/clip/clip_l.safetensors" \
        "${COMFYUI_DIR}/models/clip/t5xxl_fp16.safetensors" \
        "${COMFYUI_DIR}/models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors" \
        "${COMFYUI_DIR}/models/diffusion_models/Qwen_Image_Edit-Q8_0.gguf" \
        "${COMFYUI_DIR}/models/clip/qwen_2.5_vl_7b_fp8_scaled.safetensors" \
        "${COMFYUI_DIR}/models/vae/qwen_image_vae.safetensors" \
        "${COMFYUI_DIR}/models/loras/Qwen-Image-Edit-Lightning-8steps-V1.0.safetensors"
    do
        if [[ -f "$f" ]]; then
            printf "  OK      %s (%s)\n" "$f" "$(du -h "$f" | cut -f1)"
        else
            printf "  MISSING %s\n" "$f"
            missing=$((missing+1))
        fi
    done

    printf "\n=== Verifying custom nodes ===\n"
    for name in "ComfyUI-GGUF" "rgthree-comfy" "ControlAltAI-Nodes"; do
        if [[ -d "${COMFYUI_DIR}/custom_nodes/${name}" ]]; then
            printf "  OK      custom_nodes/%s\n" "$name"
        else
            printf "  MISSING custom_nodes/%s\n" "$name"
            missing=$((missing+1))
        fi
    done

    if [[ $missing -gt 0 ]]; then
        printf "\n!!! %s required item(s) MISSING — ComfyUI may fail !!!\n\n" "$missing"
    else
        printf "\nAll required models and custom nodes present.\n\n"
    fi
}

function provisioning_download() {
    if [[ -n "$HF_TOKEN" && "$1" == *"huggingface.co"* ]]; then
        wget -qnc --header="Authorization: Bearer $HF_TOKEN" \
             --content-disposition --show-progress -e dotbytes="4M" -P "$2" "$1"
    else
        wget -qnc --content-disposition --show-progress -e dotbytes="4M" -P "$2" "$1"
    fi
}

provisioning_start
