# Helpers for writing stack.sh / family.sh files. Sourced by provision.sh.
# Each helper appends one entry to a list declared in config.sh, so stack files never touch the lists directly.

# Download helpers all read the same way: the models subfolder, then the source, then an optional saved name.
#
#   hf      <models-subfolder> <repo[@revision]> <path-in-repo> [saved-name]     Hugging Face file
#   github  <models-subfolder> <repo[@revision]> <path-in-repo> [saved-name]     file in a GitHub repo (raw)
#   model   <models-subfolder> <url> [saved-name]                                any other direct URL
#   civitai <models-subfolder | workflows> <download-url> [saved-name]           Civitai (civitai.red or .com), URL as pasted
#
#   hf vae Comfy-Org/MiniMax-H3 vae/minimax_h3_audio_vae_fp32.safetensors
#   hf loras ausboss/Qwen-Image-2.1-Outpaint-LoRA qwen-image-2.1-outpaint-v2.safetensors qwen21_outpaint-v2.safetensors
#   civitai loras https://civitai.red/api/download/models/3357315?fileId=3244894 qwen21_nsfw-lora_v2.0.safetensors
# Revision: hf defaults to main, github to the default branch (HEAD). Pin a commit with repo@hash.
# Without saved-name the file keeps its own name (Civitai: the server's name).

hf() {
    local repo="$2" path="$3" rev=main
    [[ "$repo" == *@* ]] && { rev="${repo#*@}"; repo="${repo%%@*}"; }
    MODELS+=("$1|https://huggingface.co/$repo/resolve/$rev/$path${4:+|$4}")
}

github() {
    local repo="$2" path="$3" rev=HEAD
    [[ "$repo" == *@* ]] && { rev="${repo#*@}"; repo="${repo%%@*}"; }
    MODELS+=("$1|https://raw.githubusercontent.com/$repo/$rev/$path${4:+|$4}")
}

model()   { MODELS+=("$1|$2${3:+|$3}"); }

civitai() { CIVITAI+=("$1|$2${3:+|$3}"); }

# private <comfy-subpath> <folder>   -- a folder that must NOT be published (licence, personal files). Not downloaded:
#   you put it in the private dir on the instance ($PRIVATE_DIR, default /workspace/vastai-setup-private), and the last
#   step copies it to ComfyUI/<comfy-subpath>/<folder>. Missing folder = skipped with a log line.
#   private custom_nodes comfyui-obvpm-pro-extensions
#   private models refmods
private() { PRIVATE+=("$1|$2"); }

# node <github-owner/repo | full git URL>   -- custom node, cloned into ComfyUI/custom_nodes
node() { case "$1" in http*) NODES+=("$1");; *) NODES+=("https://github.com/$1");; esac; }

# Vision-capable llama-cpp wheel, needed by nodes that run GGUF LLMs (e.g. Prompt Forge, LC Vision)
pip_llama_cpp() {
    PIP_PACKAGES+=("--upgrade --force-reinstall --no-cache-dir https://github.com/JamePeng/llama-cpp-python/releases/download/v0.4.1-cu131-linux-20260926/llama_cpp_python-0.4.1+cu131-cp312-cp312-linux_x86_64.whl")
}
