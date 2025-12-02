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

# Detect build environment and provenance
# Returns metadata for local vs CI detection, commit info, and default platforms
# See docs/concepts/build-system.md for details
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
  # is_local depends only on CI environment, not git presence
  # Having a git repo doesn't mean we're in CI - we can build locally in a git repo
  let is_local = not $in_ci

  if $is_local {
    let local_platform = (detect-local-platform)
    return {
      ref: "",
      sha: "",
      commit_message: "",
      is_local: true,
      platforms: [$local_platform]
    }
  }

  # CI mode - use default single platform
  {
    ref: $ref,
    sha: $sha,
    commit_message: $msg,
    is_local: false,
    platforms: ["linux/amd64"]
  }
}
