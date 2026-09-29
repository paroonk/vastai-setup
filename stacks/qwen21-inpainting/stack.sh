# Stack: Qwen Image 2.1 inpainting with LanPaint (axiomgraph/ComfyUIWorkflow, GPL-3.0)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflows in this folder -> ComfyUI workflows/qwen21-inpainting/:
#   qwen21_inpainting_lanpaint_qwen35.json  prompt enhancer rebuilt on QwenVL-Mod with Qwen3.5-9B
#                                           Defiant Fable GGUF (uncensored, sees all input images).
#   qwen21_inpainting_lanpaint.json         author's graph; enhancer pointed at qwen3vl_8b bf16
#                                           (already downloaded; fallback if the Qwen3.5 copy misbehaves).
# Base nodes (rgthree, KJNodes, GGUF) come from provision.sh.
# Shared, downloaded once: Qwen Image 2.1 model/encoder/VAE (qwen21-art), Qwen3.5 GGUF + mmproj +
#   llama-cpp (mmh3-dasiwa).

# QwenVL-Mod GGUF backend: vision-capable llama-cpp (same entry as mmh3-dasiwa).
PIP_PACKAGES+=(
    "--upgrade --force-reinstall --no-cache-dir https://github.com/JamePeng/llama-cpp-python/releases/download/v0.4.1-cu131-linux-20260926/llama_cpp_python-0.4.1+cu131-cp312-cp312-linux_x86_64.whl"
)

NODES+=(
  "https://github.com/scraed/LanPaint"                 # LanPaint_KSampler (training-free inpainting sampler)
  "https://github.com/huchukato/ComfyUI-QwenVL-Mod"    # QwenVL_Unified: GGUF prompt enhancer with vision
)

# Format: "subdir|url"  (filename is taken from the URL)
MODELS+=(
  # Diffusion model (14.2 GB), text encoder (17.5 GB), VAE — shared with qwen21-art
  "diffusion_models|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/diffusion_models/qwen_image_2.1_bf16.safetensors"
  "text_encoders|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/text_encoders/qwen3vl_8b_bf16.safetensors"
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
  # Prompt enhancer LLM + vision projector (10.5 + 0.9 GB) — same files as mmh3-dasiwa's Prompt Forge
  "llm/GGUF|https://huggingface.co/DavidAU/Qwen3.5-9B-The-Defiant-Fable-Uncensored-Heretic-NEO-IMATRIX-MAX-MTP-GGUF/resolve/main/Qwen3.5-9B-The-Defiant-Fable-Uncnr-Heretic-NEO-MAX-Q8_0.gguf"
  "llm/GGUF|https://huggingface.co/DavidAU/Qwen3.5-9B-The-Defiant-Fable-Uncensored-Heretic-NEO-IMATRIX-MAX-MTP-GGUF/resolve/main/mmproj-BF16.gguf"
  # Viggle turbo v0.2.1 r128 LoRA (ComfyUI conversion by T8star), bypassed in the workflows, 0.9 GB
  "loras|https://huggingface.co/t8star/Qwen-Image-2.1-viggle-turbo-4step-r64-comfy/resolve/main/qwen_image_2.1_viggle_turbo_v0.2.1_r128_comfy.safetensors"
)

# QwenVL-Mod looks for its catalog models under models/LLM/GGUF/<author>/<repo>/ (and would re-download
# them there at run time). Link the files above instead; DaSiWa's Forge keeps using models/llm/GGUF/.
QWEN35_DIR="LLM/GGUF/DavidAU/Qwen3.5-9B-The-Defiant-Fable-Uncensored-Heretic-NEO-IMATRIX-MAX-MTP-GGUF"
LINKS+=(
  "$QWEN35_DIR/Qwen3.5-9B-The-Defiant-Fable-Uncnr-Heretic-NEO-MAX-Q8_0.gguf|llm/GGUF/Qwen3.5-9B-The-Defiant-Fable-Uncnr-Heretic-NEO-MAX-Q8_0.gguf"
  "$QWEN35_DIR/mmproj-BF16.gguf|llm/GGUF/mmproj-BF16.gguf"
)
