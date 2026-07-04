#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Behavioral contracts for cernbox-web TLS resolution and baked HEALTHCHECK wiring.

const CERNBOX_WEB_DIR = ((path self) | path dirname | path join "..")
const DOCKERFILE = ($CERNBOX_WEB_DIR | path join "Dockerfile")
const HEALTHCHECK_SCRIPT = ($CERNBOX_WEB_DIR | path join "scripts/healthcheck.nu")

use ../scripts/lib/tls.nu [resolve-revad-tls-enabled resolve-web-tls-enabled]

def read-src [path: string] {
    open --raw $path
}

def assert-truthy [cond: bool, label: string] {
    if $cond { {ok: true, label: $label} } else { {ok: false, label: $label} }
}

def assert-string-contains [haystack: string, needle: string, label: string] {
    assert-truthy ($haystack | str contains $needle) $label
}

def run-checks [checks: list] {
    mut passed = 0
    mut failed = 0
    for check in $checks {
        if $check.ok {
            $passed = ($passed + 1)
        } else {
            print $"  [FAIL] ($check.label)"
            $failed = ($failed + 1)
        }
    }
    {passed: $passed, failed: $failed}
}

def test-revad-tls-resolution [] {
    print "Testing resolve-revad-tls-enabled chain..."
    mut passed = 0
    mut failed = 0

    let cases = [
        {env: {REVAD_TLS_ENABLED: "false"}, want: "false"}
        {env: {REVAD_TLS_ENABLED: "true"}, want: "true"}
        {env: {REVAD_TLS_ENABLED: "yes"}, want: "yes"}
        {env: {REVAD_TLS_ENABLED: "", TLS_ENABLED: "false"}, want: "false"}
        {env: {REVAD_TLS_ENABLED: "   ", TLS_ENABLED: "false"}, want: "false"}
        {env: {REVAD_TLS_ENABLED: "", TLS_ENABLED: "true"}, want: "true"}
        {env: {REVAD_TLS_ENABLED: "", TLS_ENABLED: ""}, want: "true"}
        {env: {REVAD_TLS_ENABLED: "false", TLS_ENABLED: "true"}, want: "false"}
    ]

    for case in $cases {
        let got = (with-env $case.env {
            resolve-revad-tls-enabled
        })
        if $got == $case.want {
            $passed = ($passed + 1)
        } else {
            print $"  [FAIL] revad env ($case.env | to json -r): expected ($case.want), got ($got)"
            $failed = ($failed + 1)
        }
    }

    if $failed == 0 {
        print "  [PASS] resolve-revad-tls-enabled: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def test-web-tls-resolution [] {
    print "Testing resolve-web-tls-enabled chain..."
    mut passed = 0
    mut failed = 0

    let cases = [
        {env: {WEB_TLS_ENABLED: "false"}, want: "false"}
        {env: {WEB_TLS_ENABLED: "true"}, want: "true"}
        {env: {WEB_TLS_ENABLED: "", REVAD_TLS_ENABLED: "false"}, want: "false"}
        {env: {WEB_TLS_ENABLED: "   ", REVAD_TLS_ENABLED: "false"}, want: "false"}
        {env: {WEB_TLS_ENABLED: "", REVAD_TLS_ENABLED: "", TLS_ENABLED: "false"}, want: "false"}
        {env: {WEB_TLS_ENABLED: "", REVAD_TLS_ENABLED: "", TLS_ENABLED: ""}, want: "true"}
        {env: {WEB_TLS_ENABLED: "true", REVAD_TLS_ENABLED: "false"}, want: "true"}
        {env: {WEB_TLS_ENABLED: "false", REVAD_TLS_ENABLED: "true"}, want: "false"}
    ]

    for case in $cases {
        let got = (with-env $case.env {
            resolve-web-tls-enabled
        })
        if $got == $case.want {
            $passed = ($passed + 1)
        } else {
            print $"  [FAIL] web env ($case.env | to json -r): expected ($case.want), got ($got)"
            $failed = ($failed + 1)
        }
    }

    if $failed == 0 {
        print "  [PASS] resolve-web-tls-enabled: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def expect-probe-args [
    env_vars: record,
    want_args: string,
    label: string,
] {
    let probe = (run-healthcheck-probe $env_vars 0)
    if $probe.result.exit_code == 0 and $probe.args == $want_args {
        {ok: true, label: $label}
    } else {
        print $"  [FAIL] ($label): exit=($probe.result.exit_code) curl_args='($probe.args)' want='($want_args)'"
        {ok: false, label: $label}
    }
}

def test-tls-protocol-semantics [] {
    print "Testing TLS false => HTTP / otherwise => HTTPS via resolver+probe..."
    let checks = [
        (expect-probe-args {WEB_TLS_ENABLED: "false"} "-sf http://127.0.0.1/"
            "resolved false probes HTTP")
        (expect-probe-args {WEB_TLS_ENABLED: "true"} "-skf https://127.0.0.1/"
            "resolved true probes HTTPS")
        (expect-probe-args {WEB_TLS_ENABLED: "yes"} "-skf https://127.0.0.1/"
            "resolved yes probes HTTPS")
        (expect-probe-args {WEB_TLS_ENABLED: "https"} "-skf https://127.0.0.1/"
            "resolved https probes HTTPS")
        (expect-probe-args {WEB_TLS_ENABLED: "FALSE"} "-skf https://127.0.0.1/"
            "non-exact FALSE probes HTTPS")
        (expect-probe-args {
            WEB_TLS_ENABLED: ""
            REVAD_TLS_ENABLED: ""
            TLS_ENABLED: ""
        } "-skf https://127.0.0.1/"
            "default effective TLS probes HTTPS")
    ]
    let result = (run-checks $checks)
    if $result.failed == 0 {
        print "  [PASS] TLS protocol semantics: PASSED"
    }
    $result
}

def make-fake-curl-dir [
    exit_code: int = 0,
    stderr_msg: string = "",
    stdout_msg: string = "",
] {
    let dir = (^mktemp -d | str trim)
    let log = ($dir | path join "args.txt")
    let curl_bin = ($dir | path join "curl")
    mut body = $"#!/bin/sh
echo \"$@\" > ($log)
"
    if not ($stdout_msg | is-empty) {
        $body = ($body + $"echo \"($stdout_msg)\"
")
    }
    if not ($stderr_msg | is-empty) {
        $body = ($body + $"echo \"($stderr_msg)\" >&2
")
    }
    $body = ($body + $"exit ($exit_code)
")
    $body | save -f $curl_bin
    ^chmod +x $curl_bin
    {dir: $dir, log: $log}
}

def prepend-path [prefix: string] {
    let orig_path = ($env.PATH | default [])
    if (($orig_path | describe) | str starts-with "list") {
        $orig_path | prepend $prefix
    } else {
        [$prefix $orig_path] | str join (char esep)
    }
}

def run-healthcheck-probe [
    env_vars: record,
    fake_curl_exit: int = 0,
    fake_curl_stderr: string = "",
    fake_curl_stdout: string = "",
] {
    let fake = (make-fake-curl-dir $fake_curl_exit $fake_curl_stderr $fake_curl_stdout)
    let nu_bin = (which nu | first | get path)
    let merged_env = ($env_vars | merge {PATH: (prepend-path $fake.dir)})
    let result = (with-env $merged_env {
        ^$nu_bin $HEALTHCHECK_SCRIPT | complete
    })
    let args = (try { open --raw $fake.log | str trim } catch { "" })
    try { ^rm -rf $fake.dir } catch { }
    {result: $result, args: $args}
}

def test-healthcheck-execution [] {
    print "Testing healthcheck.nu execution with fake curl..."
    mut passed = 0
    mut failed = 0

    let http = (run-healthcheck-probe {WEB_TLS_ENABLED: "false"} 0)
    let http_ok = (
        $http.result.exit_code == 0
        and ($http.args == "-sf http://127.0.0.1/")
    )
    if $http_ok {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] HTTP probe: exit=($http.result.exit_code) curl_args='($http.args)'"
        $failed = ($failed + 1)
    }

    let https = (run-healthcheck-probe {WEB_TLS_ENABLED: "true"} 0)
    let https_ok = (
        $https.result.exit_code == 0
        and ($https.args == "-skf https://127.0.0.1/")
    )
    if $https_ok {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] HTTPS probe with WEB_TLS_ENABLED true: exit=($https.result.exit_code) curl_args='($https.args)'"
        $failed = ($failed + 1)
    }

    let https_default = (run-healthcheck-probe {
        WEB_TLS_ENABLED: ""
        REVAD_TLS_ENABLED: ""
        TLS_ENABLED: ""
    } 0)
    let https_default_ok = (
        $https_default.result.exit_code == 0
        and ($https_default.args == "-skf https://127.0.0.1/")
    )
    if $https_default_ok {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] HTTPS probe (default TLS): exit=($https_default.result.exit_code) curl_args='($https_default.args)'"
        $failed = ($failed + 1)
    }

    let inherited_http = (run-healthcheck-probe {
        WEB_TLS_ENABLED: "   "
        REVAD_TLS_ENABLED: "false"
    } 0)
    let inherited_http_ok = (
        $inherited_http.result.exit_code == 0
        and ($inherited_http.args == "-sf http://127.0.0.1/")
    )
    if $inherited_http_ok {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] blank WEB_TLS_ENABLED inherits REVAD false HTTP: exit=($inherited_http.result.exit_code) curl_args='($inherited_http.args)'"
        $failed = ($failed + 1)
    }

    let passthrough_https = (run-healthcheck-probe {WEB_TLS_ENABLED: "yes"} 0)
    let passthrough_ok = (
        $passthrough_https.result.exit_code == 0
        and ($passthrough_https.args == "-skf https://127.0.0.1/")
    )
    if $passthrough_ok {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] non-false passthrough yes probes HTTPS: exit=($passthrough_https.result.exit_code) curl_args='($passthrough_https.args)'"
        $failed = ($failed + 1)
    }

    let probe_fail = (run-healthcheck-probe {WEB_TLS_ENABLED: "false"} 7)
    let fail_output = ($probe_fail.result.stdout | str join "")
    let fail_ok = (
        $probe_fail.result.exit_code == 1
        and ($fail_output | str contains "healthcheck: curl probe failed")
        and ($probe_fail.args == "-sf http://127.0.0.1/")
    )
    if $fail_ok {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] probe failure path: exit=($probe_fail.result.exit_code) output='($fail_output)' curl_args='($probe_fail.args)'"
        $failed = ($failed + 1)
    }

    let stderr_detail = "curl: (7) connection refused on probe"
    let probe_fail_stderr = (run-healthcheck-probe {
        WEB_TLS_ENABLED: "false"
    } 7 $stderr_detail "curl stdout noise should not win")
    let stderr_output = ($probe_fail_stderr.result.stdout | str join "")
    let stderr_ok = (
        $probe_fail_stderr.result.exit_code == 1
        and ($stderr_output | str contains "healthcheck: curl probe failed")
        and ($stderr_output | str contains $stderr_detail)
        and not ($stderr_output | str contains "curl stdout noise should not win")
    )
    if $stderr_ok {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] stderr-preferred failure output: exit=($probe_fail_stderr.result.exit_code) output='($stderr_output)'"
        $failed = ($failed + 1)
    }

    if $failed == 0 {
        print "  [PASS] healthcheck.nu execution: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def healthcheck-dockerfile-line [dockerfile: string] {
    $dockerfile
    | lines
    | where {|line| ($line | str trim | str starts-with "HEALTHCHECK") }
    | first
    | default ""
}

def test-dockerfile-baked-healthcheck-wiring [] {
    print "Testing Dockerfile baked HEALTHCHECK wiring..."
    let dockerfile = (read-src $DOCKERFILE)
    let want_healthcheck = 'HEALTHCHECK --interval=5s --timeout=5s --start-period=90s --retries=36 CMD ["/usr/local/bin/nu", "/usr/bin/healthcheck.nu"]'
    let healthcheck_line = (healthcheck-dockerfile-line $dockerfile)
    let checks = [
        (assert-string-contains $dockerfile "./scripts/lib/tls.nu /usr/bin/lib/tls.nu"
            "Dockerfile copies tls.nu into /usr/bin/lib")
        (assert-string-contains $dockerfile "./scripts/healthcheck.nu /usr/bin/healthcheck.nu"
            "Dockerfile copies healthcheck.nu into /usr/bin")
        (assert-string-contains $dockerfile "./scripts/cernbox.nu /usr/bin/cernbox.nu"
            "Dockerfile copies cernbox.nu into /usr/bin")
        (assert-truthy ($healthcheck_line == $want_healthcheck)
            "Dockerfile HEALTHCHECK uses exact Nu wrapper one-liner")
        (assert-truthy (not ($healthcheck_line | str contains "sh -c"))
            "Dockerfile HEALTHCHECK rejects sh -c fallback")
    ]

    mut checks = $checks
    if ($HEALTHCHECK_SCRIPT | path exists) {
        $checks = ($checks | append (
            assert-truthy true "healthcheck.nu exists in cernbox-web scripts tree"
        ))
    } else {
        $checks = ($checks | append (
            assert-truthy false "healthcheck.nu exists in cernbox-web scripts tree"
        ))
    }

    let result = (run-checks $checks)
    if $result.failed == 0 {
        print "  [PASS] Dockerfile baked HEALTHCHECK wiring: PASSED"
    }
    $result
}

def main [--verbose] {
    mut total_passed = 0
    mut total_failed = 0

    for result in [
        (test-revad-tls-resolution)
        (test-web-tls-resolution)
        (test-tls-protocol-semantics)
        (test-healthcheck-execution)
        (test-dockerfile-baked-healthcheck-wiring)
    ] {
        $total_passed = ($total_passed + $result.passed)
        $total_failed = ($total_failed + $result.failed)
        print ""
    }

    print $"Tests: ($total_passed) passed, ($total_failed) failed"
    if $total_failed == 0 { exit 0 } else { exit 1 }
}
