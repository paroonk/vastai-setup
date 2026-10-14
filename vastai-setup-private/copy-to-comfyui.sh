#!/bin/bash
# Run on the Vast.ai instance: copy the uploaded private folders into ComfyUI.
#   bash copy-to-comfyui.sh [ComfyUI folder]        (default /workspace/ComfyUI; folders are read from this script's directory)
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMFY="${1:-/workspace/ComfyUI}"
[ -d "$COMFY/custom_nodes" ] || { echo "$COMFY has no custom_nodes folder"; exit 1; }

copy() {   # copy <folder> <destination parent under ComfyUI>: nodes are replaced, other folders merged
    if [ ! -d "$SRC/$1" ]; then echo "skipped: $1 is not next to this script"; return; fi
    mkdir -p "$COMFY/$2"
    if [ "$2" = "custom_nodes" ]; then
        rm -rf "$COMFY/$2/$1"
        cp -r "$SRC/$1" "$COMFY/$2/$1" && echo "$1 -> $COMFY/$2/$1"
    else
        mkdir -p "$COMFY/$2/$1"
        cp -r "$SRC/$1/." "$COMFY/$2/$1/" && echo "$1 -> $COMFY/$2/$1 (merged)"
    fi
}

copy comfyui-obvpm-pro-extensions custom_nodes
copy refmods models

if [ -f "$COMFY/custom_nodes/comfyui-obvpm-pro-extensions/requirements.txt" ]; then
    pip install -r "$COMFY/custom_nodes/comfyui-obvpm-pro-extensions/requirements.txt"
fi
echo "Done. Restart ComfyUI: supervisorctl restart comfyui"
