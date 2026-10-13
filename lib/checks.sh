# Preflight checks: free disk and API tokens. Sourced by provision.sh.

check_disk() {
    local free_gb
    free_gb=$(df -BG --output=avail "$WORKSPACE" | tail -1 | tr -dc '0-9')
    echo "Free disk on $WORKSPACE: ${free_gb} GB"
    if [ "${free_gb:-0}" -lt 100 ]; then
        echo "WARNING: <100 GB free. A single stack is 15-90 GB, all of them well over 150 GB; the exact need is shown in the download plan below."
    fi
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
