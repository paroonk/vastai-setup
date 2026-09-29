# Stack: Qwen-Image-2.1 Dual CFG Image Edit (Civitai 2965509, v1.0)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflow: qwen21-dual-cfg_edit.json -> ComfyUI workflows/qwen21-dual-cfg/ (bf16 model + heretic encoder).
# Two sampling stages with separate CFG. Core nodes only.
# Not included: the author's sample image (qwen_dual_cfg_sample_before.jpg); pick your own in Load Image.

MODELS+=(
  # Diffusion model (14.2 GB) and VAE — bf16, shared by every qwen21 stack. The text encoder is the heretic bf16
  # (families/qwen21/loras.sh), which every workflow's CLIP loader points at.
  # The workflow shipped with int8 (7.3 / 9.4 GB); pointed at bf16 here.
  "diffusion_models|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/diffusion_models/qwen_image_2.1_bf16.safetensors"
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
)
