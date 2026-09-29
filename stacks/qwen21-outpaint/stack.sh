# Stack: Qwen Image 2.1 Outpaint — auto prompt, any side, optional LoRA (Civitai 2964810, v1.1, by AusBoss)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflow: qwen21-outpaint_auto-prompt.json -> ComfyUI workflows/qwen21-outpaint/ (bf16 model + heretic encoder).
# The outpaint LoRAs (v2 on, v1 off) come from families/qwen21/loras.sh.
# The auto-prompt (TextGenerate) reuses the shared heretic bf16 encoder (families/qwen21) — no extra download.

NODES+=(
  "https://github.com/ausboss/ComfyUI-AusBoss"   # Load Image + Pad, Stitch Inpaint, LoRA Loader, Compare, Save Image, Text...
)

MODELS+=(
  # Diffusion model (14.2 GB) and VAE — bf16, shared by every qwen21 stack. The text encoder is the heretic bf16
  # (families/qwen21/loras.sh), which every workflow's CLIP loader points at.
  "diffusion_models|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/diffusion_models/qwen_image_2.1_bf16.safetensors"
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
)
