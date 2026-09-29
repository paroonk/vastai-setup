# Stack: Qwen Image 2.1 Outpaint — auto prompt, any side, optional LoRA (Civitai 2964810, v1.1, by AusBoss)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflow: qwen21-outpaint_auto-prompt.json -> ComfyUI workflows/qwen21-outpaint/ (loads the shared qwen_image_2.1 / qwen3vl_8b_heretic names).
# The outpaint LoRA v2 comes from families/qwen21/family.sh.
# The auto-prompt (TextGenerate) reuses the shared heretic encoder (families/qwen21) — no extra download.

NODES+=(
  "https://github.com/ausboss/ComfyUI-AusBoss"   # Load Image + Pad, Stitch Inpaint, LoRA Loader, Compare, Save Image, Text...
)

MODELS+=(
  # VAE, shared by every qwen21 stack. The diffusion model and the heretic text encoder come from families/qwen21/family.sh
  # (NVFP4 by default), and the workflows' neutral names (qwen_image_2.1 / qwen3vl_8b_heretic) are rewritten to them at install.
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
)
