# Stack: Qwen 2.1 EDIT workflow, 8 steps + prompt enhancer (Civitai 2969533, v1.0)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflow: qwen21-edit-8step_prompt-enhancer.json -> ComfyUI workflows/qwen21-edit-8step/ (bf16 diffusion model, heretic encoder).
# The author's uncensored encoder is kept (below).
# The 8-step LoRA (p_qwen_image_2.1_8step_v0.1-comfyui-T8) comes from families/qwen21/loras.sh.
# Nodes: core ComfyUI + rgthree (base). Nothing extra.

MODELS+=(
  # VAE, shared by every qwen21 stack. The diffusion model (NVFP4 on Blackwell, else bf16) and the heretic NVFP4 text
  # encoder come from families/qwen21/loras.sh; every workflow's UNET / CLIP loader points at them.
  # The workflow shipped with int8 diffusion (7.3 GB); pointed at bf16 here.
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
)

# The workflow loads "qwen3vl_8b_nvfp4_heretic.safetensors" (CLIP type boogu) as BOTH the image model's text encoder
# and the prompt enhancer: the heretic encoder every qwen21 stack uses (downloaded by families/qwen21).
