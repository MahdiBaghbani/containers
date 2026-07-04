#!/usr/bin/env nu

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

# Suite-local temp repo and local fragment helpers.

use ../../lib/plane/audit.nu [LOCAL_MIRROR_FILE]
use ../../lib/plane/presence.nu [local-services-path]

export def make-temp-repo [] {
  let tmp = (^mktemp -d | str trim)
  mkdir $tmp
  mkdir ($tmp | path join "services")
  ^git -C $tmp init -q
  $tmp
}

export def rm-temp-repo [dir: string] {
  try { rm -rf $dir } catch { }
}

export def run-in-temp-repo [repo: string, block: closure] {
  do -i { cd $repo; do $block }
}

export def seed-tracked-versions [
  repo: string,
  versions_manifest: record,
  name: string = "test-svc",
] {
  { name: $name } | save -f ($repo | path join $"services/($name).nuon")
  mkdir ($repo | path join $"services/($name)")
  $versions_manifest | save -f ($repo | path join $"services/($name)/versions.nuon")
}

export def save-local-fragment [repo: string, name: string, fragment: record] {
  let mirror = (local-services-path $repo | path join $name)
  mkdir $mirror
  $fragment | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
}

export def expect-error [block: closure, needle: string] {
  let result = (try {
    do $block
    { ok: true }
  } catch {|err|
    { ok: false, msg: $err.msg }
  })
  if $result.ok {
    error make {msg: $"Expected error containing '($needle)'"}
  }
  if not ($result.msg | str contains $needle) {
    error make {msg: $"Expected error to mention '($needle)', got: ($result.msg)"}
  }
  true
}
