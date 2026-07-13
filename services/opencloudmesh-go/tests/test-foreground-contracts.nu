#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Copyright (C) 2025 Mahdi Baghbani <mahdi-baghbani@azadehafzar.io>
#
# Source-contract tests for opencloudmesh-go foreground DEV execution.
# Run: nu services/opencloudmesh-go/tests/test-foreground-contracts.nu

const OCM_GO_DIR = ((path self) | path dirname | path join "..")
const DEV_DOCKERFILE = ($OCM_GO_DIR | path join "Dockerfile.development")
const ENTRYPOINT_INIT = ($OCM_GO_DIR | path join "scripts/entrypoint-init.nu")
const HEALTHCHECK_SCRIPT = ($OCM_GO_DIR | path join "scripts/healthcheck.nu")

use ../scripts/healthcheck.nu [decide-health]

def read-src [path: string] {
    open --raw $path
}

def assert_contains [label: string, haystack: string, needle: string] {
    if not ($haystack | str contains $needle) {
        error make {
            msg: $"FAIL [$label]: expected to find ($needle | to nuon)"
        }
    }
}

def assert_not_contains [label: string, haystack: string, needle: string] {
    if ($haystack | str contains $needle) {
        error make {
            msg: $"FAIL [$label]: expected NOT to find ($needle | to nuon)"
        }
    }
}

def assert_truthy [label: string, cond: bool] {
    if not $cond {
        error make {msg: $"FAIL [$label]"}
    }
}

def extract-start-ocm-go-src [entrypoint_src: string] {
    let marker = "def start_ocm_go"
    let start = ($entrypoint_src | str index-of $marker)
    if $start == null {
        return ""
    }
    let from_def = ($entrypoint_src | str substring $start..)
    # Next top-level def after start_ocm_go (export def or plain def)
    let export_next = ($from_def | str index-of "\nexport def ")
    let plain_next = ($from_def | str index-of "\ndef ")
    let candidates = ([$export_next $plain_next] | where {|i| $i != null and $i > 0})
    if ($candidates | is-empty) {
        $from_def
    } else {
        let next = ($candidates | math min)
        $from_def | str substring 0..$next
    }
}

def last-meaningful-main-line [entrypoint_src: string] {
    let parts = ($entrypoint_src | split row "def --wrapped main")
    if ($parts | length) < 2 {
        return ""
    }
    let body = ($parts | last)
    let lines = (
        $body
        | lines
        | each {|l| $l | str trim}
        | where {|t|
            ((not ($t | is-empty))
                and (not ($t | str starts-with "#"))
                and ($t != "{")
                and ($t != "}"))
        }
    )
    if ($lines | is-empty) {
        ""
    } else {
        $lines | last
    }
}

def test_dockerfile_foreground_contract [] {
    let dockerfile = (read-src $DEV_DOCKERFILE)
    assert_contains "ENTRYPOINT has tini" $dockerfile "/usr/bin/tini"
    assert_contains "ENTRYPOINT has -g" $dockerfile '"-g"'
    assert_not_contains "no CMD tail keepalive" $dockerfile 'CMD ["tail"'
    assert_contains "HEALTHCHECK present" $dockerfile "HEALTHCHECK"
    assert_contains "HEALTHCHECK runs healthcheck.nu" $dockerfile "/usr/bin/healthcheck.nu"
}

def test_healthcheck_script_contract [] {
    assert_truthy "healthcheck.nu exists" ($HEALTHCHECK_SCRIPT | path exists)
    let src = (read-src $HEALTHCHECK_SCRIPT)
    assert_contains "healthcheck probes :443" $src ":443"
    assert_contains "healthcheck uses HTTPS" $src "https://127.0.0.1:443"
}

def test_healthcheck_decide_health_behavior [] {
    let ok = (decide-health {exit_code: 0, stdout: "", stderr: ""})
    assert_truthy "decide-health success returns 0" ($ok == 0)

    # Capture printed failure detail via subprocess so the assertion sees stderr/stdout text.
    let probe_nuon = '{exit_code: 7, stdout: "", stderr: "connection refused"}'
    let code = $"use ($HEALTHCHECK_SCRIPT) [decide-health]; exit \(decide-health ($probe_nuon)\)"
    let result = (^nu -c $code | complete)
    assert_truthy "decide-health failure returns 1" ($result.exit_code == 1)
    assert_contains "decide-health failure message has detail" $result.stdout "connection refused"
}

def test_entrypoint_foreground_contract [] {
    let entrypoint_src = (read-src $ENTRYPOINT_INIT)
    let start_src = (extract-start-ocm-go-src $entrypoint_src)

    assert_truthy "start_ocm_go definition found" (($start_src | str length) > 0)
    assert_not_contains "start_ocm_go has no sh -c" $start_src "sh -c"
    assert_not_contains "start_ocm_go has no background &" $start_src " &"
    assert_not_contains "start_ocm_go has no log redirect" $start_src ">> /var/log"
    assert_not_contains "start_ocm_go has no 2>&1 redirect" $start_src "2>&1"
    assert_not_contains "start_ocm_go has no >> redirect" $start_src ">>"
    assert_contains "start_ocm_go uses binary path" $start_src "/app/bin/opencloudmesh-go"
    assert_contains "start_ocm_go builds argv list" $start_src "mut args"
    assert_contains "start_ocm_go uses run-external spread" $start_src "run-external $cmd ...$args"

    assert_not_contains "entrypoint-init does not define ensure_logfile" $entrypoint_src "def ensure_logfile"
    assert_not_contains "entrypoint-init does not call ensure_logfile" $entrypoint_src "ensure_logfile"

    let last_line = (last-meaningful-main-line $entrypoint_src)
    assert_truthy "main ends with start_ocm_go call" (
        $last_line | str starts-with "start_ocm_go "
    )
}

def main [] {
    test_dockerfile_foreground_contract
    test_healthcheck_script_contract
    test_healthcheck_decide_health_behavior
    test_entrypoint_foreground_contract
    print "PASS: all opencloudmesh-go foreground contract tests"
}
