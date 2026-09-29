# Stack: Qwen 2.1 EDIT workflow, 8 steps + prompt enhancer (Civitai 2969533, v1.0)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflow: qwen21-edit-8step_prompt-enhancer.json -> ComfyUI workflows/qwen21-edit-8step/ (bf16 diffusion model, heretic encoder).
# The author's uncensored encoder is kept (below).
# The 8-step LoRA (p_qwen_image_2.1_8step_v0.1-comfyui-T8) comes from families/qwen21/loras.sh.
# Nodes: core ComfyUI + rgthree (base). Nothing extra.

MODELS+=(
  # Diffusion model (14.2 GB) and VAE — bf16, shared by every qwen21 stack. The text encoder is the heretic bf16
  # (families/qwen21/loras.sh), which every workflow's CLIP loader points at.
  # The workflow shipped with int8 diffusion (7.3 GB); pointed at bf16 here.
  "diffusion_models|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/diffusion_models/qwen_image_2.1_bf16.safetensors"
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
)

# The workflow loads "qwen3vl_8b_nvfp4_heretic.safetensors" (CLIP type boogu) as BOTH the image model's text
# encoder and the prompt enhancer: Qwen3-VL-8B heretic (uncensored), NVFP4, Blackwell GPUs only (6.3 GB).
# Source: pottokao/Qwen-Image-2.1-Text-Encoder-Heretic-NVFP4 (same filename as the workflow expects).
# Other GPUs (TEXT_ENCODER=int8, or auto-detected): full-bf16 heretic (17.5 GB, pottokao/Qwen-Image-2.1-Text-Encoder-Heretic,
# stock CLIPLoader, downloaded by families/qwen21) is what the workflow's filename links to, so it stays uncensored everywhere.
if [ "$(gpu_text_encoder)" = "nvfp4" ]; then
    MODELS+=("text_encoders|https://huggingface.co/pottokao/Qwen-Image-2.1-Text-Encoder-Heretic-NVFP4/resolve/main/qwen3vl_8b_nvfp4_heretic.safetensors")
else
    LINKS+=("text_encoders/qwen3vl_8b_nvfp4_heretic.safetensors|text_encoders/qwen3vl_8b_bf16_heretic.safetensors")
fi
