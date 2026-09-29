# Stack: Qwen Image 2.1 inpainting with LanPaint (axiomgraph/ComfyUIWorkflow, GPL-3.0)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflow: qwen21_inpainting_lanpaint.json in this folder -> ComfyUI workflows/qwen21-inpainting/.
#   Text encoder pointed at bf16 (author used int8); everything else as shipped.
# Base nodes (rgthree, KJNodes, GGUF) come from provision.sh.
# Qwen Image 2.1 model, text encoder and VAE are the same files as qwen21-art; downloaded once.

NODES+=(
  "https://github.com/scraed/LanPaint"    # LanPaint_KSampler (training-free inpainting sampler)
)

# Format: "subdir|url"  (filename is taken from the URL)
MODELS+=(
  # Diffusion model (14.2 GB), text encoder (17.5 GB), VAE — shared with qwen21-art
  "diffusion_models|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/diffusion_models/qwen_image_2.1_bf16.safetensors"
  "text_encoders|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/text_encoders/qwen3vl_8b_bf16.safetensors"
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
  # Prompt enhancer LLM for TextGenerate in the "Positive Prompt" subgraph (on by default), 12.1 GB.
  # int8 as the author shipped it; bf16 (24 GB) exists at the same path as gemma4_12b_bf16.safetensors.
  "text_encoders|https://huggingface.co/Comfy-Org/gemma-4/resolve/main/text_encoders/gemma4_12b_int8_convrot.safetensors"
  # Viggle turbo v0.2.1 r128 LoRA (ComfyUI conversion by T8star), bypassed in the workflow, 0.9 GB
  "loras|https://huggingface.co/t8star/Qwen-Image-2.1-viggle-turbo-4step-r64-comfy/resolve/main/qwen_image_2.1_viggle_turbo_v0.2.1_r128_comfy.safetensors"
)
