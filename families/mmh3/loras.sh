# Family: mmh3 — LoRAs loaded whenever ANY stack named mmh3-* is selected.
# Sourced by provision.sh (after the stacks). Only append (+=).
# Add a MiniMax H3 LoRA here once and every mmh3 stack gets it. All go to loras/ (no subfolders).

# Format: "subdir|url"  (filename is taken from the URL)
MODELS+=(
  # MysticXXX MMH3 v1
  "loras|https://huggingface.co/noname1992/loras/resolve/main/MysticXXX_MMH3-V1.safetensors"
  # Turbo LoRAs (obvpm timeline presets)
  "loras|https://huggingface.co/lightx2v/Minimax-h3-Turbo/resolve/main/minimax_h3_fl2v_turbo_4step_v1.0_768p_comfyui_bf16.safetensors"
  "loras|https://huggingface.co/lightx2v/Minimax-h3-Turbo/resolve/main/minimax_h3_ref2v_turbo_8step_v1.0_768p_comfyui_bf16.safetensors"  # "vanilla" presets
  "loras|https://huggingface.co/Kijai/MiniMax-H3_comfy/resolve/098f8c48fccead9a93191c166ca31a130659d3bd/loras/minimax_h3_ref2v_lightx2v_turbo_4step_v0.1_resized_avg_rank_20_bf16.safetensors"  # "lightx2v" preset (pinned commit)
  "loras|https://huggingface.co/Robert1212star/TaoMate-H3-3Step-ComfyUI/resolve/main/taomate_h3_3step_comfy.safetensors"  # "taomate 3 step refine" preset
  "loras|https://huggingface.co/Momoking/MiniMax-H3-Turbo-Lora-ComfyUI/resolve/main/minimax_h3_turbo_v4_step600_ema_pruned_comfyui.safetensors"
)

# Civitai LoRAs (filename comes from the server). Needs CIVITAI_TOKEN.
CIVITAI+=(
  # Minimax H3 Turbo LoRA (turbo-multistep-v2) — DaSiWa
  "loras|https://civitai.red/api/download/models/3357658?fileId=3245274"
)
