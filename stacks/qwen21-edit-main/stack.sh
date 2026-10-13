# Stack: qwen21-edit-main (work in progress)
# Sourced by provision.sh. Append only (hf, civitai, node, ...; see lib/dsl.sh).
# *.json in this folder -> ComfyUI workflows/qwen21-edit-main/ (edit + prompt-enhancer, outpaint, rotate; saved as the author made them).
# A sub-folder here would be a custom node, copied to ComfyUI/custom_nodes/ in the last step (install_stack_nodes in lib/stacks.sh).

node Fannovel16/comfyui_controlnet_aux
node AHEKOT/ComfyUI_VNCCS_Utils
node benjiyaya/ComfyUI-Qwen-Image-2.1-Prompt-Enhancer

# VNCCS Pose Studio: 3D posing, framing, lighting and pose-library environment
hf loras MIUProject/VNCCS_PoseStudio_QI2.1 VNCCS_QI2_PoseStudioV1.1.safetensors
# SAM 3.1 (segmentation), 1.7 GB. Loaded by the edit workflow's checkpoint loader (bypassed by default). Licence tag: other.
hf checkpoints Comfy-Org/sam3.1 checkpoints/sam3.1_multiplex_fp16.safetensors
