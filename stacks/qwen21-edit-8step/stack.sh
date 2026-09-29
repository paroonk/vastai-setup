# Stack: Qwen 2.1 EDIT workflow, 8 steps + prompt enhancer (Civitai 2969533, v1.0)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflow: qwen21-edit-8step_prompt-enhancer.json -> ComfyUI workflows/qwen21-edit-8step/ (loads the shared qwen_image_2.1 / qwen3vl_8b_heretic names).
# The author's uncensored encoder is kept (below).
# The 8-step LoRA (p_qwen_image_2.1_8step_v0.1-comfyui-T8) comes from families/qwen21/family.sh.
# Nodes: core ComfyUI + rgthree (base). Nothing extra.

MODELS+=(
  # VAE, shared by every qwen21 stack. The diffusion model and the heretic text encoder come from families/qwen21/family.sh
  # (NVFP4 by default), and the workflows' neutral names (qwen_image_2.1 / qwen3vl_8b_heretic) are rewritten to them at install.
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
)

# The workflow loads "qwen3vl_8b_heretic.safetensors" (CLIP type boogu) as BOTH the image model's text encoder
# and the prompt enhancer: the heretic encoder every qwen21 stack uses (downloaded by families/qwen21).
