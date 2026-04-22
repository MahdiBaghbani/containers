# Shared window-management helpers for OCM container desktop environments.
# Invoked directly by autostart scripts in derived kasm-base images:
#   /usr/local/bin/nu /dockerstartup/ocm-window-actions.nu [flags]
#
# Flags:
#   --maximize   - spawn a wmctrl active-window maximize loop
#   --seconds    - loop duration in seconds (default 25)
#   --interval   - sleep interval between wmctrl attempts in seconds (default 1)

# Spawn a detached bash subshell that calls wmctrl on :ACTIVE: repeatedly.
# Uses command -v inside bash to skip silently when wmctrl is absent.
def spawn-maximize-loop [seconds: int, interval: int]: nothing -> nothing {
    let script = (["command -v wmctrl >/dev/null 2>&1 || exit 0; for i in $(seq 1 " ($seconds | into string) "); do wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz; sleep " ($interval | into string) "; done >/dev/null 2>&1 &"] | str join)
    ^bash -c $script
}

def main [
    --maximize,           # spawn active-window maximize loop
    --seconds: int = 25,  # loop duration in seconds
    --interval: int = 1,  # sleep between wmctrl attempts
]: nothing -> nothing {
    if $maximize {
        spawn-maximize-loop $seconds $interval
    }
}
