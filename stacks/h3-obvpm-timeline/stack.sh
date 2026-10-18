# Stack: MiniMax H3 OBVPM Timeline (chanon/comfyui-obvpm-timeline)
# Sourced by provision.sh. Append only (hf, civitai, node, ...; see lib/dsl.sh).
# Generate / extend / prepend / bridge / edit videos on a timeline, with a one-pass latent upscale.
# Needs ComfyUI 0.35.0+ (core "Model Sparse Attention" node).
# Base nodes (see NODES in lib/base.sh) are installed for every stack.
# Models (diffusion model, VAEs, TAE, latent upscaler, text encoder) and Turbo LoRAs live in families/h3/family.sh (loaded with every h3-* stack).
#
# Workflows in this folder (installed to ComfyUI workflows/h3-obvpm-timeline/):
#   RefMod - Audio.json, RefMod - Images.json   extract/save RefMods (ComfyUI-MiniMaxH3Mod; VAEs from the h3 family)
#
# Not installed by this repo: comfyui-obvpm, comfyui-obvpm-timeline, comfyui-obvpm-pro-extensions.
# Upload them to ComfyUI/custom_nodes yourself.
node Larryvrh/ComfyUI-MiniMax-H3-Turbo            # Turbo LoRA loader
node xmarre/ComfyUI-Spectrum-MiniMax-H3           # Spectrum acceleration
node Luisacaotica/ComfyUI-MiniMaxH3Mod            # RefMod loader/apply (the -refmod workflows; mods go in models/refmods)
