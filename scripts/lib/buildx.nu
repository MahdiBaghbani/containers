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

# Ensure buildx builder is set up (default driver for local, docker-container for CI)
def ensure-builder [is_local: bool = false] {
  if $is_local {
    ^docker buildx use default | ignore
  } else {
    let exists = (try { not ((^docker buildx ls | lines | where ($it | str contains "ocm-builder")) | is-empty) } catch { false })
    if not $exists {
      ^docker buildx create --name ocm-builder --driver docker-container | ignore
    }
    ^docker buildx use ocm-builder | ignore
  }
}

# Verify image exists locally (for local builds with default driver)
export def load-image-into-builder [image_ref: string] {
  let exists = (try {
    let images = (^docker images --format "{{.Repository}}:{{.Tag}}" | lines)
    ($images | where $it == $image_ref | length) > 0
  } catch {
    false
  })
  
  $exists
}

def gha-cache-args [] {
  if ((try { $env.GITHUB_ACTIONS } catch { "" }) | default "" | str length) > 0 {
    [
      "--cache-from=type=gha,scope=ocm-containers"
      "--cache-to=type=gha,mode=max,scope=ocm-containers"
    ]
  } else {
    []
  }
}

export def build [
  --context: string,
  --dockerfile: string,
  --platforms: list<string>,
  --tags: list<string>,
  --build-args: record = {},
  --labels: record = {},
  push: bool = false,  # Whether to push images to registry
  provenance: bool = false,  # Whether to include provenance
  is_local: bool = false,  # Whether this is a local build (affects image resolution)
  --progress: string = "auto"  # Build progress output: auto, plain, tty
] {
  ensure-builder $is_local

  let cache_args = (gha-cache-args)
  let push_flag = (if $push { ["--push"] } else { ["--load"] })
  let prov_flag = (if $provenance { ["--provenance=true"] } else { [] })
  let tag_args = ($tags | each {|t| $"--tag=($t)" })
  let plat = ($platforms | str join ",")

  let ba = ($build_args | columns | each {|k| 
    let val = ($build_args | get $k)
    $"--build-arg=($k)=($val)"
  })
  let la = ($labels | columns | each {|k| 
    let val = ($labels | get $k)
    $"--label=($k)=($val)"
  })
  
  let args = ([
    "buildx" "build"
    $"--file=($dockerfile)"
    $"--platform=($plat)"
    $"--progress=($progress)"
  ] | append $tag_args | append $ba | append $la | append $cache_args | append $push_flag | append $prov_flag | append [$context])

  ^docker ...$args
}
