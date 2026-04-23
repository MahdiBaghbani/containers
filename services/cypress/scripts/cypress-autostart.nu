# Cypress autostart for OCM container desktop environments.
# Invoked by custom_startup.sh:
#   /usr/local/bin/nu /dockerstartup/cypress-autostart.nu
#
# Env knobs:
#   OCM_CYPRESS_AUTOLAUNCH      - default true; false values: 0 false no off
#   OCM_CYPRESS_PROJECT_DIR     - explicit project dir (highest priority)
#   OCM_CYPRESS_EXTRA_ARGS      - optional whitespace-separated extra args
#   OCM_CYPRESS_AUTOLAUNCH_MODE - once (default) or supervise
#   OCM_CYPRESS_MAXIMIZE        - default true; passes --start-maximized
#                                 via ELECTRON_EXTRA_LAUNCH_ARGS and calls
#                                 the shared maximize helper (~25 s, 1 s interval)
#   OCM_CYPRESS_SEED_PROXY_CA   - default true; false values: 0 false no off
#                                 skip seeding the Cypress proxy CA from DockyPody
#   OCM_CYPRESS_CA_NAME         - CA keypair name (highest priority)
#   MITM_CA_NAME                - fallback CA name
#   TLS_CA_NAME                 - fallback CA name (default "dockypody")
#
# Project resolution order:
#   1. OCM_CYPRESS_PROJECT_DIR if non-empty and valid
#   2. /workspace if it is a valid Cypress project
#   3. /workspace/cypress/ocm-test-suite (legacy fallback)
#
# A valid Cypress project contains one of:
#   cypress.config.ts, cypress.config.js,
#   cypress.config.mjs, cypress.config.cjs

def is-falsy [val: string]: nothing -> bool {
    $val in ["0" "false" "no" "off"]
}

def is-valid-cypress-project [dir: string]: nothing -> bool {
    if not ($dir | path exists) {
        return false
    }
    let configs = [
        "cypress.config.ts"
        "cypress.config.js"
        "cypress.config.mjs"
        "cypress.config.cjs"
    ]
    $configs | any {|cfg| ($"($dir)/($cfg)" | path exists)}
}

def resolve-project-dir []: nothing -> string {
    let explicit = ($env.OCM_CYPRESS_PROJECT_DIR? | default "" | str trim)
    if not ($explicit | is-empty) {
        if (is-valid-cypress-project $explicit) {
            return $explicit
        }
        print $"WARNING: OCM_CYPRESS_PROJECT_DIR '($explicit)' is not a valid Cypress project - checking fallbacks."
    }
    if (is-valid-cypress-project "/workspace") {
        return "/workspace"
    }
    if (is-valid-cypress-project "/workspace/cypress/ocm-test-suite") {
        return "/workspace/cypress/ocm-test-suite"
    }
    ""
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

def launch-cypress [project_dir: string, extra_args: list<string>]: nothing -> nothing {
    let base = if ($project_dir | is-empty) {
        ["open"]
    } else {
        ["open" "--project" $project_dir]
    }
    let args = $base | append $extra_args
    ^/usr/local/bin/cypress ...$args
}

# Best-effort fallback: maximize the active window via the shared helper.
# Spawns background maximize attempts for ~25 s; does not block startup.
# Delegates to /dockerstartup/ocm-window-actions.nu; no-op if file is missing.
def call-maximize-loop [maximize: bool]: nothing -> nothing {
    if not $maximize { return }
    if not ("/dockerstartup/ocm-window-actions.nu" | path exists) { return }
    ^/usr/local/bin/nu /dockerstartup/ocm-window-actions.nu --maximize
}

def resolve-ca-name []: nothing -> string {
    let from_cypress = ($env.OCM_CYPRESS_CA_NAME? | default "")
    if not ($from_cypress | is-empty) { return $from_cypress }
    let from_mitm = ($env.MITM_CA_NAME? | default "")
    if not ($from_mitm | is-empty) { return $from_mitm }
    let from_tls = ($env.TLS_CA_NAME? | default "")
    if not ($from_tls | is-empty) { return $from_tls }
    "dockypody"
}

def find-ca-source-dir [ca_name: string]: nothing -> string {
    for dir in ["/certificate-authority" "/opt/dockypody/certificate-authority-default"] {
        if (($"($dir)/($ca_name).crt" | path exists) and ($"($dir)/($ca_name).key" | path exists)) {
            return $dir
        }
    }
    ""
}

def resolve-proxy-dir []: nothing -> string {
    let home = ($env.HOME? | default "")
    if ($home | is-empty) { return "" }
    let production = $"($home)/.config/Cypress/cy/production/proxy"
    if ($production | path exists) {
        return $production
    }
    let cy_dir = $"($home)/.config/Cypress/cy"
    let others = if ($cy_dir | path exists) {
        glob $"($cy_dir)/*/proxy"
    } else {
        []
    }
    if not ($others | is-empty) {
        return ($others | first)
    }
    $production
}

def seed-proxy-ca []: nothing -> nothing {
    let seed_flag = (
        $env.OCM_CYPRESS_SEED_PROXY_CA?
        | default "true"
        | str downcase
        | str trim
    )
    if (is-falsy $seed_flag) { return }

    let ca_name = (resolve-ca-name)
    let src_dir = (find-ca-source-dir $ca_name)
    if ($src_dir | is-empty) {
        print "No DockyPody CA keypair found, skipping proxy CA seeding"
        return
    }

    let proxy_dir = (resolve-proxy-dir)
    if ($proxy_dir | is-empty) {
        print "WARNING: Cannot resolve Cypress proxy dir, skipping proxy CA seeding"
        return
    }

    print $"Seeding Cypress proxy CA from ($src_dir)/($ca_name).{crt,key}"

    let certs_dir = $"($proxy_dir)/certs"
    let keys_dir = $"($proxy_dir)/keys"
    mkdir $certs_dir
    mkdir $keys_dir

    cp $"($src_dir)/($ca_name).crt" $"($certs_dir)/ca.pem"
    cp $"($src_dir)/($ca_name).key" $"($keys_dir)/ca.private.key"

    let node_code = "const fs=require('fs'),cr=require('crypto');const p=fs.readFileSync(process.env.PRIV_PATH);fs.writeFileSync(process.env.PUB_PATH,cr.createPublicKey(p).export({type:'spki',format:'pem'}));"
    try {
        with-env {PRIV_PATH: $"($keys_dir)/ca.private.key", PUB_PATH: $"($keys_dir)/ca.public.key"} {
            ^node -e $node_code
        }
    } catch {|err|
        print $"WARNING: Failed to generate CA public key: ($err.msg)"
    }

    "1" | save --force $"($proxy_dir)/ca_version.txt"

    let host_certs = (
        glob $"($certs_dir)/*.pem"
        | where {|f| ($f | path basename) != "ca.pem"}
    )
    let host_priv_keys = (
        glob $"($keys_dir)/*.key"
        | where {|f|
            let name = ($f | path basename)
            ((not ($name | str ends-with ".public.key"))
                and ($name != "ca.private.key"))
        }
    )
    let host_pub_keys = (
        glob $"($keys_dir)/*.public.key"
        | where {|f| ($f | path basename) != "ca.public.key"}
    )

    let n_certs = ($host_certs | length)
    let n_keys = (($host_priv_keys | length) + ($host_pub_keys | length))

    for f in $host_certs { rm $f }
    for f in $host_priv_keys { rm $f }
    for f in $host_pub_keys { rm $f }

    print $"Cleared ($n_certs) cached host certs and ($n_keys) keys"
}

def main [] {
    let autolaunch = (
        $env.OCM_CYPRESS_AUTOLAUNCH?
        | default "true"
        | str downcase
        | str trim
    )
    if (is-falsy $autolaunch) {
        idle-forever "OCM_CYPRESS_AUTOLAUNCH disabled - supervisor idle."
    }

    wait-for-desktop

    $env.DISPLAY = ($env.DISPLAY? | default ":1")
    let display = $env.DISPLAY

    apply-desktop-env

    try {
        seed-proxy-ca
    } catch {|err|
        print $"WARNING: Proxy CA seeding failed: ($err.msg)"
    }

    let maximize_raw = (
        $env.OCM_CYPRESS_MAXIMIZE?
        | default "true"
        | str downcase
        | str trim
    )
    let maximize = not (is-falsy $maximize_raw)
    if $maximize {
        let existing = ($env.ELECTRON_EXTRA_LAUNCH_ARGS? | default "")
        if not ($existing | str contains "--start-maximized") {
            $env.ELECTRON_EXTRA_LAUNCH_ARGS = if ($existing | str trim | is-empty) {
                "--start-maximized"
            } else {
                $"($existing) --start-maximized"
            }
        }
    }

    let project_dir = (resolve-project-dir)
    if ($project_dir | is-empty) {
        print "WARNING: No valid Cypress project found (tried OCM_CYPRESS_PROJECT_DIR, /workspace, /workspace/cypress/ocm-test-suite) - launching Cypress without a project."
    } else {
        print $"Cypress project: ($project_dir)"
    }

    let extra_raw = ($env.OCM_CYPRESS_EXTRA_ARGS? | default "")
    let extra_args = if ($extra_raw | str trim | is-empty) {
        []
    } else {
        $extra_raw | split row --regex '\s+' | where {|a| not ($a | is-empty)}
    }

    let mode = (
        $env.OCM_CYPRESS_AUTOLAUNCH_MODE?
        | default "once"
        | str downcase
        | str trim
    )

    if $mode == "supervise" {
        print (["Starting Cypress in supervise mode (DISPLAY=" $display ")."] | str join)
        loop {
            try {
                call-maximize-loop $maximize
                launch-cypress $project_dir $extra_args
            } catch {|err|
                print $"Cypress exited with error: ($err.msg)"
            }
            print "Cypress exited, restarting in 2s..."
            ^sleep 2
        }
    } else {
        print (["Starting Cypress (once, DISPLAY=" $display ")."] | str join)
        call-maximize-loop $maximize
        try {
            launch-cypress $project_dir $extra_args
        } catch {|err|
            print $"Cypress exited with error: ($err.msg)"
        }
        idle-forever "Cypress exited - supervisor idle."
    }
}
