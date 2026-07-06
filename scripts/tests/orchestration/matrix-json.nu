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

# build --matrix-json orchestration tests

use ../lib.nu [run-test]
use ./fixtures.nu [
    ORCH_ALL_SVCS ORCH_MATRIX_SVC ORCH_PROD_SVCS ORCH_V_MASTER ORCH_V_TAG
    ISOLATION_LOCAL_ONLY ISOLATION_SVC ISOLATION_TRACKED_V1 ISOLATION_TRACKED_V2
    run-dockypody-in-repo seed-orchestration-all-services-fixture
    seed-orchestration-matrix-fixture seed-orchestration-production-fixture
    seed-tracked-plane-isolation-fixture with-temp-repo
]

export def test-matrix-json-multi-platform [entry: string, verbose: bool] {
    run-test "build --matrix-json: multi-platform service returns 4 matrix entries" {
        with-temp-repo {|repo|
            seed-orchestration-matrix-fixture $repo
            let out = (run-dockypody-in-repo $repo $entry [build --service $ORCH_MATRIX_SVC --matrix-json])
            if $out.exit_code != 0 {
                error make {msg: $"build --matrix-json exited ($out.exit_code): ($out.stderr)"}
            }
            let data = (try { $out.stdout | from json } catch {|e|
                error make {msg: $"Output is not valid JSON: ($e.msg). stdout=($out.stdout)"}
            })
            let entries = ($data.include? | default [])
            if ($entries | length) != 4 {
                error make {msg: $"Expected 4 matrix entries, got ($entries | length)"}
            }
            let pairs = ($entries | each {|e| $"($e.version)/($e.platform)"} | sort)
            let expected = ([
                $"($ORCH_V_MASTER)/development"
                $"($ORCH_V_MASTER)/production"
                $"($ORCH_V_TAG)/development"
                $"($ORCH_V_TAG)/production"
            ] | sort)
            if $pairs != $expected {
                error make {msg: $"Expected pairs ($expected | str join ', '), got ($pairs | str join ', ')"}
            }
            if $verbose { print $"    Pairs: ($pairs | str join ', ')" }
            true
        }
    } $verbose
}

export def test-all-services-matrix-json [entry: string, verbose: bool] {
    run-test "build --all-services --matrix-json: includes seeded services" {
        with-temp-repo {|repo|
            seed-orchestration-all-services-fixture $repo
            let out = (run-dockypody-in-repo $repo $entry [build --all-services --matrix-json])
            if $out.exit_code != 0 {
                error make {msg: $"build --all-services --matrix-json exited ($out.exit_code): ($out.stderr)"}
            }
            let data = (try { $out.stdout | from json } catch {|e|
                error make {msg: $"Output is not valid JSON: ($e.msg)"}
            })
            let entries = ($data.include? | default [])
            if ($entries | is-empty) {
                error make {msg: "Expected non-empty include array"}
            }
            let services = ($entries | each {|e| $e.service?} | compact | uniq)
            for svc in $ORCH_ALL_SVCS {
                if not ($svc in $services) {
                    error make {msg: $"Expected service '($svc)' in all-services matrix output"}
                }
            }
            if $verbose { print $"    Services: ($services | sort | str join ', ')" }
            true
        }
    } $verbose
}

export def test-platform-production-matrix-json [entry: string, verbose: bool] {
    run-test "build --platform production: all-services matrix contains only production entries" {
        with-temp-repo {|repo|
            seed-orchestration-production-fixture $repo
            let out = (run-dockypody-in-repo $repo $entry [build --all-services --matrix-json --platform production])
            if $out.exit_code != 0 {
                error make {msg: $"build --platform production exited ($out.exit_code): ($out.stderr)"}
            }
            let data = (try { $out.stdout | from json } catch {|e|
                error make {msg: $"Output is not valid JSON: ($e.msg)"}
            })
            let entries = ($data.include? | default [])
            if ($entries | is-empty) {
                error make {msg: "Expected non-empty include array for production platform"}
            }
            let non_prod = ($entries | where {|e| ($e.platform? | default "") != "production"})
            if not ($non_prod | is-empty) {
                error make {msg: $"Found ($non_prod | length) non-production entries in production-only matrix"}
            }
            let svcs = ($entries | each {|e| $e.service?} | compact)
            for svc in $ORCH_PROD_SVCS {
                if not ($svc in $svcs) {
                    error make {msg: $"Expected ($svc) in production matrix"}
                }
            }
            if $verbose {
                print $"    Production services: ($svcs | uniq | sort | str join ', ')"
            }
            true
        }
    } $verbose
}

export def test-all-services-version-matrix-json [entry: string, verbose: bool] {
    run-test "build --all-services --version: fails with --version incompatibility error" {
        with-temp-repo {|repo|
            seed-orchestration-all-services-fixture $repo
            let out = (run-dockypody-in-repo $repo $entry [build --all-services --version v1.0.0 --matrix-json])
            if $out.exit_code == 0 {
                error make {msg: "Expected non-zero exit for --version with --all-services"}
            }
            if not ($out.stderr | str contains "Cannot use --version with --all-services") {
                error make {msg: $"Expected '--version' error in stderr, got: ($out.stderr)"}
            }
            if $verbose { print $"    Error: ($out.stderr | str trim)" }
            true
        }
    } $verbose
}

export def test-matrix-json-tracked-only-isolation [entry: string, verbose: bool] {
    run-test "build --matrix-json: ignores local fragment versions (tracked-only isolation)" {
        with-temp-repo {|repo|
            seed-tracked-plane-isolation-fixture $repo
            let out = (run-dockypody-in-repo $repo $entry [build --service $ISOLATION_SVC --matrix-json])
            if $out.exit_code != 0 {
                error make {msg: $"build --matrix-json exited ($out.exit_code): ($out.stderr)"}
            }
            let data = (try { $out.stdout | from json } catch {|e|
                error make {msg: $"Output is not valid JSON: ($e.msg). stdout=($out.stdout)"}
            })
            let version_names = ($data.include? | default [] | each {|e| $e.version?} | compact | uniq | sort)
            if $ISOLATION_LOCAL_ONLY in $version_names {
                error make {msg: $"Local-only version leaked into matrix JSON: ($version_names | str join ', ')"}
            }
            if not ($ISOLATION_TRACKED_V1 in $version_names) {
                error make {msg: $"Tracked version ($ISOLATION_TRACKED_V1) missing from matrix JSON"}
            }
            if not ($ISOLATION_TRACKED_V2 in $version_names) {
                error make {msg: $"Tracked version ($ISOLATION_TRACKED_V2) missing from matrix JSON"}
            }
            if ($version_names | length) != 2 {
                error make {msg: $"Expected exactly 2 tracked versions, got ($version_names | str join ', ')"}
            }
            true
        }
    } $verbose
}
