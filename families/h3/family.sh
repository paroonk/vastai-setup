# Family: h3 — shared by every h3-* stack. Append only. Usage notes per LoRA: docs/lora-notes.md

# ---- Main model ----

# Diffusion model (reference-to-video)
hf diffusion_models Comfy-Org/MiniMax-H3 diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors
# Text encoder, NVFP4 only, 15.7 GB. Uncensored alternative: Momoking/Qwen3-VL-32B-Heretic-MiniMax-H3-NVFP4
hf text_encoders Comfy-Org/MiniMax-H3 text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors
# VAE: video fp16 + int8 (v0.3 loads both), audio
hf vae Comfy-Org/MiniMax-H3 vae/minimax_h3_video_vae_fp16.safetensors
hf vae Kijai/MiniMax-H3-experimental minimax_h3_video_vae_int8_convrot.safetensors
hf vae Comfy-Org/MiniMax-H3 vae/minimax_h3_audio_vae_fp32.safetensors

# ---- Others ----

# Latent upscaler: node pack + fp16 model (v0.3 workflows)
node LBH-123-AI/Comfyui_Minimax_h3_latent_Upscaler
hf latent_upscale_models LBH-123-AI/Minimax_h3_latent_Upscaler minimax_h3_latent_upscaler_3d_conv_v1/minimax_h3_latent_upscaler_3d_conv_v1_fp16.safetensors
# TAE preview (taehv, pinned commit)
github vae_approx madebyollin/taehv@62f7591f59dfbb4c3c02b7a621d180a9eeaba26c safetensors/taeh3.safetensors

# ---- LoRAs ----

# Turbo (obvpm timeline presets). All LoRAs are saved as h3_<name>; the workflows load them by those names.
hf loras lightx2v/Minimax-h3-Turbo minimax_h3_fl2v_turbo_4step_v1.0_768p_comfyui_bf16.safetensors h3_fl2v_turbo_4step_v1.0_768p_comfyui_bf16.safetensors
hf loras lightx2v/Minimax-h3-Turbo minimax_h3_ref2v_turbo_8step_v1.0_768p_comfyui_bf16.safetensors h3_ref2v_turbo_8step_v1.0_768p_comfyui_bf16.safetensors  # "vanilla" presets
hf loras Kijai/MiniMax-H3_comfy@098f8c48fccead9a93191c166ca31a130659d3bd loras/minimax_h3_ref2v_lightx2v_turbo_4step_v0.1_resized_avg_rank_20_bf16.safetensors h3_ref2v_lightx2v_turbo_4step_v0.1_resized_avg_rank_20_bf16.safetensors  # "lightx2v" preset (pinned commit)
hf loras Robert1212star/TaoMate-H3-3Step-ComfyUI taomate_h3_3step_comfy.safetensors h3_taomate_3step_comfy.safetensors  # "taomate 3 step refine" preset
# Turbo v4 step600 (larryvrh): strength 1.0, 6-8 steps. The workflows' Turbo LoRA loader uses this file
hf loras larryvrh/MiniMax-H3-Turbo-Lora minimax_h3_turbo_v4_step600_ema.safetensors h3_turbo_v4_step600_ema.safetensors

# Realism and character swap
# People realism: prefix r34l1sm, strength 1.0
hf loras fal/MiniMax-H3-Realism-People-LoRA h3-realism-people-t2v-i2v-r2v.safetensors h3_realism_people.safetensors
# Character swap: needs Ref2VA base, strength 1.0
hf loras akatz-ai/MiniMax-H3-Character-Swap-LoRA h3_character_swap_pro4500_1000.safetensors h3_character_swap.safetensors

# Style
hf loras noname1992/loras MysticXXX_MMH3-V1.safetensors h3_mysticxxx_v1.safetensors
