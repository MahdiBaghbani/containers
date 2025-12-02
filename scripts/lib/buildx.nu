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

# Ensure buildx builder is set up for local dev builds
# In CI (GITHUB_ACTIONS set), this is a no-op - the workflow configures the builder
# Both environments use docker driver with shared daemon store
def ensure-builder [is_local: bool = false] {
  # In CI, trust the workflow-configured builder (set by docker/setup-buildx-action)
  let in_ci = (((try { $env.GITHUB_ACTIONS } catch { "" }) | default "") | str length) > 0
  if $in_ci {
    return
  }
  
  # For local dev builds, ensure we're using the default builder
  ^docker buildx use default | ignore
}

# Verify image exists in local Docker daemon
# Under unified docker driver model, this is the same store Buildx uses
export def verify-image-exists-locally [image_ref: string] {
  let exists = (try {
    let images = (^docker images --format "{{.Repository}}:{{.Tag}}" | lines)
    ($images | where {|img| $img == $image_ref} | length) > 0
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
