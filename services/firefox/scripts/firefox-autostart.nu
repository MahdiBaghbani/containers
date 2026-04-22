# Firefox autostart for OCM container desktop environments.
# Invoked by custom_startup.sh:
#   /usr/local/bin/nu /dockerstartup/firefox-autostart.nu
#
# Env knobs:
#   OCM_FIREFOX_AUTOLAUNCH          - default true; false: 0 false no off
#   OCM_FIREFOX_START_URL           - optional URL to open on launch
#   OCM_FIREFOX_EXTRA_ARGS          - optional whitespace-separated extra args
#   OCM_FIREFOX_AUTOLAUNCH_MODE     - once (default) or supervise
#   OCM_FIREFOX_PROFILE_DIR         - profile directory
#                                     (default: <profile-base>/ocm; profile-base is
#                                      ~/.config/mozilla/firefox for FF >= 147,
#                                      else ~/.mozilla/firefox)
#   OCM_FIREFOX_SUPPRESS_FIRST_RUN  - default true; disables first-run
#                                     notices and telemetry prompts
#   OCM_FIREFOX_DARK_MODE           - default true; sets
#                                     ui.systemUsesDarkTheme in user.js
#   OCM_FIREFOX_SET_DEFAULT_BROWSER - default true; passes
#                                     --setDefaultBrowser to Firefox
#   OCM_FIREFOX_MAXIMIZE            - default true; calls the shared
#                                     maximize helper (~25 s, 1 s interval)

def is-falsy [val: string]: nothing -> bool {
    $val in ["0" "false" "no" "off"]
}

# Log reason and sleep forever so the Kasm supervisor does not relaunch us.
def idle-forever [reason: string]: nothing -> nothing {
    print $reason
    loop {
        ^sleep 60
    }
}

def wait-for-desktop []: nothing -> nothing {
    if ("/usr/bin/desktop_ready" | path exists) {
        print "Waiting for desktop ready..."
        ^/usr/bin/desktop_ready
    }
}

def apply-desktop-env []: nothing -> nothing {
    if ("/dockerstartup/ocm-desktop-env.nu" | path exists) {
        ^/usr/local/bin/nu /dockerstartup/ocm-desktop-env.nu
    }
}

# Best-effort fallback: maximize the active window via the shared helper.
# Spawns background maximize attempts for ~25 s; does not block startup.
# Delegates to /dockerstartup/ocm-window-actions.nu; no-op if file is missing.
def call-maximize-loop [maximize: bool]: nothing -> nothing {
    if not $maximize { return }
    if not ("/dockerstartup/ocm-window-actions.nu" | path exists) { return }
    ^/usr/local/bin/nu /dockerstartup/ocm-window-actions.nu --maximize
}

# Return the Firefox major version as an int, or 0 on failure.
def firefox-major-version []: nothing -> int {
    let result = (try {
        ^/usr/local/bin/firefox --version | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: ""}
    })
    if $result.exit_code != 0 { return 0 }
    let raw = if not ($result.stdout | str trim | is-empty) {
        $result.stdout | str trim
    } else {
        $result.stderr | str trim
    }
    # Expects "Mozilla Firefox 147.0" or similar
    let parts = ($raw | split row " ")
    if ($parts | length) < 3 { return 0 }
    try { $parts | last | split row "." | get 0 | into int } catch { 0 }
}

# Compute the Firefox profile base dir (XDG-aware: >= 147 uses .config/mozilla).
def profile-base-dir []: nothing -> string {
    if (firefox-major-version) >= 147 {
        $env.HOME | path join ".config" "mozilla" "firefox"
    } else {
        $env.HOME | path join ".mozilla" "firefox"
    }
}

# Build the desired user.js content string.
def build-userjs-content [suppress_first_run: bool, dark_mode: bool]: nothing -> string {
    mut lines = [
        "// Managed by firefox-autostart.nu"
        "user_pref(\"security.sandbox.warn_unprivileged_namespaces\", false);"
        "user_pref(\"browser.shell.checkDefaultBrowser\", false);"
    ]
    if $suppress_first_run {
        $lines = ($lines | append [
            "user_pref(\"datareporting.policy.firstRunURL\", \"\");"
            "user_pref(\"datareporting.policy.dataSubmissionEnabled\", false);"
            "user_pref(\"datareporting.healthreport.service.enabled\", false);"
            "user_pref(\"datareporting.healthreport.uploadEnabled\", false);"
            "user_pref(\"toolkit.telemetry.reportingpolicy.firstRun\", false);"
            "user_pref(\"browser.aboutwelcome.enabled\", false);"
        ])
    }
    if $dark_mode {
        $lines = ($lines | append [
            "user_pref(\"ui.systemUsesDarkTheme\", 1);"
        ])
    }
    ($lines | str join "\n") + "\n"
}

# Write user.js only when missing or content differs (idempotent).
def write-firefox-userjs [
    profile_dir: string,
    suppress_first_run: bool,
    dark_mode: bool
]: nothing -> nothing {
    let content = (build-userjs-content $suppress_first_run $dark_mode)
    let target = ($profile_dir | path join "user.js")
    let existing = if ($target | path exists) { open --raw $target } else { "" }
    if $existing != $content {
        $content | save --force $target
    }
}

# Write file content only when it differs from disk (idempotent).
def write-if-changed [path: string, content: string]: nothing -> nothing {
    let existing = if ($path | path exists) { open --raw $path } else { "" }
    if $existing != $content {
        $content | save --force $path
    }
}

# Extract section header names (without brackets) from INI text.
def ini-section-names [content: string]: nothing -> list<string> {
    $content
    | lines
    | where {|l| $l | str trim | str starts-with "["}
    | each {|l|
        let parsed = ($l | str trim | parse "[{name}]")
        if ($parsed | is-empty) { "" } else { $parsed | get 0.name }
    }
    | where {|n| not ($n | is-empty)}
}

# Apply Default= and Locked= to sections whose header starts with
# "[<section_prefix>".  Pass "" to match every section.
# Returns the updated content string; does not write to disk.
def apply-ini-section-defaults [
    content: string,
    rel_profile: string,
    section_prefix: string,
]: nothing -> string {
    let lines = ($content | lines)
    mut out: list<string> = []
    mut active = false
    mut saw_default = false
    mut saw_locked = false
    for line in $lines {
        let trimmed = ($line | str trim)
        if ($trimmed | str starts-with "[") {
            if $active {
                if not $saw_default {
                    $out = ($out | append $"Default=($rel_profile)")
                }
                if not $saw_locked {
                    $out = ($out | append "Locked=1")
                }
            }
            $active = ($trimmed | str starts-with $"[($section_prefix)")
            $saw_default = false
            $saw_locked = false
            $out = ($out | append $line)
        } else if $active and ($trimmed | str contains "=") {
            let key = ($trimmed | split row "=" | get 0 | str trim)
            if $key == "Default" {
                $out = ($out | append $"Default=($rel_profile)")
                $saw_default = true
            } else if $key == "Locked" {
                $out = ($out | append "Locked=1")
                $saw_locked = true
            } else {
                $out = ($out | append $line)
            }
        } else {
            $out = ($out | append $line)
        }
    }
    if $active {
        if not $saw_default {
            $out = ($out | append $"Default=($rel_profile)")
        }
        if not $saw_locked {
            $out = ($out | append "Locked=1")
        }
    }
    ($out | str join "\n") + "\n"
}

# Pin Firefox so any launch (desktop icon, CLI) uses the managed profile.
#
# installs.ini sections are bare hashes: [B6EDF2B3F1564B12]
# profiles.ini Install sections look like: [InstallB6EDF2B3F1564B12]
#
# Steps:
#   1. If installs.ini absent, return (it is created on the first real GUI
#      launch, not by -CreateProfile; pin runs again after that launch).
#   2. Parse section names (hashes) from installs.ini.
#   3. For each hash, ensure [Install<hash>] exists in profiles.ini (append
#      if missing).
#   4. Set Default=<rel_profile> + Locked=1 in every [Install...] section
#      of profiles.ini.
#   5. Set Default=<rel_profile> + Locked=1 in every section of installs.ini
#      (sections are bare hashes, so prefix "" matches all).
#   All writes are idempotent (skipped when content is unchanged).
def pin-firefox-profile [
    profile_dir: string,
    profile_base: string,
]: nothing -> nothing {
    let installs_path = ($profile_base | path join "installs.ini")
    let profiles_path = ($profile_base | path join "profiles.ini")

    if not ($installs_path | path exists) { return }

    let rel_profile = if ($profile_dir | str starts-with $"($profile_base)/") {
        $profile_dir | str replace $"($profile_base)/" ""
    } else {
        $profile_dir
    }

    let installs_content = (open --raw $installs_path)
    let hashes = (ini-section-names $installs_content)

    # Ensure profiles.ini has an [Install<hash>] section for every hash, then
    # apply Default= and Locked= to all [Install...] sections.
    if ($profiles_path | path exists) {
        mut profiles_content = (open --raw $profiles_path)
        if not ($hashes | is-empty) {
            let existing = (ini-section-names $profiles_content)
            for hash in $hashes {
                let section = $"Install($hash)"
                if not ($section in $existing) {
                    let sep = if ($profiles_content | str ends-with "\n") { "" } else { "\n" }
                    $profiles_content = ($profiles_content + $"($sep)[Install($hash)]\n")
                }
            }
        }
        let updated = (apply-ini-section-defaults $profiles_content $rel_profile "Install")
        write-if-changed $profiles_path $updated
    }

    # Update all sections in installs.ini (prefix "" matches every section).
    let updated_installs = (apply-ini-section-defaults $installs_content $rel_profile "")
    write-if-changed $installs_path $updated_installs
}

# Ensure the managed profile is the default in profiles.ini.
# Works even when installs.ini does not yet exist.
# Sets Default=1 in the [Profile*] section whose Path= matches
# rel_profile (or the absolute path when IsRelative=0), and removes
# Default= from all other [Profile*] sections. Idempotent.
def mark-profiles-ini-default [
    profile_dir: string,
    profile_base: string,
]: nothing -> nothing {
    let profiles_path = ($profile_base | path join "profiles.ini")
    if not ($profiles_path | path exists) { return }

    let rel_profile = if ($profile_dir | str starts-with $"($profile_base)/") {
        $profile_dir | str replace $"($profile_base)/" ""
    } else {
        $profile_dir
    }

    let content = (open --raw $profiles_path)
    let lines = ($content | lines)

    # Pass 1: identify the target [Profile*] section header.
    mut target_header = ""
    mut cur_header = ""
    mut cur_path = ""
    mut cur_is_rel = 1
    for line in $lines {
        let trimmed = ($line | str trim)
        if ($trimmed | str starts-with "[") {
            if ($cur_header | str starts-with "[Profile") {
                let matches = if $cur_is_rel == 1 {
                    $cur_path == $rel_profile
                } else {
                    $cur_path == $profile_dir
                }
                if $matches { $target_header = $cur_header }
            }
            $cur_header = $trimmed
            $cur_path = ""
            $cur_is_rel = 1
        } else if ($trimmed | str starts-with "Path=") {
            $cur_path = ($trimmed | str replace "Path=" "")
        } else if ($trimmed | str starts-with "IsRelative=") {
            $cur_is_rel = (try {
                $trimmed | str replace "IsRelative=" "" | into int
            } catch { 1 })
        }
    }
    # Flush the last section.
    if ($cur_header | str starts-with "[Profile") {
        let matches = if $cur_is_rel == 1 {
            $cur_path == $rel_profile
        } else {
            $cur_path == $profile_dir
        }
        if $matches { $target_header = $cur_header }
    }

    # No matching [Profile*] section - do not rewrite (would strip Default= from
    # other profiles without setting it anywhere).
    if ($target_header | is-empty) { return }

    # Pass 2: rewrite - set Default=1 in target, remove it from all others.
    mut out: list<string> = []
    $cur_header = ""
    mut in_profile = false
    mut is_target = false
    mut saw_default = false
    for line in $lines {
        let trimmed = ($line | str trim)
        if ($trimmed | str starts-with "[") {
            if $is_target and not $saw_default {
                $out = ($out | append "Default=1")
            }
            $cur_header = $trimmed
            $in_profile = ($trimmed | str starts-with "[Profile")
            $is_target = (($trimmed == $target_header) and not ($target_header | is-empty))
            $saw_default = false
            $out = ($out | append $line)
        } else if $in_profile and ($trimmed | str starts-with "Default=") {
            if $is_target {
                $out = ($out | append "Default=1")
                $saw_default = true
            }
            # else: drop Default= from non-target [Profile*] sections
        } else {
            $out = ($out | append $line)
        }
    }
    # Flush the last section.
    if $is_target and not $saw_default {
        $out = ($out | append "Default=1")
    }

    let updated = (($out | str join "\n") + "\n")
    write-if-changed $profiles_path $updated
}

# One-time profile init: create named profile, write user.js, pin in INI files.
#
# Pinning is delegated to pin-firefox-profile, which handles installs.ini
# section names correctly (bare hashes, not [Install...] prefixes).
# If installs.ini does not yet exist (before any real Firefox GUI launch),
# pinning is a no-op here; main calls pin-firefox-profile again after each
# Firefox exit so the pin is applied before the next launch.
#
# profile_base must be the version-derived XDG base dir so INI lookups target
# the right directory even when OCM_FIREFOX_PROFILE_DIR is a custom path.
def init-firefox-profile [
    profile_dir: string,
    profile_base: string,
    suppress_first_run: bool,
    dark_mode: bool
]: nothing -> nothing {
    mkdir $profile_dir

    # -CreateProfile registers the profile in profiles.ini.  Run only when the
    # directory is empty (freshly created by mkdir above).
    if (ls $profile_dir | is-empty) {
        let profile_name = ($profile_dir | path basename)
        print (["Registering Firefox profile at " $profile_dir "."] | str join)
        try {
            let r = (^/usr/local/bin/firefox -headless "-CreateProfile" $"($profile_name) ($profile_dir)" | complete)
            if $r.exit_code != 0 {
                print "Warning: -CreateProfile exited non-zero; continuing."
            }
        } catch {|err|
            print $"Warning: -CreateProfile failed: ($err.msg)"
        }
    }

    write-firefox-userjs $profile_dir $suppress_first_run $dark_mode

    mark-profiles-ini-default $profile_dir $profile_base
    pin-firefox-profile $profile_dir $profile_base
}

def launch-firefox [
    url: string,
    extra_args: list<string>,
    profile_dir: string,
    set_default: bool
]: nothing -> nothing {
    mut args = ["--profile" $profile_dir]
    if $set_default {
        $args = ($args | append "--setDefaultBrowser")
    }
    if not ($url | is-empty) {
        $args = ($args | append $url)
    }
    $args = ($args | append $extra_args)
    ^/usr/local/bin/firefox ...$args
}

def main [] {
    let autolaunch = (
        $env.OCM_FIREFOX_AUTOLAUNCH?
        | default "true"
        | str downcase
        | str trim
    )
    if (is-falsy $autolaunch) {
        idle-forever "OCM_FIREFOX_AUTOLAUNCH disabled - supervisor idle."
    }

    wait-for-desktop

    $env.DISPLAY = ($env.DISPLAY? | default ":1")
    let display = $env.DISPLAY

    apply-desktop-env

    let profile_base = (profile-base-dir)
    let profile_dir_raw = ($env.OCM_FIREFOX_PROFILE_DIR? | default "" | str trim)
    let profile_dir = if not ($profile_dir_raw | is-empty) {
        $profile_dir_raw
    } else {
        $profile_base | path join "ocm"
    }

    let suppress_first_run_raw = (
        $env.OCM_FIREFOX_SUPPRESS_FIRST_RUN?
        | default "true"
        | str downcase
        | str trim
    )
    let suppress_first_run = not (is-falsy $suppress_first_run_raw)

    let dark_mode_raw = (
        $env.OCM_FIREFOX_DARK_MODE?
        | default "true"
        | str downcase
        | str trim
    )
    let dark_mode = not (is-falsy $dark_mode_raw)

    let set_default_raw = (
        $env.OCM_FIREFOX_SET_DEFAULT_BROWSER?
        | default "true"
        | str downcase
        | str trim
    )
    let set_default = not (is-falsy $set_default_raw)

    let maximize_raw = (
        $env.OCM_FIREFOX_MAXIMIZE?
        | default "true"
        | str downcase
        | str trim
    )
    let maximize = not (is-falsy $maximize_raw)

    init-firefox-profile $profile_dir $profile_base $suppress_first_run $dark_mode

    let url = ($env.OCM_FIREFOX_START_URL? | default "")
    let extra_raw = ($env.OCM_FIREFOX_EXTRA_ARGS? | default "")
    let extra_args = if ($extra_raw | str trim | is-empty) {
        []
    } else {
        $extra_raw | split row --regex '\s+' | where {|a| not ($a | is-empty)}
    }

    let mode = (
        $env.OCM_FIREFOX_AUTOLAUNCH_MODE?
        | default "once"
        | str downcase
        | str trim
    )

    if $mode == "supervise" {
        print (["Starting Firefox in supervise mode (DISPLAY=" $display ")."] | str join)
        loop {
            try {
                call-maximize-loop $maximize
                launch-firefox $url $extra_args $profile_dir $set_default
            } catch {|err|
                print $"Firefox exited with error: ($err.msg)"
            }
            pin-firefox-profile $profile_dir $profile_base
            print "Firefox exited, restarting in 2s..."
            ^sleep 2
        }
    } else {
        print (["Starting Firefox (once, DISPLAY=" $display ")."] | str join)
        call-maximize-loop $maximize
        launch-firefox $url $extra_args $profile_dir $set_default
        pin-firefox-profile $profile_dir $profile_base
        idle-forever "Firefox exited - supervisor idle."
    }
}
