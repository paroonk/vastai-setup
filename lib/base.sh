# Base install: what every stack gets. Sourced by provision.sh after dsl.sh. Stacks and families append to these lists.

APT_PACKAGES+=(
    "ffmpeg"
    "aria2"
)

PIP_PACKAGES+=(
    "huggingface_hub[hf_xet]"
    "sageattention"
)

# Custom nodes every stack uses (github owner/repo)
node rgthree/rgthree-comfy
node kijai/ComfyUI-KJNodes
node city96/ComfyUI-GGUF
node ClownsharkBatwing/RES4LYF
node chrisgoringe/cg-use-everywhere
node ltdrdata/ComfyUI-Inspire-Pack
node WASasquatch/was-node-suite-comfyui
node crystian/comfyui-crystools
node PGCRT/CRT-Nodes
node AlexYez/comfyui-artius-browser
node ausboss/ComfyUI-AusBoss
node yolain/ComfyUI-Easy-Use
node ltdrdata/ComfyUI-Impact-Pack
node Suzie1/ComfyUI_Comfyroll_CustomNodes
