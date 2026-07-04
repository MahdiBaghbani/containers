#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Unit tests for scripts/healthcheck.nu (baked development-image gRPC probe).

const HEALTHCHECK_SCRIPT = ((path self) | path dirname | path join "../scripts/healthcheck.nu")

def healthcheck-script [] {
    $HEALTHCHECK_SCRIPT
}

def run-healthcheck [env_vars: record] {
    with-env $env_vars {
        ^nu (healthcheck-script) | complete
    }
}

def wait-for-listener [pidfile: string, max_ms: int = 5000] {
    mut elapsed = 0
    loop {
        if ($pidfile | path exists) {
            return true
        }
        if $elapsed >= $max_ms {
            return false
        }
        sleep 200ms
        $elapsed = ($elapsed + 200)
    }
}

def start-tcp-listener [port: string] {
    let script = (^mktemp --suffix=.py | str trim)
    let pidfile = (^mktemp | str trim)
    [
        "import os"
        "import socket"
        "import time"
        $"port = ($port | into int)"
        $"pidfile = r'($pidfile)'"
        "s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)"
        "s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)"
        "s.bind(('127.0.0.1', port))"
        "s.listen(1)"
        "with open(pidfile, 'w') as f:"
        "    f.write(str(os.getpid()))"
        "time.sleep(15)"
    ] | str join (char nl) | save -f $script
    ^sh -c $"python3 ($script) >/dev/null 2>&1 &"
    if not (wait-for-listener $pidfile) {
        stop-tcp-listener {script: $script, pidfile: $pidfile}
        error make {msg: $"listener failed to bind port ($port)"}
    }
    {script: $script, pidfile: $pidfile}
}

def stop-tcp-listener [handle: record] {
    if ($handle.pidfile | path exists) {
        let pid = (open $handle.pidfile | str trim | into int)
        try { ^kill $pid } catch { }
        rm -f $handle.pidfile
    }
    try { rm -f $handle.script } catch { }
}

def write-fake-ss [bin_dir: string, script_body: string] {
    $script_body | save ($bin_dir | path join "ss")
    ^chmod +x ($bin_dir | path join "ss")
}

def run-healthcheck-with-path [env_vars: record, path_prefix: string] {
    let nu_bin = (which nu | first | get path)
    with-env ($env_vars | merge {PATH: $"($path_prefix):($env.PATH)"}) {
        ^$nu_bin (healthcheck-script) | complete
    }
}

def test_missing_container_mode [] {
    print "Testing healthcheck requires REVAD_CONTAINER_MODE..."
    mut passed = 0
    mut failed = 0

    let result = (run-healthcheck {REVAD_CONTAINER_MODE: ""})
    if $result.exit_code == 1 and ($result.stdout | str contains "REVAD_CONTAINER_MODE is required") {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] missing mode: exit ($result.exit_code), stdout: ($result.stdout | str trim)"
        $failed = ($failed + 1)
    }

    if $failed == 0 {
        print "  [PASS] Missing REVAD_CONTAINER_MODE: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def test_port_resolution_failure [] {
    print "Testing healthcheck port resolution failures..."
    mut passed = 0
    mut failed = 0

    let unknown = (run-healthcheck {REVAD_CONTAINER_MODE: "not-a-real-mode"})
    if $unknown.exit_code == 1 and ($unknown.stdout | str contains "unknown REVAD_CONTAINER_MODE") {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] unknown mode: exit ($unknown.exit_code)"
        $failed = ($failed + 1)
    }

    let dataprovider = (run-healthcheck {REVAD_CONTAINER_MODE: "dataprovider-ocm"})
    if $dataprovider.exit_code == 1 and ($dataprovider.stdout | str contains "REVAD_DATAPROVIDER_OCM_GRPC_PORT is required") {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] dataprovider without env: exit ($dataprovider.exit_code)"
        $failed = ($failed + 1)
    }

    if $failed == 0 {
        print "  [PASS] Port resolution failures: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def test_probe_no_listener [] {
    print "Testing healthcheck fails when gRPC port is not listening..."
    mut passed = 0
    mut failed = 0

    let port = "59144"
    let result = (run-healthcheck {
        REVAD_CONTAINER_MODE: "gateway"
        REVAD_GATEWAY_GRPC_PORT: $port
    })
    if $result.exit_code == 1 and ($result.stdout | str contains "no listener on gRPC port") {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] expected no-listener failure on ($port), exit ($result.exit_code)"
        $failed = ($failed + 1)
    }

    if $failed == 0 {
        print "  [PASS] Probe no listener: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def test_ss_probe_failure [] {
    print "Testing healthcheck fails when ss probe command fails..."
    mut passed = 0
    mut failed = 0

    let bin_dir = (^mktemp -d | str trim)
    write-fake-ss $bin_dir "#!/bin/sh
echo 'ss: simulated failure' >&2
exit 1
"
    let result = (run-healthcheck-with-path {
        REVAD_CONTAINER_MODE: "gateway"
        REVAD_GATEWAY_GRPC_PORT: "59145"
    } $bin_dir)
    try { ^rm -rf $bin_dir } catch { }

    if $result.exit_code == 1 and ($result.stdout | str contains "ss probe failed") {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] expected ss probe failure, exit ($result.exit_code), stdout: ($result.stdout | str trim)"
        $failed = ($failed + 1)
    }

    if $failed == 0 {
        print "  [PASS] ss probe failure: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def test_probe_listening [] {
    print "Testing healthcheck succeeds when gRPC port is listening..."
    mut passed = 0
    mut failed = 0

    let port = "59143"
    let handle = (try { start-tcp-listener $port } catch {|e|
        print $"  [FAIL] ($e.msg)"
        return {passed: 0, failed: 1}
    })
    let result = (try {
        run-healthcheck {
            REVAD_CONTAINER_MODE: "gateway"
            REVAD_GATEWAY_GRPC_PORT: $port
        }
    } catch {|e|
        stop-tcp-listener $handle
        error make {msg: $"healthcheck subprocess error: ($e.msg)"}
    })
    stop-tcp-listener $handle

    if $result.exit_code == 0 {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] expected exit 0 with listener on ($port), got ($result.exit_code)"
        $failed = ($failed + 1)
    }

    if $failed == 0 {
        print "  [PASS] Probe listening: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def main [--verbose] {
    mut total_passed = 0
    mut total_failed = 0

    for result in [
        (test_missing_container_mode)
        (test_port_resolution_failure)
        (test_probe_no_listener)
        (test_ss_probe_failure)
        (test_probe_listening)
    ] {
        $total_passed = ($total_passed + $result.passed)
        $total_failed = ($total_failed + $result.failed)
    }

    print ""
    print $"Tests: ($total_passed) passed, ($total_failed) failed"
    if $total_failed == 0 { exit 0 } else { exit 1 }
}
