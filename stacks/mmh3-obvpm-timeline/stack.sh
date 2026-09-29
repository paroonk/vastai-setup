# Stack: MiniMax H3 OBVPM Timeline (chanon/comfyui-obvpm-timeline)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Generate / extend / prepend / bridge / edit videos on a timeline, with a one-pass latent upscale.
# Needs ComfyUI 0.35.0+ (core "Model Sparse Attention" node).
# Base nodes (rgthree, KJNodes, GGUF) come from provision.sh.
# Turbo LoRAs live in families/mmh3/family.sh (loaded with every mmh3-* stack).
# MiniMax H3 base files below are the same as mmh3-dasiwa; downloaded once when both are selected.

NODES+=(
  "https://github.com/chanon/comfyui-obvpm-timeline"               # Timeline node, pins, joint render, upscale pass
  "https://github.com/chanon/comfyui-obvpm"                        # Bundles, Settings Presets, switches/gates (needs 0.2.9+)
  "https://github.com/LBH-123-AI/Comfyui_Minimax_h3_latent_Upscaler" # original pack, NOT the "Plus" fork (breaks the upscale pass)
  "https://github.com/Larryvrh/ComfyUI-MiniMax-H3-Turbo"            # Turbo LoRA loader
  "https://github.com/xmarre/ComfyUI-Spectrum-MiniMax-H3"           # Spectrum acceleration
)

# Workflow: mmh3-obvpm-timeline_r2v_v0.1.1.json from chanon/comfyui-obvpm-timeline (GPL-3.0, upstream 4a027a0);
#   h3\ LoRA prefixes removed, latent upscaler pointed at the conv_v1_bf16 file below (author uses fp16).

# Format: "subdir|url"  (filename is taken from the URL)
MODELS+=(
  # Diffusion model: reference-to-video (the timeline is r2v)
  "diffusion_models|https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors"
  # Video + audio VAE, TAE preview
  "vae|https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_fp16.safetensors"
  "vae|https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors"
  "vae_approx|https://huggingface.co/Kijai/MiniMax-H3-TAE/resolve/main/vae_approx/taeh3.safetensors"
  # Latent upscaler (official, bf16). The saved workflow points at this file.
  "latent_upscale_models|https://huggingface.co/LBH-123-AI/Minimax_h3_latent_Upscaler/resolve/main/minimax_h3_latent_upscaler_3d_conv_v1/minimax_h3_latent_upscaler_3d_conv_v1_bf16.safetensors"
)

# Text encoder by GPU, same choice and files as mmh3-dasiwa (TEXT_ENCODER env var).
if [ "$(gpu_text_encoder)" = "nvfp4" ]; then
    MODELS+=("text_encoders|https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors")
else
    MODELS+=("text_encoders|https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors")
fi
