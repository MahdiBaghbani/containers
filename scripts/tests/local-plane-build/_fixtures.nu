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

# Local-plane-build suite fixtures (temp repos, docker stub, log parsing).

export def make-temp-repo [] {
    let tmp = (^mktemp -d | str trim)
    mkdir $tmp
    mkdir ($tmp | path join "services")
    mkdir ($tmp | path join "scripts" "lib" "ssh")
    "# test stub for prepare-ssh-context" | save -f ($tmp | path join "scripts" "lib" "ssh" "sshd.nu")
    ^git -C $tmp init -q
    ^git -C $tmp add -A
    ^git -C $tmp -c user.email="test@example.com" -c user.name="test" commit -q -m "init"
    $tmp
}

export def rm-temp-repo [dir: string] {
    try { rm -rf $dir } catch { }
}

export def seed-build-service [
    repo: string,
    name: string,
    dependencies: record = {},
    parent_defaults: record = {}
] {
    mkdir ($repo | path join "services" $name)
    "FROM scratch" | save -f ($repo | path join "services" $name "Dockerfile")

    mut manifest = {
        name: $name
        context: $"services/($name)"
        dockerfile: $"services/($name)/Dockerfile"
    }
    if not ($dependencies | is-empty) {
        $manifest = ($manifest | insert dependencies $dependencies)
    }
    $manifest | save -f ($repo | path join "services" $"($name).nuon")

    mut versions = {
        default: "v1"
        versions: [{
            name: "v1"
            latest: true
            tags: ["extra"]
        }]
    }
    if not ($parent_defaults | is-empty) {
        $versions = ($versions | insert defaults $parent_defaults)
    }
    $versions | save -f ($repo | path join "services" $name "versions.nuon")
}

export def make-docker-stub [log_file: string] {
    let stub_dir = (^mktemp -d | str trim)
    let script = "#!/bin/sh\nprintf '%s\\n' \"$*\" >> '" + $log_file + "'\nexit 0\n"
    $script | save -f ($stub_dir | path join "docker")
    ^chmod +x ($stub_dir | path join "docker")
    $stub_dir
}

export def extract-buildx-build-lines [log_text: string] {
    $log_text
        | lines
        | where {|line|
            ($line | str contains "buildx build")
        }
}

export def extract-tag-args [line: string] {
    ($line
        | split row " "
        | where {|token| $token | str starts-with "--tag="}
        | each {|token| $token | str substring 6..})
}
