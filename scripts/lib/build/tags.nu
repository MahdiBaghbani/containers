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

# Image tag generation
# See docs/concepts/build-system.md for tag format documentation

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
        # Generate tags only for the current CI platform
        let ci_platform = (try { $registry_info.ci_platform } catch { "local" })
        
        if $ci_platform == "github" {
            let base_image_name = $"($registry_info.github_registry)/($registry_info.github_path)/($service)"
            $base_tags | each {|t| $"($base_image_name):($t)"}
        } else if $ci_platform == "forgejo" {
            let base_image_name = $"($registry_info.forgejo_registry)/($registry_info.forgejo_path)/($service)"
            $base_tags | each {|t| $"($base_image_name):($t)"}
        } else {
            # Fallback to local tags
            $base_tags | each {|t| $"($service):($t)"}
        }
    }
}
