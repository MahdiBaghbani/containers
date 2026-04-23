#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Copyright (C) 2025 Mahdi Baghbani <mahdi-baghbani@azadehafzar.io>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Entrypoint for the mitmproxy service.
#
# Env vars:
#   MITM_UI / MITM_WEB          "true" -> default cmd is mitmweb (when no args)
#   MITM_CA_NAME                CA base name for TLS interception
#   TLS_CA_NAME                 Legacy alias for MITM_CA_NAME
#   MITM_CA_REQUIRED            "false" -> skip CA setup when no keypair found
#                               (default: "true")
#   MITM_UI_TLS_TERMINATION     "false" -> disable nginx for mitmweb HTTPS
#                               (default: "true")
#   MITM_UI_TLS_CRT             Path to TLS cert for nginx (overrides auto-detect)
#   MITM_UI_TLS_KEY             Path to TLS key for nginx (overrides auto-detect)
#   MITM_UI_SERVER_NAME         nginx server_name (default "_")
#   MITM_UI_HTTP_PORT           nginx HTTP listen port (default "80")
#   MITM_UI_HTTPS_PORT          nginx HTTPS listen port (default "443")
#   MITM_UI_UPSTREAM_HOST       mitmweb upstream host (default "127.0.0.1")
#   MITM_UI_UPSTREAM_PORT       mitmweb upstream port
#                               (default: MITM_WEB_PORT if set, else "8081")
#   MITM_WEB_PASSWORD           Optional mitmweb UI password
#   MITM_WEB_PORT               Override mitmweb web_port; also sets upstream port
#   MITMPROXY_CONFDIR           Conf dir (default /tmp/mitmproxy/conf)
#   DOCKYPODY_CA_DIR_MOUNT      Mounted CA dir (default /certificate-authority)
#   DOCKYPODY_CA_DIR_DEFAULT    Baked-in CA dir
#                               (default /opt/dockypody/certificate-authority-default)
#   MITM_UI_AUTO_LOGIN          "true" -> when cmd is mitmweb with TLS termination,
#                               ensure UI is accessible without a login prompt by
#                               injecting a Bearer token into nginx; auto-generates
#                               a token when none is known (default: "true")
#   MITM_UI_BEARER_TOKEN        Optional explicit plaintext token for nginx
#                               Authorization Bearer header injection; must not be
#                               empty/whitespace or contain double-quotes/newlines
#   MITM_UI_PRINT_BEARER_TOKEN  "true" -> print a one-line message revealing the
#                               effective bearer token; otherwise the token is never
#                               printed (default: "false")
#   MITM_UPSTREAM_TRUST_BUNDLE_ENABLE
#                               "false" -> skip injecting ssl_verify_upstream_trusted_ca
#                               into mitmproxy args (default: "true")

def main [...args: string] {
    let conf_dir = ($env.MITMPROXY_CONFDIR? | default "/tmp/mitmproxy/conf")

    # Determine command and remaining args.
    let is_empty = ($args | is-empty)
    let cmd = if $is_empty { resolve_default_cmd } else { $args | first }
    let rest = if $is_empty { [] } else { $args | skip 1 }

    # Resolve CA name and set up the CA PEM when a keypair is available.
    # bundle_path is the upstream trust bundle path when a CA is configured,
    # or null when no CA is present (skips upstream trust injection).
    let ca_name = resolve_ca_name
    let bundle_path = if $ca_name != null {
        let ca_dir = find_ca_dir $ca_name
        setup_conf_dir $conf_dir $ca_dir $ca_name
        build_upstream_trust_bundle $conf_dir $ca_dir $ca_name
    } else {
        let ca_required = ($env.MITM_CA_REQUIRED? | default "true" | str downcase)
        if $ca_required != "false" {
            error make {
                msg: "No CA keypair found. Set MITM_CA_NAME, TLS_CA_NAME, or mount a keypair. Set MITM_CA_REQUIRED=false to run without CA setup."
            }
        }
        print "No CA keypair found - skipping CA setup (MITM_CA_REQUIRED=false)"
        null
    }

    # Inject mitmweb UI defaults and optional password.
    let rest_with_defaults = (inject_mitmweb_defaults $cmd $rest)

    # Resolve bearer token using original args (before defaults injection) so
    # we do not double-count a password that inject_mitmweb_defaults appended.
    let auth_result = (resolve_bearer_token $cmd $rest)
    let auth_header_block = if $auth_result.token != null {
        $"    proxy_set_header Authorization \"Bearer ($auth_result.token)\";"
    } else {
        ""
    }

    # Start nginx TLS termination when mitmweb is the command and termination is enabled.
    if $cmd == "mitmweb" {
        let ui_tls = ($env.MITM_UI_TLS_TERMINATION? | default "true" | str downcase)
        if $ui_tls == "true" {
            start_nginx_for_mitmweb $auth_header_block
        }
    }

    # Merge defaults, any auto-generated password arg, then confdir.
    let augmented = ($rest_with_defaults | append $auth_result.extra_args)
    let has_confdir = ($augmented | any {|a| ($a | str contains "confdir")})
    let with_confdir = if $has_confdir {
        $augmented
    } else {
        $augmented | append ["--set" $"confdir=($conf_dir)"]
    }

    # Inject upstream CA trust option when a CA bundle is available.
    let final_args = (inject_upstream_trust_args $with_confdir $bundle_path)

    # exec does not support the ^$var sigil form; resolve to an absolute path first.
    let cmd_path = if ($cmd | str contains "/") {
        $cmd
    } else {
        let found = (which $cmd)
        if ($found | is-empty) {
            error make {msg: $"Command not found: '($cmd)'. Ensure it is installed and on PATH."}
        }
        $found | first | get path
    }

    print $"Running: ($cmd) ($final_args | str join ' ')"
    exec $cmd_path ...$final_args
}

# Return "mitmweb" when MITM_UI or MITM_WEB is "true", else "mitmdump".
def resolve_default_cmd [] {
    let ui = ($env.MITM_UI? | default "" | str downcase)
    let web = ($env.MITM_WEB? | default "" | str downcase)
    if ($ui == "true") or ($web == "true") { "mitmweb" } else { "mitmdump" }
}

# Return a CA name from env overrides or by auto-detecting a keypair on disk.
# Returns null when no CA name can be determined.
def resolve_ca_name [] {
    let explicit = ($env.MITM_CA_NAME? | default "" | str trim)
    if not ($explicit | is-empty) { return $explicit }

    let legacy = ($env.TLS_CA_NAME? | default "" | str trim)
    if not ($legacy | is-empty) { return $legacy }

    auto_detect_ca_name
}

# Scan mount dir then default dir for a matching *.crt + *.key pair.
# Returns the base name (without extension) of the first pair found, or null.
def auto_detect_ca_name [] {
    let mount_dir = ($env.DOCKYPODY_CA_DIR_MOUNT? | default "/certificate-authority")
    let default_dir = ($env.DOCKYPODY_CA_DIR_DEFAULT? | default "/opt/dockypody/certificate-authority-default")

    for dir in [$mount_dir $default_dir] {
        if ($dir | path exists) {
            let name = (find_keypair_in_dir $dir)
            if $name != null {
                print $"Auto-detected CA '($name)' in ($dir)"
                return $name
            }
        }
    }
    null
}

# Return the stem of the first *.crt whose matching *.key also exists, or null.
def find_keypair_in_dir [dir: string] {
    let crt_files = (glob $"($dir)/*.crt")
    for crt in $crt_files {
        let stem = ($crt | path parse | get stem)
        if ($"($dir)/($stem).key" | path exists) {
            return $stem
        }
    }
    null
}

# Find a CA dir that contains both <ca_name>.crt and <ca_name>.key.
def find_ca_dir [ca_name: string] {
    let mount_dir = ($env.DOCKYPODY_CA_DIR_MOUNT? | default "/certificate-authority")
    let default_dir = ($env.DOCKYPODY_CA_DIR_DEFAULT? | default "/opt/dockypody/certificate-authority-default")

    if (ca_dir_has_keypair $mount_dir $ca_name) {
        print $"Using mounted CA directory: ($mount_dir)"
        return $mount_dir
    }

    if (ca_dir_has_keypair $default_dir $ca_name) {
        print $"Using default CA directory: ($default_dir)"
        return $default_dir
    }

    error make {
        msg: $"CA keypair not found for '($ca_name)'. Checked: ($mount_dir), ($default_dir)"
    }
}

# Check whether a directory contains both the cert and key files.
def ca_dir_has_keypair [dir: string, ca_name: string] {
    if not ($dir | path exists) {
        return false
    }
    let crt = $"($dir)/($ca_name).crt"
    let key = $"($dir)/($ca_name).key"
    ($crt | path exists) and ($key | path exists)
}

# Create the mitmproxy conf dir and write the combined CA PEM file.
def setup_conf_dir [conf_dir: string, ca_dir: string, ca_name: string] {
    try {
        ^mkdir -p $conf_dir
        ^chmod 700 $conf_dir
    } catch {|err|
        print $"Warning: could not set permissions on ($conf_dir): ($err.msg)"
    }

    let key_path = $"($ca_dir)/($ca_name).key"
    let crt_path = $"($ca_dir)/($ca_name).crt"
    let pem_path = $"($conf_dir)/mitmproxy-ca.pem"

    let key_content = (open --raw $key_path)
    let crt_content = (open --raw $crt_path)

    # mitmproxy expects key then cert concatenated in the CA PEM.
    $"($key_content)($crt_content)" | save --force $pem_path

    try {
        ^chmod 600 $pem_path
    } catch {|err|
        print $"Warning: could not set permissions on ($pem_path): ($err.msg)"
    }

    print $"CA PEM written to: ($pem_path)"
}

# Write a combined upstream trust bundle to <conf_dir>/upstream-ca-bundle.pem.
# Concatenates the system CA bundle (if present) and the DockyPody CA cert so
# that mitmproxy trusts both public CAs and DockyPody-issued service certs when
# verifying upstream connections.  The file is rewritten deterministically on
# every start.  Returns the bundle path.
def build_upstream_trust_bundle [conf_dir: string, ca_dir: string, ca_name: string] {
    let bundle_path = $"($conf_dir)/upstream-ca-bundle.pem"
    let ca_crt_path = $"($ca_dir)/($ca_name).crt"
    let system_bundle = "/etc/ssl/certs/ca-certificates.crt"

    let system_content = if ($system_bundle | path exists) {
        open --raw $system_bundle
    } else {
        ""
    }
    let ca_content = (open --raw $ca_crt_path)

    $"($system_content)($ca_content)" | save --force $bundle_path

    try {
        ^chmod 644 $bundle_path
    } catch {|err|
        print $"Warning: could not set permissions on ($bundle_path): ($err.msg)"
    }

    print $"Upstream trust bundle written to: ($bundle_path)"
    $bundle_path
}

# Append mitmweb UI defaults when cmd is "mitmweb" and the flags are absent.
# Guards accept both underscore and hyphen CLI forms so that user-supplied
# --web-host or --set web_host=... both suppress the default injection.
def inject_mitmweb_defaults [cmd: string, rest: list<string>] {
    if $cmd != "mitmweb" {
        return $rest
    }
    mut augmented = $rest
    let has_host = ($rest | any {|a| ($a | str contains "web_host") or ($a | str contains "web-host")})
    if not $has_host {
        $augmented = ($augmented | append ["--set" "web_host=0.0.0.0"])
    }
    let has_open = ($rest | any {|a| ($a | str contains "web_open_browser") or ($a | str contains "web-open-browser") or ($a | str contains "web_open")})
    if not $has_open {
        $augmented = ($augmented | append ["--set" "web_open_browser=false"])
    }
    let web_password = ($env.MITM_WEB_PASSWORD? | default "")
    let has_password = ($rest | any {|a| ($a | str contains "web_password") or ($a | str contains "web-password")})
    if (not ($web_password | is-empty)) and (not $has_password) {
        $augmented = ($augmented | append ["--set" $"web_password=($web_password)"])
    }
    let web_port = ($env.MITM_WEB_PORT? | default "")
    let has_web_port = ($rest | any {|a| ($a | str contains "web_port") or ($a | str contains "web-port")})
    if (not ($web_port | is-empty)) and (not $has_web_port) {
        $augmented = ($augmented | append ["--set" $"web_port=($web_port)"])
    }
    $augmented
}

# Append --set ssl_verify_upstream_trusted_ca=<bundle_path> to args unless the
# operator has already configured upstream verification or disabled the feature.
#
# Skips injection when:
#   - bundle_path is null (no CA was configured)
#   - MITM_UPSTREAM_TRUST_BUNDLE_ENABLE is "false"
#   - args already contain ssl_verify_upstream_trusted_ca,
#     ssl_verify_upstream_trusted_confdir, ssl_insecure, --ssl-insecure, or -k
def inject_upstream_trust_args [args: list<string>, bundle_path: any] {
    if $bundle_path == null {
        return $args
    }

    let enable = ($env.MITM_UPSTREAM_TRUST_BUNDLE_ENABLE? | default "true" | str downcase)
    if $enable == "false" {
        return $args
    }

    let already_set = ($args | any {|a|
        (($a | str contains "ssl_verify_upstream_trusted_ca")
            or ($a | str contains "ssl_verify_upstream_trusted_confdir")
            or ($a | str contains "ssl_insecure")
            or ($a == "--ssl-insecure")
            or ($a == "-k"))
    })
    if $already_set {
        return $args
    }

    print $"Injecting upstream CA trust: ssl_verify_upstream_trusted_ca=($bundle_path)"
    $args | append ["--set" $"ssl_verify_upstream_trusted_ca=($bundle_path)"]
}

# Resolve the effective bearer token for nginx Authorization header injection.
#
# Preconditions checked here (returns {token: null, extra_args: []} on skip):
#   - cmd must be "mitmweb"
#   - MITM_UI_TLS_TERMINATION must be "true"
#   - MITM_UI_AUTO_LOGIN must be "true"
#
# Resolution order:
#   1. MITM_UI_BEARER_TOKEN env (explicit, non-empty)
#   2. MITM_WEB_PASSWORD env (plaintext, i.e. not starting with '$')
#   3. CLI args: "--set web_password=...", "web_password=...", "--web-password ..."
#   4. Auto-generate via openssl rand -hex 16 (only when no password is set anywhere)
#
# Returns {token: string|null, extra_args: list<string>}.
# extra_args is ["--set" "web_password=<token>"] only for the auto-generate case.
def resolve_bearer_token [cmd: string, args: list<string>] {
    if $cmd != "mitmweb" {
        return {token: null, extra_args: []}
    }
    let ui_tls = ($env.MITM_UI_TLS_TERMINATION? | default "true" | str downcase)
    if $ui_tls != "true" {
        return {token: null, extra_args: []}
    }
    let auto_login = ($env.MITM_UI_AUTO_LOGIN? | default "true" | str downcase)
    if $auto_login != "true" {
        return {token: null, extra_args: []}
    }

    let bearer_env = ($env.MITM_UI_BEARER_TOKEN? | default "" | str trim)
    let web_pw_env = ($env.MITM_WEB_PASSWORD? | default "" | str trim)

    # Guard: both env vars are plaintext but differ -> operator error.
    if (not ($bearer_env | is-empty)) and (not ($web_pw_env | is-empty)) and (not ($web_pw_env | str starts-with "$")) {
        if $bearer_env != $web_pw_env {
            error make {
                msg: "MITM_UI_BEARER_TOKEN and MITM_WEB_PASSWORD are both set as plaintext but differ. Align them or unset MITM_UI_BEARER_TOKEN to derive the token from MITM_WEB_PASSWORD."
            }
        }
    }

    # 1. Explicit bearer token env.
    if not ($bearer_env | is-empty) {
        validate_bearer_token_safety $bearer_env
        maybe_print_bearer_token $bearer_env
        return {token: $bearer_env, extra_args: []}
    }

    # 2. Plaintext web password from env.
    if (not ($web_pw_env | is-empty)) and (not ($web_pw_env | str starts-with "$")) {
        validate_bearer_token_safety $web_pw_env
        maybe_print_bearer_token $web_pw_env
        return {token: $web_pw_env, extra_args: []}
    }

    # 3. Extract plaintext web_password from CLI args.
    let from_args = (extract_web_password_from_args $args)
    if $from_args != null {
        validate_bearer_token_safety $from_args
        maybe_print_bearer_token $from_args
        return {token: $from_args, extra_args: []}
    }

    # 4. Auto-generate only when no password is configured at all.
    # If a password exists but is hashed (argon2 starts with '$'), skip injection.
    let has_pw_arg = ($args | any {|a| ($a | str contains "web_password") or ($a | str contains "web-password")})
    if (not ($web_pw_env | is-empty)) or $has_pw_arg {
        return {token: null, extra_args: []}
    }

    let gen = (try {
        ^openssl rand -hex 16 | complete
    } catch {
        error make {
            msg: "openssl is not available; cannot auto-generate a bearer token. Install openssl or set MITM_UI_AUTO_LOGIN=false to skip injection."
        }
    })
    if $gen.exit_code != 0 {
        error make {msg: $"Failed to auto-generate bearer token via openssl rand -hex 16: ($gen.stderr)"}
    }
    let generated = ($gen.stdout | str trim)
    validate_bearer_token_safety $generated
    maybe_print_bearer_token $generated
    {token: $generated, extra_args: ["--set" $"web_password=($generated)"]}
}

# Extract a plaintext web_password value from CLI args.
# Handles: "--set web_password=VALUE", "web_password=VALUE", "--web-password VALUE".
# Returns null when not found or when the value starts with '$' (argon2 hash).
def extract_web_password_from_args [args: list<string>] {
    let n = ($args | length)

    # Standalone positional form: "web_password=VALUE"
    for a in $args {
        if ($a | str starts-with "web_password=") {
            let val = ($a | str replace "web_password=" "")
            if not ($val | str starts-with "$") { return $val }
        }
    }

    # Two-token forms: "--set web_password=VALUE" or "--web-password VALUE"
    let indexed = ($args | enumerate)
    for e in $indexed {
        let i = $e.index
        let a = $e.item
        if ($a == "--set") and (($i + 1) < $n) {
            let next = ($args | get ($i + 1))
            if ($next | str starts-with "web_password=") {
                let val = ($next | str replace "web_password=" "")
                if not ($val | str starts-with "$") { return $val }
            }
        }
        if ($a == "--web-password") and (($i + 1) < $n) {
            let val = ($args | get ($i + 1))
            if not ($val | str starts-with "$") { return $val }
        }
    }

    null
}

# Error out when the token contains characters that would break nginx config.
def validate_bearer_token_safety [token: string] {
    if ($token | str contains "\"") {
        error make {
            msg: "Bearer token contains a double-quote character, which is unsafe in nginx config. Provide a token without double quotes."
        }
    }
    if ($token | str contains "\n") {
        error make {
            msg: "Bearer token contains a newline character, which is unsafe in nginx config. Provide a single-line token."
        }
    }
}

# Print the effective bearer token when MITM_UI_PRINT_BEARER_TOKEN is "true".
def maybe_print_bearer_token [token: string] {
    let print_it = ($env.MITM_UI_PRINT_BEARER_TOKEN? | default "false" | str downcase)
    if $print_it == "true" {
        print $"mitmweb bearer token: ($token)"
    }
}

# Start nginx for HTTPS termination of the mitmweb UI.
# Generates /etc/nginx/conf.d/mitmweb.conf from the committed template,
# then tests and starts nginx.
# auth_header_block: nginx directive line to inject (e.g. the Authorization
# proxy_set_header line), or empty string to omit it.
def start_nginx_for_mitmweb [auth_header_block: string] {
    let tls = (resolve_nginx_tls)

    let server_name = ($env.MITM_UI_SERVER_NAME? | default "_")
    let http_port = ($env.MITM_UI_HTTP_PORT? | default "80")
    let https_port = ($env.MITM_UI_HTTPS_PORT? | default "443")
    let upstream_host = ($env.MITM_UI_UPSTREAM_HOST? | default "127.0.0.1")
    let web_port_env = ($env.MITM_WEB_PORT? | default "")
    let upstream_port = (
        $env.MITM_UI_UPSTREAM_PORT? | default (
            if not ($web_port_env | is-empty) { $web_port_env } else { "8081" }
        )
    )

    let template_path = "/etc/nginx/templates-available/mitmweb.conf.template"
    let conf_path = "/etc/nginx/conf.d/mitmweb.conf"
    let template_content = (open --raw $template_path)
    let processed = ($template_content
        | str replace -a '$MITM_UI_HTTP_PORT' $http_port
        | str replace -a '$MITM_UI_HTTPS_PORT' $https_port
        | str replace -a '$MITM_UI_SERVER_NAME' $server_name
        | str replace -a '$TLS_CRT' $tls.crt
        | str replace -a '$TLS_KEY' $tls.key
        | str replace -a '$MITM_UI_UPSTREAM_HOST' $upstream_host
        | str replace -a '$MITM_UI_UPSTREAM_PORT' $upstream_port
        | str replace -a '$MITM_UI_AUTHZ_HEADER_BLOCK' $auth_header_block
    )
    $processed | save -f $conf_path

    let test_result = (^nginx -t | complete)
    if $test_result.exit_code != 0 {
        error make {
            msg: $"nginx config test failed - nginx -t:\n($test_result.stderr)"
        }
    }

    let start_result = (^nginx | complete)
    if $start_result.exit_code != 0 {
        error make {
            msg: $"nginx failed to start:\n($start_result.stderr)"
        }
    }

    print "nginx started for mitmweb HTTPS termination"
}

# Resolve the TLS cert/key paths for nginx.
# Uses MITM_UI_TLS_CRT / MITM_UI_TLS_KEY when set, otherwise auto-detects
# the first *.crt + *.key pair under /tls.
def resolve_nginx_tls [] {
    let explicit_crt = ($env.MITM_UI_TLS_CRT? | default "" | str trim)
    let explicit_key = ($env.MITM_UI_TLS_KEY? | default "" | str trim)

    if (not ($explicit_crt | is-empty)) and (not ($explicit_key | is-empty)) {
        return {crt: $explicit_crt, key: $explicit_key}
    }

    let tls_dir = "/tls"
    let stem = (find_keypair_in_dir $tls_dir)
    if $stem != null {
        return {
            crt: $"($tls_dir)/($stem).crt"
            key: $"($tls_dir)/($stem).key"
        }
    }

    error make {
        msg: "No TLS keypair found for nginx. Set MITM_UI_TLS_CRT and MITM_UI_TLS_KEY, or mount a *.crt/*.key pair under /tls."
    }
}
