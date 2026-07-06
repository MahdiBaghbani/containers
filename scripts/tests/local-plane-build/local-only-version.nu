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

# Local-only version resolution via build-cli.

use ../../lib/build/cli.nu [build-cli]
use ../../lib/plane/audit.nu [LOCAL_MIRROR_FILE]
use ../../lib/plane/presence.nu [local-root-path]
use ../lib.nu [run-test]
use ./build-suppression.nu [assert-local-plane-build-line]
use ./_fixtures.nu [
  extract-buildx-build-lines make-docker-stub make-temp-repo rm-temp-repo seed-build-service
]

export def test-local-only-version-via-build-cli [verbose: bool] {
    run-test "local plane build-cli resolves local-only version name" {
        let repo = (make-temp-repo)
        seed-build-service $repo "local-svc"
        mkdir (local-root-path $repo)
        let mirror = (local-root-path $repo | path join "services" "local-svc")
        mkdir $mirror
        {
            default: "devlocal"
            versions: [{
                name: "devlocal"
                latest: true
            }]
        } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)

        let log_file = ($repo | path join "docker-invocations.log")
        let stub_dir = (make-docker-stub $log_file)
        let patched_path = ([$stub_dir] | append ($env.PATH | default []))

        let build_error = (try {
            with-env {PATH: $patched_path} {
                do -i {||
                    cd $repo
                    build-cli --service local-svc --version devlocal --plane local
                }
            }
            null
        } catch {|err|
            try { $err.msg } catch { "Unknown error" }
        })

        let log_text = (try { open --raw $log_file | decode utf-8 } catch { "" })
        rm-temp-repo $repo
        try { rm -rf $stub_dir } catch { }

        if $build_error != null {
            error make {msg: $"Expected build-cli local-only version success, got: ($build_error)"}
        }

        let build_lines = (extract-buildx-build-lines $log_text)
        if ($build_lines | length) != 1 {
            error make {msg: $"Expected one build invocation for local-only version, got ($build_lines | length): ($build_lines | to json)"}
        }

        assert-local-plane-build-line ($build_lines | first) "local-svc" "devlocal"
        true
    } $verbose
}
