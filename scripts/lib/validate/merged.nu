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

# Merged and service config validation

use ./_shared.nu [validate-source-entries]
use ./tls.nu [validate-tls-config]
use ./ssh.nu [validate-ssh-config]

# Validate service config (strict separation: metadata only when platforms exist)
export def validate-service-config [
  config: record,
  has_platforms: bool = false,
  service_name: string = ""
] {
  mut errors = []
  mut warnings = []

  let service_ctx = (if ($service_name | str length) > 0 { $"Service '($service_name)'" } else { "Service config" })

  if $has_platforms {
    # When platforms.nuon exists, base config can ONLY contain metadata fields:
    # name, context, tls, ssh, and labels. Labels are metadata like TLS/SSH
    # (Docker image labels), not infrastructure or version control.
    let forbidden_fields = ["dockerfile", "external_images", "sources", "dependencies", "build_args"]

    for field in $forbidden_fields {
      if $field in ($config | columns) {
        let field_val = ($config | get $field)
        let is_empty = (try {
          if ($field_val | describe | str starts-with "record") {
            ($field_val | columns | is-empty)
          } else if ($field_val | describe | str starts-with "list") {
            ($field_val | is-empty)
          } else {
            false
          }
        } catch { false })

        if not $is_empty {
          $errors = ($errors | append $"($service_ctx): ($field): Field forbidden when platforms.nuon exists. Move to platforms.nuon \(infrastructure\) or versions.nuon \(versions\).")
        }
      }
    }
  }

  if not ("name" in ($config | columns)) {
    $errors = ($errors | append "Missing required field: 'name'")
  }
  if not ("context" in ($config | columns)) {
    $errors = ($errors | append "Missing required field: 'context'")
  }
  if not $has_platforms {
    if not ("dockerfile" in ($config | columns)) {
      $errors = ($errors | append "Missing required field: 'dockerfile' (required for single-platform services)")
    }
  }

  if "sources" in ($config | columns) {
    if $has_platforms {
      $errors = ($errors | append $"($service_ctx): sources: Section forbidden when platforms.nuon exists. Define in versions.nuon defaults or overrides.")
    } else {
      let src_validation = (validate-source-entries $config.sources $service_ctx true)
      if not $src_validation.valid {
        $errors = ($errors | append $src_validation.errors)
      }
    }
  }
  # Note: sources is NOT required in base config for single-platform services.
  # Single-platform services can define sources entirely in versions.nuon defaults.

  if "external_images" in ($config | columns) {
    if $has_platforms {
      $errors = ($errors | append $"($service_ctx): external_images: Section forbidden when platforms.nuon exists. Move to platforms.nuon \(infrastructure\) or versions.nuon \(versions\).")
    } else {
      let ext_images = $config.external_images
      for img_key in ($ext_images | columns) {
        let img = ($ext_images | get $img_key)

        if "image" in ($img | columns) {
          $errors = ($errors | append $"($service_ctx): external_images.($img_key).image: Field forbidden \(legacy\). Use 'name' field in base config.")
        }

        if "tag" in ($img | columns) {
          $errors = ($errors | append $"($service_ctx): external_images.($img_key).tag: Field forbidden. Define in versions.nuon overrides.")
        }

        if not ("name" in ($img | columns)) {
          $errors = ($errors | append $"External image '($img_key)' missing required field: 'name'")
        }
        if not ("build_arg" in ($img | columns)) {
          $errors = ($errors | append $"External image '($img_key)' missing required field: 'build_arg'")
        }
      }
    }
  }

  if "dependencies" in ($config | columns) {
    if $has_platforms {
      $errors = ($errors | append $"($service_ctx): dependencies: Section forbidden when platforms.nuon exists. Move to platforms.nuon \(infrastructure\) or versions.nuon \(versions\).")
    } else {
      let deps = $config.dependencies
      for dep_key in ($deps | columns) {
        let dep = ($deps | get $dep_key)

        if "version" in ($dep | columns) {
          $errors = ($errors | append $"($service_ctx): dependencies.($dep_key).version: Field forbidden. Define in versions.nuon overrides.")
        }

        if "single_platform" in ($dep | columns) {
          $errors = ($errors | append $"($service_ctx): dependencies.($dep_key).single_platform: Field forbidden. Define in versions.nuon overrides.")
        }

        if not ("build_arg" in ($dep | columns)) {
          $errors = ($errors | append $"Dependency '($dep_key)' missing required field: 'build_arg'")
        }
      }
    }
  }

  if "tls" in ($config | columns) {
    let tls_config = (try { $config.tls } catch { null })
    if $tls_config != null {
      let tls_validation = (validate-tls-config $tls_config (try { $config.name } catch { "" }))
      if not $tls_validation.valid {
        $errors = ($errors | append $tls_validation.errors)
      }
      if "warnings" in ($tls_validation | columns) {
        $warnings = ($warnings | append $tls_validation.warnings)
      }
    }
  }

  # SSH is allowed in base service config (unlike TLS, it may vary per platform
  # and per version, but base placement is valid); validate when present.
  if "ssh" in ($config | columns) {
    let ssh_config = (try { $config.ssh } catch { null })
    if $ssh_config != null {
      let ssh_validation = (validate-ssh-config $ssh_config $"Service '($config.name? | default "")'")
      if not $ssh_validation.valid {
        $errors = ($errors | append $ssh_validation.errors)
      }
      if "warnings" in ($ssh_validation | columns) {
        $warnings = ($warnings | append $ssh_validation.warnings)
      }
    }
  }

  {
    valid: ($errors | is-empty)
    errors: $errors
    warnings: $warnings
  }
}

export def validate-merged-config [
    merged_config: record,
    service: string,
    has_platforms: bool,
    platform_name: string = ""
] {
    mut errors = []
    
    let context = (if ($platform_name | str length) > 0 {
        $"Merged config for platform '($platform_name)'"
    } else {
        "Merged config"
    })
    
    # Validate external_images have name, tag, build_arg
    if "external_images" in ($merged_config | columns) {
        let ext_images = $merged_config.external_images
        
        let ext_images_type = ($ext_images | describe)
        if not ($ext_images_type | str starts-with "record") {
            $errors = ($errors | append $"($context): external_images: Must be a record.")
        } else {
            for img_key in ($ext_images | columns) {
                let img = ($ext_images | get $img_key)
                
                let img_type = ($img | describe)
                if not ($img_type | str starts-with "record") {
                    $errors = ($errors | append $"($context): external_images.($img_key): Must be a record.")
                    continue
                }
                
                if not ("name" in ($img | columns)) {
                    $errors = ($errors | append $"($context): external_images.($img_key): Missing required field 'name'. Define in base config \(single-platform\) or platforms.nuon \(multi-platform\).")
                }
                
                if not ("tag" in ($img | columns)) {
                    $errors = ($errors | append $"($context): external_images.($img_key): Missing required field 'tag'. Define in versions.nuon overrides.external_images.($img_key).tag.")
                }
                
                if not ("build_arg" in ($img | columns)) {
                    $errors = ($errors | append $"($context): external_images.($img_key): Missing required field 'build_arg'. Define in base config \(single-platform\) or platforms.nuon \(multi-platform\).")
                }
            }
        }
    }
    
    # Validate sources via centralized validator (merged configs must be complete:
    # git sources need both url and ref)
    if "sources" in ($merged_config | columns) {
        let src_validation = (validate-source-entries $merged_config.sources $context true)
        if not $src_validation.valid {
            $errors = ($errors | append $src_validation.errors)
        }
    }
    
    {
        valid: ($errors | is-empty),
        errors: $errors
    }
}