# System packages, Python packages, ComfyUI update, custom nodes. Sourced by provision.sh.

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
