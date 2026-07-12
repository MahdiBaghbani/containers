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

# Local-plane build suppression tests.

use ../../lib/build/version.nu [build-single-version]
use ../../lib/manifest/core.nu [
  apply-version-defaults get-default-version get-version-spec load-versions-manifest
]
use ../../lib/plane/guard.nu [guard-local-plane-presence]
use ../../lib/plane/presence.nu [local-root-path]
use ../lib.nu [run-test]
use ../mocks.nu
use ./_fixtures.nu [
  extract-buildx-build-lines extract-tag-args make-docker-stub make-temp-repo rm-temp-repo
  seed-build-service
]

export def assert-local-plane-build-line [line: string, expected_service: string, expected_version: string] {
    if ($line | str contains "--push") {
        error make {msg: $"Local plane build must not use --push: ($line)"}
    }
    if not ($line | str contains "--load") {
        error make {msg: $"Local plane build must use --load: ($line)"}
    }

    let tags = (extract-tag-args $line)
    let expected_tag = $"($expected_service):($expected_version)"
    if ($tags | length) != 1 {
        error make {msg: $"Expected exactly one --tag for ($expected_service), got: ($tags | to json)"}
    }
    if ($tags | first) != $expected_tag {
        error make {msg: $"Expected primary tag ($expected_tag), got: ($tags | to json)"}
    }

    for forbidden in ["latest", ":extra", "ghcr.io", "forgejo"] {
        if ($line | str contains $forbidden) {
            error make {msg: $"Publish/tag fan-out artifact '($forbidden)' must be suppressed: ($line)"}
        }
    }
    true
}

export def test-local-plane-build-suppression [verbose: bool] {
    run-test "local plane build suppresses publish and dependency fan-out" {
        let repo = (make-temp-repo)
        seed-build-service $repo "dep-svc"
        seed-build-service $repo "parent-svc" {
            dep-svc: { build_arg: "BASE_IMAGE" }
        } {
            dependencies: {
                dep-svc: { version: "v1" }
            }
        }
        mkdir (local-root-path $repo)

        let log_file = ($repo | path join "docker-invocations.log")
        let stub_dir = (make-docker-stub $log_file)
        let patched_path = ([$stub_dir] | append ($env.PATH | default []))

        let plane_ctx = (guard-local-plane-presence $repo)
        let meta = (mocks detect-build)
        let info = {
            ci_platform: "local"
            is_local: true
            github_registry: ""
            github_path: ""
            forgejo_registry: ""
            forgejo_path: ""
        }

        let build_error = (try {
            do -i {||
                cd $repo
                let manifest = (load-versions-manifest "parent-svc")
                let version_name = (get-default-version $manifest)
                let version_spec = (apply-version-defaults $manifest (get-version-spec $manifest $version_name))
                with-env {PATH: $patched_path} {
                    build-single-version "parent-svc" $version_spec true true "publish" false "plain" $info $meta {} "" "" null "" false "off" true true {} $plane_ctx
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
            error make {msg: $"Expected local-plane build-single-version success, got: ($build_error)"}
        }

        let build_lines = (extract-buildx-build-lines $log_text)
        if ($build_lines | length) != 2 {
            error make {msg: $"Expected dep + parent build invocations, got ($build_lines | length): ($build_lines | to json)"}
        }

        let dep_line = ($build_lines | where {|l| $l | str contains "dep-svc"} | first)
        let parent_line = ($build_lines | where {|l| $l | str contains "parent-svc"} | first)
        if $dep_line == null or $parent_line == null {
            error make {msg: $"Missing dep or parent build line in log: ($build_lines | to json)"}
        }

        assert-local-plane-build-line $dep_line "dep-svc" "v1"
        assert-local-plane-build-line $parent_line "parent-svc" "v1"

        if $verbose {
            print $"    docker build invocations: ($build_lines | length)"
        }
        true
    } $verbose
}
