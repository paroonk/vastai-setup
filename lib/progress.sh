# Logging, step counter and status file. Sourced by provision.sh.

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
