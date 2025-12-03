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

# Service definition hash computation for CI dependency reuse
# See docs/concepts/build-system.md for details on hash inputs and stability guarantees

use ./build-order.nu [build-dependency-graph topological-sort-dfs]
use ./build-ops.nu [load-service-config]
use ./manifest.nu [check-versions-manifest-exists load-versions-manifest get-version-or-null]
use ./platforms.nu [check-platforms-manifest-exists load-platforms-manifest get-default-platform strip-platform-suffix]
use ./common.nu [get-repo-root]

# Normalize a record for deterministic hashing by sorting keys recursively
# Returns a stable string representation suitable for hashing
def normalize-for-hash [value: any] {
    let type = ($value | describe)
    
    if ($type | str starts-with "record") {
        # Sort keys and recursively normalize values
        let keys = ($value | columns | sort)
        let normalized = ($keys | reduce --fold {} {|key, acc|
            let val = (try { $value | get $key } catch { null })
            let normalized_val = (normalize-for-hash $val)
            $acc | upsert $key $normalized_val
        })
        $normalized | to nuon
    } else if ($type | str starts-with "list") {
        # Lists preserve order (order is significant for sources, deps)
        let normalized = ($value | each {|item| normalize-for-hash $item})
        $normalized | to nuon
    } else if $value == null {
        "null"
    } else {
        # Primitives: convert to string representation
        $value | to nuon
    }
}

# Extract hash-relevant inputs from a service configuration
# Returns a record containing only fields that affect the built image
def extract-definition-inputs [
    service: string,
    version_name: string,
    platform: string,
    cfg: record,
    source_shas: record,
    source_types: record,
    dep_hashes: record
] {
    let repo_root = (get-repo-root)
    
    # Read Dockerfile contents for inclusion in hash
    let dockerfile_path = (try { $cfg.dockerfile } catch { "" })
    let dockerfile_contents = (if ($dockerfile_path | str length) > 0 {
        let full_path = ($repo_root | path join $dockerfile_path)
        if ($full_path | path exists) {
            try { open $full_path | into string } catch { "" }
        } else {
            ""
        }
    } else {
        ""
    })
    
    # Process sources: git sources use SHA, local sources use "local" sentinel
    let cfg_sources = (try { $cfg.sources } catch { {} })
    let sources_for_hash = (if ($cfg_sources | is-empty) {
        {}
    } else {
        ($cfg_sources | columns | reduce --fold {} {|source_key, acc|
            let source = ($cfg_sources | get $source_key)
            let source_type = (try { $source_types | get $source_key } catch { "git" })
            
            let source_value = (if $source_type == "local" {
                # Local sources use stable sentinel (not path, which varies)
                {type: "local", sentinel: "local"}
            } else {
                # Git sources use SHA for cache-busting and ref for identity
                let sha_key = $"($source_key | str upcase)_SHA"
                let sha = (try { $source_shas | get $sha_key } catch { "" })
                let ref = (try { $source.ref } catch { "" })
                let url = (try { $source.url } catch { "" })
                {type: "git", sha: $sha, ref: $ref, url: $url}
            })
            $acc | upsert $source_key $source_value
        })
    })
    
    # Extract external images
    let external_images = (try { $cfg.external_images } catch { {} })
    
    # Extract static build args
    let build_args = (try { $cfg.build_args } catch { {} })
    
    # Extract TLS-relevant fields
    let tls_enabled = (try { $cfg.tls.enabled | default false } catch { false })
    let tls_mode = (try { $cfg.tls.mode } catch { "" })
    
    # Sort dep_hashes by key for deterministic ordering
    let sorted_dep_hashes = (if ($dep_hashes | is-empty) {
        {}
    } else {
        let keys = ($dep_hashes | columns | sort)
        ($keys | reduce --fold {} {|key, acc|
            $acc | upsert $key ($dep_hashes | get $key)
        })
    })
    
    # Build the definition record (all fields that affect the image)
    {
        identity: {
            service: $service,
            version: $version_name,
            platform: $platform
        },
        dockerfile: {
            path: $dockerfile_path,
            contents: $dockerfile_contents
        },
        sources: $sources_for_hash,
        external_images: $external_images,
        build_args: $build_args,
        tls: {
            enabled: $tls_enabled,
            mode: $tls_mode
        },
        dep_hashes: $sorted_dep_hashes
    }
}

# Compute service definition hash for a single build node
# Returns the full 64-character SHA-256 hex digest
export def compute-service-def-hash [
    service: string,
    version_name: string,
    platform: string,
    cfg: record,
    source_shas: record,
    source_types: record,
    dep_hashes: record
] {
    let inputs = (extract-definition-inputs $service $version_name $platform $cfg $source_shas $source_types $dep_hashes)
    let normalized = (normalize-for-hash $inputs)
    $normalized | hash sha256
}

# Compute service definition hashes for all nodes in a build scope
# Must be called with nodes in topological order (dependencies before dependents)
# Returns {node_key: hash} record
export def compute-service-def-hash-graph [
    build_order: list,
    registry_info: record,
    sha_cache: record
] {
    use ./sources.nu [extract-source-shas]
    use ./build-config.nu [detect-all-source-types]
    
    # Process nodes in topological order, accumulating hashes
    let result = ($build_order | reduce --fold {hashes: {}, sha_cache: $sha_cache} {|node, acc|
        # Parse node: service:version or service:version:platform
        let parts = ($node | split row ":")
        if ($parts | length) < 2 {
            # Skip invalid nodes
            $acc
        } else {
            let service = ($parts | get 0)
            let version_name = ($parts | get 1)
            let platform = (if ($parts | length) > 2 { $parts | get 2 } else { "" })
            
            # Load service config
            let node_config = (try {
                load-node-config $service $version_name $platform
            } catch {|err|
                print $"WARNING: Could not load config for ($node): (try { $err.msg } catch { 'Unknown error' })"
                null
            })
            
            if $node_config == null {
                # Skip nodes that fail to load
                $acc
            } else {
                let cfg = $node_config.cfg
                let version_spec = $node_config.version_spec
                let platforms_manifest = $node_config.platforms_manifest
                
                # Extract source types
                let cfg_sources = (try { $cfg.sources } catch { {} })
                let source_types = (if not ($cfg_sources | is-empty) {
                    detect-all-source-types $cfg_sources
                } else {
                    {}
                })
                
                # Extract source SHAs (for git sources only)
                let sha_result = (if ($cfg_sources | is-empty) {
                    {shas: {}, cache: $acc.sha_cache}
                } else {
                    # Filter to git sources
                    let git_sources = ($cfg_sources | columns | where {|k| 
                        (try { $source_types | get $k } catch { "git" }) == "git"
                    } | reduce --fold {} {|k, inner_acc|
                        $inner_acc | upsert $k ($cfg_sources | get $k)
                    })
                    
                    if ($git_sources | is-empty) {
                        {shas: {}, cache: $acc.sha_cache}
                    } else {
                        extract-source-shas $git_sources $service $acc.sha_cache
                    }
                })
                
                # Collect dependency hashes from already-computed nodes
                let deps = (try { $cfg.dependencies } catch { {} })
                let dep_hashes = (if ($deps | is-empty) {
                    {}
                } else {
                    ($deps | columns | reduce --fold {} {|dep_key, dep_acc|
                        let dep_config = ($deps | get $dep_key)
                        let dep_service = (try { $dep_config.service } catch { $dep_key })
                        let dep_version = (try { $dep_config.version } catch { $version_name })
                        
                        # Determine dep platform (inherits from parent if multi-platform)
                        let dep_has_platforms = (check-platforms-manifest-exists $dep_service)
                        let dep_platform = (if $dep_has_platforms and ($platform | str length) > 0 {
                            let single_platform = (try { $dep_config.single_platform | default false } catch { false })
                            if $single_platform { "" } else { $platform }
                        } else {
                            ""
                        })
                        
                        # Build dep node key
                        let dep_node_key = (if ($dep_platform | str length) > 0 {
                            $"($dep_service):($dep_version):($dep_platform)"
                        } else {
                            $"($dep_service):($dep_version)"
                        })
                        
                        # Get hash from already-computed hashes
                        let dep_hash = (try { $acc.hashes | get $dep_node_key } catch { "" })
                        if ($dep_hash | str length) > 0 {
                            $dep_acc | upsert $dep_node_key $dep_hash
                        } else {
                            $dep_acc
                        }
                    })
                })
                
                # Compute hash for this node
                let hash = (compute-service-def-hash $service $version_name $platform $cfg $sha_result.shas $source_types $dep_hashes)
                
                # Update accumulator
                {
                    hashes: ($acc.hashes | upsert $node $hash),
                    sha_cache: $sha_result.cache
                }
            }
        }
    })
    
    $result.hashes
}

# Load node configuration for hash computation
# Returns {cfg: record, version_spec: record, platforms_manifest: any}
def load-node-config [
    service: string,
    version_name: string,
    platform: string
] {
    # Load versions manifest
    if not (check-versions-manifest-exists $service) {
        error make { msg: $"Service '($service)' does not have a version manifest" }
    }
    
    let versions_manifest = (load-versions-manifest $service)
    
    # Check for platforms manifest
    let has_platforms = (check-platforms-manifest-exists $service)
    let platforms_manifest = (if $has_platforms {
        try { load-platforms-manifest $service } catch { null }
    } else {
        null
    })
    
    # Strip platform suffix from version name if present
    let base_version_name = (if $platforms_manifest != null {
        let stripped = (try {
            strip-platform-suffix $version_name $platforms_manifest
        } catch {
            {base_name: $version_name, platform_name: ""}
        })
        $stripped.base_name
    } else {
        $version_name
    })
    
    # Get version spec
    let version_spec = (get-version-or-null $versions_manifest $base_version_name)
    if $version_spec == null {
        error make { msg: $"Version '($base_version_name)' not found in manifest for service '($service)'" }
    }
    
    # Load merged config
    let cfg = (load-service-config $service $version_spec $platform $platforms_manifest)
    
    {
        cfg: $cfg,
        version_spec: $version_spec,
        platforms_manifest: $platforms_manifest
    }
}
