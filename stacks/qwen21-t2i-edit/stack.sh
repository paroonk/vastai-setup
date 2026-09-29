# Stack: Qwen Image 2.1 Workflows (T2I + Edit) with SageAttention, by StefanFalkok (Civitai 2951890, v1.1 Edit Resolution)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflows -> ComfyUI workflows/qwen21-t2i-edit/: _text-to-image and _image-edit (each also with _prompt-enhancer), _seedvr2-upscale.
# Changes: models -> bf16 (path "qwenimage21\" removed); the enhancer
#   workflows' Gemma 4 12B encoder (13 GB) -> qwen3vl_8b_bf16_heretic (from families/qwen21), CLIP type -> qwen_image.
#   The author's enhancer prompt text is an LTX-video prompt template, left as shipped.
# LoRAs: the workflows use LoRA Manager, which reads whatever is in loras/ (families/qwen21/loras.sh).
# SeedVR2 models go to models/SEEDVR2 (the node would also fetch them on first run).

NODES+=(
  "https://github.com/WASasquatch/was-node-suite-comfyui"         # Image Save
  "https://github.com/willmiao/ComfyUI-Lora-Manager"              # Lora Loader / Prompt / TriggerWord Toggle (LoraManager)
  "https://github.com/pixaroma/ComfyUI-Pixaroma"                  # PixaromaLabel
  "https://github.com/yolain/ComfyUI-Easy-Use"                    # easy prompt
  "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"       # ShowText|pysssss
  "https://github.com/alexopus/ComfyUI-Image-Saver"               # Seed Generator (registry id: comfy-image-saver)
  "https://github.com/1038lab/ComfyUI-RMBG"                       # AILab_ImageStitch
  "https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler"         # SeedVR2 upscaler
  "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"       # VHS nodes (SeedVR2 workflow)
)

MODELS+=(
  # Diffusion model (14.2 GB) and VAE — bf16, shared by every qwen21 stack. The text encoder is the heretic bf16
  # (families/qwen21/loras.sh), which every workflow's CLIP loader points at.
  # The workflow shipped with int8 (7.3 / 9.4 GB); pointed at bf16 here.
  "diffusion_models|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/diffusion_models/qwen_image_2.1_bf16.safetensors"
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
  # SeedVR2 upscale: 7B sharp fp16 (16.5 GB, active), 3B fp16 (6.8 GB, bypassed alternative), VAE (0.5 GB)
  "SEEDVR2|https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_7b_sharp_fp16.safetensors"
  "SEEDVR2|https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_3b_fp16.safetensors"
  "SEEDVR2|https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors"
)
