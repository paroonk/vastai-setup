# Download engine: size lookup + plan, Hugging Face / wget / Civitai downloads. Sourced by provision.sh.

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
        IFS='|' read -r subdir url fname <<< "$entry"; name="${fname:-${url##*/}}"
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
        IFS='|' read -r subdir url fname <<< "$entry"   # fname optional: save under this name
        local name="${fname:-${url##*/}}"
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

# One Civitai file into dir $2 (optional saved name $3). Resumable.
# The API URL answers with a redirect to a signed storage URL. We resolve that redirect with
# curl (which sends the token only to Civitai), then hand the signed URL, with no token, to
# aria2c for 16 parallel connections: wget/aria2 would forward the token to the storage host,
# which rejects it with HTTP 400. Any aria2 problem falls back to plain curl.
civitai_fetch() {
    local url="$1" dir="$2" fname="$3" signed try
    local auth=(-H "Authorization: Bearer $CIVITAI_TOKEN")
    for try in 1 2 3; do
        if command -v aria2c >/dev/null 2>&1; then
            signed=$(curl -s -o /dev/null -w '%{redirect_url}' "${auth[@]}" "$url")
            if [ -n "$signed" ]; then
                local oname=(); [ -n "$fname" ] && oname=(-o "$fname")
                aria2c -x16 -s16 -k4M -c --file-allocation=none --max-tries=3 --retry-wait=3 \
                    --console-log-level=warn --summary-interval=15 --download-result=hide \
                    -d "$dir" "${oname[@]}" "$signed" && return 0
                echo "WARN: aria2c failed (try $try/3), retrying"
                continue
            fi
        fi
        # fallback: single-stream curl. -C - resumes, but only with a fixed name (-J has none yet).
        if [ -n "$fname" ]; then
            (cd "$dir" && curl -fL -C - -o "$fname" --retry 3 "${auth[@]}" "$url") && return 0
        else
            rm -f "$dir"/* 2>/dev/null
            (cd "$dir" && curl -fL -J -O --retry 3 "${auth[@]}" "$url") && return 0
        fi
    done
    return 1
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
        mkdir -p "$tmp"   # kept between attempts and re-runs so partial files resume
        if ! civitai_fetch "$url" "$tmp" "$fname"; then
            FAILED+=("civitai: $target ($url)"); continue   # tmp kept: a re-run resumes
        fi

        local file
        file=$(find "$tmp" -maxdepth 1 -type f ! -name '*.aria2' | head -1)
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
    [ ${#FAILED[@]} -eq 0 ] && rm -rf "$WORKSPACE/.tmp_civitai" 2>/dev/null   # else keep partials for a re-run
    return 0
}
