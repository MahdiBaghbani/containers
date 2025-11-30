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

# Build operations for container image builds

use ./platforms.nu [merge-version-overrides merge-platform-config get-platform-spec check-platforms-manifest-exists]
use ./common.nu [get-service-config-path get-tls-mode get-repo-root]
use ./validate.nu [validate-merged-config validate-local-path]

# Load service config and merge platform/version overrides
# See docs/concepts/service-configuration.md for merge order
export def load-service-config [
    service: string,
    version_spec: record,
    platform: string = "",
    platforms: any = null
] {
    let cfg_path = (get-service-config-path $service)
    let base_cfg = (open $cfg_path)
    
    mut merged_cfg = $base_cfg
    
    if ($platform | str length) > 0 {
        if $platforms == null {
            error make { msg: $"Platform '($platform)' specified but platforms manifest not provided to load-service-config" }
        }
        let platform_spec = (get-platform-spec $platforms $platform)
        $merged_cfg = (merge-platform-config $merged_cfg $platform_spec)
    }
    
    $merged_cfg = (merge-version-overrides $merged_cfg $version_spec $platform $platforms)
    
    # Validate merged config before returning
    let has_platforms = (if $platforms != null { true } else { (check-platforms-manifest-exists $service) })
    let validation = (validate-merged-config $merged_cfg $service $has_platforms $platform)
    if not $validation.valid {
        mut error_msg = "Merged config validation failed:\n"
        for error in $validation.errors {
            $error_msg = ($error_msg + $"  - ($error)\n")
        }
        error make { msg: $error_msg }
    }
    
    $merged_cfg
}

export def extract-tls-metadata [
    cfg: record,
    ca_name: string = ""  # CA name from ca.json (read once per build in build.nu)
] {
    let tls_enabled = (try { $cfg.tls.enabled | default false } catch { false })
    
    let tls_mode_raw = (get-tls-mode $cfg)
    let tls_mode = (if $tls_enabled {
        if $tls_mode_raw == null {
            error make {msg: "tls.mode is required when tls.enabled=true (validation should have caught this)"}
        }
        $tls_mode_raw
    } else {
        "disabled"
    })
    
    let tls_cert_name = (try { $cfg.tls.cert_name } catch { "" })
    
    let tls_ca_name = (if $tls_enabled {
        if ($ca_name | str trim | is-empty) {
            error make {msg: "CA name must be provided when TLS is enabled. This is a build system bug - CA name should have been read and validated in build.nu."}
        }
        $ca_name
    } else {
        ""
    })
    
    {
        enabled: $tls_enabled,
        mode: $tls_mode,
        cert_name: $tls_cert_name,
        ca_name: $tls_ca_name
    }
}

export def prepare-tls-context [
    service: string,
    context: string,
    tls_enabled: bool,
    tls_mode: string  # Mode parameter (required, no default to prevent masking validation errors)
] {
    if not $tls_enabled {
        return {copied: false, files: []}
    }
    
    if ($tls_mode | str trim | is-empty) or $tls_mode == "disabled" {
        error make {msg: "tls_mode parameter is required when tls_enabled=true. This is a build system bug."}
    }
    
    if $tls_mode == "ca-only" {
        print "CA-only mode: Skipping copy-tls.nu copy (not needed)"
        return {copied: false, files: []}
    }
    
    # Verify TLS helper script exists before copying
    let tls_helper_script = "scripts/tls/copy-tls.nu"
    if not ($tls_helper_script | path exists) {
        error make {
            msg: ($"TLS helper script not found: ($tls_helper_script)\n\n" +
                  "This script is required for TLS modes 'ca-and-cert' and 'cert-only'.\n" +
                  "The file should be located at scripts/tls/copy-tls.nu.\n\n")
        }
    }
    
    mkdir ($"($context)/scripts/tls")
    cp $tls_helper_script $"($context)/scripts/tls/copy-tls.nu"
    print "Copied TLS helper script to service context: copy-tls.nu"
    {copied: true, files: ["copy-tls.nu"]}
}

export def cleanup-tls-context [
    context: string,
    tls_context: record
] {
    if not $tls_context.copied {
        return
    }
    
    for file in $tls_context.files {
        rm -f $"($context)/scripts/tls/($file)"
    }
    
    try { rmdir $"($context)/scripts/tls" } catch { }
    print "Cleaned up TLS helper script(s) from service context"
}

# Prepare local sources context by copying local source directories into build context
# Returns record mapping source_key -> resolved_path_in_context (paths relative to context root for Docker)
# Note: Copied sources are left in .build-sources/ after build for debugging (consistent with TLS helper pattern)
export def prepare-local-sources-context [
    service: string,
    context: string,
    sources: record,
    source_types: record,
    repo_root: string
] {
    # Filter to only local sources
    let local_source_keys = ($sources | columns | where {|k| ($source_types | get $k | default "git") == "local"})
    
    if ($local_source_keys | is-empty) {
        return {}
    }
    
    # Resolve context to absolute path (if relative, resolve relative to repo root)
    let resolved_context = (if ($context | path expand | str starts-with "/") {
        ($context | path expand)
    } else {
        ($repo_root | path join $context | path expand)
    })
    
    # Create .build-sources directory in context
    let build_sources_dir = ($resolved_context | path join ".build-sources")
    mkdir $build_sources_dir
    
    # Process each local source
    let resolved_paths = ($local_source_keys | reduce --fold {} {|source_key, acc|
        let source = ($sources | get $source_key)
        let path_value = (try { $source.path } catch { "" })
        
        if ($path_value | str length) == 0 {
            error make {msg: $"Local source '($source_key)' has empty path field"}
        }
        
        # Resolve path relative to repo root
        let resolved_source_path = (if ($path_value | path expand | str starts-with "/") {
            # Absolute path - validate it's within repo root
            let abs_path = ($path_value | path expand)
            let repo_root_expanded = ($repo_root | path expand)
            if not ($abs_path | str starts-with $repo_root_expanded) {
                error make {msg: $"Local source '($source_key)' path '($path_value)' is outside repository root"}
            }
            $abs_path
        } else {
            # Relative path - resolve relative to repo root
            ($repo_root | path join $path_value | path expand)
        })
        
        # Validate path exists and is directory
        let path_validation = (validate-local-path $resolved_source_path $repo_root)
        if not $path_validation.valid {
            error make {msg: ($"Local source '($source_key)' path validation failed: " + ($path_validation.errors | str join "; "))}
        }
        
        # Check directory size and warn if large (>100MB)
        let dir_size_bytes = (try {
            (ls -a $resolved_source_path | get size | math sum)
        } catch {
            0
        })
        # Convert to MB (1MB = 1,048,576 bytes) - convert to int for comparison
        let dir_size_int = ($dir_size_bytes | into int)
        let size_mb = ($dir_size_int / 1048576)
        if $size_mb > 100 {
            let size_mb_str = ($size_mb | into string | str substring 0..5)
            print $"WARNING: [($service)] Local source '($source_key)' directory is large \(($size_mb_str) MB\). This may slow down builds."
        }
        
        # Copy source directory to build context
        let target_dir = ($build_sources_dir | path join $source_key)
        # Remove target directory if it exists (cleanup from previous builds)
        try {
            if ($target_dir | path exists) {
                rm -rf $target_dir
            }
        } catch {|err|
            error make {msg: $"Failed to remove existing target directory '($target_dir)': ($err.msg)"}
        }
        # Use cp -rL to follow symlinks (matches git clone behavior)
        # Note: Nushell's cp command follows symlinks by default, but we use ^cp for explicit control
        try {
            ^cp -rL $resolved_source_path $target_dir
        } catch {|err|
            error make {msg: $"Failed to copy local source '($source_key)' from '($resolved_source_path)' to '($target_dir)': ($err.msg)"}
        }
        
        # Return resolved path relative to context root (for Docker COPY commands)
        let resolved_path_in_context = $".build-sources/($source_key)"
        $acc | upsert $source_key $resolved_path_in_context
    })
    
    $resolved_paths
}

# Generate image tags (default platform gets unprefixed versions of all tags, others get platform-suffixed only)
export def generate-tags [
    service: string,
    version_spec: record,
    is_local: bool,
    registry_info: record,
    platform: string = "",
    default_platform: string = ""
] {
    mut base_tags = []
    
    let version_tag = (if ($platform | str length) > 0 {
        $"($version_spec.name)-($platform)"
    } else {
        $version_spec.name
    })
    $base_tags = ($base_tags | append $version_tag)
    
    # Default platform also gets unprefixed version name
    let is_default_platform = (($platform | str length) > 0 and $platform == $default_platform)
    if $is_default_platform {
        $base_tags = ($base_tags | append $version_spec.name)
    }
    
    let is_latest = (try { $version_spec.latest } catch { false })
    if $is_latest {
        if ($platform | str length) > 0 {
            $base_tags = ($base_tags | append $"latest-($platform)")
            if $platform == $default_platform {
                $base_tags = ($base_tags | append "latest")
            }
        } else {
            $base_tags = ($base_tags | append "latest")
        }
    }
    
    let custom_tags = (try { $version_spec.tags } catch { [] })
    for tag in $custom_tags {
        let tag_with_platform = (if ($platform | str length) > 0 {
            $"($tag)-($platform)"
        } else {
            $tag
        })
        $base_tags = ($base_tags | append $tag_with_platform)
        
        # Default platform also gets unprefixed custom tags
        if $is_default_platform {
            $base_tags = ($base_tags | append $tag)
        }
    }
    
    if $is_local {
        $base_tags | each {|t| $"($service):($t)"}
    } else {
        let base_image_name_forgejo = $"($registry_info.forgejo_registry)/($registry_info.forgejo_path)/($service)"
        let base_image_name_ghcr = $"($registry_info.github_registry)/($registry_info.github_path)/($service)"
        $base_tags | each {|t| [$"($base_image_name_forgejo):($t)", $"($base_image_name_ghcr):($t)"]} | flatten
    }
}

export def generate-labels [
    service: string,
    meta: record,
    cfg: record,
    source_shas: record = {},
    source_types: record = {}
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

    $base_labels | merge (try { $cfg.labels } catch { {} } | default {})
}

# Generate build arguments (priority order documented in docs/concepts/build-system.md)
export def generate-build-args [
    version_tag: string,
    cfg: record,
    meta: record,
    deps_resolved: record,
    tls_meta: record,
    cache_bust_override: string = "",
    no_cache: bool = false,
    source_shas: record = {},
    source_types: record = {},
    local_source_paths: record = {}
] {
    use ./build-config.nu [process-sources-to-build-args process-external-images-to-build-args]
    
    let commit_sha = (if ($meta.sha | str length) > 0 { $meta.sha } else { "local" })
    let version = (if $meta.is_release { $meta.base_tag } else if ($meta.sha | str length) > 0 { $meta.sha } else { $version_tag })
    
    mut build_args = {
        COMMIT_SHA: $commit_sha,
        VERSION: $version
    }
    
    let cfg_sources = (try { $cfg.sources } catch { {} })
    if not ($cfg_sources | is-empty) {
        let source_args = (process-sources-to-build-args $cfg_sources $source_types)
        # Update local source paths if provided (from context preparation - Task 4.2)
        # For now, if local_source_paths has entries, update corresponding _PATH args
        let source_args_updated = (if not ($local_source_paths | is-empty) {
            ($source_args | columns | reduce --fold $source_args {|arg_key, acc|
                if ($arg_key | str ends-with "_PATH") {
                    # Extract source key from arg key (e.g., REVAD_PATH -> revad)
                    let source_key = ($arg_key | str replace "_PATH" "" | str downcase)
                    if $source_key in ($local_source_paths | columns) {
                        $acc | upsert $arg_key ($local_source_paths | get $source_key)
                    } else {
                        $acc
                    }
                } else {
                    $acc
                }
            })
        } else {
            $source_args
        })
        $build_args = ($build_args | merge $source_args_updated)

        # Add SHA build args (for label generation only, Dockerfiles can optionally declare and use if needed)
        # Use reduce instead of for loop (for loops don't work with mut variables in Nushell)
        $build_args = ($source_shas | columns | reduce --fold $build_args {|sha_key, acc|
            let sha_value = ($source_shas | get $sha_key)
            $acc | upsert $sha_key $sha_value
        })
    }
    
    let cfg_external_images = (try { $cfg.external_images } catch { {} })
    if not ($cfg_external_images | is-empty) {
        let ext_img_args = (process-external-images-to-build-args $cfg_external_images)
        $build_args = ($build_args | merge $ext_img_args)
    }
    
    let cfg_build_args = (try { $cfg.build_args } catch { {} })
    $build_args = ($build_args | merge $cfg_build_args)
    
    # Apply env var overrides first (TLS_MODE excluded - system-managed)
    for arg_name in ($build_args | columns) {
        let env_val = (try { ($env | get -o $arg_name) } catch { "" })
        if ($env_val != null) and ($env_val | str length) > 0 {
            $build_args = ($build_args | upsert $arg_name $env_val)
        }
    }
    
    $build_args = ($build_args | merge $deps_resolved)
    
    # Set TLS args after env var loop to prevent override of system-managed values
    $build_args = ($build_args | upsert TLS_ENABLED ($tls_meta.enabled | into string))
    
    if $tls_meta.enabled {
        if ($tls_meta.mode | str trim | is-empty) or $tls_meta.mode == "disabled" {
            error make {msg: "TLS_MODE is required when TLS_ENABLED=true. Build system should have validated this - this is a build system bug."}
        }
    }
    
    let env_tls_mode = (try { $env.TLS_MODE } catch { "" })
    if ($env_tls_mode | str trim | is-not-empty) {
        print $"WARNING: TLS_MODE environment variable is set to '($env_tls_mode)' but will be ignored. TLS_MODE is system-managed from config."
    }
    
    $build_args = ($build_args | upsert TLS_MODE (try { $tls_meta.mode } catch { "" }))
    $build_args = ($build_args | upsert TLS_CERT_NAME (try { $tls_meta.cert_name } catch { "" }))
    $build_args = ($build_args | upsert TLS_CA_NAME (try { $tls_meta.ca_name } catch { "" }))
    
    # Compute CACHEBUST value
    let cache_bust = (if ($cache_bust_override | str length) > 0 {
        $cache_bust_override  # Global override from --cache-bust flag
    } else if $no_cache {
        (random uuid)  # Global random from --no-cache flag
    } else {
        let env_cache_bust = (try { $env.CACHEBUST } catch { "" })
        if ($env_cache_bust | str length) > 0 {
            $env_cache_bust  # Environment variable
        } else {
            # Per-service: compute from service's sources (HYBRID: refs + SHAs)
            # Explicitly filter local sources before computation
            let cfg_sources = (try { $cfg.sources } catch { {} })
            if ($cfg_sources | is-empty) {
                # No sources at all - use existing fallback logic
                if ($meta.sha | str length) > 0 {
                    $meta.sha
                } else {
                    "local"
                }
            } else {
                # Filter to only git sources (exclude local sources)
                let git_sources = (if not ($source_types | is-empty) {
                    ($cfg_sources | columns | where {|k| ($source_types | get $k | default "git") == "git"})
                } else {
                    # Fallback: filter by checking for path field
                    ($cfg_sources | columns | where {|k|
                        let source = ($cfg_sources | get $k)
                        not ("path" in ($source | columns))
                    })
                })
                
                # Condition: If git_sources is empty AND cfg_sources is NOT empty -> all sources are local -> always-bust
                if ($git_sources | is-empty) {
                    # All sources are local - always-bust by default (use random UUID or "local" sentinel)
                    (random uuid)
                } else {
                    # Proceed with cache bust computation using git sources only
                    # Hybrid: Combine refs and SHAs (sorted by source key for consistency)
                    # Use reduce instead of for loop (for loops don't work with mut variables in Nushell)
                    let source_keys_sorted = ($git_sources | sort)
                    let cache_bust_parts = ($source_keys_sorted | reduce --fold [] {|key, acc|
                        let source = ($cfg_sources | get $key)
                        let ref = (try { $source.ref } catch { "" })
                        let sha_key = $"($key | str upcase)_SHA"
                        let sha = (try { $source_shas | get $sha_key } catch { "" })

                        # Use SHA if available, fallback to ref
                        if ($sha | str length) > 0 {
                            $acc | append $sha
                        } else if ($ref | str length) > 0 {
                            $acc | append $ref
                        } else {
                            $acc
                        }
                    })

                    let cache_bust_input = ($cache_bust_parts | str join ":")
                    if ($cache_bust_input | str length) > 0 {
                        let hash_full = ($cache_bust_input | hash sha256)
                        ($hash_full | str substring 0..15)  # First 16 characters (0-15 inclusive)
                    } else {
                        # Fallback: use Git SHA
                        if ($meta.sha | str length) > 0 {
                            $meta.sha
                        } else {
                            "local"
                        }
                    }
                }
            }
        }
    })
    
    # Ensure CACHEBUST is never empty (final safety check)
    # This allows Dockerfiles to use simple ${CACHEBUST} syntax without fallback patterns
    let cache_bust = (if ($cache_bust | str length) == 0 {
        "default"  # Ultimate fallback - should never happen, but safety net
    } else {
        $cache_bust
    })
    
    $build_args = ($build_args | upsert CACHEBUST $cache_bust)
    
    $build_args
}
