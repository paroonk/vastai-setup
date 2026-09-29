# Stack: Lonecats Qwen 2.1 Fast Workflow w/ upscalers and post processing (Civitai 2960068, v1.0 Beta)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflow: qwen21-lonecats-fast_upscale-postprocess.json -> ComfyUI workflows/qwen21-lonecats-fast/ (model paths flattened: the author's
#   "Qwen\..." subfolder prefixes removed). Turbo LoRA is bypassed by default (switch on).
# LoRAs come from families/qwen21/family.sh. Nodes: base (rgthree, KJNodes Get/SetNode, GGUF) + the packs below.
# Not downloaded: the bypassed GGUF diffusion model (qwenImage21GGUF_v10_q80) and BiRefNet (LCRemBG, bypassed; auto-downloads).
# First run of the VOSR2 loader auto-downloads its ~7 GB bundle (models/vosr2/VOSR2) from CSWRY/VOSR — takes ~5 min.

# LC Vision loads GGUF through the vision-capable llama-cpp (same wheel as mmh3-dasiwa)
PIP_PACKAGES+=(
    "--upgrade --force-reinstall --no-cache-dir https://github.com/JamePeng/llama-cpp-python/releases/download/v0.4.1-cu131-linux-20260926/llama_cpp_python-0.4.1+cu131-cp312-cp312-linux_x86_64.whl"
)

NODES+=(
  "https://github.com/lonecatone23/ComfyUI_LC123_nodes"          # LC* nodes, sample LUTs (LC_Crushed_Blacks.cube)
  "https://github.com/lonecatone23/ComfyUI_LC_Vision_nodes"      # LC Vision Loader / Caption / Prompt Enhancer
  "https://github.com/lonecatone23/ComfyUI_LC_MaskMaker_nodes"   # LCRemBG
  "https://github.com/ClownsharkBatwing/RES4LYF"                 # ClownSampler, Sigmas Gaussian / Hyperbolic
  "https://github.com/Jonseed/ComfyUI-Detail-Daemon"             # DetailDaemonSamplerNode
  "https://github.com/erosDiffusion/ComfyUI-EulerDiscreteScheduler"  # FlowMatchEulerDiscreteScheduler (Custom)
  "https://github.com/Smirnov75/ComfyUI-mxToolkit"               # mxSlider
  "https://github.com/vslinx/ComfyUI-vslinx-nodes"               # vsLinx_BooleanFlip
  "https://github.com/ylchen333/ComfyUI-VOSR2"                   # VOSR2ModelLoader / VOSR2Upscale (4x one-step upscaler)
)

MODELS+=(
  # VAE, shared by every qwen21 stack. The diffusion model and the heretic text encoder come from families/qwen21/family.sh
  # (NVFP4 by default), and the workflows' neutral names (qwen_image_2.1 / qwen3vl_8b_heretic) are rewritten to them at install.
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
  # LC Vision model (Qwen3-VL-4B abliterated Q4_K_M + f16 mmproj, 2.5 + 0.8 GB) — own folder so its mmproj pairs correctly
  "LLM/Qwen3-VL-4B-abliterated|https://huggingface.co/mradermacher/Qwen3-VL-4B-Instruct-c_abliterated-v2-GGUF/resolve/main/Qwen3-VL-4B-Instruct-c_abliterated-v2.Q4_K_M.gguf"
  "LLM/Qwen3-VL-4B-abliterated|https://huggingface.co/mradermacher/Qwen3-VL-4B-Instruct-c_abliterated-v2-GGUF/resolve/main/Qwen3-VL-4B-Instruct-c_abliterated-v2.mmproj-f16.gguf"
)
