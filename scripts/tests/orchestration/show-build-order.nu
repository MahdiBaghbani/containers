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

# build --show-build-order orchestration tests

use ../../lib/manifest/core.nu [get-default-version get-version-or-null load-versions-manifest]
use ../../lib/platforms/core.nu [get-default-platform load-platforms-manifest]
use ../../lib/build/config.nu [load-service-config]
use ../../lib/build/dependencies.nu [resolve-dep-node]
use ../lib.nu [run-test]
use ./fixtures.nu [
    ORCH_BASE_DEP ORCH_MATRIX_SVC ORCH_V_MASTER ORCH_V_TAG TRACKED_SMOKE_SVC
    run-dockypody-in-repo seed-orchestration-matrix-fixture with-temp-repo
]

export def test-show-build-order-synthetic [entry: string, verbose: bool] {
    run-test "build --show-build-order: synthetic default version and dependency order" {
        with-temp-repo {|repo|
            seed-orchestration-matrix-fixture $repo
            let out = (run-dockypody-in-repo $repo $entry [build --service $ORCH_MATRIX_SVC --show-build-order])
            if $out.exit_code != 0 {
                error make {msg: $"build --show-build-order exited ($out.exit_code): ($out.stderr)"}
            }
            let stdout = $out.stdout
            let dep_line = $"1. ($ORCH_BASE_DEP):v1.0.0:debian"
            let parent_line = $"2. ($ORCH_MATRIX_SVC):($ORCH_V_TAG):production"
            if not ($stdout | str contains $dep_line) {
                error make {msg: $"Expected '($dep_line)' in output: ($stdout)"}
            }
            if not ($stdout | str contains $parent_line) {
                error make {msg: $"Expected '($parent_line)' in output: ($stdout)"}
            }
            if $verbose { print ($stdout | str trim) }
            true
        }
    } $verbose
}

export def test-all-versions-show-build-order [entry: string, verbose: bool] {
    run-test "build --all-versions --show-build-order: all 4 sections with numbered build order" {
        with-temp-repo {|repo|
            seed-orchestration-matrix-fixture $repo
            let out = (run-dockypody-in-repo $repo $entry [
                build --service $ORCH_MATRIX_SVC --all-versions --show-build-order
            ])
            if $out.exit_code != 0 {
                error make {msg: $"build --all-versions --show-build-order exited ($out.exit_code): ($out.stderr)"}
            }
            let stdout = $out.stdout
            let dep_line = $"1. ($ORCH_BASE_DEP):v1.0.0:debian"
            for section in [
                {
                    header: $"Version: ($ORCH_V_MASTER) production"
                    parent: $"2. ($ORCH_MATRIX_SVC):($ORCH_V_MASTER):production"
                }
                {
                    header: $"Version: ($ORCH_V_MASTER) development"
                    parent: $"2. ($ORCH_MATRIX_SVC):($ORCH_V_MASTER):development"
                }
                {
                    header: $"Version: ($ORCH_V_TAG) production"
                    parent: $"2. ($ORCH_MATRIX_SVC):($ORCH_V_TAG):production"
                }
                {
                    header: $"Version: ($ORCH_V_TAG) development"
                    parent: $"2. ($ORCH_MATRIX_SVC):($ORCH_V_TAG):development"
                }
            ] {
                if not ($stdout | str contains $section.header) {
                    error make {msg: $"Expected section '($section.header)' in output"}
                }
                if not ($stdout | str contains $dep_line) {
                    error make {msg: $"Expected numbered dep line '($dep_line)' in output"}
                }
                if not ($stdout | str contains $section.parent) {
                    error make {msg: $"Expected numbered parent line '($section.parent)' for section '($section.header)'"}
                }
            }
            let section_blocks = ($stdout | split row "Version:" | skip 1)
            if ($section_blocks | length) < 4 {
                error make {msg: $"Expected 4 version sections, found ($section_blocks | length)"}
            }
            for block in $section_blocks {
                let has_numbered = ($block | lines | any {|line|
                    ($line | str trim) =~ '^\d+\.'
                })
                if not $has_numbered {
                    let preview = (try { $block | str trim | str substring 0..80 } catch { $block })
                    error make {msg: $"Expected at least one numbered build-order line in section block: ($preview)"}
                }
            }
            if $verbose { print ($stdout | str trim) }
            true
        }
    } $verbose
}

export def test-show-build-order-kasm-base [entry: string, verbose: bool] {
    run-test "build --show-build-order: tracked kasm-base default version and dependency order" {
        let vm = (load-versions-manifest $TRACKED_SMOKE_SVC)
        let pm = (load-platforms-manifest $TRACKED_SMOKE_SVC)
        let version = (get-default-version $vm)
        let platform = (get-default-platform $pm)
        let vspec = (get-version-or-null $vm $version)
        let cfg = (load-service-config $TRACKED_SMOKE_SVC $vspec $platform $pm)
        let dep_config = ($cfg.dependencies | get "common-tools")
        let dep_service = (try { $dep_config.service } catch { "common-tools" })
        let resolved = (resolve-dep-node $dep_config $dep_service $version $platform true)

        let out = (^nu $entry build --service $TRACKED_SMOKE_SVC --show-build-order | complete)
        if $out.exit_code != 0 {
            error make {msg: $"build --show-build-order exited ($out.exit_code): ($out.stderr)"}
        }
        let stdout = $out.stdout
        let dep_line = $"1. ($resolved.node_key)"
        let parent_line = $"2. ($TRACKED_SMOKE_SVC):($version):($platform)"
        if not ($stdout | str contains $dep_line) {
            error make {msg: $"Expected '($dep_line)' in output: ($stdout)"}
        }
        if not ($stdout | str contains $parent_line) {
            error make {msg: $"Expected '($parent_line)' in output: ($stdout)"}
        }
        if $verbose { print ($stdout | str trim) }
        true
    } $verbose
}
