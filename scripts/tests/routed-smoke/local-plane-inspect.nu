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

# Local-plane inspect, materialization, and fragment precedence cases.

use ../../lib/plane/presence.nu [local-root-path local-services-path]
use ../../lib/plane/audit.nu [LOCAL_MIRROR_FILE]
use ../lib.nu [run-test]
use ./_fixtures.nu [
    dockypody-entry make-temp-repo rm-temp-repo run-dockypody-in-repo
    seed-service-with-git-source seed-tracked-service
]
use ./assertions.nu [assert-inspect-semantic-baseline assert-routed-failure-names-contract]

export def test-smoke-local-baseline-inspect [verbose: bool] {
    run-test "smoke: routed inspect effective-config baseline local-plane semantics" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo "test-svc" true
        mkdir (local-root-path $repo)
        let out = (run-dockypody-in-repo $repo [inspect effective-config --service test-svc --plane local])
        if $out.exit_code != 0 {
            rm-temp-repo $repo
            error make {msg: $"Expected inspect success, exit ($out.exit_code): ($out.stderr)"}
        }
        let cfg = (try {
            $out.stdout | from json
        } catch {
            rm-temp-repo $repo
            error make {msg: $"Expected JSON stdout, got: ($out.stdout)"}
        })
        assert-inspect-semantic-baseline $cfg $repo "test-svc" "v1" false ""
        if $cfg.env_only {
            error make {msg: "Baseline local inspect must not be classified as env_only"}
        }
        if ($cfg.env_keys_used | length) != 0 {
            error make {msg: $"Expected empty env_keys_used for baseline local inspect, got: ($cfg.env_keys_used | to json)"}
        }
        if ($cfg.source_origin.my_src? | default "") != "tracked-git" {
            error make {msg: $"Expected source_origin.my_src 'tracked-git', got: ($cfg.source_origin | to json)"}
        }
        if $cfg.precedence_summary != "tracked manifest" {
            error make {msg: $"Expected precedence_summary 'tracked manifest', got: ($cfg.precedence_summary)"}
        }
        rm-temp-repo $repo
        true
    } $verbose
}

export def test-smoke-local-env-materialization [verbose: bool] {
    run-test "smoke: routed inspect effective-config env-only path materialization" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        mkdir (local-root-path $repo)
        mkdir ($repo | path join "local-src")
        let expected_path = ($repo | path join "local-src" | path expand)
        let entry = (dockypody-entry)
        let out = (do -i {||
            cd $repo
            $env.MY_SRC_PATH = ($env.PWD | path join "local-src")
            ^nu $entry inspect effective-config --service test-svc --plane local
        } | complete)
        if $out.exit_code != 0 {
            error make {msg: $"Expected inspect success, exit ($out.exit_code): ($out.stderr)"}
        }
        let cfg = (try {
            $out.stdout | from json
        } catch {
            error make {msg: $"Expected JSON stdout, got: ($out.stdout)"}
        })
        assert-inspect-semantic-baseline $cfg $repo "test-svc" "v1" false ""
        let materialized = (try { $cfg.sources.my_src.path | path expand } catch { "" })
        if $materialized != $expected_path {
            error make {msg: $"Expected env-only path ($expected_path), got: ($materialized)"}
        }
        if ("url" in ($cfg.sources.my_src | columns)) or ("ref" in ($cfg.sources.my_src | columns)) {
            error make {msg: "Env-only materialization must replace git fields with path only"}
        }
        if not $cfg.env_only {
            error make {msg: "Expected env_only true for env PATH materialization"}
        }
        if not ("MY_SRC_PATH" in $cfg.env_keys_used) {
            error make {msg: $"Expected MY_SRC_PATH in env_keys_used, got: ($cfg.env_keys_used | to json)"}
        }
        if ($cfg.source_origin.my_src? | default "") != "env-only" {
            error make {msg: $"Expected source_origin.my_src 'env-only', got: ($cfg.source_origin | to json)"}
        }
        if not ($cfg.precedence_summary | str contains "env PATH materialization") {
            error make {msg: $"Expected precedence_summary to mention env PATH, got: ($cfg.precedence_summary)"}
        }
        rm-temp-repo $repo
        true
    } $verbose
}

export def test-smoke-local-only-version-inspect [verbose: bool] {
    run-test "smoke: routed inspect effective-config local-only version from fragment versions array" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        mkdir (local-root-path $repo)
        let mirror = (local-services-path $repo | path join "test-svc")
        mkdir $mirror
        mkdir ($repo | path join "local-only-src")
        {
            versions: [
                {
                    name: "local-only-v"
                    overrides: {
                        sources: {
                            my_src: { path: "local-only-src" }
                        }
                    }
                }
            ]
        } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
        let out = (run-dockypody-in-repo $repo [
            inspect effective-config --service test-svc --plane local --version local-only-v
        ])
        if $out.exit_code != 0 {
            rm-temp-repo $repo
            error make {msg: $"Expected inspect success for local-only version, exit ($out.exit_code): ($out.stderr)"}
        }
        let cfg = (try {
            $out.stdout | from json
        } catch {
            rm-temp-repo $repo
            error make {msg: $"Expected JSON stdout, got: ($out.stdout)"}
        })
        assert-inspect-semantic-baseline $cfg $repo "test-svc" "local-only-v" true $mirror
        if not ($cfg.precedence_summary | str contains "local-only version") {
            error make {msg: $"Expected precedence_summary to mention local-only version, got: ($cfg.precedence_summary)"}
        }
        if ($cfg.sources.my_src.path? | default "") != "local-only-src" {
            error make {msg: $"Expected local-only source path, got: ($cfg.sources.my_src.path)"}
        }
        rm-temp-repo $repo
        true
    } $verbose
}

export def test-smoke-tracked-miss-local-only-inspect [verbose: bool] {
    run-test "smoke: routed inspect effective-config tracked plane miss for local-only version names guidance" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        mkdir (local-root-path $repo)
        let mirror = (local-services-path $repo | path join "test-svc")
        mkdir $mirror
        {
            versions: [{ name: "devlocal" }]
        } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
        let out = (run-dockypody-in-repo $repo [
            inspect effective-config --service test-svc --version devlocal
        ])
        rm-temp-repo $repo
        if $out.exit_code == 0 {
            error make {msg: "Expected tracked-plane inspect miss for local-only version"}
        }
        let combined = ($out.stdout + $out.stderr)
        if not ($combined | str contains "--plane local") {
            error make {msg: $"Expected --plane local guidance, got: ($combined)"}
        }
        if not ($combined | str contains "local fragment") {
            error make {msg: $"Expected local fragment mention, got: ($combined)"}
        }
        if not ($combined | str contains ".dockypody.local/services/test-svc/versions.nuon") {
            error make {msg: $"Expected local fragment path suffix in output, got: ($combined)"}
        }
        true
    } $verbose
}

export def test-smoke-local-version-replace-inspect [verbose: bool] {
    run-test "smoke: routed inspect effective-config local version replaces tracked same name" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        mkdir (local-root-path $repo)
        let mirror = (local-services-path $repo | path join "test-svc")
        mkdir $mirror
        mkdir ($repo | path join "replaced-src")
        {
            versions: [
                {
                    name: "v1"
                    overrides: {
                        sources: {
                            my_src: { path: "replaced-src" }
                        }
                    }
                }
            ]
        } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
        let out = (run-dockypody-in-repo $repo [
            inspect effective-config --service test-svc --plane local --version v1
        ])
        if $out.exit_code != 0 {
            rm-temp-repo $repo
            error make {msg: $"Expected inspect success for replaced version, exit ($out.exit_code): ($out.stderr)"}
        }
        let cfg = (try {
            $out.stdout | from json
        } catch {
            rm-temp-repo $repo
            error make {msg: $"Expected JSON stdout, got: ($out.stdout)"}
        })
        assert-inspect-semantic-baseline $cfg $repo "test-svc" "v1" true $mirror
        if not ($cfg.precedence_summary | str contains "local version (replace)") {
            error make {msg: $"Expected precedence_summary to mention local version replace, got: ($cfg.precedence_summary)"}
        }
        if ($cfg.sources.my_src.path? | default "") != "replaced-src" {
            error make {msg: $"Expected replaced local path 'replaced-src', got: ($cfg.sources.my_src.path)"}
        }
        if ("url" in ($cfg.sources.my_src | columns)) or ("ref" in ($cfg.sources.my_src | columns)) {
            error make {msg: "Replaced local version must materialize path-only source, not git fields"}
        }
        if ($cfg.source_origin.my_src? | default "") != "fragment-local" {
            error make {msg: $"Expected source_origin.my_src 'fragment-local', got: ($cfg.source_origin | to json)"}
        }
        rm-temp-repo $repo
        true
    } $verbose
}

export def test-smoke-local-version-scoped-fragment-precedence [verbose: bool] {
    run-test "smoke: routed inspect version-scoped fragment sources align precedence_summary with source_origin" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        mkdir (local-root-path $repo)
        let mirror = (local-services-path $repo | path join "test-svc")
        mkdir $mirror
        mkdir ($repo | path join "version-scoped-src")
        {
            versions: [
                {
                    name: "v1"
                    overrides: {
                        sources: {
                            my_src: { path: "version-scoped-src" }
                        }
                    }
                }
            ]
        } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
        let out = (run-dockypody-in-repo $repo [
            inspect effective-config --service test-svc --plane local --version v1
        ])
        if $out.exit_code != 0 {
            rm-temp-repo $repo
            error make {msg: $"Expected inspect success, exit ($out.exit_code): ($out.stderr)"}
        }
        let cfg = (try {
            $out.stdout | from json
        } catch {
            rm-temp-repo $repo
            error make {msg: $"Expected JSON stdout, got: ($out.stdout)"}
        })
        if ($cfg.source_origin.my_src? | default "") != "fragment-local" {
            rm-temp-repo $repo
            error make {msg: $"Expected source_origin.my_src 'fragment-local', got: ($cfg.source_origin | to json)"}
        }
        if $cfg.precedence_summary == "tracked manifest" {
            rm-temp-repo $repo
            error make {
                msg: $"precedence_summary must not be plain 'tracked manifest' when source_origin is fragment-local, got: ($cfg.precedence_summary)"
            }
        }
        if not ($cfg.precedence_summary | str contains "local fragment overrides") {
            rm-temp-repo $repo
            error make {
                msg: $"Expected precedence_summary to mention version-scoped fragment overrides, got: ($cfg.precedence_summary)"
            }
        }
        rm-temp-repo $repo
        true
    } $verbose
}

export def test-smoke-local-incomplete-mirror [verbose: bool] {
    run-test "smoke: routed inspect bad topology names incomplete mirror contract before materialization" {
        let repo = (make-temp-repo)
        seed-tracked-service $repo
        mkdir (local-root-path $repo)
        mkdir (local-services-path $repo | path join "test-svc")
        let result = (run-dockypody-in-repo $repo [inspect effective-config --service test-svc --plane local])
        rm-temp-repo $repo
        assert-routed-failure-names-contract $result "Incomplete local service mirror" [
            "Additive source id"
            "Partial git source is forbidden"
        ]
    } $verbose
}
