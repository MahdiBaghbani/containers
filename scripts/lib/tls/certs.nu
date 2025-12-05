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

# Generate certificates for all TLS-enabled services
# See docs/concepts/tls-management.md

use ./lib.nu [
    ensure-service-tls-dirs
    copy-shared-ca-to-service
    read-shared-ca-name
]
use ./cert.nu [generate-cert]
use ../services/core.nu [list-services]

export def generate-all-certs [
    --domain-suffix: string = "docker",
    --instance-count: int = 1,
    --filter: list<string> = [],  # optional allow-list of service names
    --force-copy-ca,
    --verbose,
] {
    let ca_name = (read-shared-ca-name)
    if $ca_name == null {
        error make {msg: "CA metadata file not found. Run 'dockypody tls ca' first"}
    }
    
    let all_services = (list-services --tls-only)
    let enabled_services = (if ($filter | is-empty) {
        $all_services
    } else {
        $all_services | where {|svc| $filter | any {|f| $f == $svc.name }}
    })
    
    if ($enabled_services | is-empty) {
        if ($filter | is-empty) {
            print "No services with TLS enabled found."
        } else {
            print "No services matched the provided filter or TLS is disabled."
        }
        return
    }
    
    for svc in $enabled_services {
        let name = $svc.name
        let tls_cfg = ($svc.tls | default {})
        
        let cert_name = (try { $tls_cfg.cert_name } catch { $name } | default $name)
        let tls_instances = (try { $tls_cfg.instances } catch { $instance_count } | default $instance_count)
        let suffix = (try { $tls_cfg.domain_suffix } catch { $domain_suffix } | default $domain_suffix)
        let sans = (try { $tls_cfg.sans } catch { [] } | default [])
        
        ensure-service-tls-dirs $name
        
        if $verbose {
            print $"Ensuring CA ($ca_name) is synced to service ($name)..."
        }
        try {
            if $force_copy_ca {
                copy-shared-ca-to-service $name --force
            } else {
                copy-shared-ca-to-service $name
            }
        } catch {|err|
            error make {msg: $"Failed to sync CA for service ($name): ($err.msg)"}
        }
        
        for i in 1..$tls_instances {
            let hostname = (if $tls_instances > 1 { $"($cert_name)($i)" } else { $cert_name })
            let domain = $"($hostname).($suffix)"
            
            if $verbose {
                print $"Generating cert for service=($name) domain=($domain) ca=($ca_name)"
            } else {
                print $"Generating cert for service=($name) domain=($domain)"
            }
            
            try {
                if $verbose {
                    generate-cert --service $name --domain $domain --cert-name $hostname --san $sans --verbose
                } else {
                    generate-cert --service $name --domain $domain --cert-name $hostname --san $sans
                }
            } catch {|err|
                error make {msg: $"Failed to generate certificate for ($domain): ($err.msg)"}
            }
        }
    }
    
    print "Certificate generation complete for all services."
}

