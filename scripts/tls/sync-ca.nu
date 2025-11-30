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

use ./lib.nu [
    read-shared-ca-name
    copy-shared-ca-to-service
]
use ../lib/services.nu [list-services]

def main [
    --service (-s): list<string> = [],
    --dry-run,
    --force,
    --verbose,
] {
    print "Syncing shared CA to services..."
    
    let ca_name = (read-shared-ca-name)
    if $ca_name == null {
        error make {msg: "CA metadata file not found. Please run scripts/tls/generate-ca.nu first"}
    }
    
    let all_services = (list-services --tls-only)
    let enabled_services = (if ($service | is-empty) {
        $all_services
    } else {
        $all_services | where {|svc| $service | any {|filter| $filter == $svc.name }}
    })
    
    if ($enabled_services | is-empty) {
        if ($service | is-empty) {
            print "No services with TLS enabled found."
        } else {
            print "No services matched the provided filter or TLS is disabled."
        }
        return
    }
    
    for svc in $enabled_services {
        let service_name = $svc.name
        
        if $dry_run {
            print $"[dry-run] Would sync CA ($ca_name) to service ($service_name)"
        } else {
            if $verbose {
                print $"Syncing CA ($ca_name) to service ($service_name)..."
            }
            try {
                if $force {
                    copy-shared-ca-to-service $service_name --force
                } else {
                    copy-shared-ca-to-service $service_name
                }
                if $verbose {
                    print $"  CA synced successfully"
                }
            } catch {|err|
                print $"  Failed to sync CA: ($err.msg)"
            }
        }
    }
    
    if $dry_run {
        print "Sync dry-run complete."
    } else {
        print "CA sync complete."
    }
}
