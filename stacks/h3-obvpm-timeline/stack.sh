# Stack: MiniMax H3 OBVPM Timeline (chanon/comfyui-obvpm-timeline)
# Sourced by provision.sh. Append only (hf, civitai, node, ...; see lib/dsl.sh).
# Generate / extend / prepend / bridge / edit videos on a timeline, with a one-pass latent upscale.
# Needs ComfyUI 0.35.0+ (core "Model Sparse Attention" node).
# Base nodes (see NODES in lib/base.sh) are installed for every stack.
# Models (diffusion model, VAEs, TAE, latent upscaler, text encoder) and Turbo LoRAs live in families/h3/family.sh (loaded with every h3-* stack).
#
# Workflows in this folder (all installed to ComfyUI workflows/h3-obvpm-timeline/):
#   h3_obvpm_timeline_r2v_v0.3.0-010.json                   plain timeline
#   h3_obvpm_timeline_r2v_v0.3.0-010-pro.json               + Pro extensions (high-quality copy, schedule preview)
#   h3_obvpm_timeline_r2v_v0.3.0-010-pro-refmod.json        + RefMods (needs ComfyUI-MiniMaxH3Mod)
#   h3_obvpm_timeline_r2v_v0.3.0-010-pro-refmod-picker.json + visual RefMod picker
# All are the author's files as shipped (GPL-3.0, chanon/comfyui-obvpm-timeline); LoRA names inside them are the h3_<name> files from families/h3/family.sh.

# Bundled in this folder (copied to custom_nodes in the last step, so no `node` line):
#   comfyui-obvpm-timeline (timeline node, pins, joint render, upscale pass), comfyui-obvpm (bundles, presets, switches/gates),
#   comfyui-obvpm-pro-extensions (needs comfyui-obvpm-timeline 0.3.0+).
node Larryvrh/ComfyUI-MiniMax-H3-Turbo            # Turbo LoRA loader
node xmarre/ComfyUI-Spectrum-MiniMax-H3           # Spectrum acceleration
node Luisacaotica/ComfyUI-MiniMaxH3Mod            # RefMod loader/apply (the -refmod workflows; mods go in models/refmods)

