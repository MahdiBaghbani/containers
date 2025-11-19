#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# Open Cloud Mesh Containers: container build scripts and images
# Copyright (C) 2025 Open Cloud Mesh Contributors
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

# CERNBox web frontend configuration script
# Configures nginx templates and frontend config.json based on environment variables

def main [] {
    let cernbox_web_hostname = (try { $env.CERNBOX_WEB_HOSTNAME } catch {
        print "Error: CERNBOX_WEB_HOSTNAME is required"
        exit 1
    })
    
    # Derive REVAD_* vars from REVAD_TLS_ENABLED (backend sets this, web follows)
    let revad_tls_enabled = (try {
        let val = $env.REVAD_TLS_ENABLED
        if ($val | str trim | is-empty) {
            try { $env.TLS_ENABLED } catch { "true" }
        } else {
            $val
        }
    } catch {
        try { $env.TLS_ENABLED } catch { "true" }
    })
    
    let revad_protocol = (if $revad_tls_enabled == "false" {
        try { $env.REVAD_PROTOCOL } catch { "http" }
    } else {
        try { $env.REVAD_PROTOCOL } catch { "https" }
    })
    
    let revad_port = (if $revad_tls_enabled == "false" {
        try { $env.REVAD_PORT } catch { "80" }
    } else {
        try { $env.REVAD_PORT } catch { "443" }
    })
    
    # REVAD_HOST defaults to CERNBOX_WEB_HOSTNAME but can be overridden
    let revad_host = (try { $env.REVAD_HOST } catch { $cernbox_web_hostname })
    
    # Validate all REVAD_* vars are set
    if ($revad_protocol | str trim | is-empty) or ($revad_port | str trim | is-empty) or ($revad_host | str trim | is-empty) {
        print $"Error: Failed to derive REVAD_PROTOCOL, REVAD_PORT, or REVAD_HOST"
        print $"  REVAD_PROTOCOL=($revad_protocol)"
        print $"  REVAD_PORT=($revad_port)"
        print $"  REVAD_HOST=($revad_host)"
        exit 1
    }
    
    # Export vars for nginx envsubst processing
    $env.REVAD_PROTOCOL = $revad_protocol
    $env.REVAD_PORT = $revad_port
    $env.REVAD_HOST = $revad_host
    $env.CERNBOX = $cernbox_web_hostname
    
    let idp_domain = (try { $env.IDP_DOMAIN } catch { "idp.docker" })
    $env.IDP_URL = (try { $env.IDP_URL } catch { $"https://($idp_domain)" })
    $env.TLS_CRT = (try { $env.TLS_CRT } catch { "/tls/server.crt" })
    $env.TLS_KEY = (try { $env.TLS_KEY } catch { "/tls/server.key" })
    
    # Frontend TLS can be controlled independently from backend
    let web_tls_enabled = (try { $env.WEB_TLS_ENABLED } catch { $revad_tls_enabled })
    
    let templates_dir = "/etc/nginx/templates-available"
    let nginx_conf = "/etc/nginx/conf.d/cernbox.conf"
    let source_template = (if $web_tls_enabled == "false" {
        $"($templates_dir)/cernbox-http.conf.template"
    } else {
        $"($templates_dir)/cernbox-https.conf.template"
    })
    
    # Process template manually (not in /etc/nginx/templates/) to avoid nginx entrypoint auto-processing
    # Use Nushell string substitution instead of envsubst (more reliable and doesn't require external deps)
    let template_content = (open $source_template)
    let processed_content = ($template_content
        | str replace -a '$REVAD_HOST' $revad_host
        | str replace -a '$REVAD_PORT' $revad_port
        | str replace -a '$REVAD_PROTOCOL' $revad_protocol
        | str replace -a '$CERNBOX' $cernbox_web_hostname
        | str replace -a '$IDP_URL' (try { $env.IDP_URL } catch { "https://idp.docker" })
        | str replace -a '$TLS_CRT' (try { $env.TLS_CRT } catch { "/tls/server.crt" })
        | str replace -a '$TLS_KEY' (try { $env.TLS_KEY } catch { "/tls/server.key" })
    )
    $processed_content | save -f $nginx_conf
    
    # Copy web assets from image to runtime location if missing (enables mountable volumes)
    let ASSETS_DIR = "/assets/cernbox-web"
    let web_assets_source = $"($ASSETS_DIR)/web"
    let web_assets_dest = "/var/www/web"
    let cernbox_assets_source = $"($ASSETS_DIR)/cernbox"
    let cernbox_assets_dest = "/var/www/cernbox"
    
    if not ($web_assets_dest | path exists) {
        if not ($web_assets_source | path exists) {
            error make { msg: $"Web assets source not found: ($web_assets_source)" }
        }
        # Create parent directory if it doesn't exist
        let parent_dir = ($web_assets_dest | path dirname)
        if not ($parent_dir | path exists) {
            ^mkdir -p $parent_dir
        }
        ^cp -r $web_assets_source $web_assets_dest
        ^chown -R nginx:nginx $web_assets_dest
    }
    
    if not ($cernbox_assets_dest | path exists) {
        if not ($cernbox_assets_source | path exists) {
            error make { msg: $"Cernbox assets source not found: ($cernbox_assets_source)" }
        }
        # Create parent directory if it doesn't exist
        let parent_dir = ($cernbox_assets_dest | path dirname)
        if not ($parent_dir | path exists) {
            ^mkdir -p $parent_dir
        }
        ^cp -r $cernbox_assets_source $cernbox_assets_dest
        ^chown -R nginx:nginx $cernbox_assets_dest
    }
    
    # Copy and template config.json if missing
    let CONFIG_DIR = "/configs/cernbox-web"
    let config_source = $"($CONFIG_DIR)/config.json"
    let config_dest = "/var/www/web/config.json"
    let web_original = "your.nginx.org"
    let web_replacement = $cernbox_web_hostname
    let idp_original = "your-idp.org:your-idp-port"
    let idp_hostname = (try { $env.CERNBOX_IDP_HOSTNAME } catch { "idp.docker" })
    let idp_port = (try { $env.CERNBOX_IDP_PORT } catch { "443" })
    let idp_replacement = $"($idp_hostname):($idp_port)"
    
    if not ($config_dest | path exists) {
        if not ($CONFIG_DIR | path exists) {
            error make { msg: $"Config dir not found: ($CONFIG_DIR)" }
        }
        ^cp $config_source $config_dest
        ^chown nginx:nginx $config_dest
        ^sed -i $"s#($web_original)#($web_replacement)#g" $config_dest
        ^sed -i $"s#($idp_original)#($idp_replacement)#g" $config_dest
    }
    
    # Replace mesh directory endpoint in built JS files
    let meshdir_original = "sciencemesh.cesnet.cz/iop"
    let meshdir_replacement = (try { $env.MESHDIR_DOMAIN } catch { "meshdir.docker" })
    let find_result = (^find /var/www/web -name "web-app-science*.mjs" -type f 2>/dev/null | complete)
    if $find_result.exit_code == 0 and ($find_result.stdout | str trim | str length) > 0 {
        ^find /var/www/web -name "web-app-science*.mjs" -type f -exec sed -i $"s|($meshdir_original)|($meshdir_replacement)|g" {} \;
    }
}
