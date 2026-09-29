# Stack: Qwen image 2.1 Integrated Image Editing to Accelerate Workflows (Civitai 2965021, v1.0)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflow: qwen21-integrated_edit.json -> ComfyUI workflows/qwen21-integrated/ (bf16 model + heretic NVFP4 encoder).
# Speed-ups: SageAttention, EasyCache (author: quality loss, use Sage only).
# LoRAs come from families/qwen21/loras.sh. Nodes: core + KJNodes + rgthree (all base). Nothing extra.
# Not downloaded: the t2i prompt enhancer (qwen3.5_9b_qwen_image_2.1_pe_t2i.int8_convrot, 9.5 GB) that the
#   author's note mentions for text-to-image; the workflow itself only references the i2i one.

MODELS+=(
  # VAE, shared by every qwen21 stack. The diffusion model (NVFP4 on Blackwell, else bf16) and the heretic NVFP4 text
  # encoder come from families/qwen21/loras.sh; every workflow's UNET / CLIP loader points at them.
  # The workflow shipped with int8 (7.3 / 9.4 GB); pointed at bf16 here.
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
  # Prompt enhancer for image editing (Qwen3.5-9B PE i2i, 9.5 GB, int8 only) — bypassed in the workflow
  "text_encoders|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/text_encoders/qwen3.5_9b_qwen_image_2.1_pe_i2i.int8_convrot.safetensors"
)
