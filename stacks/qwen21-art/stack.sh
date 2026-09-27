# Stack: Qwen Image 2.1 "(N)SFW workflow for your ART" V2.5 (Civitai 2730327)
# Sourced by provision.sh. Only add to the lists here; the download engine lives in provision.sh.
# Workflow: NSFWWorkflowForYour_qwen21V25.json in this folder -> ComfyUI workflows/qwen21-art/.
#   Model/LoRA paths fixed to this stack (no subfolders; bf16 diffusion model + text encoder).
# Base nodes (rgthree, KJNodes, GGUF) come from provision.sh.
# Bypassed features that use models ARE installed (still bypassed in the workflow; enable when needed):
#   SAM3 subject cut/keep, ControlNet refs (canny/depth/pose), prompt enhancer (GGUF LLM), PID 4K upscale.
# Not installed (by choice): Post-processing FX (CRT, Darkroom, Fill, WAS bloom) and Krea moodboard.
#   Those nodes show as missing if you enable them.

NODES+=(
  "https://github.com/ClownsharkBatwing/RES4LYF"                 # ClownSampler_Beta, ClownSamplerSelector_Beta
  "https://github.com/Jonseed/ComfyUI-Detail-Daemon"              # DetailDaemonSamplerNode
  "https://github.com/lonecatone23/ComfyUI_LC123_nodes"           # LCAnySwitch
  "https://github.com/pixaroma/ComfyUI-Pixaroma"                  # PixaromaResolution / Seed / Sliders
  "https://github.com/chrisgoringe/cg-use-everywhere"             # Anything Everywhere
  "https://github.com/DemonAlone/DemonAlone-nodes-ComfyUI"        # AnytoIntegerAdapterNode
  "https://github.com/alexopus/ComfyUI-Image-Saver"               # Image Saver Simple / Metadata
  "https://github.com/giriss/comfy-image-saver"                   # String Literal (older pack; names don't clash with alexopus)
  "https://github.com/yolain/ComfyUI-Easy-Use"                    # easy showAnything / cleanGpuUsed / clearCacheAll
  "https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes"       # CR Text Replace
  "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"       # ShowText|pysssss
  "https://github.com/EllangoK/ComfyUI-post-processing-nodes"     # ChromaticAberration
  "https://github.com/vslinx/ComfyUI-vslinx-nodes"                # vsLinx_AppendLorasFromNodeToString
  "https://github.com/Derfuu/Derfuu_ComfyUI_ModdedNodes"          # DF_Text
  # --- for bypassed features ---
  "https://github.com/Fannovel16/comfyui_controlnet_aux"          # Canny / DepthAnythingV2 / DWPose preprocessors (download their models on first use, ~1.6 GB)
  "https://github.com/aria1th/ComfyUI-LogicUtils"                 # ResizeLongestToNode (reference image groups)
  "https://github.com/capitan01R/Capitan-ConditioningEnhancer"    # CapitanAdvancedEnhancer (in the PID 4K upscale chain)
)

# Format: "subdir|url"  (filename is taken from the URL). bf16 = best quality.
MODELS+=(
  # Diffusion model (14.2 GB) — workflow shipped with int8, pointed here
  "diffusion_models|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/diffusion_models/qwen_image_2.1_bf16.safetensors"
  # Text encoder (17.5 GB) — workflow shipped with int8, pointed here
  "text_encoders|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/text_encoders/qwen3vl_8b_bf16.safetensors"
  # VAE
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
  # Turbo 4-step LoRA (on by default)
  "loras|https://huggingface.co/Viggle/Qwen-Image-2.1-viggle-turbo/resolve/main/Qwen-Image-2.1-viggle-turbo-4step-lora-r64.safetensors"
  # nicegirls v2 (in the Power Lora Loader, off by default)
  "loras|https://huggingface.co/Danrisi/nicegirls2_qwen2.1/resolve/main/nicegirls_v2_qwen21.safetensors"
  # --- bypassed features ---
  # SAM3 subject cut/keep (1.75 GB)
  "checkpoints|https://huggingface.co/Comfy-Org/sam3.1/resolve/main/checkpoints/sam3.1_multiplex_fp16.safetensors"
  # Prompt enhancer LLM for TextGenerate via CLIPLoaderGGUF (8.7 GB)
  "text_encoders|https://huggingface.co/prithivMLmods/Qwen3-VL-8B-Instruct-abliterated-v2-GGUF/resolve/main/Qwen3-VL-8B-Instruct-abliterated-v2.Q8_0.gguf"
  # PID 4K upscale: PixelDiT diffusion model (2.8 GB), gemma text encoder (5.2 GB), Qwen-Image VAE
  "diffusion_models|https://huggingface.co/Comfy-Org/PixelDiT/resolve/main/diffusion_models/pid_1.5_qwenimage_1024_to_4096_4step_bf16.safetensors"
  "text_encoders|https://huggingface.co/Comfy-Org/PixelDiT/resolve/main/text_encoders/gemma_2_2b_it_elm_bf16.safetensors"
  "vae|https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors"
)

# Civitai LoRAs, saved under readable names. Needs CIVITAI_TOKEN.
# Format: "target|url|filename"
CIVITAI+=(
  # NSFW LORA | Qwen Image 2.1 v2.0 (server name: "NSFW Qwen by TheseAlpacas V2") — Power Lora Loader, on
  "loras|https://civitai.red/api/download/models/3357315?fileId=3244894|qwen21_nsfw-lora_v2.0.safetensors"
  # qwen 2.1 vagina v1.0 (server name: qwen21_v2_000002750) — Power Lora Loader, on
  "loras|https://civitai.red/api/download/models/3354330?fileId=3241739|qwen21_vagina_v1.0.safetensors"
  # Pornmaster Qwen Image 2.1 Breasts Slider V1 — not in the workflow; add it to the Power Lora Loader to use
  "loras|https://civitai.red/api/download/models/3346363?fileId=3233286|qwen21_pornmaster-breasts-slider_v1.safetensors"
)
