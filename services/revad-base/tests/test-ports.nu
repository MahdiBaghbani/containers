#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Unit tests for scripts/lib/ports.nu (gRPC port SSOT).

use ../scripts/lib/ports.nu [
    default-grpc-port-for-mode
    default-dataprovider-registry-grpc-port
    resolve-grpc-port-for-mode
    require-dataprovider-grpc-port
    resolve-gateway-grpc-port
    resolve-authprovider-grpc-port
    resolve-dataprovider-registry-grpc-port
    resolve-shareproviders-grpc-port
    resolve-groupuserproviders-grpc-port
]

def test_fixed_mode_defaults [] {
    print "Testing fixed mode default gRPC ports..."
    mut passed = 0
    mut failed = 0

    let cases = [
        {mode: "gateway", port: "9142"}
        {mode: "shareproviders", port: "9144"}
        {mode: "groupuserproviders", port: "9145"}
        {mode: "authprovider-oidc", port: "9158"}
        {mode: "authprovider-machine", port: "9166"}
        {mode: "authprovider-publicshares", port: "9160"}
        {mode: "authprovider-ocmshares", port: "9278"}
        {mode: "authprovider-ocmsharecode", port: "9280"}
        {mode: "authprovider-ocmexchangedtoken", port: "9282"}
    ]

    for case in $cases {
        let got = (default-grpc-port-for-mode $case.mode)
        if $got == $case.port {
            $passed = ($passed + 1)
        } else {
            print $"  [FAIL] ($case.mode): expected ($case.port), got ($got)"
            $failed = ($failed + 1)
        }
    }

    if $failed == 0 {
        print "  [PASS] Fixed mode defaults: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def test_dataprovider_registry_defaults [] {
    print "Testing dataprovider registry default ports..."
    mut passed = 0
    mut failed = 0

    let cases = [
        {type: "localhome", port: "9143"}
        {type: "ocm", port: "9146"}
        {type: "sciencemesh", port: "9147"}
    ]

    for case in $cases {
        let got = (default-dataprovider-registry-grpc-port $case.type)
        if $got == $case.port {
            $passed = ($passed + 1)
        } else {
            print $"  [FAIL] registry ($case.type): expected ($case.port), got ($got)"
            $failed = ($failed + 1)
        }
    }

    if $failed == 0 {
        print "  [PASS] Dataprovider registry defaults: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def test_dataprovider_mode_requires_env [] {
    print "Testing dataprovider mode requires explicit GRPC_PORT env..."
    mut passed = 0
    mut failed = 0

    let err1 = (try {
        default-grpc-port-for-mode "dataprovider-localhome"
        null
    } catch {|e| $e.msg})
    if ($err1 | str contains "no default gRPC port") {
        $passed = ($passed + 1)
    } else {
        print "  [FAIL] default-grpc-port-for-mode should reject dataprovider mode"
        $failed = ($failed + 1)
    }

    let err2 = (try {
        with-env {REVAD_DATAPROVIDER_LOCALHOME_GRPC_PORT: ""} {
            require-dataprovider-grpc-port "localhome"
        }
        null
    } catch {|e| $e.msg})
    if ($err2 | str contains "REVAD_DATAPROVIDER_LOCALHOME_GRPC_PORT is required") {
        $passed = ($passed + 1)
    } else {
        print "  [FAIL] require-dataprovider-grpc-port should error without env"
        $failed = ($failed + 1)
    }

    let ok = (with-env {REVAD_DATAPROVIDER_OCM_GRPC_PORT: "9146"} {
        require-dataprovider-grpc-port "ocm"
    })
    if $ok == "9146" {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] require-dataprovider-grpc-port with env: got ($ok)"
        $failed = ($failed + 1)
    }

    if $failed == 0 {
        print "  [PASS] Dataprovider env requirement: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def test_resolve_with_env_override [] {
    print "Testing env override resolution..."
    mut passed = 0
    mut failed = 0

    let gateway = (with-env {REVAD_GATEWAY_GRPC_PORT: "19042"} {
        resolve-grpc-port-for-mode "gateway"
    })
    if $gateway == "19042" {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] gateway override: got ($gateway)"
        $failed = ($failed + 1)
    }

    let oidc = (with-env {REVAD_AUTHPROVIDER_OIDC_GRPC_PORT: "9159"} {
        resolve-authprovider-grpc-port "oidc"
    })
    if $oidc == "9159" {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] oidc override: got ($oidc)"
        $failed = ($failed + 1)
    }

    let gw_helper = (resolve-gateway-grpc-port)
    if $gw_helper == "9142" {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] resolve-gateway-grpc-port default: got ($gw_helper)"
        $failed = ($failed + 1)
    }

    if $failed == 0 {
        print "  [PASS] Env override resolution: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def test_empty_string_override_fallback [] {
    print "Testing empty-string env overrides fall back to defaults..."
    mut passed = 0
    mut failed = 0

    let gateway = (with-env {REVAD_GATEWAY_GRPC_PORT: ""} {
        resolve-grpc-port-for-mode "gateway"
    })
    if $gateway == "9142" {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] gateway empty override: got ($gateway)"
        $failed = ($failed + 1)
    }

    let share = (with-env {REVAD_SHAREPROVIDERS_GRPC_PORT: "   "} {
        resolve-shareproviders-grpc-port
    })
    if $share == "9144" {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] shareproviders whitespace override: got ($share)"
        $failed = ($failed + 1)
    }

    let group = (with-env {REVAD_GROUPUSERPROVIDERS_GRPC_PORT: ""} {
        resolve-groupuserproviders-grpc-port
    })
    if $group == "9145" {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] groupuserproviders empty override: got ($group)"
        $failed = ($failed + 1)
    }

    let registry = (with-env {REVAD_DATAPROVIDER_OCM_GRPC_PORT: ""} {
        resolve-dataprovider-registry-grpc-port "ocm"
    })
    if $registry == "9146" {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] registry empty override: got ($registry)"
        $failed = ($failed + 1)
    }

    if $failed == 0 {
        print "  [PASS] Empty-string override fallback: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def test_invalid_port_rejection [] {
    print "Testing invalid resolved ports are rejected..."
    mut passed = 0
    mut failed = 0

    let cases = [
        {env: {REVAD_GATEWAY_GRPC_PORT: "0"}, mode: "gateway", needle: "invalid gRPC port"}
        {env: {REVAD_GATEWAY_GRPC_PORT: "70000"}, mode: "gateway", needle: "invalid gRPC port"}
        {env: {REVAD_GATEWAY_GRPC_PORT: "abc"}, mode: "gateway", needle: "invalid gRPC port"}
        {env: {REVAD_DATAPROVIDER_OCM_GRPC_PORT: "not-a-port"}, mode: "dataprovider-ocm", needle: "invalid gRPC port"}
    ]

    for case in $cases {
        let err = (try {
            with-env $case.env {
                resolve-grpc-port-for-mode $case.mode
            }
            null
        } catch {|e| $e.msg})
        if ($err | str contains $case.needle) {
            $passed = ($passed + 1)
        } else {
            print $"  [FAIL] ($case.mode) invalid port: ($err)"
            $failed = ($failed + 1)
        }
    }

    let dp_empty = (try {
        with-env {REVAD_DATAPROVIDER_LOCALHOME_GRPC_PORT: ""} {
            resolve-grpc-port-for-mode "dataprovider-localhome"
        }
        null
    } catch {|e| $e.msg})
    if ($dp_empty | str contains "REVAD_DATAPROVIDER_LOCALHOME_GRPC_PORT is required") {
        $passed = ($passed + 1)
    } else {
        print $"  [FAIL] dataprovider empty env should still fail: ($dp_empty)"
        $failed = ($failed + 1)
    }

    if $failed == 0 {
        print "  [PASS] Invalid port rejection: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def main [--verbose] {
    mut total_passed = 0
    mut total_failed = 0

    for result in [
        (test_fixed_mode_defaults)
        (test_dataprovider_registry_defaults)
        (test_dataprovider_mode_requires_env)
        (test_resolve_with_env_override)
        (test_empty_string_override_fallback)
        (test_invalid_port_rejection)
    ] {
        $total_passed = ($total_passed + $result.passed)
        $total_failed = ($total_failed + $result.failed)
    }

    print ""
    print $"Tests: ($total_passed) passed, ($total_failed) failed"
    if $total_failed == 0 { exit 0 } else { exit 1 }
}
