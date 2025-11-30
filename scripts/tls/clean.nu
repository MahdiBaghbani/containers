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
    get-services-dir
    get-shared-ca-dir
    read-shared-ca-name
]
use ../lib/services.nu [list-services]

let SERVICES_DIR = (get-services-dir)
let SHARED_CA_DIR = (get-shared-ca-dir)

def summarise-removal [label files dry_run] {
    # Ensure files is a list
    let file_list = (if ($files | describe | str starts-with "list<") {
        $files
    } else {
        if ($files | is-empty) {
            []
        } else {
            [$files]
        }
    })
    
    if ($file_list | is-empty) {
        print $"No ($label) files to remove."
        return
    }

    let count = ($file_list | length)
    if $dry_run {
        print $"[dry-run] Would remove ($count) ($label) files."
    } else {
        print $"Removing ($count) ($label) files."
    }
}

def remove-paths [paths dry_run] {
    if ($paths | is-empty) { return }
    if $dry_run { return }
    # Transform to list of strings, handling both single values and lists
    mut path_list = []
    if ($paths | describe | str starts-with "list<") {
        for p in $paths {
            let p_str = (try {
                if ($p | describe) == "string" {
                    $p
                } else {
                    $p | to text
                }
            } catch {
                continue
            })
            $path_list = ($path_list | append $p_str)
        }
    } else {
        let p_str = (try {
            if (($paths | describe) == "string") {
                $paths
            } else {
                $paths | to text
            }
        } catch {
            return
        })
        $path_list = [$p_str]
    }
    if ($path_list | length) > 0 {
        # Use rm command directly with each file to ensure deletion works
        for p in $path_list {
            rm -f $p | ignore
        }
    }
}

def remove-directory-when-empty [dir keep_empty dry_run] {
    if $keep_empty { return }
    if $dry_run { return }
    if not ($dir | path exists) { return }
    let contents = (try { ls $dir } catch { [] })
    if ($contents | is-empty) {
        rm -rf $dir | ignore
    }
}

def main [
    --service (-s): list<string> = [],
    --dry-run,
    --skip-shared-ca,
    --keep-empty-dirs,
] {
    print "Cleaning up generated certificates..."

    let shared_ca_name = (read-shared-ca-name)
    let all_services = (list-services --tls-only)
    let selected_services = (if ($service | is-empty) { 
        $all_services
    } else { 
        $all_services | where {|svc| $service | any {|filter| $filter == $svc.name }}
    })

    if ($selected_services | is-empty) {
        if ($service | is-empty) {
            print "No services with TLS configuration found."
        } else {
            print "No services matched the provided filter."
        }
    }

    for svc in $selected_services {

        let service_name = $svc.name
        let service_dir = ($SERVICES_DIR | path join $service_name)
        let certs_dir = ($service_dir | path join "tls" "certificates")
        let service_ca_dir = ($service_dir | path join "tls" "certificate-authority")

        if ($certs_dir | path exists) {
            let cert_files = (
                ["*.crt", "*.key", "*.csr", "*.cnf"]
                | reduce -f [] {|pattern, acc|
                    let matches = (try { glob ($certs_dir | path join $pattern) } catch { [] })
                    if ($matches | is-empty) { $acc } else { $acc | append $matches }
                }
            )
            summarise-removal $"($service_name) cert" $cert_files $dry_run
            remove-paths $cert_files $dry_run
            remove-directory-when-empty $certs_dir $keep_empty_dirs $dry_run
        } else {
            print $"Certificate directory not found for ($service_name): ($certs_dir)"
        }

        if ($service_ca_dir | path exists) {
            let ca_files = (if $shared_ca_name != null {
                mut files = [
                    ($service_ca_dir | path join $"($shared_ca_name).crt"),
                    ($service_ca_dir | path join $"($shared_ca_name).key")
                ]
                $files = ($files | where {|file| $file | path exists })
                let meta = ($service_ca_dir | path join "ca.json")
                if ($meta | path exists) {
                    $files = ($files | append $meta)
                }

                if ($files | describe) == "list<any>" {
                    $files
                } else {
                    []
                }
            } else {
                # Fallback: list all files in directory and filter
                try {
                    (ls $service_ca_dir | where {|f| 
                        let name = ($f.name | path basename)
                        $name | str ends-with ".crt" or $name | str ends-with ".key" or $name == "ca.json"
                    } | get name)
                } catch {
                    []
                }
            })

            summarise-removal $"($service_name) CA" $ca_files $dry_run
            remove-paths $ca_files $dry_run
            remove-directory-when-empty $service_ca_dir $keep_empty_dirs $dry_run
        } else {
            print $"Service CA directory not found for ($service_name): ($service_ca_dir)"
        }
    }

    if not $skip_shared_ca {
        if ($SHARED_CA_DIR | path exists) {
            let shared_files = (try {
                mut found = []
                let crt_files = (try { glob ($SHARED_CA_DIR | path join "*.crt") } catch { [] })
                let key_files = (try { glob ($SHARED_CA_DIR | path join "*key") } catch { [] })
                let srl_files = (try { glob ($SHARED_CA_DIR | path join "*.srl") } catch { [] })
                let json_file = (try { glob ($SHARED_CA_DIR | path join "ca.json") } catch { [] })
                for f in $crt_files { $found = ($found | append $f) }
                for f in $key_files { $found = ($found | append $f) }
                for f in $srl_files { $found = ($found | append $f) }
                for f in $json_file { $found = ($found | append $f) }
                $found | where {|f| $f | path exists } | each {|f| $f | to text }
            } catch {
                []
            })

            if $shared_ca_name == null {
                print "Shared CA metadata missing or unreadable. Falling back to glob removal."
            }

            summarise-removal "shared CA" $shared_files $dry_run
            remove-paths $shared_files $dry_run
            remove-directory-when-empty $SHARED_CA_DIR $keep_empty_dirs $dry_run
        } else {
            print $"Shared CA directory not found: ($SHARED_CA_DIR)"
        }
    }

    if $dry_run {
        print "Cleanup dry-run complete."
    } else {
        print "Cleanup complete."
    }
}
