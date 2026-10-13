# Family: qwen21 — shared by every qwen21-* stack. Append only. Usage notes per LoRA: docs/lora-notes.md
# Workflows use the neutral names qwen_image_2.1 / qwen3vl_8b_heretic; WF_SUBST rewrites names to the files below at install.

# ---- Main model (NVFP4 only) ----

# Diffusion model, 4.2 GB, uncensored (UC) NVFP4 quant. Workflows saved with the UC int8 file are pointed at it.
hf diffusion_models abenzerps/Qwen-Image-2.1-Uncensored-Quantized qwen-image-2.1-UC-NVFP4.safetensors
WF_SUBST+=(
    "qwen-image-2.1-UC-int8_convrot.safetensors|qwen-image-2.1-UC-NVFP4.safetensors"
)

# Text encoder, 6.3 GB, heretic (uncensored). The standard encoder is not downloaded.
hf text_encoders pottokao/Qwen-Image-2.1-Text-Encoder-Heretic-NVFP4 qwen3vl_8b_nvfp4_heretic.safetensors
WF_SUBST+=(
    "qwen3vl_8b_int8_convrot_heretic.safetensors|qwen3vl_8b_nvfp4_heretic.safetensors"
)

# VAE
hf vae Comfy-Org/Qwen-Image-2.1 vae/qwen_image_2.1_vae_bf16.safetensors

# ---- LoRAs (saved names start with qwen21_; Civitai needs CIVITAI_TOKEN, use civitai.red for NSFW) ----

# Speed
# Viggle Turbo v0.3, 6-step
hf loras Viggle/Qwen-Image-2.1-viggle-turbo Qwen-Image-2.1-viggle-turbo-v0.3-6step-lora-r256.safetensors qwen21_viggle-turbo-v0.3-6step-lora-r256.safetensors

# Editing control
# Consistency: keeps unchanged parts of the source (consistency-2000 = tighter)
hf loras ausboss/Qwen-Image-2.1-Consistency-LoRA qwen-image-2.1-consistency.safetensors qwen21_consistency.safetensors
# hf loras ausboss/Qwen-Image-2.1-Consistency-LoRA qwen-image-2.1-consistency-2000.safetensors
# Outpaint v2: pad with gray #808080
hf loras ausboss/Qwen-Image-2.1-Outpaint-LoRA qwen-image-2.1-outpaint-v2.safetensors qwen21_outpaint-v2.safetensors
# Outfit swap, keeps framing/face/pose
hf loras ausboss/Qwen-Image-2.1-Outfit-Swap-Consistency-LoRA qwen-image-2.1-outfit-swap.safetensors qwen21_outfit-swap-consistency.safetensors
# Restore: 1.0 sharp photos, 0.5 blurry
hf loras ausboss/Qwen-Image-2.1-Restore-LoRA qwen-image-2.1-restore.safetensors qwen21_restore.safetensors

# Realism
# Nice Asians, strength 0.6-0.8
hf loras Danrisi/niceasians_qwen2.1 niceasians_qwen21.safetensors qwen21_niceasians.safetensors
# Realism Edit v2, trigger "convert this into a real phone photo"
hf loras houseofboern/realism-qwen-image-2.1-edit-v2 realism-qwen-image-2.1-edit-v2.safetensors qwen21_realism-edit-v2.safetensors

# BFS face/body swap (needs RES4LYF; prompts and settings in the notes)
civitai loras https://civitai.red/api/download/models/3356102?fileId=3248321 qwen21_bfs_head_v1.1.safetensors
civitai loras https://civitai.red/api/download/models/3363725?fileId=3251548 qwen21_bfs_body_swap_v1.0.safetensors

# Sliders
# Skin tone: + darker, - lighter
civitai loras https://civitai.red/api/download/models/3360658?fileId=3248339 qwen21_skin-tone-slider_v1.safetensors
# Pornmaster breasts: + more volume, - less
civitai loras https://civitai.red/api/download/models/3357878?fileId=3245457 qwen21_pornmaster-breasts-slider_v1.safetensors

# NSFW
# NSFW v2.0: er_sde, beta, CFG 3-6
civitai loras https://civitai.red/api/download/models/3357315?fileId=3244894 qwen21_nsfw-lora_v2.0.safetensors
# Vagina v1.0
civitai loras https://civitai.red/api/download/models/3354330?fileId=3241739 qwen21_vagina_v1.0.safetensors
# Nude Edit v3.0, CFG 3 (triggers in the notes)
civitai loras https://civitai.red/api/download/models/3385982?fileId=3274859 qwen21_nude-edit_v3.0.safetensors
# FemaledVaginus v1.3: er_sde, beta, CFG 3
civitai loras https://civitai.red/api/download/models/3388157?fileId=3277181 qwen21_femaledVaginus-nsfw-v1.3.safetensors
