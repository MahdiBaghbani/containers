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

# GitHub Actions matrix JSON generation

# Generate GitHub Actions matrix JSON (always includes 'platform' field)
export def generate-matrix-json [
  manifest: record,
  platforms: any = null,
  --include-metadata = true
] {
  let versions = (try {
    $manifest.versions
  } catch {
    []
  })
  
  if ($versions | is-empty) {
    return {include: []}
  }
  
  let is_multi_platform = ($platforms != null)
  
  let matrix_entries = if $is_multi_platform {
    use ../platforms/core.nu [expand-version-to-platforms get-default-platform]
    let default_platform = (get-default-platform $platforms)
    
    $versions | each {|version|
      let expanded = (expand-version-to-platforms $version $platforms $default_platform)
      $expanded | each {|exp|
        mut entry = {
          version: $exp.name,
          platform: $exp.platform
        }
        
        if $include_metadata {
          $entry = ($entry | insert latest (try { $exp.latest } catch { false }))
          $entry = ($entry | insert tags (try { $exp.tags | str join "," } catch { $exp.name }))
        }
        
        $entry
      }
    } | flatten
  } else {
    $versions | each {|version|
      mut entry = {
        version: $version.name,
        platform: ""
      }
      
      if $include_metadata {
        $entry = ($entry | insert latest (try { $version.latest } catch { false }))
        $entry = ($entry | insert tags (try { $version.tags | str join "," } catch { $version.name }))
      }
      
      $entry
    }
  }
  
  {include: $matrix_entries}
}

export def generate-service-matrix [
  service: string,
  --include-metadata = true
] {
  let manifest_path = $"services/($service)/versions.nuon"
  
  if not ($manifest_path | path exists) {
    error make { msg: $"No version manifest found for service '($service)'" }
  }
  
  use ../manifest/core.nu [load-versions-manifest]
  use ../platforms/core.nu [check-platforms-manifest-exists load-platforms-manifest]
  
  let manifest = (load-versions-manifest $service)
  
  let platforms = if (check-platforms-manifest-exists $service) {
    load-platforms-manifest $service
  } else {
    null
  }
  
  generate-matrix-json $manifest $platforms --include-metadata=$include_metadata
}

export def generate-multi-service-matrix [
  services: list<string>,
  --include-metadata = true
] {
  use ../manifest/core.nu [check-versions-manifest-exists load-versions-manifest]
  use ../platforms/core.nu [check-platforms-manifest-exists load-platforms-manifest expand-version-to-platforms get-default-platform]
  
  let all_entries = ($services | each {|service|
    if not (check-versions-manifest-exists $service) {
      return []
    }
    
    let manifest = (load-versions-manifest $service)
    let versions = (try { $manifest.versions } catch { [] })
    
    let platforms = if (check-platforms-manifest-exists $service) {
      load-platforms-manifest $service
    } else {
      null
    }
    
    let is_multi_platform = ($platforms != null)
    
    if $is_multi_platform {
      let default_platform = (get-default-platform $platforms)
      $versions | each {|version|
        let expanded = (expand-version-to-platforms $version $platforms $default_platform)
        $expanded | each {|exp|
          mut entry = {
            service: $service,
            version: $exp.name,
            platform: $exp.platform
          }
          
          if $include_metadata {
            $entry = ($entry | insert latest (try { $exp.latest } catch { false }))
            $entry = ($entry | insert tags (try { $exp.tags | str join "," } catch { $exp.name }))
          }
          
          $entry
        }
      } | flatten
    } else {
      $versions | each {|version|
        mut entry = {
          service: $service,
          version: $version.name,
          platform: ""
        }
        
        if $include_metadata {
          $entry = ($entry | insert latest (try { $version.latest } catch { false }))
          $entry = ($entry | insert tags (try { $version.tags | str join "," } catch { $version.name }))
        }
        
        $entry
      }
    }
  } | flatten)
  
  {include: $all_entries}
}

export def print-matrix [
  matrix: record
] {
  let entries = ($matrix.include | default [])
  
  if ($entries | is-empty) {
    print "Matrix is empty - no versions to build"
    return
  }
  
  print $"Matrix has ($entries | length) entries:"
  print ""
  
  for entry in $entries {
    let platform_display = if "platform" in ($entry | columns) and ($entry.platform | str length) > 0 {
      $" \(($entry.platform)\)"
    } else {
      ""
    }
    
    if "service" in ($entry | columns) {
      print $"  - Service: ($entry.service), Version: ($entry.version)($platform_display)"
    } else {
      print $"  - Version: ($entry.version)($platform_display)"
    }
    
    if "latest" in ($entry | columns) and $entry.latest {
      print $"    (marked as latest)"
    }
    
    if "tags" in ($entry | columns) {
      print $"    Tags: ($entry.tags)"
    }
  }
}
