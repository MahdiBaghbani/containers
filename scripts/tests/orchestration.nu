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
use ../lib/plane/presence.nu [local-root-path local-services-path]
use ../lib/plane/audit.nu [LOCAL_MIRROR_FILE]
use ../lib/manifest/core.nu [get-default-version get-version-or-null load-versions-manifest]
use ../lib/platforms/core.nu [get-default-platform load-platforms-manifest]
use ../lib/build/config.nu [load-service-config]
use ../lib/build/dependencies.nu [resolve-dep-node]
use ./lib.nu [run-test print-test-summary]

const TRACKED_SMOKE_SVC = "kasm-base"

const ISOLATION_SVC = "test-svc"
const ISOLATION_TRACKED_V1 = "v1"
const ISOLATION_TRACKED_V2 = "v2"
const ISOLATION_LOCAL_ONLY = "dev-local-only"

const ORCH_MATRIX_SVC = "orch-matrix-svc"
const ORCH_BASE_DEP = "orch-base-dep"
const ORCH_V_MASTER = "master"
const ORCH_V_TAG = "v2.0.0"
const ORCH_ALL_SVCS = ["orch-svc-a" "orch-svc-b" "orch-svc-c" "orch-svc-d"]
const ORCH_PROD_SVCS = ["orch-prod-a" "orch-prod-b"]

def make-temp-repo [] {
    let tmp = (^mktemp -d | str trim)
    mkdir $tmp
    mkdir ($tmp | path join "services")
    ^git -C $tmp init -q
    $tmp
}

def rm-temp-repo [dir: string] {
    try { rm -rf $dir } catch { }
}

def with-temp-repo [block: closure] {
    let repo = (make-temp-repo)
    let result = (try {
        do $block $repo
    } catch {|err|
        rm-temp-repo $repo
        error make {msg: $err.msg}
    })
    rm-temp-repo $repo
    $result
}

def seed-tracked-versions [repo: string, versions_manifest: record, name: string] {
    { name: $name } | save -f ($repo | path join $"services/($name).nuon")
    mkdir ($repo | path join $"services/($name)")
    $versions_manifest | save -f ($repo | path join $"services/($name)/versions.nuon")
}

def save-local-fragment [repo: string, name: string, fragment: record] {
    let mirror = (local-services-path $repo | path join $name)
    mkdir $mirror
    $fragment | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
}

def seed-minimal-service-base [repo: string, name: string] {
    {
        name: $name
        context: $"services/($name)"
        dockerfile: $"services/($name)/Dockerfile"
        sources: {
            app: { url: "https://example.com/app.git", ref: "main" }
        }
        external_images: {
            build: { name: "golang", tag: "1.25-trixie", build_arg: "BASE_BUILD_IMAGE" }
        }
    } | save -f ($repo | path join $"services/($name).nuon")
    mkdir ($repo | path join $"services/($name)")
}

def seed-prod-dev-platforms [repo: string, name: string] {
    {
        default: "production"
        platforms: [
            {
                name: "production"
                dockerfile: $"services/($name)/Dockerfile.production"
                external_images: {
                    build: { name: "golang", build_arg: "BASE_BUILD_IMAGE" }
                }
            }
            {
                name: "development"
                dockerfile: $"services/($name)/Dockerfile.development"
                external_images: {
                    build: { name: "golang", build_arg: "BASE_BUILD_IMAGE" }
                }
            }
        ]
    } | save -f ($repo | path join $"services/($name)/platforms.nuon")
}

def seed-debian-platforms [repo: string, name: string] {
    {
        default: "debian"
        platforms: [
            {
                name: "debian"
                dockerfile: $"services/($name)/Dockerfile.debian"
                external_images: {
                    build: { name: "golang", build_arg: "BASE_BUILD_IMAGE" }
                }
            }
            {
                name: "alpine"
                dockerfile: $"services/($name)/Dockerfile.alpine"
                external_images: {
                    build: { name: "golang", build_arg: "BASE_BUILD_IMAGE" }
                }
            }
        ]
    } | save -f ($repo | path join $"services/($name)/platforms.nuon")
}

def seed-orchestration-matrix-fixture [repo: string] {
    seed-minimal-service-base $repo $ORCH_MATRIX_SVC
    seed-prod-dev-platforms $repo $ORCH_MATRIX_SVC
    {
        default: $ORCH_V_TAG
        defaults: {
            dependencies: {
                ($ORCH_BASE_DEP): { version: "v1.0.0-debian" }
            }
        }
        versions: [
            { name: $ORCH_V_MASTER, overrides: {} }
            { name: $ORCH_V_TAG, overrides: {} }
        ]
    } | save -f ($repo | path join $"services/($ORCH_MATRIX_SVC)/versions.nuon")

    seed-minimal-service-base $repo $ORCH_BASE_DEP
    seed-debian-platforms $repo $ORCH_BASE_DEP
    {
        default: "v1.0.0"
        versions: [{ name: "v1.0.0", overrides: {} }]
    } | save -f ($repo | path join $"services/($ORCH_BASE_DEP)/versions.nuon")
}

def seed-orchestration-all-services-fixture [repo: string] {
    for name in $ORCH_ALL_SVCS {
        seed-minimal-service-base $repo $name
        {
            default: "v1.0.0"
            versions: [{ name: "v1.0.0", overrides: {} }]
        } | save -f ($repo | path join $"services/($name)/versions.nuon")
    }
}

def seed-orchestration-production-fixture [repo: string] {
    for name in $ORCH_PROD_SVCS {
        seed-minimal-service-base $repo $name
        seed-prod-dev-platforms $repo $name
        {
            default: "v1.0.0"
            versions: [{ name: "v1.0.0", overrides: {} }]
        } | save -f ($repo | path join $"services/($name)/versions.nuon")
    }
}

def seed-tracked-plane-isolation-fixture [repo: string] {
    seed-tracked-versions $repo {
        default: $ISOLATION_TRACKED_V1
        versions: [
            { name: $ISOLATION_TRACKED_V1, overrides: {} }
            { name: $ISOLATION_TRACKED_V2, overrides: {} }
        ]
    } $ISOLATION_SVC
    mkdir (local-root-path $repo)
    save-local-fragment $repo $ISOLATION_SVC {
        versions: [
            {
                name: $ISOLATION_LOCAL_ONLY
                overrides: {}
            }
            {
                name: $ISOLATION_TRACKED_V2
                overrides: {
                    sources: {
                        my_src: { path: "../local-src" }
                    }
                }
            }
        ]
    }
}

def run-dockypody-in-repo [repo: string, entry: string, args: list<string>] {
    do -i { cd $repo; ^nu $entry ...$args } | complete
}

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    let root = (get-repo-root)
    let entry = ($root | path join "scripts" "dockypody.nu")

    # ------------------------------------------------------------------
    # build --service <synthetic> --matrix-json
    # Expected: 4 entries (master/production, master/development,
    # v2.0.0/production, v2.0.0/development)
    # ------------------------------------------------------------------

    let t1 = (run-test "build --matrix-json: multi-platform service returns 4 matrix entries" {
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
            if $verbose_flag { print $"    Pairs: ($pairs | str join ', ')" }
            true
        }
    } $verbose_flag)
    $results = ($results | append $t1)

    # ------------------------------------------------------------------
    # build --all-services --matrix-json
    # Expected: includes every seeded synthetic service
    # ------------------------------------------------------------------

    let t2 = (run-test "build --all-services --matrix-json: includes seeded services" {
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
            if $verbose_flag { print $"    Services: ($services | sort | str join ', ')" }
            true
        }
    } $verbose_flag)
    $results = ($results | append $t2)

    # ------------------------------------------------------------------
    # build --service <synthetic> --show-build-order
    # Expected: numbered list showing base dep first, then parent service
    # ------------------------------------------------------------------

    let t3 = (run-test "build --show-build-order: synthetic default version and dependency order" {
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
            if $verbose_flag { print ($stdout | str trim) }
            true
        }
    } $verbose_flag)
    $results = ($results | append $t3)

    # ------------------------------------------------------------------
    # build --service <synthetic> --all-versions --show-build-order
    # Expected: 4 version sections (master production/development,
    # v2.0.0 production/development), each with numbered build list
    # ------------------------------------------------------------------

    let t4 = (run-test "build --all-versions --show-build-order: all 4 sections with numbered build order" {
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
            if $verbose_flag { print ($stdout | str trim) }
            true
        }
    } $verbose_flag)
    $results = ($results | append $t4)

    # ------------------------------------------------------------------
    # build --all-services --matrix-json --platform production
    # Expected: only entries with platform == "production"; seeded
    # multi-platform services must be present
    # ------------------------------------------------------------------

    let t5 = (run-test "build --platform production: all-services matrix contains only production entries" {
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
            if $verbose_flag {
                print $"    Production services: ($svcs | uniq | sort | str join ', ')"
            }
            true
        }
    } $verbose_flag)
    $results = ($results | append $t5)

    # ------------------------------------------------------------------
    # build --all-services --version v1.0.0 --matrix-json
    # Expected: non-zero exit with error mentioning --version incompatibility
    # ------------------------------------------------------------------

    let t6 = (run-test "build --all-services --version: fails with --version incompatibility error" {
        with-temp-repo {|repo|
            seed-orchestration-all-services-fixture $repo
            let out = (run-dockypody-in-repo $repo $entry [build --all-services --version v1.0.0 --matrix-json])
            if $out.exit_code == 0 {
                error make {msg: "Expected non-zero exit for --version with --all-services"}
            }
            if not ($out.stderr | str contains "Cannot use --version with --all-services") {
                error make {msg: $"Expected '--version' error in stderr, got: ($out.stderr)"}
            }
            if $verbose_flag { print $"    Error: ($out.stderr | str trim)" }
            true
        }
    } $verbose_flag)
    $results = ($results | append $t6)

    let t7 = (run-test "build --matrix-json --plane local: rejected as tracked-only surface" {
        with-temp-repo {|repo|
            seed-orchestration-matrix-fixture $repo
            let out = (run-dockypody-in-repo $repo $entry [
                build --service $ORCH_MATRIX_SVC --matrix-json --plane local
            ])
            if $out.exit_code == 0 {
                error make {msg: "Expected non-zero exit for --matrix-json with --plane local"}
            }
            if not ($out.stderr | str contains "--plane local is not supported") {
                error make {msg: $"Expected tracked-only rejection in stderr, got: ($out.stderr)"}
            }
            true
        }
    } $verbose_flag)
    $results = ($results | append $t7)

    let t8 = (run-test "build --matrix-json: ignores local fragment versions (tracked-only isolation)" {
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
    } $verbose_flag)
    $results = ($results | append $t8)

    let t9 = (run-test "build --matrix-json --plane local: rejected when local fragment is present" {
        with-temp-repo {|repo|
            seed-tracked-plane-isolation-fixture $repo
            let out = (run-dockypody-in-repo $repo $entry [
                build --service $ISOLATION_SVC --matrix-json --plane local
            ])
            if $out.exit_code == 0 {
                error make {msg: "Expected non-zero exit for --matrix-json with --plane local"}
            }
            if not ($out.stderr | str contains "--plane local is not supported") {
                error make {msg: $"Expected tracked-only rejection in stderr, got: ($out.stderr)"}
            }
            true
        }
    } $verbose_flag)
    $results = ($results | append $t9)

    # ------------------------------------------------------------------
    # build --service kasm-base --show-build-order (tracked manifest smoke)
    # Uses live default version/platform; dependency node key from resolver.
    # ------------------------------------------------------------------

    let t10 = (run-test "build --show-build-order: tracked kasm-base default version and dependency order" {
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
        if $verbose_flag { print ($stdout | str trim) }
        true
    } $verbose_flag)
    $results = ($results | append $t10)

    print-test-summary $results

    if ($results | any {|r| not $r}) {
        exit 1
    }
}
