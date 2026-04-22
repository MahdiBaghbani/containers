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

def main [...args: string] {
    let conf_dir = ($env.MITMPROXY_CONFDIR? | default "/tmp/mitmproxy/conf")

    # Determine command and remaining args.
    let is_empty = ($args | is-empty)
    let cmd = if $is_empty { resolve_default_cmd } else { $args | first }
    let rest = if $is_empty { [] } else { $args | skip 1 }

    # Resolve CA name and set up the CA PEM when a keypair is available.
    let ca_name = resolve_ca_name
    if $ca_name != null {
        let ca_dir = find_ca_dir $ca_name
        setup_conf_dir $conf_dir $ca_dir $ca_name
    } else {
        let ca_required = ($env.MITM_CA_REQUIRED? | default "true" | str downcase)
        if $ca_required != "false" {
            error make {
                msg: "No CA keypair found. Set MITM_CA_NAME, TLS_CA_NAME, or mount a keypair. Set MITM_CA_REQUIRED=false to run without CA setup."
            }
        }
        print "No CA keypair found - skipping CA setup (MITM_CA_REQUIRED=false)"
    }

    # Inject mitmweb UI defaults and optional password.
    let rest_with_defaults = (inject_mitmweb_defaults $cmd $rest)

    # Start nginx TLS termination when mitmweb is the command and termination is enabled.
    if $cmd == "mitmweb" {
        let ui_tls = ($env.MITM_UI_TLS_TERMINATION? | default "true" | str downcase)
        if $ui_tls == "true" {
            start_nginx_for_mitmweb
        }
    }

    # Inject confdir unless already present in args.
    let has_confdir = ($rest_with_defaults | any {|a| ($a | str contains "confdir")})
    let final_args = if $has_confdir {
        $rest_with_defaults
    } else {
        $rest_with_defaults | append ["--set" $"confdir=($conf_dir)"]
    }

    print $"Running: ($cmd) ($final_args | str join ' ')"
    exec ^$cmd ...$final_args
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

# Start nginx for HTTPS termination of the mitmweb UI.
# Generates /etc/nginx/conf.d/mitmweb.conf from the committed template,
# then tests and starts nginx.
def start_nginx_for_mitmweb [] {
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
    )
    $processed | save -f $conf_path

    let test_result = (^nginx -t | complete)
    if $test_result.exit_code != 0 {
        error make {
            msg: $"nginx config test failed (nginx -t):\n($test_result.stderr)"
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
