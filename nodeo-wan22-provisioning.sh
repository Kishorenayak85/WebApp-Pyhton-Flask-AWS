#!/bin/bash
# Nodeo provisioning script for ai-dock/comfyui — Wan 2.2 I2V (fast tier)
#
# Video generation stage: image-to-video via Wan 2.2 14B, accelerated with the
# LightX2V 4-step LoRA (2+2 KSamplerAdvanced split, shift 5.0, cfg 1). Matches
# comfyui_workflows/video/wan22_i2v_fast.json exactly — do not change model
# filenames without re-exporting that workflow's API JSON to match.
#
# No custom nodes required: this graph runs entirely on core ComfyUI nodes
# (UNETLoader, CLIPLoader, VAELoader, LoraLoaderModelOnly, ModelSamplingSD3,
# KSamplerAdvanced, WanImageToVideo, CreateVideo, SaveVideo). Confirmed during
# manual validation — unlike the FLUX/Qwen instance, no ComfyUI-GGUF or
# equivalent is needed here.
#
# HF_TOKEN read from container ENV — not required for these repos (both are
# ungated), kept for parity with the image-generation script and in case that
# changes upstream.

set -u

# ----------------------------------------------------------------------------
# Resolve the real ComfyUI directory. ai-dock images vary: /opt vs /workspace.
# ----------------------------------------------------------------------------
COMFYUI_DIR=""
for c in "/opt/ComfyUI" "${WORKSPACE:-/workspace}/ComfyUI" "/workspace/ComfyUI" "$HOME/ComfyUI"; do
    if [[ -d "$c" ]]; then COMFYUI_DIR="$c"; break; fi
done
if [[ -z "$COMFYUI_DIR" ]]; then
    COMFYUI_DIR="/opt/ComfyUI"
fi
echo "[provision] Using ComfyUI dir: $COMFYUI_DIR"

MODELS_DIR="${COMFYUI_DIR}/models"

# ----------------------------------------------------------------------------
# MODELS — Wan 2.2 I2V 14B (fp8 scaled) + LightX2V 4-step acceleration LoRA
# ----------------------------------------------------------------------------
WAN_DIFFUSION_MODELS=(
  "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors"
  "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors"
)
WAN_LORA_MODELS=(
  "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors"
  "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors"
)
WAN_VAE_MODELS=(
  "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors"
)
WAN_TEXT_ENCODER_MODELS=(
  "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header

    provisioning_get_models "${MODELS_DIR}/diffusion_models" "${WAN_DIFFUSION_MODELS[@]}"
    provisioning_get_models "${MODELS_DIR}/loras"            "${WAN_LORA_MODELS[@]}"
    provisioning_get_models "${MODELS_DIR}/vae"               "${WAN_VAE_MODELS[@]}"
    provisioning_get_models "${MODELS_DIR}/text_encoders"      "${WAN_TEXT_ENCODER_MODELS[@]}"

    provisioning_verify
    provisioning_print_end
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

function provisioning_download() {
    if [[ -n "${HF_TOKEN:-}" && "$1" == *"huggingface.co"* ]]; then
        wget -qnc --header="Authorization: Bearer $HF_TOKEN" --content-disposition --show-progress -e dotbytes="4M" -P "$2" "$1"
    else
        wget -qnc --content-disposition --show-progress -e dotbytes="4M" -P "$2" "$1"
    fi
}

function provisioning_print_header() {
    printf "\n###################################################\n# Nodeo: provisioning Wan 2.2 I2V (fast tier)      #\n###################################################\n\n"
}

function provisioning_print_end() {
    printf "\nNodeo provisioning complete.\n\n"
}

function provisioning_verify() {
    printf "\n=== Verifying models ===\n"
    local missing=0
    for f in \
        "${MODELS_DIR}/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors" \
        "${MODELS_DIR}/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors" \
        "${MODELS_DIR}/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors" \
        "${MODELS_DIR}/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors" \
        "${MODELS_DIR}/vae/wan_2.1_vae.safetensors" \
        "${MODELS_DIR}/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
    do
        if [[ -f "$f" ]]; then printf "  OK      %s\n" "$f"
        else printf "  MISSING %s\n" "$f"; missing=$((missing+1)); fi
    done

    if [[ $missing -gt 0 ]]; then
        printf "\n!!! %s item(s) MISSING — expect failures !!!\n\n" "$missing"
    else
        printf "\nAll models present.\n\n"
    fi
}

provisioning_start
