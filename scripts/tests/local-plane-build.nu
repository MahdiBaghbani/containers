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

# Local-plane build suppression integration tests (stubbed docker, no daemon)

use ../lib/build/version.nu [build-single-version]
use ../lib/build/meta.nu [detect-build]
use ../lib/build/tags.nu [generate-tags]
use ../lib/inspect/effective-config.nu [inspect-effective-config]
use ../lib/manifest/core.nu [
  apply-version-defaults get-default-version get-version-spec load-versions-manifest
]
use ../lib/registries/info.nu [get-registry-info]
use ../lib/plane/guard.nu [guard-local-plane-presence]
use ../lib/plane/presence.nu [local-root-path]
use ./lib.nu [run-test print-test-summary]
use ./mocks.nu

def make-temp-repo [] {
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

def rm-temp-repo [dir: string] {
    try { rm -rf $dir } catch { }
}

def seed-build-service [
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

def make-docker-stub [log_file: string] {
    let stub_dir = (^mktemp -d | str trim)
    let script = "#!/bin/sh\nprintf '%s\\n' \"$*\" >> '" + $log_file + "'\nexit 0\n"
    $script | save -f ($stub_dir | path join "docker")
    ^chmod +x ($stub_dir | path join "docker")
    $stub_dir
}

def extract-buildx-build-lines [log_text: string] {
    $log_text
        | lines
        | where {|line|
            ($line | str contains "buildx build")
        }
}

def extract-tag-args [line: string] {
    ($line
        | split row " "
        | where {|token| $token | str starts-with "--tag="}
        | each {|token| $token | str substring 6..})
}

def assert-local-plane-build-line [line: string, expected_service: string, expected_version: string] {
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

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    let test_local_plane_build_suppression = (run-test "local plane build suppresses publish and dependency fan-out" {
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
                    build-single-version "parent-svc" $version_spec true true "publish" false "plain" $info $meta {} "" "" null "" false "off" true true {} "" $plane_ctx
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

        if $verbose_flag {
            print $"    docker build invocations: ($build_lines | length)"
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_local_plane_build_suppression)

    let test_local_plane_ci_like_inspect_build_tag = (run-test "local plane inspect primary tag matches build in CI-like mode" {
        let repo = (make-temp-repo)
        seed-build-service $repo "ci-svc"
        mkdir (local-root-path $repo)
        ^git -C $repo remote add origin https://github.com/ocm/containers.git

        let plane_ctx = (guard-local-plane-presence $repo)

        let alignment = (with-env {
            GITHUB_ACTIONS: "true"
            GITHUB_REPOSITORY: "ocm/containers"
        } {
            do -i {||
                cd $repo
                let manifest = (load-versions-manifest "ci-svc")
                let version_name = (get-default-version $manifest)
                let version_spec = (apply-version-defaults $manifest (get-version-spec $manifest $version_name))
                let meta = (detect-build)
                if $meta.is_local {
                    error make {msg: "Expected CI-like detect-build is_local false"}
                }
                let info = (get-registry-info)
                let build_tags = (generate-tags "ci-svc" $version_spec $meta.is_local $info "" "" true)
                let cfg = (inspect-effective-config "ci-svc" $plane_ctx "" "")
                {
                    build_primary: ($build_tags | first)
                    inspect_primary: ($cfg.single_primary_tag_state | get -o primary_tag | default "")
                }
            }
        })

        rm-temp-repo $repo

        if ($alignment.inspect_primary | str length) == 0 {
            error make {msg: "Expected inspect single_primary_tag_state.primary_tag in CI-like local plane"}
        }
        if $alignment.inspect_primary != $alignment.build_primary {
            error make {msg: $"Inspect/build primary tag mismatch. build=($alignment.build_primary), inspect=($alignment.inspect_primary)"}
        }
        if not ($alignment.build_primary | str starts-with "ghcr.io/ocm/containers/ci-svc:") {
            error make {msg: $"Expected GHCR-qualified primary tag, got: ($alignment.build_primary)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_local_plane_ci_like_inspect_build_tag)

    print-test-summary $results

    if ($results | any {|r| not $r}) {
        exit 1
    }
}
