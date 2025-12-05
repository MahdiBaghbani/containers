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

# Build configuration - flag parsing, source detection, validation, and config loading
# See docs/concepts/build-system.md for architecture

use ../core/repo.nu [get-repo-root]
use ../manifest/core.nu [check-versions-manifest-exists load-versions-manifest]
use ../platforms/core.nu [check-platforms-manifest-exists load-platforms-manifest get-default-platform get-platform-names merge-version-overrides merge-platform-config get-platform-spec]
use ../services/core.nu [get-service-config-path]
use ../validate/core.nu [validate-merged-config validate-local-path]

# === Flag Parsing Utilities ===

export def parse-bool-flag [value: any] {
    if ($value | describe) == "bool" {
        return $value
    }
    
    let value_str = ($value | into string | str downcase)
    $value_str in ["true", "1", "yes"]
}

export def parse-list-flag [value: string, separator: string = ","] {
    if ($value | str length) == 0 {
        return []
    }
    
    $value | split row $separator | each {|v| $v | str trim}
}

export def parse-build-flags [
    push: any,
    latest: any,
    provenance: any,
    all_versions: any,
    latest_only: any,
    matrix_json: any,
    versions: string
] {
    {
        push: (parse-bool-flag $push),
        latest: (parse-bool-flag $latest),
        provenance: (parse-bool-flag $provenance),
        all_versions: (parse-bool-flag $all_versions),
        latest_only: (parse-bool-flag $latest_only),
        matrix_json: (parse-bool-flag $matrix_json),
        versions_list: (parse-list-flag $versions)
    }
}

export def generate-buildx-flags [
    push: bool,
    provenance: bool,
    is_local: bool
] {
    mut flags = []
    
    if $push {
        $flags = ($flags | append "--push")
    } else {
        $flags = ($flags | append "--load")
    }
    
    if $provenance {
        $flags = ($flags | append "--provenance=true")
    }
    
    $flags
}

export def get-env-or-config [env_name: string, config_val: any] {
    let env_val = (try { ($env | get -o $env_name) } catch { null })
    if ($env_val != null) and ($env_val | str length) > 0 {
        $env_val
    } else {
        ($config_val | default "")
    }
}

# === Source Detection Utilities ===

# Detect source type for a single source (local or git)
# Returns "local" if path field present or {SOURCE_KEY}_PATH env var exists, otherwise "git"
export def detect-source-type [source: record, source_key: string] {
    # Check environment variable first (highest priority)
    let env_path_key = $"($source_key | str upcase)_PATH"
    let env_path = (try { ($env | get -o $env_path_key) } catch { null })
    if ($env_path != null) and ($env_path | str length) > 0 {
        return "local"
    }
    
    # Check for path field in config
    if "path" in ($source | columns) {
        return "local"
    }
    
    # Default to git (backward compatible)
    "git"
}

# Detect source types for all sources (batch operation)
# Returns record mapping source_key -> "local" | "git"
export def detect-all-source-types [sources: record] {
    ($sources | columns | reduce --fold {} {|source_key, acc|
        let source = ($sources | get $source_key)
        let source_type = (detect-source-type $source $source_key)
        $acc | upsert $source_key $source_type
    })
}

# === Build Args Processing ===

# Process sources into build args (auto-generates {SOURCE_KEY}_REF and {SOURCE_KEY}_URL for git, or {SOURCE_KEY}_PATH and {SOURCE_KEY}_MODE for local)
# See docs/concepts/service-configuration.md#source-build-arguments-convention for convention
export def process-sources-to-build-args [
    sources: record,
    source_types: record = {}
] {
    let repo_root = (get-repo-root)
    # If source_types is empty, detect inline
    let detected_types = (if ($source_types | is-empty) {
        detect-all-source-types $sources
    } else {
        $source_types
    })
    
    ($sources | columns | reduce --fold {} {|source_key, acc|
        let source = ($sources | get $source_key)
        let source_type = (try { $detected_types | get $source_key } catch { "git" })
        let source_type = (if ($source_type | str length) == 0 { "git" } else { $source_type })
        
        let source_key_upper = ($source_key | str upcase)
        mut result = $acc

        if $source_type == "local" {
            # Local source - generate _PATH and _MODE args
            let path_build_arg = $"($source_key_upper)_PATH"
            let mode_build_arg = $"($source_key_upper)_MODE"
            
            # Check for env var override first (highest priority)
            let env_path_key = $"($source_key_upper)_PATH"
            let env_path = (try { ($env | get -o $env_path_key) } catch { null })
            
            if ($env_path != null) and ($env_path | str length) > 0 {
                # Validate env var path
                let path_validation = (validate-local-path $env_path $repo_root)
                if not $path_validation.valid {
                    error make {
                        msg: ($"Environment variable '($env_path_key)' contains invalid path: " + ($path_validation.errors | str join "; "))
                    }
                }
                $result = ($result | upsert $path_build_arg $env_path)
            } else {
                # Use config path field
                let path_value = (try { $source.path } catch { "" })
                if ($path_value | str length) > 0 {
                    $result = ($result | upsert $path_build_arg $path_value)
                }
            }
            
            # Always set MODE to "local" for local sources
            $result = ($result | upsert $mode_build_arg "local")
        } else {
            # Git source - generate _REF and _URL args (existing behavior)
            let ref_build_arg = $"($source_key_upper)_REF"
            let url_build_arg = $"($source_key_upper)_URL"
            
            let ref_value = (try { $source.ref } catch { "" })
            if ($ref_value | str length) > 0 {
                $result = ($result | upsert $ref_build_arg (get-env-or-config $ref_build_arg $ref_value))
            }

            let url_value = (try { $source.url } catch { "" })
            if ($url_value | str length) > 0 {
                $result = ($result | upsert $url_build_arg (get-env-or-config $url_build_arg $url_value))
            }
        }

        $result
    })
}

export def process-external-images-to-build-args [external_images: record] {
    ($external_images | columns | reduce --fold {} {|img_key, acc|
        let img = ($external_images | get $img_key)
        let build_arg = (try { $img.build_arg } catch { "" })
        if ($build_arg | str length) > 0 {
            # Check for legacy image field (hard error, no parsing)
            if "image" in ($img | columns) {
                error make {
                    msg: $"External image '($img_key)' has legacy 'image' field. Expected 'name' and 'tag' fields. Migration should have converted this."
                }
            }
            
            let name = (try { $img.name } catch { "" })
            let tag = (try { $img.tag } catch { "" })
            
            if ($name | str length) == 0 {
                error make {
                    msg: $"External image '($img_key)' missing required field 'name'"
                }
            }
            
            if ($tag | str length) == 0 {
                error make {
                    msg: $"External image '($img_key)' missing required field 'tag'"
                }
            }
            
            let image_value = $"($name):($tag)"
            $acc | upsert $build_arg (get-env-or-config $build_arg $image_value)
        } else {
            $acc
        }
    })
}

# === Flag Validation ===

# Validate flag conflicts for --all-services mode
# Returns error if incompatible flags are provided
export def validate-all-services-flags [
  service: any,
  version: string,
  versions: string
] {
  let service_provided = (try { ($service | str length) > 0 } catch { false })
  if $service_provided {
    error make {
      msg: "Cannot use --service with --all-services. Use --all-services alone to build all services."
    }
  }
  
  if ($version | str length) > 0 {
    error make {
      msg: "Cannot use --version with --all-services. Use --latest-only or --all-versions to control version selection."
    }
  }
  
  if ($versions | str length) > 0 {
    error make {
      msg: "Cannot use --versions with --all-services. Use --latest-only or --all-versions to control version selection."
    }
  }
}

# Validate that --service is provided when --all-services is not
export def validate-service-required [service: any] {
  let service_provided = (try { ($service | str length) > 0 } catch { false })
  if not $service_provided {
    error make {
      msg: "Either --service <name> or --all-services must be specified."
    }
  }
}

# Load service manifests (versions and platforms)
# Returns: { has_versions: bool, versions_manifest: any, has_platforms: bool, platforms_manifest: any, default_platform: string }
export def load-service-manifests [service: string] {
  let has_versions = (check-versions-manifest-exists $service)
  let versions_manifest = (if $has_versions { load-versions-manifest $service } else { null })
  let has_platforms = (check-platforms-manifest-exists $service)
  let platforms_manifest = (if $has_platforms { load-platforms-manifest $service } else { null })
  let default_platform = (if $has_platforms { get-default-platform $platforms_manifest } else { "" })
  
  {
    has_versions: $has_versions,
    versions_manifest: $versions_manifest,
    has_platforms: $has_platforms,
    platforms_manifest: $platforms_manifest,
    default_platform: $default_platform
  }
}

# Validate platform flag against service's platforms manifest
export def validate-platform-flag [
  platform: string,
  service: string,
  has_platforms: bool,
  platforms_manifest: any
] {
  if ($platform | str length) == 0 {
    return  # No platform specified, nothing to validate
  }
  
  if not $has_platforms {
    error make { 
      msg: ($"Platform '($platform)' specified but service '($service)' has no platforms manifest.\n\n" +
            "The --platform flag is only valid for multi-platform services.\n" +
            "Options:\n" +
            "1. Remove the --platform flag (service is single-platform)\n" +
            $"2. Create a platforms manifest: services/($service)/platforms.nuon\n" +
            "3. See docs/guides/multi-platform-builds.md for details")
    }
  }
  
  let platform_names = (get-platform-names $platforms_manifest)
  if not ($platform in $platform_names) {
    let available = ($platform_names | str join ", ")
    let first_platform = ($available | split row ", " | first)
    error make { 
      msg: ($"Platform '($platform)' not found in platforms manifest for service '($service)'.\n\n" +
            $"Available platforms: ($available)\n" +
            "Options:\n" +
            $"1. Use one of the available platforms: --platform ($first_platform)\n" +
            $"2. Add the platform to services/($service)/platforms.nuon\n" +
            "3. Check for typos in the platform name")
    }
  }
}

# Validate that service has a versions manifest (required for matrix, build order, etc.)
export def require-versions-manifest [
  service: string,
  has_versions: bool,
  operation: string  # "generate matrix" | "show build order" | "build"
] {
  if not $has_versions {
    error make { 
      msg: ($"Service '($service)' does not have a version manifest. Cannot ($operation).\n\n" +
            "This operation requires a version manifest.\n" +
            "To fix:\n" +
            $"1. Create services/($service)/versions.nuon\n" +
            "2. Define at least one version with a 'default' field\n" +
            "3. See docs/guides/multi-version-builds.md for examples")
    }
  }
}

# Check if any multi-version flags are set
export def has-multi-version-flags [
  all_versions: bool,
  versions: string,
  latest_only: bool
] {
  $all_versions or ($versions | str length) > 0 or $latest_only
}

# Determine if this is a metadata-only operation (no actual build)
export def is-metadata-only-mode [
  show_build_order: bool,
  matrix_json: bool
] {
  $show_build_order or $matrix_json
}

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
