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

# Docker image label generation
# See docs/concepts/build-system.md for architecture

use ./constants.nu [LABEL_SYSTEM_PREFIX LABEL_SERVICE_DEF_HASH]

export def generate-labels [
    service: string,
    meta: record,
    cfg: record,
    source_shas: record = {},
    source_types: record = {},
    service_def_hash: string = ""
] {
    let image_source = (try {
        git remote get-url origin | str trim
    } catch {
        "local"
    })
    let image_revision = (if ($meta.sha | str length) > 0 { $meta.sha } else { "local" })

    mut base_labels = {
        "org.opencontainers.image.source": $image_source,
        "org.opencontainers.image.revision": $image_revision,
        "org.opencloudmesh.service": $service
    }

    # Add source-specific labels if sources exist
    let cfg_sources = (try { $cfg.sources } catch { {} })
    if not ($cfg_sources | is-empty) {
        # Filter to only git sources BEFORE the reduce call (local sources don't get labels)
        let source_keys = ($cfg_sources | columns)
        let git_source_keys = (if not ($source_types | is-empty) {
            ($source_keys | where {|k| ($source_types | get $k | default "git") == "git"})
        } else {
            # Fallback: filter by checking for path field
            ($source_keys | where {|k|
                let source = ($cfg_sources | get $k)
                not ("path" in ($source | columns))
            })
        })
        
        # Only process git sources for label generation
        if not ($git_source_keys | is-empty) {
            # Check for label conflicts (user-defined source revision labels)
            let user_labels = (try { $cfg.labels } catch { {} } | default {})
            let source_revision_label_prefix_oci = "org.opencontainers.image.source."
            let source_revision_label_prefix_custom = "org.opencloudmesh.source."
            let source_revision_label_suffix = ".revision"

            # Use reduce instead of for loop (for loops don't work with mut variables in Nushell)
            $base_labels = ($git_source_keys | reduce --fold $base_labels {|source_key, acc|
            let source = ($cfg_sources | get $source_key)
            let sha = (try { $source_shas | get $"($source_key | str upcase)_SHA" } catch { "" })
            let ref = (try { $source.ref } catch { "" })
            let url = (try { $source.url } catch { "" })

            # OCI-standard source revision label: org.opencontainers.image.source.{source_key}.revision
            let oci_label_key = $"($source_revision_label_prefix_oci)($source_key)($source_revision_label_suffix)"
            let custom_label_key = $"($source_revision_label_prefix_custom)($source_key)($source_revision_label_suffix)"

            # Check if user has overridden these labels
            let user_oci_override = (try { $user_labels | get $oci_label_key } catch { null })
            let user_custom_override = (try { $user_labels | get $custom_label_key } catch { null })

            mut labels = $acc

            # Set OCI-standard revision label (unless user overridden)
            if $user_oci_override == null {
                if ($sha | str length) > 0 {
                    $labels = ($labels | upsert $oci_label_key $sha)
                } else {
                    let ref_display = (if ($ref | str length) > 0 { $ref } else { "unknown" })
                    $labels = ($labels | upsert $oci_label_key $"missing:($ref_display)")
                }
            } else {
                print $"WARNING: [($service)] User-defined label '($oci_label_key)' overrides generated source revision label. Using user value: ($user_oci_override)"
            }

            # Set custom namespace revision label (unless user overridden)
            if $user_custom_override == null {
                if ($sha | str length) > 0 {
                    $labels = ($labels | upsert $custom_label_key $sha)
                } else {
                    let ref_display = (if ($ref | str length) > 0 { $ref } else { "unknown" })
                    $labels = ($labels | upsert $custom_label_key $"missing:($ref_display)")
                }
            } else {
                print $"WARNING: [($service)] User-defined label '($custom_label_key)' overrides generated source revision label. Using user value: ($user_custom_override)"
            }

            # Source ref and URL (always include, user can override if needed)
            # Defensive: wrap in try-catch for safety (should not be needed if filtering is correct)
            let ref = (try { $source.ref } catch { "" })
            let url = (try { $source.url } catch { "" })
            if ($ref | str length) > 0 {
                $labels = ($labels | upsert $"org.opencloudmesh.source.($source_key).ref" $ref)
            }
            if ($url | str length) > 0 {
                $labels = ($labels | upsert $"org.opencloudmesh.source.($source_key).url" $url)
            }

            $labels
            })
        }
    }

    # Merge user labels
    let user_labels = (try { $cfg.labels } catch { {} } | default {})
    
    # Warn if user tries to set system-owned labels (org.opencloudmesh.system.*)
    let system_label_keys = ($user_labels | columns | where {|k| $k | str starts-with $LABEL_SYSTEM_PREFIX})
    if not ($system_label_keys | is-empty) {
        for key in $system_label_keys {
            let user_value = ($user_labels | get $key)
            print $"WARNING: [($service)] User-defined label '($key)' is in system-owned namespace '($LABEL_SYSTEM_PREFIX)*'. This label will be ignored and overwritten by the build system."
        }
    }
    
    # Merge user labels into base labels
    mut final_labels = ($base_labels | merge $user_labels)
    
    # Inject service definition hash label (always overwrites, even if user tried to set it)
    if ($service_def_hash | str length) > 0 {
        $final_labels = ($final_labels | upsert $LABEL_SERVICE_DEF_HASH $service_def_hash)
    }
    
    $final_labels
}
