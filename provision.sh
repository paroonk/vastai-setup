#!/bin/bash
# Vast.ai PROVISIONING_SCRIPT — ComfyUI, stack-based
# Set PROVISIONING_SCRIPT to:
#   https://raw.githubusercontent.com/paroonk/vastai-setup/main/provision.sh
#
# Template env vars:
#   STACKS         - which stacks to install: "mmh3", "mmh3,qwen21", or "all" (default: all)
#                    Each stack = stacks/<name>/stack.sh (nodes, models) + its workflow JSONs.
#   CIVITAI_TOKEN  - Civitai API key (required for Civitai downloads)
#   HF_TOKEN       - HuggingFace token (needed only for gated/private repos)
#   TEXT_ENCODER   - "nvfp4" | "int8" | "auto" (default auto: nvfp4 on Blackwell, else int8)
#   AUTO_UPDATE    - "false" to skip git pull on existing custom nodes
#   SETUP_REF      - branch or tag of this repo to use for stacks (default: main)
#   SETUP_REPO     - repo URL override (default: paroonk/vastai-setup on GitHub)

# No `set -e`: one flaky download must not abort a 70+ GB provisioning run.
set -o pipefail

source /venv/main/bin/activate

WORKSPACE="${WORKSPACE:-/workspace}"
COMFY="${WORKSPACE}/ComfyUI"
M="${COMFY}/models"
FAILED=()

SETUP_REPO="${SETUP_REPO:-https://github.com/paroonk/vastai-setup.git}"
SETUP_REF="${SETUP_REF:-main}"
STACKS="${STACKS:-all}"
REPO_DIR="$WORKSPACE/.tmp_setup_repo"
SELECTED=()   # stacks actually loaded

# ============================================================
# BASE CONFIG — installed for every stack. Stacks add to these lists.
# ============================================================

APT_PACKAGES=(
    "ffmpeg"
    "aria2"
)

# Each entry is passed to pip unquoted, so an entry may carry its own flags.
PIP_PACKAGES=(
    "huggingface_hub[hf_xet]"
    "sageattention"
)

NODES=()
MODELS=()     # "subdir|url"
CIVITAI=()    # "target|url"

### ============================================================
### FUNCTIONS — download engine (unchanged from the original gist)
### ============================================================

log() { echo -e "\n==========================================\n$*\n=========================================="; }

check_disk() {
    local free_gb
    free_gb=$(df -BG --output=avail "$WORKSPACE" | tail -1 | tr -dc '0-9')
    echo "Free disk on $WORKSPACE: ${free_gb} GB"
    if [ "${free_gb:-0}" -lt 100 ]; then
        echo "WARNING: <100 GB free. Full set needs ~70-80 GB. Downloads may fail."
    fi
}

install_apt() {
    local missing=()
    for p in "${APT_PACKAGES[@]}"; do
        # dpkg check, not command -v: the aria2 package installs "aria2c", not "aria2"
        dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    [ ${#missing[@]} -eq 0 ] && { echo "APT packages already present."; return; }
    local SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
    $SUDO apt-get update && $SUDO apt-get install -y "${missing[@]}" \
        || FAILED+=("apt: ${missing[*]}")
}

install_pip() {
    set -f   # no globbing: "huggingface_hub[hf_xet]" must not be treated as a file pattern
    for p in "${PIP_PACKAGES[@]}"; do
        echo "Installing: $p"
        # $p unquoted on purpose so entries can include their own pip flags
        pip install --root-user-action=ignore --no-cache-dir $p || FAILED+=("pip: $p")
    done
    set +f
}
install_nodes() {
    mkdir -p "$COMFY/custom_nodes"
    for repo in "${NODES[@]}"; do
        local name="${repo##*/}"
        local path="$COMFY/custom_nodes/$name"
        log "Custom node: $name"

        if [ -d "$path/.git" ]; then
            if [ "${AUTO_UPDATE,,}" = "false" ]; then
                echo "Exists, AUTO_UPDATE=false -> skip"
                continue
            fi
            git -C "$path" pull --ff-only || echo "WARN: pull failed for $name, keeping current version"
        else
            git clone --recursive "$repo" "$path" || { FAILED+=("node: $name"); continue; }
        fi

        if [ -f "$path/requirements.txt" ]; then
            pip install --root-user-action=ignore --no-cache-dir -r "$path/requirements.txt" \
                || FAILED+=("node reqs: $name")
        fi
    done
}
# HF files: hf CLI (Xet, parallel, resumable). Downloads into a hidden temp dir and
# moves into place only on success, so "final file exists" == "download complete".
download_hf() {
    local url="$1" dest="$2"
    local repo_id repo_path tmp
    repo_id=$(echo "$url" | awk -F/ '{print $4"/"$5}')
    repo_path=$(echo "$url" | sed -E 's#https?://[^/]+/[^/]+/[^/]+/resolve/[^/]+/(.+)#\1#')
    tmp="$M/.tmp_hf/${repo_id//\//_}"
    mkdir -p "$tmp"

    HF_XET_HIGH_PERFORMANCE=1 hf download "$repo_id" "$repo_path" --local-dir "$tmp" \
        && [ -f "$tmp/$repo_path" ] \
        && mv -f "$tmp/$repo_path" "$dest"
}

# Non-HF files: wget to .part, move on success.
download_wget() {
    local url="$1" dest="$2"
    wget -c -q --show-progress -O "$dest.part" "$url" && mv -f "$dest.part" "$dest"
}

download_models() {
    for entry in "${MODELS[@]}"; do
        IFS='|' read -r subdir url <<< "$entry"
        local name="${url##*/}"
        local dest="$M/$subdir/$name"
        mkdir -p "$M/$subdir"

        if [ -f "$dest" ]; then
            echo "OK (exists): $subdir/$name"
            continue
        fi

        log "Downloading: $subdir/$name"
        local ok=1
        if [[ "$url" =~ ^https://huggingface\.co/ ]]; then
            download_hf "$url" "$dest" || ok=0
        else
            download_wget "$url" "$dest" || ok=0
        fi

        # Guard: a wrong link (e.g. /blob/) returns an HTML page, not a model
        if [ $ok -eq 1 ] && head -c 512 "$dest" | grep -qi "<html"; then
            echo "ERROR: $name is an HTML page. Check the URL."
            rm -f "$dest"; ok=0
        fi

        [ $ok -eq 1 ] || FAILED+=("model: $subdir/$name")
    done
    # Keep temp dir if anything failed, so a re-run can resume partial files
    [ ${#FAILED[@]} -eq 0 ] && rm -rf "$M/.tmp_hf" 2>/dev/null
    return 0
}

# Civitai: filename unknown until download, so a marker file tracks completion
# (keyed by URL) and re-runs skip finished items.
download_civitai() {
    local wf_dir="$COMFY/user/default/workflows"
    for entry in "${CIVITAI[@]}"; do
        IFS='|' read -r target url <<< "$entry"
        local dest
        if [ "$target" = "workflows" ]; then dest="$wf_dir"; else dest="$M/$target"; fi
        mkdir -p "$dest"
 
        local key marker tmp
        key=$(echo -n "$url" | md5sum | cut -c1-12)
        marker="$dest/.civitai_${key}.done"
        if [ -f "$marker" ]; then
            echo "OK (exists): civitai $target $(cat "$marker")"
            continue
        fi
 
        log "Downloading (Civitai): $target"
        if [ -z "${CIVITAI_TOKEN:-}" ]; then
            echo "ERROR: CIVITAI_TOKEN not set."
            FAILED+=("civitai: $target ($url) — no token"); continue
        fi
 
        tmp="$WORKSPACE/.tmp_civitai/$key"
        rm -rf "$tmp"; mkdir -p "$tmp"
        # curl, not wget: wget forwards the Authorization header to Civitai's
        # signed storage redirect, which then rejects it with HTTP 400.
        # curl drops the header on cross-host redirects; -J uses the server filename.
        if ! (cd "$tmp" && curl -fL -J -O --retry 3 \
                -H "Authorization: Bearer $CIVITAI_TOKEN" "$url"); then
            FAILED+=("civitai: $target ($url)"); rm -rf "$tmp"; continue
        fi
 
        local file
        file=$(find "$tmp" -maxdepth 1 -type f | head -1)
        if [ -z "$file" ] || head -c 512 "$file" | grep -qi "<html"; then
            echo "ERROR: got an HTML page or nothing (bad token / link?)"
            FAILED+=("civitai: $target ($url)"); rm -rf "$tmp"; continue
        fi
 
        local name="${file##*/}"
        if [[ "$name" == *.zip ]]; then
            python -m zipfile -e "$file" "$dest" || { FAILED+=("civitai unzip: $name"); rm -rf "$tmp"; continue; }
            echo "Extracted $name -> $dest"
        else
            mv -f "$file" "$dest/$name"
            echo "Saved $dest/$name"
        fi
        echo "$name" > "$marker"
        rm -rf "$tmp"
    done
    rm -rf "$WORKSPACE/.tmp_civitai" 2>/dev/null
    return 0
}

check_civitai_token() {
    if [ -z "${CIVITAI_TOKEN:-}" ]; then
        echo "CIVITAI_TOKEN not set: Civitai downloads will be skipped."
        return
    fi
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" "https://civitai.com/api/v1/models?hidden=1&limit=1")
    [ "$code" = "200" ] && echo "CIVITAI_TOKEN valid." || echo "WARNING: CIVITAI_TOKEN check returned HTTP $code."
}

summary() {
    log "Provisioning finished"
    du -sh "$M"/*/ 2>/dev/null

    if [ ${#FAILED[@]} -gt 0 ]; then
        echo -e "\n!!! ${#FAILED[@]} item(s) FAILED:"
        printf '  - %s\n' "${FAILED[@]}"
        echo "Re-run this script from the terminal to retry; completed files are skipped."
    else
        echo -e "\nAll items OK."
    fi
}
check_hf_token() {
    if [ -z "${HF_TOKEN:-}" ]; then
        echo "HF_TOKEN not set: public repos only (gated repos will fail)."
        return
    fi
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $HF_TOKEN" https://huggingface.co/api/whoami-v2)
    if [ "$code" = "200" ]; then
        echo "HF_TOKEN valid."
    else
        echo "WARNING: HF_TOKEN rejected (HTTP $code). Unsetting so public downloads still work."
        unset HF_TOKEN
    fi
}

### ============================================================
### FUNCTIONS — stacks
### ============================================================

# Remove duplicate entries in place, keeping first-seen order (shared models/nodes install once).
dedupe() {
    local -n _arr="$1"
    local -A _seen=()
    local _out=() _x
    for _x in "${_arr[@]}"; do
        [ -n "${_seen["$_x"]+1}" ] && continue
        _seen["$_x"]=1
        _out+=("$_x")
    done
    _arr=("${_out[@]}")
}

# For stacks with GPU-dependent files. Prints "nvfp4" or "int8" (logs go to stderr).
gpu_text_encoder() {
    local choice="${TEXT_ENCODER:-auto}"
    if [ "$choice" = "auto" ]; then
        local cc
        cc=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1)
        echo "GPU compute capability: ${cc:-unknown}" >&2
        if [ -n "$cc" ] && [ "${cc%%.*}" -ge 10 ]; then choice="nvfp4"; else choice="int8"; fi
    fi
    echo "Text encoder: $choice" >&2
    echo "$choice"
}

# Sparse-clone this repo, fetching only the selected stacks/ folders.
fetch_stacks() {
    rm -rf "$REPO_DIR"
    if ! git clone --quiet --depth 1 --branch "$SETUP_REF" --filter=blob:none --sparse \
            "$SETUP_REPO" "$REPO_DIR"; then
        FAILED+=("stacks: cannot clone $SETUP_REPO @ $SETUP_REF")
        return 1
    fi

    local available
    available=$(git -C "$REPO_DIR" ls-tree -d --name-only HEAD stacks/ | sed 's#^stacks/##')
    if [ -z "$available" ]; then
        FAILED+=("stacks: repo has no stacks/ folders")
        return 1
    fi

    local wanted=() s
    if [ "${STACKS,,}" = "all" ]; then
        mapfile -t wanted <<< "$available"
    else
        IFS=',' read -ra req <<< "$STACKS"
        for s in "${req[@]}"; do
            s="${s//[[:space:]]/}"
            [ -z "$s" ] && continue
            if grep -qxF -- "$s" <<< "$available"; then
                wanted+=("$s")
            else
                echo "ERROR: unknown stack '$s'"
                FAILED+=("stack: unknown '$s'")
            fi
        done
    fi
    dedupe wanted

    if [ ${#wanted[@]} -eq 0 ]; then
        echo "No valid stacks selected. Available: $(echo $available)"
        return 1
    fi
    if ! git -C "$REPO_DIR" sparse-checkout set "${wanted[@]/#/stacks/}"; then
        FAILED+=("stacks: sparse checkout failed")
        return 1
    fi
    SELECTED=("${wanted[@]}")
    echo "STACKS=$STACKS -> installing: ${SELECTED[*]}   (available: $(echo $available))"
}

# Source each selected stack.sh; each only appends to the lists above.
load_stacks() {
    local s f
    for s in "${SELECTED[@]}"; do
        f="$REPO_DIR/stacks/$s/stack.sh"
        if [ -f "$f" ]; then
            source "$f"
            echo "Loaded stack: $s"
        else
            echo "Stack '$s' has no stack.sh (workflows only)."
        fi
    done
    dedupe APT_PACKAGES; dedupe PIP_PACKAGES; dedupe NODES; dedupe MODELS; dedupe CIVITAI
    echo "To install: ${#NODES[@]} nodes, ${#MODELS[@]} models, ${#CIVITAI[@]} Civitai files"
}

# Copy stacks/<name>/*.json to ComfyUI workflows/<name>/ (overwrites same-named files there).
install_stack_workflows() {
    local wf="$COMFY/user/default/workflows" s files
    shopt -s nullglob
    for s in "${SELECTED[@]}"; do
        files=("$REPO_DIR/stacks/$s"/*.json)
        if [ ${#files[@]} -eq 0 ]; then
            echo "$s: no workflow JSONs"
            continue
        fi
        mkdir -p "$wf/$s"
        if cp -f "${files[@]}" "$wf/$s/"; then
            echo "$s: installed ${#files[@]} workflow(s) -> $wf/$s"
        else
            FAILED+=("workflows: $s")
        fi
    done
    shopt -u nullglob
}

### ============================================================
### MAIN
### ============================================================

provisioning_start() {
    check_disk
    log "Stacks"; fetch_stacks && load_stacks
    check_hf_token
    check_civitai_token
    log "APT packages";  install_apt
    log "PIP packages";  install_pip
    install_nodes
    download_models
    download_civitai
    log "Workflows"; install_stack_workflows
    rm -rf "$REPO_DIR"
    summary
}

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
