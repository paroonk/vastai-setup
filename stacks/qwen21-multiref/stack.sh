# Stack: Qwen Image 2.1 Multi-Reference Editing (huchukato, Civitai v1.1)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflow zip (Civitai) extracts to ComfyUI workflows/. Any *.json in this folder -> workflows/qwen21-multiref/.
# Base nodes (rgthree, KJNodes, GGUF) come from provision.sh.

# QwenVL enhancer runs in GGUF mode: vision-capable llama-cpp.
# Same entry as mmh3-dasiwa; installed once when both stacks are selected.
PIP_PACKAGES+=(
    "--upgrade --force-reinstall --no-cache-dir https://github.com/JamePeng/llama-cpp-python/releases/download/v0.4.1-cu131-linux-20260926/llama_cpp_python-0.4.1+cu131-cp312-cp312-linux_x86_64.whl"
)

NODES+=(
  "https://github.com/huchukato/ComfyUI-TagForge"      # WildcardProcessor + qwen21 wildcard library
  "https://github.com/huchukato/ComfyUI-QwenVL-Mod"    # QwenVL Unified prompt enhancer
  "https://github.com/pixaroma/ComfyUI-Pixaroma"       # Show Text + Compare nodes used by the workflow
)

# Format: "subdir|url"  (filename is taken from the URL). bf16 = best quality (~32.5 GB).
MODELS+=(
  # Diffusion model (14.2 GB)
  "diffusion_models|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/diffusion_models/qwen_image_2.1_bf16.safetensors"
  # Text encoder (17.5 GB)
  "text_encoders|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/text_encoders/qwen3vl_8b_bf16.safetensors"
  # VAE
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
  # Detailer LoRA for __qwen21/enhance__ (~80 MB)
  "loras|https://huggingface.co/reverentelusarca/elusarcas-qwen-2.1-detail-enhancer-lora/resolve/main/elusarcas-qwen2-1-detailer-v1.safetensors"
  # QwenVL enhancer LLM (GGUF) + vision projector — same files as mmh3-dasiwa, downloaded once
  "llm/GGUF|https://huggingface.co/DavidAU/Qwen3.5-9B-The-Defiant-Fable-Uncensored-Heretic-NEO-IMATRIX-MAX-MTP-GGUF/resolve/main/Qwen3.5-9B-The-Defiant-Fable-Uncnr-Heretic-NEO-MAX-Q8_0.gguf"
  "llm/GGUF|https://huggingface.co/DavidAU/Qwen3.5-9B-The-Defiant-Fable-Uncensored-Heretic-NEO-IMATRIX-MAX-MTP-GGUF/resolve/main/mmproj-F16.gguf"
)

# Civitai files. Needs CIVITAI_TOKEN.  Format: "target|url"
CIVITAI+=(
  # QwenImageEdit21 v1.1 workflow (QwenImageEdit21-Wildcards-Qwen3.5.json.zip) — auto-extracted
  "workflows|https://civitai.red/api/download/models/3353811?fileId=3246053"
)
