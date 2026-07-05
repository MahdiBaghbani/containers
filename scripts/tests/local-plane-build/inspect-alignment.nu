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

# Local-plane inspect/build primary tag alignment in CI-like mode.

use ../../lib/build/meta.nu [detect-build]
use ../../lib/build/tags.nu [generate-tags]
use ../../lib/inspect/effective-config.nu [inspect-effective-config]
use ../../lib/manifest/core.nu [
  apply-version-defaults get-default-version get-version-spec load-versions-manifest
]
use ../../lib/registries/info.nu [get-registry-info]
use ../../lib/plane/guard.nu [guard-local-plane-presence]
use ../../lib/plane/presence.nu [local-root-path]
use ../lib.nu [run-test]
use ./_fixtures.nu [make-temp-repo rm-temp-repo seed-build-service]

export def test-local-plane-inspect-alignment [verbose: bool] {
    run-test "local plane inspect primary tag matches build in CI-like mode" {
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
    } $verbose
}
