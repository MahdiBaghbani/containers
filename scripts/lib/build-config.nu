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

# Build configuration utilities

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

# Process sources into build args (auto-generates {SOURCE_KEY}_REF and {SOURCE_KEY}_URL)
# See docs/concepts/service-configuration.md#source-build-arguments-convention for convention
export def process-sources-to-build-args [sources: record] {
    ($sources | columns | reduce --fold {} {|source_key, acc|
        let source = ($sources | get $source_key)

        let source_key_upper = ($source_key | str upcase)
        let ref_build_arg = $"($source_key_upper)_REF"
        let url_build_arg = $"($source_key_upper)_URL"

        mut result = $acc

        let ref_value = (try { $source.ref } catch { "" })
        if ($ref_value | str length) > 0 {
            $result = ($result | upsert $ref_build_arg (get-env-or-config $ref_build_arg $ref_value))
        }

        let url_value = (try { $source.url } catch { "" })
        if ($url_value | str length) > 0 {
            $result = ($result | upsert $url_build_arg (get-env-or-config $url_build_arg $url_value))
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
