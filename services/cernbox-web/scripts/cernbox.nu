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
    
    # Gateway environment variables
    let gateway_host = (try { $env.REVAD_GATEWAY_HOST } catch { "cernbox-1-test-revad-gateway" })
    let gateway_port = (try { $env.REVAD_GATEWAY_PORT } catch { $revad_port })
    
    # Export vars for nginx template processing
    $env.REVAD_PROTOCOL = $revad_protocol
    $env.REVAD_GATEWAY_HOST = $gateway_host
    $env.REVAD_GATEWAY_PORT = $gateway_port
    $env.CERNBOX = $cernbox_web_hostname
    
    let idp_domain = (try { $env.IDP_DOMAIN } catch { "idp.docker" })
    # Construct IDP_URL from IDP_DOMAIN, IDP_PORT, and IDP_PROTOCOL if IDP_URL is not provided
    $env.IDP_URL = (try { $env.IDP_URL } catch {
        let idp_port = (try { $env.IDP_PORT } catch {
            if $revad_tls_enabled == "false" { "80" } else { "443" }
        })
        let idp_protocol = (try { $env.IDP_PROTOCOL } catch {
            if $revad_tls_enabled == "false" { "http" } else { "https" }
        })
        $"($idp_protocol)://($idp_domain):($idp_port)"
    })
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
        | str replace -a '$REVAD_PROTOCOL' $revad_protocol
        | str replace -a '$REVAD_GATEWAY_HOST' $gateway_host
        | str replace -a '$REVAD_GATEWAY_PORT' $gateway_port
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
    
    if not ($config_dest | path exists) {
        if not ($CONFIG_DIR | path exists) {
            error make { msg: $"Config dir not found: ($CONFIG_DIR)" }
        }
        ^cp $config_source $config_dest
        ^chown nginx:nginx $config_dest
        
        # Replace web server URL (your.nginx.org -> actual hostname)
        # Use WEB_DOMAIN if available, otherwise use CERNBOX_WEB_HOSTNAME
        let web_domain = (try { $env.WEB_DOMAIN } catch { $cernbox_web_hostname })
        # Prioritize WEB_PROTOCOL if set (external protocol, e.g., HTTPS via Traefik)
        # Fallback to deriving from WEB_TLS_ENABLED if WEB_PROTOCOL not set
        let web_protocol = (try { $env.WEB_PROTOCOL } catch {
            (if $web_tls_enabled == "false" { "http" } else { "https" })
        })
        let web_url = $"($web_protocol)://($web_domain)"
        let web_pattern = "https://your.nginx.org"
        ^sed -i $"s|($web_pattern)|($web_url)|g" $config_dest
        
        # Replace IDP URL (your-idp.org:your-idp-port -> actual IDP URL)
        # Parse IDP_URL to extract hostname:port, or construct from IDP_DOMAIN, IDP_PORT, and IDP_PROTOCOL
        let idp_url_final = (try { $env.IDP_URL } catch {
            let idp_domain_final = (try { $env.IDP_DOMAIN } catch { "idp.docker" })
            let idp_port_final = (try { $env.IDP_PORT } catch { 
                if $revad_tls_enabled == "false" { "80" } else { "443" }
            })
            let idp_protocol_final = (try { $env.IDP_PROTOCOL } catch {
                if $revad_tls_enabled == "false" { "http" } else { "https" }
            })
            $"($idp_protocol_final)://($idp_domain_final):($idp_port_final)"
        })
        # Extract hostname:port from IDP_URL (remove protocol)
        let idp_host_port = ($idp_url_final | str replace -a "https://" "" | str replace -a "http://" "")
        let idp_pattern = "your-idp.org:your-idp-port"
        ^sed -i $"s|($idp_pattern)|($idp_host_port)|g" $config_dest
    }
    
    # Replace mesh directory endpoint in built JS files
    let meshdir_original = "sciencemesh.cesnet.cz/iop"
    let meshdir_replacement = (try { $env.MESHDIR_DOMAIN } catch { "meshdir.docker" })
    let find_result = (^find /var/www/web -name "web-app-science*.mjs" -type f 2>/dev/null | complete)
    if $find_result.exit_code == 0 and ($find_result.stdout | str trim | str length) > 0 {
        ^find /var/www/web -name "web-app-science*.mjs" -type f -exec sed -i $"s|($meshdir_original)|($meshdir_replacement)|g" {} \;
    }
}
