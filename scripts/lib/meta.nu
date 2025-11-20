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

# Detect local platform architecture
def detect-local-platform [] {
  let arch = (try {
    (^uname -m | str trim | str downcase)
  } catch {
    "amd64"
  })
  let platform = (match $arch {
    "x86_64" | "amd64" => { "linux/amd64" }
    "aarch64" | "arm64" => { "linux/arm64" }
    "armv7l" | "armhf" => { "linux/arm/v7" }
    "armv6l" => { "linux/arm/v6" }
    _ => { $"linux/($arch)" }
  })
  $platform
}

# Detect build context (local, CI, release, dev, stage)
export def detect-build [] {
  let ref = (try {
    (try { $env.GITHUB_REF } catch { "" }) | default (git rev-parse --abbrev-ref HEAD | str trim)
  } catch {
    ""
  })
  let sha = (try {
    (try { $env.GITHUB_SHA } catch { "" }) | default (git rev-parse --short HEAD | str trim)
  } catch {
    ""
  })
  let msg = (try {
    git log -1 --pretty=%B | str trim
  } catch {
    ""
  })

  let in_ci = (((try { $env.GITHUB_ACTIONS } catch { "" }) | default "") | str length) > 0
  let has_git = (($ref | str length) > 0) or (($sha | str length) > 0)
  # is_local depends only on CI environment, not git presence
  # Having a git repo doesn't mean we're in CI - we can build locally in a git repo
  let is_local = not $in_ci

  if $is_local {
    let local_platform = (detect-local-platform)
    return {
      ref: "",
      sha: "",
      commit_message: "",
      is_release: false,
      build_type: "local",
      platforms: [$local_platform],
      base_tag: "local"
    }
  }

  let is_tag = ($ref | str starts-with "refs/tags/")
  let tag = (if $is_tag { $ref | str replace -a "refs/tags/" "" } else { "" })
  let is_release = $is_tag and ($tag | str starts-with "v")

  let has_dev = ($msg | str contains "(dev-build)") or ($msg | str contains "[dev-build]")
  let has_stage = ($msg | str contains "(stage-build)") or ($msg | str contains "[stage-build]")

  let branch = (if $is_tag { "" } else { $ref | str replace -a "refs/heads/" "" })

  let build_type = (if $is_release { "release" } else if $has_stage { "stage" } else if $has_dev { "dev" } else { "skip" })

  let platforms = (if $is_release { ["linux/amd64", "linux/arm64"] } else { ["linux/amd64"] })

  let base_tag = (if $is_release { $tag } else { if $has_stage { $"($branch)-($sha)-stage" } else if $has_dev { $"($branch)-($sha)-dev" } else { "" } })

  {
    ref: $ref,
    sha: $sha,
    commit_message: $msg,
    is_release: $is_release,
    build_type: $build_type,
    platforms: $platforms,
    base_tag: $base_tag
  }
}
