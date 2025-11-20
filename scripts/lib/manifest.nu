# SPDX-License-Identifier: AGPL-3.0-or-later
# Open Cloud Mesh Containers: container build scripts and images
# Copyright (C) 2025 Open Cloud Mesh Contributors
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

export def check-versions-manifest-exists [
  service: string
] {
  let manifest_path = $"services/($service)/versions.nuon"
  $manifest_path | path exists
}

export def load-versions-manifest [
  service: string
] {
  let manifest_path = $"services/($service)/versions.nuon"
  
  if not ($manifest_path | path exists) {
    error make { msg: $"Version manifest not found: ($manifest_path)" }
  }
  
  try {
    open $manifest_path
  } catch {
    error make { msg: $"Failed to parse version manifest: ($manifest_path)" }
  }
}

export def get-default-version [
  manifest: record
] {
  try {
    $manifest.default
  } catch {
    error make { msg: "Manifest missing 'default' field" }
  }
}

export def get-version-spec [
  manifest: record,
  version_name: string
] {
  let versions = (try {
    $manifest.versions
  } catch {
    error make { msg: "Manifest missing 'versions' field" }
  })
  
  let found = ($versions | where name == $version_name)
  
  if ($found | is-empty) {
    error make { msg: $"Version '($version_name)' not found in manifest" }
  }
  
  $found.0
}

export def get-latest-versions [
  manifest: record
] {
  let versions = (try {
    $manifest.versions
  } catch {
    []
  })
  
  $versions | where ($it.latest? | default false) == true
}

# Filter versions (strips platform suffixes from input, returns {versions, detected_platforms})
export def filter-versions [
  manifest: record,
  platforms_manifest: any = null,
  --all = false,
  --versions: string = "",
  --latest-only = false
] {
  let all_versions = (try {
    $manifest.versions
  } catch {
    []
  })
  
  if $all {
    return {versions: $all_versions, detected_platforms: []}
  }
  
  if $latest_only {
    return {versions: ($all_versions | where ($it.latest? | default false) == true), detected_platforms: []}
  }
  
  if ($versions | str length) > 0 {
    let requested = ($versions | split row "," | each {|v| $v | str trim} | where ($it | str length) > 0)
    
    if ($requested | is-empty) {
      return {versions: [], detected_platforms: []}
    }
    
    mut base_names = []
    mut detected_platforms = []
    
    for version_name in $requested {
      if $platforms_manifest != null {
        use ./platforms.nu [strip-platform-suffix]
        let stripped = (try {
          strip-platform-suffix $version_name $platforms_manifest
        } catch {
          {base_name: $version_name, platform_name: ""}
        })
        
        $base_names = ($base_names | append $stripped.base_name)
        
        if ($stripped.platform_name | str length) > 0 {
          if not ($stripped.platform_name in $detected_platforms) {
            $detected_platforms = ($detected_platforms | append $stripped.platform_name)
          }
        }
      } else {
        $base_names = ($base_names | append $version_name)
      }
    }
    
    let unique_base_names = ($base_names | uniq)
    let matched = ($all_versions | where $it.name in $unique_base_names)
    
    return {versions: $matched, detected_platforms: $detected_platforms}
  }
  
  return {versions: [], detected_platforms: []}
}

# Resolve version name from CLI args or manifest (returns {base_name, detected_platform})
export def resolve-version-name [
  version_arg: string,
  versions_manifest: record,
  platforms_manifest: any,
  version_suffix_info: any
] {
  if $version_suffix_info != null {
    return {
      base_name: $version_suffix_info.base_name,
      detected_platform: $version_suffix_info.platform_name
    }
  }
  
  if ($version_arg | str length) > 0 {
    if $platforms_manifest != null {
      use ./platforms.nu [strip-platform-suffix]
      let stripped = (try {
        strip-platform-suffix $version_arg $platforms_manifest
      } catch {
        return {base_name: $version_arg, detected_platform: ""}
      })
      return {base_name: $stripped.base_name, detected_platform: $stripped.platform_name}
    } else {
      return {base_name: $version_arg, detected_platform: ""}
    }
  }
  
  if $versions_manifest != null {
    let default_version = (get-default-version $versions_manifest)
    return {base_name: $default_version, detected_platform: ""}
  }
  
  return {base_name: "", detected_platform: ""}
}

export def get-version-or-null [
  versions_manifest: record,
  version_name: string
] {
  if $versions_manifest == null {
    return null
  }
  
  if ($version_name | str length) == 0 {
    let default_name = (get-default-version $versions_manifest)
    return (get-version-spec $versions_manifest $default_name)
  }
  
  try {
    get-version-spec $versions_manifest $version_name
  } catch {
    return null
  }
}
