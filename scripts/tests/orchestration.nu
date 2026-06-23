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

# Orchestration tests: non-Docker metadata-only build command paths
#
# Exercises operator-facing dispatch through scripts/dockypody.nu for
# --matrix-json and --show-build-order paths.
# Non-Docker and CI-safe: no docker build/pull/push, no image inspection,
# no registry-dependent checks.

use ../lib/core/repo.nu [get-repo-root]
use ./lib.nu [run-test print-test-summary]

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    let root = (get-repo-root)
    let entry = ($root | path join "scripts" "dockypody.nu")

    # ------------------------------------------------------------------
    # build --service revad-base --matrix-json
    # Expected: 4 entries (master/production, master/development,
    # v3.3.3/production, v3.3.3/development)
    # ------------------------------------------------------------------

    let t1 = (run-test "build --matrix-json: revad-base returns 4 matrix entries" {
        let out = (^nu $entry build --service revad-base --matrix-json | complete)
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
        let expected = (["master/development" "master/production" "v3.3.3/development" "v3.3.3/production"] | sort)
        if $pairs != $expected {
            error make {msg: $"Expected pairs ($expected | str join ', '), got ($pairs | str join ', ')"}
        }
        if $verbose_flag { print $"    Pairs: ($pairs | str join ', ')" }
        true
    } $verbose_flag)
    $results = ($results | append $t1)

    # ------------------------------------------------------------------
    # build --all-services --matrix-json
    # Expected: includes known services (cernbox-revad, common-tools,
    # cypress, revad-base)
    # ------------------------------------------------------------------

    let t2 = (run-test "build --all-services --matrix-json: includes known services" {
        let out = (^nu $entry build --all-services --matrix-json | complete)
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
        for svc in ["cernbox-revad" "common-tools" "cypress" "revad-base"] {
            if not ($svc in $services) {
                error make {msg: $"Expected service '($svc)' in all-services matrix output"}
            }
        }
        if $verbose_flag { print $"    Services: ($services | sort | str join ', ')" }
        true
    } $verbose_flag)
    $results = ($results | append $t2)

    # ------------------------------------------------------------------
    # build --service revad-base --show-build-order
    # Expected: numbered list showing common-tools first, then revad-base
    # ------------------------------------------------------------------

    let t3 = (run-test "build --show-build-order: revad-base default version" {
        let out = (^nu $entry build --service revad-base --show-build-order | complete)
        if $out.exit_code != 0 {
            error make {msg: $"build --show-build-order exited ($out.exit_code): ($out.stderr)"}
        }
        let stdout = $out.stdout
        if not ($stdout | str contains "1. common-tools:v1.0.0:debian") {
            error make {msg: $"Expected '1. common-tools:v1.0.0:debian' in output: ($stdout)"}
        }
        if not ($stdout | str contains "2. revad-base:v3.3.3:production") {
            error make {msg: $"Expected '2. revad-base:v3.3.3:production' in output: ($stdout)"}
        }
        if $verbose_flag { print ($stdout | str trim) }
        true
    } $verbose_flag)
    $results = ($results | append $t3)

    # ------------------------------------------------------------------
    # build --service revad-base --all-versions --show-build-order
    # Expected: 4 version sections (master production/development,
    # v3.3.3 production/development), each with numbered build list
    # ------------------------------------------------------------------

    let t4 = (run-test "build --all-versions --show-build-order: shows all 4 version sections" {
        let out = (^nu $entry build --service revad-base --all-versions --show-build-order | complete)
        if $out.exit_code != 0 {
            error make {msg: $"build --all-versions --show-build-order exited ($out.exit_code): ($out.stderr)"}
        }
        let stdout = $out.stdout
        for section in [
            "Version: master production"
            "Version: master development"
            "Version: v3.3.3 production"
            "Version: v3.3.3 development"
        ] {
            if not ($stdout | str contains $section) {
                error make {msg: $"Expected section '($section)' in output"}
            }
        }
        if $verbose_flag { print ($stdout | str trim) }
        true
    } $verbose_flag)
    $results = ($results | append $t4)

    # ------------------------------------------------------------------
    # build --all-services --matrix-json --platform production
    # Expected: only entries with platform == "production"; revad-base
    # and cernbox-revad must be present
    # ------------------------------------------------------------------

    let t5 = (run-test "build --platform production: all-services matrix contains only production entries" {
        let out = (^nu $entry build --all-services --matrix-json --platform production | complete)
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
        if not ("revad-base" in $svcs) {
            error make {msg: "Expected revad-base in production matrix"}
        }
        if not ("cernbox-revad" in $svcs) {
            error make {msg: "Expected cernbox-revad in production matrix"}
        }
        if $verbose_flag {
            print $"    Production services: ($svcs | uniq | sort | str join ', ')"
        }
        true
    } $verbose_flag)
    $results = ($results | append $t5)

    # ------------------------------------------------------------------
    # build --all-services --version v1.0.0 --matrix-json
    # Expected: non-zero exit with error mentioning --version incompatibility
    # ------------------------------------------------------------------

    let t6 = (run-test "build --all-services --version: fails with --version incompatibility error" {
        let out = (^nu $entry build --all-services --version v1.0.0 --matrix-json | complete)
        if $out.exit_code == 0 {
            error make {msg: "Expected non-zero exit for --version with --all-services"}
        }
        if not ($out.stderr | str contains "Cannot use --version with --all-services") {
            error make {msg: $"Expected '--version' error in stderr, got: ($out.stderr)"}
        }
        if $verbose_flag { print $"    Error: ($out.stderr | str trim)" }
        true
    } $verbose_flag)
    $results = ($results | append $t6)

    let t7 = (run-test "build --matrix-json --plane local: rejected as tracked-only surface" {
        let out = (^nu $entry build --service revad-base --matrix-json --plane local | complete)
        if $out.exit_code == 0 {
            error make {msg: "Expected non-zero exit for --matrix-json with --plane local"}
        }
        if not ($out.stderr | str contains "--plane local is not supported") {
            error make {msg: $"Expected tracked-only rejection in stderr, got: ($out.stderr)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t7)

    print-test-summary $results

    if ($results | any {|r| not $r}) {
        exit 1
    }
}
