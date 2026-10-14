# Stack selection, loading, and workflow installation. Sourced by provision.sh.

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
                # a family name (qwen21, h3) selects every stack in that family
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
    if ! git -C "$REPO_DIR" sparse-checkout set lib families "${wanted[@]/#/stacks/}"; then
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
    # Family files (shared LoRAs/models): a stack named <family>-<name> (e.g. qwen21-edit-main, h3-obvpm-timeline) pulls in
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
            echo "Loaded family: $fam"
        fi
    done
    dedupe APT_PACKAGES; dedupe PIP_PACKAGES; dedupe NODES; dedupe MODELS; dedupe CIVITAI; dedupe LINKS; dedupe PRIVATE
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

# Copy stacks/<name>/*.json to ComfyUI workflows/<name>/ (overwrites same-named files there).
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

# Copy each stacks/<name>/<folder>/ (except originals/) into ComfyUI/custom_nodes/<folder>, replacing any copy already there
# (e.g. a git clone from NODES), then install its requirements.txt. Runs last, so bundled nodes override cloned ones.
install_stack_nodes() {
    local s d name dest
    for s in "${SELECTED[@]}"; do
        for d in "$REPO_DIR/stacks/$s"/*/; do
            [ -d "$d" ] || continue
            name=$(basename "$d")
            [ "$name" = "originals" ] && continue
            dest="$COMFY/custom_nodes/$name"
            mkdir -p "$COMFY/custom_nodes"
            rm -rf "$dest"
            if cp -r "${d%/}" "$dest"; then
                echo "$s: installed custom node $name -> $dest"
                if [ -f "$dest/requirements.txt" ]; then
                    pip install --root-user-action=ignore --no-cache-dir -r "$dest/requirements.txt"                         || FAILED+=("node reqs: $name")
                fi
            else
                FAILED+=("bundled node: $s/$name")
            fi
        done
    done
}

# Copy the folders listed with `private` from the private dir on the instance into ComfyUI. The private dir is
# $PRIVATE_DIR (default $WORKSPACE/vastai-setup-private); upload the folders there yourself (scp / Jupyter).
# A folder that is already in ComfyUI is replaced. Nodes get their requirements.txt installed.
install_private() {
    local dir="${PRIVATE_DIR:-$WORKSPACE/vastai-setup-private}" entry sub folder src dest
    if [ ${#PRIVATE[@]} -eq 0 ]; then return 0; fi
    for entry in "${PRIVATE[@]}"; do
        IFS='|' read -r sub folder <<< "$entry"
        src="$dir/$folder"
        dest="$COMFY/$sub/$folder"
        if [ ! -d "$src" ]; then
            echo "private: $src not found, skipped ($folder)"
            continue
        fi
        mkdir -p "$COMFY/$sub"
        rm -rf "$dest"
        if cp -r "$src" "$dest"; then
            echo "private: $folder -> $dest"
            if [ "$sub" = "custom_nodes" ] && [ -f "$dest/requirements.txt" ]; then
                pip install --root-user-action=ignore --no-cache-dir -r "$dest/requirements.txt"                     || FAILED+=("node reqs: $folder")
            fi
        else
            FAILED+=("private: $folder")
        fi
    done
}
