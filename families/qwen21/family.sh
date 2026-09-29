# Family: qwen21 — shared by every qwen21-* stack: diffusion model, text encoder, LoRAs, and workflow-name rewrites (WF_SUBST).
# Sourced by provision.sh (after the stacks). Only append (+=).
# Add a Qwen Image 2.1 LoRA here once and every qwen21 stack gets it.

# The repo's qwen21 workflows use two neutral names (no symlinks): qwen_image_2.1.safetensors (diffusion model) and
# qwen3vl_8b_heretic.safetensors (heretic, uncensored, text encoder). provision.sh rewrites them (WF_SUBST) to the file that
# was actually downloaded when it installs the workflows, so each installed workflow names its real file.

# Diffusion model. QWEN21_DIFFUSION = auto (default) | nvfp4 | bf16. auto: pottokao's NVFP4 DiT (3.9 GB, community quant of
# the official model, non-commercial licence) on Blackwell GPUs, else the official bf16 (14.2 GB).
_q21_dit="${QWEN21_DIFFUSION:-auto}"
if [ "$_q21_dit" = "auto" ]; then
    if gpu_is_blackwell; then _q21_dit=nvfp4; else _q21_dit=bf16; fi
fi
echo "Qwen21 diffusion model: $_q21_dit" >&2
if [ "$_q21_dit" = "nvfp4" ]; then
    MODELS+=("diffusion_models|https://huggingface.co/pottokao/Qwen-Image-2.1-DiT-NVFP4-ComfyUI/resolve/main/qwen_image_2.1_nvfp4.safetensors")
    WF_SUBST+=("qwen_image_2.1.safetensors|qwen_image_2.1_nvfp4.safetensors")
else
    MODELS+=("diffusion_models|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/diffusion_models/qwen_image_2.1_bf16.safetensors")
    WF_SUBST+=(
        "Qwen-Image-2.1-DiT-NVFP4-ComfyUI/resolve/main/qwen_image_2.1_nvfp4.safetensors|Qwen-Image-2.1/resolve/main/diffusion_models/qwen_image_2.1_bf16.safetensors"
        "qwen_image_2.1.safetensors|qwen_image_2.1_bf16.safetensors"
    )
fi
unset _q21_dit

# Text encoder: Qwen3-VL-8B heretic (uncensored) by pottokao. QWEN21_ENCODER = nvfp4 (default, 6.3 GB) | bf16 (17.5 GB).
# The standard (non-heretic) encoder is not downloaded.
if [ "${QWEN21_ENCODER:-nvfp4}" != "bf16" ]; then      # default (unset or "nvfp4")
    MODELS+=("text_encoders|https://huggingface.co/pottokao/Qwen-Image-2.1-Text-Encoder-Heretic-NVFP4/resolve/main/qwen3vl_8b_nvfp4_heretic.safetensors")
    WF_SUBST+=("qwen3vl_8b_heretic.safetensors|qwen3vl_8b_nvfp4_heretic.safetensors")
else                                                      # QWEN21_ENCODER=bf16
    MODELS+=("text_encoders|https://huggingface.co/pottokao/Qwen-Image-2.1-Text-Encoder-Heretic/resolve/main/qwen3vl_8b_bf16_heretic.safetensors")
    WF_SUBST+=(
        "Qwen-Image-2.1-Text-Encoder-Heretic-NVFP4/resolve/main/qwen3vl_8b_nvfp4_heretic.safetensors|Qwen-Image-2.1-Text-Encoder-Heretic/resolve/main/qwen3vl_8b_bf16_heretic.safetensors"
        "qwen3vl_8b_heretic.safetensors|qwen3vl_8b_bf16_heretic.safetensors"
    )
fi

# Format: "subdir|url"  (filename is taken from the URL)
MODELS+=(
  # 8-step turbo v0.1 (RunningHub, ComfyUI T8 build), 0.34 GB — on in qwen21-edit-8step
  "loras|https://huggingface.co/RunningHubAI/rh-p-qwen-image-2.1-8step-v0.1-comfyui-t8-lora/resolve/main/p_qwen_image_2.1_8step_v0.1-comfyui-T8.safetensors"
  # Turbo v0.2 5-step r256 (Viggle), 1.4 GB — bypassed in qwen21-lonecats-fast
  "loras|https://huggingface.co/Viggle/Qwen-Image-2.1-viggle-turbo/resolve/main/Qwen-Image-2.1-viggle-turbo-v0.2-5step-lora-r256.safetensors"
  # Outpaint LoRA v2 by ausboss, 159 MB — rotate/crop/outpaint edits (used by qwen21-outpaint)
  "loras|https://huggingface.co/ausboss/Qwen-Image-2.1-Outpaint-LoRA/resolve/main/qwen-image-2.1-outpaint-v2.safetensors"
  # Consistency LoRA by ausboss, 159 MB each: edits stay on the original's frame. step 1500 = start here (same file as
  #   Civitai 2969143), step 2000 = tighter alignment, slightly paler paintings. No trigger word; strength 1.0 after the model loader.
  "loras|https://huggingface.co/ausboss/Qwen-Image-2.1-Consistency-LoRA/resolve/main/qwen-image-2.1-consistency.safetensors"
  "loras|https://huggingface.co/ausboss/Qwen-Image-2.1-Consistency-LoRA/resolve/main/qwen-image-2.1-consistency-2000.safetensors"
)

# Civitai LoRAs, saved under readable names. Needs CIVITAI_TOKEN.
# Format: "target|url|filename"
CIVITAI+=(
  # NSFW LORA | Qwen Image 2.1 v2.0 (server name: "NSFW Qwen by TheseAlpacas V2")
  "loras|https://civitai.red/api/download/models/3357315?fileId=3244894|qwen21_nsfw-lora_v2.0.safetensors"
  # qwen 2.1 vagina v1.0 (server name: qwen21_v2_000002750)
  "loras|https://civitai.red/api/download/models/3354330?fileId=3241739|qwen21_vagina_v1.0.safetensors"
  # Pornmaster Qwen Image 2.1 Breasts Slider V1 — add it to a Power Lora Loader to use
  "loras|https://civitai.red/api/download/models/3346363?fileId=3233286|qwen21_pornmaster-breasts-slider_v1.safetensors"
  # Skin Tone Slider V1 (Civitai 766017; Qwen 2.1 version), 78 MB. T2I: -0.8..-0.4 fair, +0.3..+0.6 tan, +0.7..+1.0 dark;
  #   edits: -1.0..-0.8 lighter, +1.2..+1.8 tan to brown, +2.0 strongest. No trigger word for Qwen.
  "loras|https://civitai.red/api/download/models/3360658?fileId=3248339|qwen21_skin-tone-slider_v1.safetensors"
  # Qwen-Image-2.1 Edit LoRA | Nude Edit v2.0 (server name: "Qwen-Image-2.1 NSFW Image EditV2"), 82 MB. Edit workflows.
  #   Prompt in CHINESE; modes: 全裸 nude / 开腿 legs spread / 女上位 cowgirl / 口交 oral. v2 adds pubic hair (describe it).
  "loras|https://civitai.red/api/download/models/3368467?fileId=3256521|qwen21_nude-edit_v2.0.safetensors"
)
