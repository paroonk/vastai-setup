# QUIET_LOG: pause Vast services while provisioning. Sourced by provision.sh.

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
