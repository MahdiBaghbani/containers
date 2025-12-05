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

# Docker build argument generation
# See docs/concepts/build-system.md for architecture

use ./config.nu [process-sources-to-build-args process-external-images-to-build-args]

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
    let commit_sha = (if ($meta.sha | str length) > 0 { $meta.sha } else { "local" })
    let version = $version_tag
    
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
