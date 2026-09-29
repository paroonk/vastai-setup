# Stack: Qwen-Image-2.1 Dual CFG Image Edit (Civitai 2965509, v1.0)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflow: qwen21-dual-cfg_edit.json -> ComfyUI workflows/qwen21-dual-cfg/ (loads the shared qwen_image_2.1 / qwen3vl_8b_heretic names).
# Two sampling stages with separate CFG. Core nodes only.
# Not included: the author's sample image (qwen_dual_cfg_sample_before.jpg); pick your own in Load Image.

MODELS+=(
  # VAE, shared by every qwen21 stack. The diffusion model and the heretic text encoder come from families/qwen21/family.sh
  # (NVFP4 by default), and the workflows' neutral names (qwen_image_2.1 / qwen3vl_8b_heretic) are rewritten to them at install.
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
)
