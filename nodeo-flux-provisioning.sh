#!/bin/bash
# Nodeo FLUX.1-dev + IP-Adapter provisioning script for ai-dock/comfyui
# Sourced automatically by init.sh via PROVISIONING_SCRIPT
# HF_TOKEN is read automatically by AI-Dock's download mechanism — do not hardcode it here

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

# This one needs a rename: source is "model.safetensors", destination filename differs
CLIP_VISION_URL="https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors"
CLIP_VISION_FILENAME="CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors"

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header
    provisioning_get_models "/workspace/ComfyUI/models/unet" "${UNET_MODELS[@]}"
    provisioning_get_models "/workspace/ComfyUI/models/vae" "${VAE_MODELS[@]}"
    provisioning_get_models "/workspace/ComfyUI/models/clip" "${CLIP_MODELS[@]}"
    provisioning_get_models "/workspace/ComfyUI/models/ipadapter" "${IPADAPTER_MODELS[@]}"
    provisioning_get_renamed_model "/workspace/ComfyUI/models/clip_vision" "$CLIP_VISION_URL" "$CLIP_VISION_FILENAME"
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

# For files that need renaming on save (source filename != desired filename)
function provisioning_get_renamed_model() {
    dir="$1"
    url="$2"
    filename="$3"
    mkdir -p "$dir"
    dest_path="${dir}/${filename}"
    if [[ -f "$dest_path" ]]; then
        printf "Skipping (already exists): %s\n" "$dest_path"
        return 0
    fi
    printf "Downloading (renamed): %s -> %s\n" "${url}" "${dest_path}"
    wget -q --show-progress -e dotbytes="4M" -O "$dest_path" "$url"
}

function provisioning_print_header() {
    printf "\n##############################################\n# Nodeo: provisioning FLUX.1-dev + IP-Adapter #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nNodeo provisioning complete: ComfyUI will start now\n\n"
}

function provisioning_download() {
    wget -qnc --content-disposition --show-progress -e dotbytes="4M" -P "$2" "$1"
}

provisioning_start
