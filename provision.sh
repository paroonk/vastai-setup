#!/bin/bash
# Vast.ai PROVISIONING_SCRIPT — ComfyUI, stack-based
# Set PROVISIONING_SCRIPT to:
#   https://raw.githubusercontent.com/paroonk/vastai-setup/main/provision.sh
#
# This file only bootstraps: it clones this repo, then loads lib/*.sh (the engine),
# stacks/<name>/stack.sh and families/<family>/family.sh (what to install).
#
# Template env vars:
#   STACKS         - which stacks to install: "h3-obvpm-timeline", "h3-obvpm-timeline,qwen21-edit-main", a family name ("qwen21" = every qwen21-* stack, "h3" likewise), or "all" (default: all);
#                    names are case-insensitive
#                    Each stack = stacks/<name>/stack.sh (nodes, models) + its workflow JSONs.
#   CIVITAI_TOKEN  - Civitai API key (required for Civitai downloads)
#   HF_TOKEN       - HuggingFace token (needed only for gated/private repos)
#   AUTO_UPDATE    - "true" (default) git-pulls custom nodes already on disk; "false" keeps them as they are
#   QUIET_LOG      - "true" (default) pauses Vast's ComfyUI/api-wrapper services while provisioning, so the
#                    log is not flooded with "startup paused..." every 5 s; they are restarted at the end.
#                    "false" leaves them alone.
#   SETUP_REF      - branch or tag of this repo to use (default: main)
#   SETUP_REPO     - repo URL override (default: paroonk/vastai-setup on GitHub)

# No `set -e`: one flaky download must not abort a 70+ GB provisioning run.
set -o pipefail

source /venv/main/bin/activate

WORKSPACE="${WORKSPACE:-/workspace}"
SETUP_REPO="${SETUP_REPO:-https://github.com/paroonk/vastai-setup.git}"
SETUP_REF="${SETUP_REF:-main}"
REPO_DIR="$WORKSPACE/.tmp_setup_repo"

# Fetch the engine (lib/) and family files; stacks/ is added once STACKS is resolved (fetch_stacks).
bootstrap() {
    rm -rf "$REPO_DIR"
    git clone --quiet --depth 1 --branch "$SETUP_REF" --filter=blob:none --sparse "$SETUP_REPO" "$REPO_DIR" \
        && git -C "$REPO_DIR" sparse-checkout set lib families \
        || { echo "ERROR: cannot clone $SETUP_REPO @ $SETUP_REF"; exit 1; }
    local f
    for f in config progress dsl base checks setup download stacks quiet; do
        source "$REPO_DIR/lib/$f.sh" || { echo "ERROR: cannot load lib/$f.sh"; exit 1; }
    done
}

provisioning_start() {
    bootstrap
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
    step "Links, workflows, bundled nodes"; create_links; install_stack_workflows; install_stack_nodes
    rm -rf "$REPO_DIR"
    quiet_off
    summary
}

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
