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

# Service validation entrypoints and focused module re-exports.
# The orchestration below owns validation sequencing and merge-aware traversal;
# structural validators remain in the focused sibling modules.

use ./merged.nu [validate-merged-config]
use ./sources.nu [validate-service-file validate-manifest-file]
use ./platforms-validate.nu [validate-platforms-manifest]
use ./dockerfile.nu [validate-dockerfile-paths]
use ./tls.nu [validate-tls-config-merged]
use ./ssh.nu [validate-ssh-config-merged]
use ./clone-compat.nu [validate-source-clone-compat]
use ../platforms/core.nu [check-platforms-manifest-exists load-platforms-manifest]
use ../platforms/core.nu [
  get-platform-names
  get-platform-spec
  merge-platform-config
  merge-version-overrides
]
use ../manifest/core.nu [
  check-versions-manifest-exists
  load-versions-manifest
  apply-version-defaults
]
use ../plane/guard.nu [PLANE_LOCAL]
use ../plane/effective-config.nu [apply-local-plane-effective-sources]
use ../plane/versions.nu [load-effective-versions-manifest]

export use ./paths.nu [validate-local-path]
export use ./tls.nu [
  validate-tls-config
  validate-version-overrides-tls
  validate-tls-config-merged
]

export use ./platforms-validate.nu [
  validate-platform-config
  validate-platform-defaults
  validate-platforms-manifest
]

export use ./versions.nu [
  validate-version-defaults
  validate-version-manifest
  validate-version-overrides-structure
]

export use ./merged.nu [
  validate-merged-config
  validate-service-config
]

export use ./sources.nu [
  validate-service-file
  validate-manifest-file
]

export use ./dockerfile.nu [validate-dockerfile-paths]

export use ./clone-compat.nu [validate-source-clone-compat]

# Combine one layer result without requiring every validator to expose warnings.
def combine-validation-result [state: record, result: record] {
  let result_errors = (if $result.valid { [] } else { $result.errors })
  let result_warnings = (try { $result.warnings } catch { [] })
  {
    errors: ($state.errors | append $result_errors)
    warnings: ($state.warnings | append $result_warnings)
  }
}

# Platform validation is optional for single-platform services, but a present
# platforms manifest must be both loadable and structurally valid.
def validate-platform-layer [service: string, has_platforms: bool] {
  if not $has_platforms {
    return {valid: true, errors: [], warnings: []}
  }

  try {
    let platforms = (load-platforms-manifest $service)
    validate-platforms-manifest $platforms
  } catch {|err|
    {
      valid: false
      errors: [$"Failed to validate platforms manifest: ($err.msg)"]
      warnings: []
    }
  }
}

# File-level checks are kept together so complete validation can decide whether
# merge-aware checks are safe to run after all base layers have passed.
def validate-file-layers [service: string] {
  {
    dockerfile: (validate-dockerfile-paths $service)
    manifest: (validate-manifest-file $service)
  }
}

# Validate the independent service layers before merge-aware validation.
def validate-base-layers [service: string] {
  let config_result = (validate-service-file $service)
  let has_platforms = (check-platforms-manifest-exists $service)
  let platform_result = (validate-platform-layer $service $has_platforms)
  let file_layers = (validate-file-layers $service)

  let initial = {errors: [], warnings: []}
  let with_config = (combine-validation-result $initial $config_result)
  let with_platforms = (combine-validation-result $with_config $platform_result)
  let with_dockerfile = (combine-validation-result $with_platforms $file_layers.dockerfile)
  let combined = (combine-validation-result $with_dockerfile $file_layers.manifest)
  {
    has_platforms: $has_platforms
    errors: $combined.errors
    warnings: $combined.warnings
  }
}

# Run all merge-aware checks for one fully merged version/platform config.
def validate-merged-bundle [
  merged: record,
  service: string,
  has_platforms: bool,
  platform_name: string,
  ctx: string
] {
  mut errors = []
  mut warnings = []

  let struct_result = (validate-merged-config $merged $service $has_platforms $platform_name)
  if not $struct_result.valid {
    $errors = ($errors | append ($struct_result.errors | each {|e| $"($ctx): ($e)"}))
  }

  let tls_result = (validate-tls-config-merged $merged $service)
  if not $tls_result.valid {
    $errors = ($errors | append ($tls_result.errors | each {|e| $"($ctx): ($e)"}))
  }
  if "warnings" in ($tls_result | columns) {
    $warnings = ($warnings | append $tls_result.warnings)
  }

  let ssh_result = (validate-ssh-config-merged $merged $service)
  if not $ssh_result.valid {
    $errors = ($errors | append ($ssh_result.errors | each {|e| $"($ctx): ($e)"}))
  }
  if "warnings" in ($ssh_result | columns) {
    $warnings = ($warnings | append $ssh_result.warnings)
  }

  let clone_compat = (validate-source-clone-compat $merged $service $ctx)
  if not $clone_compat.valid {
    $errors = ($errors | append $clone_compat.errors)
  }

  {valid: ($errors | is-empty), errors: $errors, warnings: $warnings}
}

# Build and validate one version across all applicable platform configs.
def validate-merged-version [
  service: string,
  base_config: record,
  manifest: record,
  version_spec: record,
  has_platforms: bool,
  platforms: any,
  is_local_plane: bool,
  plane_ctx: any
] {
  mut errors = []
  mut warnings = []
  let version_name = (try { $version_spec.name } catch { "" })
  let version_with_defaults = (apply-version-defaults $manifest $version_spec)

  if $has_platforms and $platforms != null {
    let platform_names = (get-platform-names $platforms)
    for platform in $platform_names {
      let ctx = $"Service '($service)' version '($version_name)' platform '($platform)'"
      let merge_result = (try {
        let platform_spec = (get-platform-spec $platforms $platform)
        let with_platform = (merge-platform-config $base_config $platform_spec)
        {
          ok: true
          merged: (merge-version-overrides $with_platform $version_with_defaults $platform $platforms)
        }
      } catch {|err|
        {ok: false, msg: $err.msg}
      })
      if $merge_result.ok {
        mut merged = $merge_result.merged
        if $is_local_plane {
          $merged = (apply-local-plane-effective-sources $merged $service $version_with_defaults $plane_ctx)
        }
        let bundle = (validate-merged-bundle $merged $service $has_platforms $platform $ctx)
        $errors = ($errors | append $bundle.errors)
        $warnings = ($warnings | append $bundle.warnings)
      } else {
        $errors = ($errors | append $"($ctx): Failed to build merged config: ($merge_result.msg)")
      }
    }
  } else {
    let ctx = $"Service '($service)' version '($version_name)'"
    let merge_result = (try {
      {ok: true, merged: (merge-version-overrides $base_config $version_with_defaults "" null)}
    } catch {|err|
      {ok: false, msg: $err.msg}
    })
    if $merge_result.ok {
      mut merged = $merge_result.merged
      if $is_local_plane {
        $merged = (apply-local-plane-effective-sources $merged $service $version_with_defaults $plane_ctx)
      }
      let bundle = (validate-merged-bundle $merged $service $has_platforms "" $ctx)
      $errors = ($errors | append $bundle.errors)
      $warnings = ($warnings | append $bundle.warnings)
    } else {
      $errors = ($errors | append $"($ctx): Failed to build merged config: ($merge_result.msg)")
    }
  }

  {errors: $errors, warnings: $warnings}
}

# Load the exact base, version, platform, and plane inputs used by merging.
def load-merge-validation-inputs [
  service: string,
  has_platforms: bool,
  plane_ctx: any
] {
  let cfg_path = $"services/($service).nuon"
  let base_config = (try { open $cfg_path } catch { null })
  if $base_config == null {
    return {
      valid: true
      base_config: null
      manifest: null
      platforms: null
      is_local_plane: false
    }
  }

  let is_local_plane = (
    $plane_ctx != null
    and (try { $plane_ctx.plane } catch { "" }) == $PLANE_LOCAL
  )
  let manifest = (if $is_local_plane {
    if not (check-versions-manifest-exists $service) {
      null
    } else {
      try {
        load-effective-versions-manifest $service $plane_ctx
      } catch {|err|
        return {valid: false, errors: [$err.msg], warnings: []}
      }
    }
  } else {
    try { load-versions-manifest $service } catch { null }
  })
  let platforms = (if $has_platforms {
    try { load-platforms-manifest $service } catch { null }
  } else {
    null
  })
  {
    valid: true
    base_config: $base_config
    manifest: $manifest
    platforms: $platforms
    is_local_plane: $is_local_plane
  }
}

# Build and validate merged configs in the same order used by the build path.
def validate-service-merged-configs [
  service: string,
  has_platforms: bool,
  plane_ctx: any = null
] {
  mut errors = []
  mut warnings = []
  let inputs = (load-merge-validation-inputs $service $has_platforms $plane_ctx)
  if not $inputs.valid {
    return $inputs
  }
  if $inputs.manifest == null {
    return {valid: true, errors: [], warnings: []}
  }

  for version_spec in $inputs.manifest.versions {
    let version_result = (
      validate-merged-version
        $service
        $inputs.base_config
        $inputs.manifest
        $version_spec
        $has_platforms
        $inputs.platforms
        $inputs.is_local_plane
        $plane_ctx
    )
    $errors = ($errors | append $version_result.errors)
    $warnings = ($warnings | append $version_result.warnings)
  }

  {valid: ($errors | is-empty), errors: $errors, warnings: $warnings}
}

# Validate base layers first, then validate every merged version/platform.
export def validate-service-complete [
  service: string,
  plane_ctx: any = null
] {
  let base = (validate-base-layers $service)
  mut all_errors = $base.errors
  mut all_warnings = $base.warnings

  if ($all_errors | is-empty) {
    let merged_result = (validate-service-merged-configs $service $base.has_platforms $plane_ctx)
    if not $merged_result.valid {
      $all_errors = ($all_errors | append $merged_result.errors)
    }
    if "warnings" in ($merged_result | columns) {
      $all_warnings = ($all_warnings | append $merged_result.warnings)
    }
  }

  {
    valid: ($all_errors | is-empty)
    errors: $all_errors
    warnings: $all_warnings
  }
}

# Print validation results in the CLI's existing human-readable format.
export def print-validation-results [
  results: record
] {
  if $results.valid {
    print "✓ Validation passed"
  } else {
    print "✗ Validation failed"
    print ""
    print "Errors:"
    for error in $results.errors {
      print $"  - ($error)"
    }
  }

  if "warnings" in ($results | columns) and (not ($results.warnings | is-empty)) {
    print ""
    print "Warnings:"
    for warning in $results.warnings {
      print $"  - ($warning)"
    }
  }
}
