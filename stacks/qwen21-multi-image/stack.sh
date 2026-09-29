# Stack: Qwen Image 2.1 Multi-image Editing, up to 10 reference images (Civitai 2958067, v1.0)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflow: qwen21-multi-image_edit.json -> ComfyUI workflows/qwen21-multi-image/ (paths point at bf16 + heretic NVFP4; author shipped int8).
# LoRAs come from families/qwen21/loras.sh. Base nodes (rgthree, KJNodes, GGUF) come from provision.sh.

NODES+=(
  "https://github.com/zhinangubei/Comfyui_ZNGBNodes"              # ZNGB_ImageBatchMulti (image batch for the reference images)
  "https://github.com/yolain/ComfyUI-Easy-Use"                    # easy showAnything
)

MODELS+=(
  # VAE, shared by every qwen21 stack. The diffusion model (NVFP4 on Blackwell, else bf16) and the heretic NVFP4 text
  # encoder come from families/qwen21/loras.sh; every workflow's UNET / CLIP loader points at them.
  # The workflow shipped with int8 (7.3 / 9.4 GB); pointed at bf16 here.
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
  # Prompt enhancer (reference-aware, TextGenerateLTX2Prompt): Qwen3.5-9B tuned for Qwen Image 2.1, 9.5 GB
  # (only published as int8; the workflow uses it as shipped)
  "text_encoders|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/text_encoders/qwen3.5_9b_qwen_image_2.1_pe_i2i.int8_convrot.safetensors"
)
