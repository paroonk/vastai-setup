# Stack: MiniMax H3 on ComfyUI
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflows: every *.json in this folder is installed to ComfyUI workflows/mmh3-dasiwa/.

# Each entry is passed to pip unquoted, so an entry may carry its own flags.
PIP_PACKAGES+=(
    "--upgrade --force-reinstall --no-cache-dir https://github.com/JamePeng/llama-cpp-python/releases/download/v0.4.1-cu131-linux-20260926/llama_cpp_python-0.4.1+cu131-cp312-cp312-linux_x86_64.whl"
)

# Base nodes (rgthree, KJNodes, GGUF) come from provision.sh
NODES+=(
  "https://github.com/darksidewalker/ComfyUI-DaSiWa-Nodes"
  "https://github.com/bbaudio-2025/Comfyui-MMH3-UltimateUpscale"
)

# Format: "subdir|url"  (filename is taken from the URL)
MODELS+=(
  # Video VAE (both variants)
  "vae|https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_fp16.safetensors"
  "vae|https://huggingface.co/Kijai/MiniMax-H3-experimental/resolve/main/minimax_h3_video_vae_int8_convrot.safetensors"
  # Audio VAE
  "vae|https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors"
  # TAE preview
  "vae_approx|https://huggingface.co/Kijai/MiniMax-H3-TAE/resolve/main/vae_approx/taeh3.safetensors"
  # Diffusion models (~21 GB each)
  "diffusion_models|https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors"
  "diffusion_models|https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors"
  # LoRA
  "loras|https://huggingface.co/noname1992/loras/resolve/main/MysticXXX_MMH3-V1.safetensors"
  # Latent upscaler
  "latent_upscale_models|https://huggingface.co/LBH-123-AI/Minimax_h3_latent_Upscaler/resolve/main/minimax_h3_latent_upscaler_3d_conv_v1/minimax_h3_latent_upscaler_3d_conv_v1_bf16.safetensors"
  # Frame interpolation
  "frame_interpolation|https://huggingface.co/Comfy-Org/frame_interpolation/resolve/main/frame_interpolation/rife_v4.26.safetensors"
  # Upscale models
  "upscale_models|https://huggingface.co/Kim2091/UltraSharp/resolve/main/4x-UltraSharp.safetensors"
  "upscale_models|https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth"
  # LLM models
  # (QwenVL-Mod GGUF nodes read models/llm/GGUF; mmproj must sit next to the model)
  "llm/GGUF|https://huggingface.co/DavidAU/Qwen3.5-9B-The-Defiant-Fable-Uncensored-Heretic-NEO-IMATRIX-MAX-MTP-GGUF/resolve/main/Qwen3.5-9B-The-Defiant-Fable-Uncnr-Heretic-NEO-MAX-Q8_0.gguf"
  # Vision projector (F16): enables image input / captioning. Drop it for text-only.
  "llm/GGUF|https://huggingface.co/DavidAU/Qwen3.5-9B-The-Defiant-Fable-Uncensored-Heretic-NEO-IMATRIX-MAX-MTP-GGUF/resolve/main/mmproj-F16.gguf"
)

# Civitai files (filename comes from the server). Needs CIVITAI_TOKEN.
# Format: "target|url"   target = "workflows" or a models subdir
CIVITAI+=(
  # DaSiWa MiniMax H3 workflows (C-MMH3 v2.4) — zip is auto-extracted
  "workflows|https://civitai.red/api/download/models/3195699?fileId=3247382"
  # DaSiWa MiniMax H3 checkpoint (DaSiWa Hybrid v2)
  "diffusion_models|https://civitai.red/api/download/models/3314675?fileId=3203130"
  # Minimax H3 Turbo LoRA (turbo-multistep-v2)
  "loras|https://civitai.red/api/download/models/3357658?fileId=3245274"
)

# Text encoder by GPU. TEXT_ENCODER = "nvfp4" | "int8" | "auto" (default: nvfp4 on Blackwell, else int8)
MMH3_TE_NVFP4="https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"   # 15.7 GB, Blackwell only
# MMH3_TE_NVFP4="https://huggingface.co/Momoking/Qwen3-VL-32B-Heretic-MiniMax-H3-NVFP4/resolve/main/qwen3vl_32b_heretic_minimax_h3_nvfp4.safetensors"   # 15.7 GB, Blackwell only (Uncensored)
MMH3_TE_INT8="https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors"  # 27.1 GB, any GPU

if [ "$(gpu_text_encoder)" = "nvfp4" ]; then
    MODELS+=("text_encoders|$MMH3_TE_NVFP4")
else
    MODELS+=("text_encoders|$MMH3_TE_INT8")
fi
