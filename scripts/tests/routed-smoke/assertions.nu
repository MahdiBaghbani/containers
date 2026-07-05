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

# Routed-smoke shared assertion helpers.

use ../../lib/plane/presence.nu [local-root-path]

export def assert-routed-failure-names-contract [
    result: record,
    contract: string,
    forbidden: list<string> = []
] {
    if $result.exit_code == 0 {
        error make {msg: $"Expected routed command to fail for contract '($contract)'"}
    }
    let combined = ($result.stdout + $result.stderr)
    if not ($combined | str contains $contract) {
        error make {msg: $"Expected routed failure to name contract '($contract)', got: ($combined)"}
    }
    for needle in $forbidden {
        if ($combined | str contains $needle) {
            error make {msg: $"Contract '($contract)' failure must not mention '($needle)', got: ($combined)"}
        }
    }
    true
}

def inspect-suppressed-tag-fanout [] {
    [
        "manifest-latest"
        "cli-latest"
        "extra-tag"
        "publish"
        "dependency-tag-fanout"
        "dependency-push-fanout"
    ]
}

def assert-single-primary-tag-state [cfg: record, service: string, version: string] {
    let tag_state = $cfg.single_primary_tag_state
    if not $tag_state.active {
        error make {msg: "Expected single_primary_tag_state.active true on local plane"}
    }
    if $tag_state.policy != "single-primary-non-publish" {
        error make {msg: $"Expected single-primary policy, got: ($tag_state.policy)"}
    }
    let expected_primary = $"($service):($version)"
    if ($tag_state.primary_tag? | default "") != $expected_primary {
        error make {msg: $"Expected primary_tag ($expected_primary), got: ($tag_state.primary_tag)"}
    }
    let expected_suppressed = (inspect-suppressed-tag-fanout)
    for item in $expected_suppressed {
        if not ($item in $tag_state.suppressed) {
            error make {msg: $"Expected suppressed fan-out item '($item)' in single_primary_tag_state"}
        }
    }
    if ($tag_state.suppressed | length) != ($expected_suppressed | length) {
        error make {msg: $"Unexpected suppressed fan-out entries: ($tag_state.suppressed | to json)"}
    }
    true
}

export def assert-inspect-semantic-baseline [
    cfg: record,
    repo: string,
    service: string,
    version: string,
    fragment_present: bool,
    mirror_path: string = ""
] {
    for required_key in [
        plane service version tracked_service tracked_version local_root
        local_fragment_present local_mirror_path env_only env_keys_used
        source_origin precedence_summary single_primary_tag_state
    ] {
        if not ($required_key in ($cfg | columns)) {
            error make {msg: $"Missing required inspect semantic key: ($required_key)"}
        }
    }

    if $cfg.plane != "local" {
        error make {msg: $"Expected plane 'local', got: ($cfg.plane)"}
    }
    if $cfg.service != $service {
        error make {msg: $"Expected service '($service)', got: ($cfg.service)"}
    }
    if $cfg.version != $version {
        error make {msg: $"Expected version '($version)', got: ($cfg.version)"}
    }
    if $cfg.tracked_service != $service {
        error make {msg: $"Expected tracked_service '($service)', got: ($cfg.tracked_service)"}
    }
    if $cfg.tracked_version != $version {
        error make {msg: $"Expected tracked_version '($version)', got: ($cfg.tracked_version)"}
    }

    let expected_local_root = (local-root-path $repo | path expand)
    let actual_local_root = (try { $cfg.local_root | path expand } catch { "" })
    if $actual_local_root != $expected_local_root {
        error make {msg: $"Expected local_root ($expected_local_root), got: ($actual_local_root)"}
    }

    if $cfg.local_fragment_present != $fragment_present {
        error make {msg: $"Expected local_fragment_present ($fragment_present), got: ($cfg.local_fragment_present)"}
    }

    let expected_mirror = (if ($mirror_path | str length) > 0 {
        $mirror_path | path expand
    } else {
        ""
    })
    let actual_mirror = (if ($cfg.local_mirror_path | str length) > 0 {
        $cfg.local_mirror_path | path expand
    } else {
        ""
    })
    if $actual_mirror != $expected_mirror {
        error make {msg: $"Expected local_mirror_path '($expected_mirror)', got: '($actual_mirror)'"}
    }

    assert-single-primary-tag-state $cfg $service $version
    true
}

export def parse-public-suite-block [help_output: string] {
    let lines = ($help_output | lines)
    let available = ($lines | enumerate | where item == "Available suites:")
    if ($available | is-empty) {
        error make {msg: "test help missing Available suites marker"}
    }

    let block_lines = (
        $lines
            | skip (($available | first | get index) + 1)
            | take while {|line| ($line | str trim) != ""}
    )

    $block_lines | each {|line|
        let parsed = ($line | parse --regex '^\s+(?P<name>\S+)\s+(?P<desc>.+)$')
        if ($parsed | is-empty) {
            error make {msg: $"unable to parse public suite line: ($line)"}
        }
        $parsed | get 0.name
    }
}
