#!/bin/bash
# Vast.ai PROVISIONING_SCRIPT — ComfyUI, stack-based
# Set PROVISIONING_SCRIPT to:
#   https://raw.githubusercontent.com/paroonk/vastai-setup/main/provision.sh
#
# Template env vars:
#   STACKS         - which stacks to install: "mmh3-dasiwa", "mmh3-dasiwa,qwen21-outpaint", a family name ("qwen21" = every qwen21-* stack, "mmh3" likewise), or "all" (default: all);
#                    names are case-insensitive
#                    Each stack = stacks/<name>/stack.sh (nodes, models) + its workflow JSONs.
#   CIVITAI_TOKEN  - Civitai API key (required for Civitai downloads)
#   HF_TOKEN       - HuggingFace token (needed only for gated/private repos)
#   TEXT_ENCODER   - "nvfp4" | "int8" | "auto" (default auto: nvfp4 on Blackwell, else int8)
#   AUTO_UPDATE    - "true" (default) git-pulls custom nodes already on disk; "false" keeps them as they are
#   QUIET_LOG      - "true" (default) pauses Vast's ComfyUI/api-wrapper services while provisioning, so the
#                    log is not flooded with "startup paused..." every 5 s; they are restarted at the end.
#                    "false" leaves them alone.
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
AUTO_UPDATE="${AUTO_UPDATE:-true}"
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

# Custom nodes every stack uses
NODES=(
  "https://github.com/rgthree/rgthree-comfy"
  "https://github.com/kijai/ComfyUI-KJNodes"
  "https://github.com/city96/ComfyUI-GGUF"
)
MODELS=()     # "subdir|url"
CIVITAI=()    # "target|url"
LINKS=()      # "link|target", both relative to models/: expose one downloaded file at a second path
WF_SUBST=()   # "from|to": text replaced in installed workflow JSONs (e.g. a model filename swapped for the file actually downloaded)

### ============================================================
### FUNCTIONS — download engine (unchanged from the original gist)
### ============================================================

log() { echo -e "\n==========================================\n$*\n=========================================="; }

# ---- progress reporting ----
# Steps print "[n/N] ..." with timing; /workspace/provision-status.txt always holds the current state
# (Vast's web log is interleaved with its own "startup paused" lines: `cat` the status file instead).
STATUS_FILE="$WORKSPACE/provision-status.txt"
PROV_T0=$(date +%s); STEP_N=0; STEP_TOTAL=9; STEP_NAME=""; STEP_T0=$PROV_T0
PLAN_BYTES=0; DONE_BYTES=0; declare -A SIZE_OF=()
fmt_dur() { local s=$1; printf '%dm%02ds' $((s/60)) $((s%60)); }
gb()      { awk -v b="${1:-0}" 'BEGIN{printf "%.1f", b/1e9}'; }
status()  { printf '%s  %s\n' "$(date '+%H:%M:%S')" "$*" > "$STATUS_FILE" 2>/dev/null || true; }
step_done() {
    [ -n "$STEP_NAME" ] && echo "✓ [$STEP_N/$STEP_TOTAL] $STEP_NAME — done in $(fmt_dur $(( $(date +%s) - STEP_T0 )))"
    return 0
}
step() {
    step_done
    STEP_N=$((STEP_N+1)); STEP_NAME="$*"; STEP_T0=$(date +%s)
    log "[$STEP_N/$STEP_TOTAL] $*"
    status "[$STEP_N/$STEP_TOTAL] $*"
}
# Size of a remote file in bytes (0 if unknown). HF answers HEAD with x-linked-size.
remote_size() {
    local url="$1" auth="${2:-}" h s
    if [ -n "$auth" ]; then h=$(curl -sIL --max-time 20 -H "$auth" "$url" 2>/dev/null)
    else h=$(curl -sIL --max-time 20 "$url" 2>/dev/null); fi
    h=$(printf '%s' "$h" | tr -d '\r' | tr 'A-Z' 'a-z')
    s=$(printf '%s\n' "$h" | awk -F': ' '$1=="x-linked-size"{v=$2} END{print v}')
    [ -z "$s" ] && s=$(printf '%s\n' "$h" | awk -F': ' '$1=="content-length"{v=$2} END{print v}')
    [[ "$s" =~ ^[0-9]+$ ]] && echo "$s" || echo 0
}
# Look up sizes of everything still to download, so each file can show "x / total GB".
plan_downloads() {
    local entry subdir url name target fname key dest n=0 have=0 unknown=0 sz hfauth=""
    [ -n "${HF_TOKEN:-}" ] && hfauth="Authorization: Bearer $HF_TOKEN"
    status "[$STEP_N/$STEP_TOTAL] checking sizes of files to download"
    for entry in "${MODELS[@]}"; do
        IFS='|' read -r subdir url <<< "$entry"; name="${url##*/}"
        if [ -f "$M/$subdir/$name" ]; then have=$((have+1)); continue; fi
        if [[ "$url" =~ ^https://huggingface\.co/ ]]; then sz=$(remote_size "$url" "$hfauth"); else sz=$(remote_size "$url"); fi
        SIZE_OF["$entry"]=$sz; PLAN_BYTES=$((PLAN_BYTES+sz)); n=$((n+1)); [ "$sz" -eq 0 ] && unknown=$((unknown+1))
    done
    for entry in "${CIVITAI[@]}"; do
        IFS='|' read -r target url fname <<< "$entry"
        if [ "$target" = "workflows" ]; then dest="$COMFY/user/default/workflows"; else dest="$M/$target"; fi
        key=$(echo -n "$url" | md5sum | cut -c1-12)
        if [ -f "$dest/.civitai_${key}.done" ]; then have=$((have+1)); continue; fi
        sz=0; [ -n "${CIVITAI_TOKEN:-}" ] && sz=$(remote_size "$url" "Authorization: Bearer $CIVITAI_TOKEN")
        SIZE_OF["$entry"]=$sz; PLAN_BYTES=$((PLAN_BYTES+sz)); n=$((n+1)); [ "$sz" -eq 0 ] && unknown=$((unknown+1))
    done
    echo "Download plan: $n file(s), $(gb $PLAN_BYTES) GB$([ $unknown -gt 0 ] && echo " (+$unknown of unknown size)"); $have already present."
    local free_gb; free_gb=$(df -BG --output=avail "$WORKSPACE" | tail -1 | tr -dc '0-9')
    if [ "${free_gb:-0}" -gt 0 ] && [ $((PLAN_BYTES/1000000000)) -ge "$free_gb" ]; then
        echo "WARNING: plan ($(gb $PLAN_BYTES) GB) does not fit in ${free_gb} GB free. Downloads will fail; pick fewer stacks or a bigger disk."
    fi
}

check_disk() {
    local free_gb
    free_gb=$(df -BG --output=avail "$WORKSPACE" | tail -1 | tr -dc '0-9')
    echo "Free disk on $WORKSPACE: ${free_gb} GB"
    if [ "${free_gb:-0}" -lt 100 ]; then
        echo "WARNING: <100 GB free. A single stack is 15-90 GB, all of them well over 150 GB; the exact need is shown in the download plan below."
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
# Move ComfyUI to its latest release tag (never downgrades), then install its requirements.
# Runs for every stack: some node packs need a recent ComfyUI (e.g. obvpm timeline needs 0.35.0+).
comfy_version() {
    local v=""
    [ -f "$COMFY/comfyui_version.py" ] && v=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$COMFY/comfyui_version.py" | head -1)
    [ -n "$v" ] || v=$(git -C "$COMFY" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
    echo "${v:-0.0.0}"
}

update_comfyui() {
    if ! git -C "$COMFY" rev-parse --git-dir >/dev/null 2>&1; then
        FAILED+=("comfyui update: $COMFY is not a git checkout")
        return 0
    fi
    local cur latest
    cur=$(comfy_version)
    if ! git -C "$COMFY" fetch --quiet --tags --force origin; then
        FAILED+=("comfyui update: fetch failed (staying on $cur)")
        return 0
    fi
    # newest stable release tag (no -rc/-beta)
    latest=$(git -C "$COMFY" tag --list 'v[0-9]*' | grep -vE -- '-' | sed 's/^v//' | sort -V | tail -1)
    if [ -z "$latest" ]; then
        FAILED+=("comfyui update: no release tags found (staying on $cur)")
        return 0
    fi
    if [ "$(printf '%s\n%s\n' "$cur" "$latest" | sort -V | tail -1)" = "$cur" ]; then
        echo "ComfyUI $cur is already >= latest release $latest; not changing it."
    else
        echo "Updating ComfyUI $cur -> $latest"
        # no --force: if the image has local edits, the checkout fails and is reported instead of discarding them
        if ! git -C "$COMFY" checkout --quiet "v$latest"; then
            FAILED+=("comfyui update: checkout v$latest failed (local changes?); staying on $cur")
            return 0
        fi
    fi
    pip install --root-user-action=ignore --no-cache-dir -r "$COMFY/requirements.txt" \
        || FAILED+=("comfyui update: requirements install")
    echo "ComfyUI now: $(comfy_version)"
}

install_nodes() {
    mkdir -p "$COMFY/custom_nodes"
    local k=0
    for repo in "${NODES[@]}"; do
        local name="${repo##*/}"
        local path="$COMFY/custom_nodes/$name"
        k=$((k+1))
        echo -e "\n--- [node $k/${#NODES[@]}] $name"
        status "[$STEP_N/$STEP_TOTAL] Custom nodes $k/${#NODES[@]}: $name"

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
    local repo_id repo_path rev tmp
    repo_id=$(echo "$url" | awk -F/ '{print $4"/"$5}')
    repo_path=$(echo "$url" | sed -E 's#https?://[^/]+/[^/]+/[^/]+/resolve/[^/]+/(.+)#\1#')
    rev=$(echo "$url" | sed -E 's#https?://[^/]+/[^/]+/[^/]+/resolve/([^/]+)/.*#\1#')   # branch or pinned commit
    tmp="$M/.tmp_hf/${repo_id//\//_}"
    mkdir -p "$tmp"

    HF_XET_HIGH_PERFORMANCE=1 hf download "$repo_id" "$repo_path" --revision "$rev" --local-dir "$tmp" \
        && [ -f "$tmp/$repo_path" ] \
        && mv -f "$tmp/$repo_path" "$dest"
}

# Non-HF files: wget to .part, move on success.
download_wget() {
    local url="$1" dest="$2"
    wget -c -q --show-progress -O "$dest.part" "$url" && mv -f "$dest.part" "$dest"
}

download_models() {
    local total=0 k=0 e
    for e in "${MODELS[@]}"; do [ -n "${SIZE_OF["$e"]+x}" ] && total=$((total+1)); done
    for entry in "${MODELS[@]}"; do
        IFS='|' read -r subdir url <<< "$entry"
        local name="${url##*/}"
        local dest="$M/$subdir/$name"
        mkdir -p "$M/$subdir"

        if [ -f "$dest" ]; then
            echo "OK (exists): $subdir/$name"
            continue
        fi

        k=$((k+1)); local sz=${SIZE_OF["$entry"]:-0}
        log "[models $k/$total] $subdir/$name ($( [ "$sz" -gt 0 ] && echo "$(gb $sz) GB" || echo "size ?"))   — $(gb $DONE_BYTES)/$(gb $PLAN_BYTES) GB done"
        status "[$STEP_N/$STEP_TOTAL] Models $k/$total: $name — $(gb $DONE_BYTES)/$(gb $PLAN_BYTES) GB done"
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

        if [ $ok -eq 1 ]; then
            DONE_BYTES=$((DONE_BYTES + $(stat -c%s "$dest" 2>/dev/null || echo "$sz")))
        else
            FAILED+=("model: $subdir/$name")
        fi
    done
    # Keep temp dir if anything failed, so a re-run can resume partial files
    [ ${#FAILED[@]} -eq 0 ] && rm -rf "$M/.tmp_hf" 2>/dev/null
    return 0
}

# Civitai: filename unknown until download, so a marker file tracks completion
# (keyed by URL) and re-runs skip finished items.
download_civitai() {
    local wf_dir="$COMFY/user/default/workflows" total=0 k=0 e
    for e in "${CIVITAI[@]}"; do [ -n "${SIZE_OF["$e"]+x}" ] && total=$((total+1)); done
    for entry in "${CIVITAI[@]}"; do
        IFS='|' read -r target url fname <<< "$entry"   # fname optional: save under this name
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
 
        k=$((k+1)); local sz=${SIZE_OF["$entry"]:-0}
        log "[civitai $k/$total] $target/${fname:-(server name)} ($( [ "$sz" -gt 0 ] && echo "$(gb $sz) GB" || echo "size ?"))   — $(gb $DONE_BYTES)/$(gb $PLAN_BYTES) GB done"
        status "[$STEP_N/$STEP_TOTAL] Civitai $k/$total: ${fname:-$target} — $(gb $DONE_BYTES)/$(gb $PLAN_BYTES) GB done"
        if [ -z "${CIVITAI_TOKEN:-}" ]; then
            echo "ERROR: CIVITAI_TOKEN not set."
            FAILED+=("civitai: $target ($url) — no token"); continue
        fi
 
        tmp="$WORKSPACE/.tmp_civitai/$key"
        rm -rf "$tmp"; mkdir -p "$tmp"
        # curl, not wget: wget forwards the Authorization header to Civitai's
        # signed storage redirect, which then rejects it with HTTP 400.
        # curl drops the header on cross-host redirects; -J uses the server filename
        # unless the entry gives its own (third field).
        local name_args=(-J -O)
        [ -n "$fname" ] && name_args=(-o "$fname")
        if ! (cd "$tmp" && curl -fL "${name_args[@]}" --retry 3 \
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
        DONE_BYTES=$((DONE_BYTES + sz))
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
    step_done
    local took; took=$(fmt_dur $(( $(date +%s) - PROV_T0 )))
    log "Provisioning finished in $took — downloaded $(gb $DONE_BYTES) GB"
    du -sh "$M"/*/ 2>/dev/null

    if [ ${#FAILED[@]} -gt 0 ]; then
        echo -e "\n!!! ${#FAILED[@]} item(s) FAILED:"
        printf '  - %s\n' "${FAILED[@]}"
        echo "Re-run this script from the terminal to retry; completed files are skipped."
        status "FINISHED in $took with ${#FAILED[@]} failure(s) — see the end of the provisioning log"
    else
        echo -e "\nAll items OK."
        status "FINISHED in $took — all items OK ($(gb $DONE_BYTES) GB downloaded)"
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

# True on Blackwell (compute capability >= 10), where NVFP4 has native kernels.
gpu_is_blackwell() {
    local cc
    cc=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1)
    [ -n "$cc" ] && [ "${cc%%.*}" -ge 10 ]
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

    local wanted=() s fam
    if [ "${STACKS,,}" = "all" ]; then
        mapfile -t wanted <<< "$available"
    else
        IFS=',' read -ra req <<< "$STACKS"
        for s in "${req[@]}"; do
            s="${s//[[:space:]]/}"
            [ -z "$s" ] && continue
            local match
            match=$(grep -ixF -- "$s" <<< "$available" | head -1)   # case-insensitive, real folder name kept
            if [ -n "$match" ]; then
                wanted+=("$match")
            elif grep -qiE -- "^${s}-" <<< "$available"; then
                # a family name (qwen21, mmh3) selects every stack in that family
                mapfile -t fam <<< "$(grep -iE -- "^${s}-" <<< "$available")"
                wanted+=("${fam[@]}")
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
    if ! git -C "$REPO_DIR" sparse-checkout set families "${wanted[@]/#/stacks/}"; then
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
    # Family files (shared LoRAs/models): a stack named <family>-<name> (e.g. qwen21-outpaint, mmh3-dasiwa) pulls in
    # families/<family>/family.sh once, however many stacks of that family are selected.
    local fam
    local -A famseen=()
    for s in "${SELECTED[@]}"; do
        fam="${s%%-*}"
        [ -n "${famseen[$fam]+1}" ] && continue
        famseen[$fam]=1
        f="$REPO_DIR/families/$fam/family.sh"
        if [ -f "$f" ]; then
            source "$f"
            echo "Loaded family LoRAs: $fam"
        fi
    done
    dedupe APT_PACKAGES; dedupe PIP_PACKAGES; dedupe NODES; dedupe MODELS; dedupe CIVITAI; dedupe LINKS
    echo "To install: ${#NODES[@]} nodes, ${#MODELS[@]} models, ${#CIVITAI[@]} Civitai files"
}

# Symlink downloaded files to extra paths some nodes expect (no second download).
create_links() {
    local entry link target src dst
    for entry in "${LINKS[@]}"; do
        IFS='|' read -r link target <<< "$entry"
        src="$M/$target"; dst="$M/$link"
        if [ ! -e "$src" ]; then
            FAILED+=("link: $link (target missing: $target)"); continue
        fi
        mkdir -p "$(dirname "$dst")"
        if ln -sfn "$(realpath "$src")" "$dst"; then
            echo "Linked $link -> $target"
        else
            FAILED+=("link: $link")
        fi
    done
}

# Copy stacks/<name>/*.json to ComfyUI workflows/<name>/ (overwrites same-named files there).
# Apply WF_SUBST ("from|to" literal replacements, in order) to one installed workflow file.
apply_wf_subst() {
    local f="$1" e from to
    [ ${#WF_SUBST[@]} -eq 0 ] && return 0
    for e in "${WF_SUBST[@]}"; do
        from=$(printf '%s' "${e%%|*}" | sed 's/[][\.*^$|]/\\&/g')
        to=$(printf '%s' "${e#*|}" | sed 's/[&|\\]/\\&/g')
        sed -i "s|$from|$to|g" "$f" || FAILED+=("workflow edit: $f")
    done
}

install_stack_workflows() {
    local wf="$COMFY/user/default/workflows" s files orig
    shopt -s nullglob
    for s in "${SELECTED[@]}"; do
        files=("$REPO_DIR/stacks/$s"/*.json)
        orig=("$REPO_DIR/stacks/$s"/originals/*.json)   # author's files as shipped, kept for comparison
        if [ ${#files[@]} -eq 0 ] && [ ${#orig[@]} -eq 0 ]; then
            echo "$s: no workflow JSONs"
            continue
        fi
        mkdir -p "$wf/$s"
        if [ ${#files[@]} -gt 0 ]; then
            if cp -f "${files[@]}" "$wf/$s/"; then
                local f
                for f in "${files[@]}"; do apply_wf_subst "$wf/$s/$(basename "$f")"; done
                echo "$s: installed ${#files[@]} workflow(s) -> $wf/$s"
            else
                FAILED+=("workflows: $s")
            fi
        fi
        if [ ${#orig[@]} -gt 0 ]; then
            mkdir -p "$wf/$s/originals"
            if cp -f "${orig[@]}" "$wf/$s/originals/"; then
                echo "$s: installed ${#orig[@]} original workflow(s) -> $wf/$s/originals"
            else
                FAILED+=("workflows (originals): $s")
            fi
        fi
    done
    shopt -u nullglob
}

### ============================================================
### FUNCTIONS — quiet log
### ============================================================

# Vast's comfyui / api-wrapper services print "startup paused until provisioning has completed" every 5 s
# while /.provisioning exists. Stop them for the duration and start exactly those we stopped afterwards.
QUIET_STOPPED=()
quiet_on() {
    [ "${QUIET_LOG:-true}" = "false" ] && return 0
    command -v supervisorctl >/dev/null 2>&1 || return 0
    local svc
    for svc in comfyui api-wrapper; do
        if supervisorctl status "$svc" 2>/dev/null | grep -q RUNNING; then
            supervisorctl stop "$svc" >/dev/null 2>&1 && QUIET_STOPPED+=("$svc")
        fi
    done
    [ ${#QUIET_STOPPED[@]} -gt 0 ] && echo "QUIET_LOG: paused ${QUIET_STOPPED[*]} (restarted when provisioning ends)"
    return 0
}
quiet_off() {
    local svc
    for svc in "${QUIET_STOPPED[@]}"; do
        supervisorctl start "$svc" >/dev/null 2>&1 || echo "WARNING: could not restart $svc — run: supervisorctl start $svc"
    done
    QUIET_STOPPED=()
}

### ============================================================
### MAIN
### ============================================================

provisioning_start() {
    quiet_on
    trap quiet_off EXIT          # restart the services even if the script dies
    trap 'exit 143' INT TERM
    step "Stacks";                         fetch_stacks && load_stacks
    step "Checks (disk, tokens)";          check_disk; check_hf_token; check_civitai_token
    step "System packages (apt)";          install_apt
    step "ComfyUI update";                 update_comfyui
    step "Python packages (${#PIP_PACKAGES[@]})"; install_pip
    step "Custom nodes (${#NODES[@]})";    install_nodes
    step "Models";                         plan_downloads; download_models
    step "Civitai files (${#CIVITAI[@]})"; download_civitai
    step "Links + workflows";              create_links; install_stack_workflows
    rm -rf "$REPO_DIR"
    quiet_off
    summary
}

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
