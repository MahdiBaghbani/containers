#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Source-contract tests for baked revad health boundaries and example compose files.

const REVAD_BASE_DIR = ((path self) | path dirname | path join "..")
const CONTAINERS_ROOT = ($REVAD_BASE_DIR | path join "../..")
const DEV_DOCKERFILE = ($REVAD_BASE_DIR | path join "Dockerfile.development")
const HEALTHCHECK_SCRIPT = ($REVAD_BASE_DIR | path join "scripts/healthcheck.nu")

def read-src [path: string] {
    open --raw $path
}

def is-compose-top-level-service-line [line: string] {
    not (($line | parse --regex '^  [^\s].+:$' | is-empty))
}

def extract-compose-service-block [src: string, service: string] {
    let marker = $"  ($service):"
    let lines = ($src | lines)
    let start = ($lines | enumerate | where {|e| $e.item == $marker} | first)
    if ($start == null) {
        return null
    }
    let tail = ($lines | skip ($start.index + 1))
    let next = ($tail | enumerate | where {|e| (is-compose-top-level-service-line $e.item)} | first)
    let end = if ($next == null) { ($tail | length) } else { $next.index }
    $tail | take $end | str join (char newline)
}

def assert-truthy [cond: bool, label: string] {
    if $cond { {ok: true, label: $label} } else { {ok: false, label: $label} }
}

def assert-string-contains [haystack: string, needle: string, label: string] {
    assert-truthy ($haystack | str contains $needle) $label
}

def revad-gateway-services [prefix: string] {
    [
        $"($prefix)-revad-gateway"
        $"($prefix)-revad-authprovider-oidc"
        $"($prefix)-revad-authprovider-machine"
        $"($prefix)-revad-authprovider-ocmshares"
        $"($prefix)-revad-authprovider-ocmsharecode"
        $"($prefix)-revad-authprovider-ocmexchangedtoken"
        $"($prefix)-revad-authprovider-publicshares"
        $"($prefix)-revad-shareproviders"
        $"($prefix)-revad-groupuserproviders"
        $"($prefix)-revad-dataprovider-localhome"
        $"($prefix)-revad-dataprovider-ocm"
        $"($prefix)-revad-dataprovider-sciencemesh"
    ]
}

def test-development-dockerfile-baked-health [] {
    print "Testing Dockerfile.development baked health boundary..."
    mut passed = 0
    mut failed = 0

    let dockerfile = (read-src $DEV_DOCKERFILE)
    mut checks = [
        (assert-string-contains $dockerfile "COPY ./scripts /tmp/scripts"
            "development Dockerfile copies service scripts into build stage")
        (assert-string-contains $dockerfile "cp {} /usr/bin/"
            "development Dockerfile stages top-level scripts into /usr/bin")
        (assert-string-contains $dockerfile "cp -r /tmp/scripts/lib/* /usr/bin/lib/"
            "development Dockerfile stages script lib into /usr/bin/lib")
        (assert-string-contains $dockerfile "COPY --chmod=755 --from=directory /usr/bin /usr/bin"
            "runtime image inherits staged /usr/bin from directory stage")
        (assert-string-contains $dockerfile "HEALTHCHECK"
            "development Dockerfile declares baked HEALTHCHECK")
        (assert-string-contains $dockerfile '"/usr/bin/healthcheck.nu"'
            "HEALTHCHECK points at /usr/bin/healthcheck.nu")
    ]

    if ($HEALTHCHECK_SCRIPT | path exists) {
        $checks = ($checks | append (
            assert-truthy true "healthcheck.nu exists in revad-base scripts tree"
        ))
    } else {
        $checks = ($checks | append (
            assert-truthy false "healthcheck.nu exists in revad-base scripts tree"
        ))
    }

    for check in $checks {
        if $check.ok {
            $passed = ($passed + 1)
        } else {
            print $"  [FAIL] ($check.label)"
            $failed = ($failed + 1)
        }
    }

    if $failed == 0 {
        print "  [PASS] Development Dockerfile baked health: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def test-cernbox-example-compose-contract [example: string, idp_svc: string, gateway_prefix: string, web_svc: string] {
    print $"Testing ($example) compose baked-health contract..."
    mut passed = 0
    mut failed = 0

    let compose_path = ($CONTAINERS_ROOT | path join "examples" $example "docker-compose.yaml")
    let src = (read-src $compose_path)
    let revad_services = (revad-gateway-services $gateway_prefix)

    mut checks = [
        (assert-truthy (not ($src | str contains "sport = :"))
            $"($example) has no inline compose sport = : gRPC probes")
        (assert-truthy (not ($src | str contains "healthcheck:"))
            $"($example) has no compose healthcheck blocks on baked-health images")
    ]

    let gateway = $"($gateway_prefix)-revad-gateway"
    let gateway_block = (extract-compose-service-block $src $gateway)
    $checks = ($checks | append [
        (assert-truthy ($gateway_block != null) $"($gateway) block exists")
        (assert-truthy ($gateway_block | str contains $"($idp_svc):")
            "gateway depends_on idp")
        (assert-truthy ($gateway_block | str contains "condition: service_healthy")
            "gateway waits on idp with service_healthy")
    ])

    for svc in ($revad_services | skip 1) {
        let block = (extract-compose-service-block $src $svc)
        $checks = ($checks | append [
            (assert-truthy ($block != null) $"($svc) block exists")
            (assert-truthy ($block | str contains $"($gateway):")
                $"($svc) depends_on gateway")
            (assert-truthy ($block | str contains "condition: service_healthy")
                $"($svc) waits on gateway with service_healthy")
        ])
    }

    let web_block = (extract-compose-service-block $src $web_svc)
    $checks = ($checks | append [
        (assert-truthy ($web_block != null) $"($web_svc) block exists")
        (assert-truthy ($web_block | str contains $"($idp_svc):")
            "web depends_on idp with service_healthy")
        (assert-truthy ($web_block | str contains "condition: service_healthy")
            "web uses service_healthy for baked-health dependencies")
    ])

    for svc in $revad_services {
        $checks = ($checks | append [
            (assert-truthy ($web_block | str contains $"($svc):")
                $"web depends_on full Reva runtime service ($svc)")
        ])
    }

    for check in $checks {
        if $check.ok {
            $passed = ($passed + 1)
        } else {
            print $"  [FAIL] ($check.label)"
            $failed = ($failed + 1)
        }
    }

    if $failed == 0 {
        print $"  [PASS] ($example) compose contract: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def test-nextcloud-example-compose-contract [] {
    print "Testing nextcloud compose health contract..."
    mut passed = 0
    mut failed = 0

    let compose_path = ($CONTAINERS_ROOT | path join "examples" "nextcloud" "docker-compose.yaml")
    let src = (read-src $compose_path)

    mut checks = [
        (assert-truthy (not ($src | str contains "cernbox-revad"))
            "nextcloud example has no revad services")
        (assert-truthy (not ($src | str contains "sport = :"))
            "nextcloud example has no inline gRPC sport probes")
        (assert-string-contains $src 'test: ["CMD", "valkey-cli", "ping"]'
            "nextcloud cache services keep valkey healthcheck")
        (assert-string-contains $src "curl -skf https://127.0.0.1/status.php"
            "nextcloud app services keep curl status.php healthcheck")
    ]

    let firefox_block = (extract-compose-service-block $src "nextcloud-firefox")
    $checks = ($checks | append [
        (assert-truthy ($firefox_block != null) "nextcloud-firefox block exists")
        (assert-truthy ($firefox_block | str contains "nextcloud1:")
            "firefox depends_on nextcloud1")
        (assert-truthy ($firefox_block | str contains "nextcloud2:")
            "firefox depends_on nextcloud2")
        (assert-truthy ($firefox_block | str contains "condition: service_healthy")
            "firefox waits on nextcloud instances with service_healthy")
    ])

    for check in $checks {
        if $check.ok {
            $passed = ($passed + 1)
        } else {
            print $"  [FAIL] ($check.label)"
            $failed = ($failed + 1)
        }
    }

    if $failed == 0 {
        print "  [PASS] nextcloud compose contract: PASSED"
    }
    {passed: $passed, failed: $failed}
}

def main [--verbose] {
    mut total_passed = 0
    mut total_failed = 0

    for result in [
        (test-development-dockerfile-baked-health)
        (test-cernbox-example-compose-contract "one-cernbox" "one-cernbox-idp" "one-cernbox-1" "one-cernbox-1-web")
        (test-cernbox-example-compose-contract "two-cernbox" "two-cernbox-idp1" "two-cernbox-1" "two-cernbox-1-web")
        (test-cernbox-example-compose-contract "two-cernbox" "two-cernbox-idp2" "two-cernbox-2" "two-cernbox-2-web")
        (test-nextcloud-example-compose-contract)
    ] {
        $total_passed = ($total_passed + $result.passed)
        $total_failed = ($total_failed + $result.failed)
    }

    print ""
    print $"Tests: ($total_passed) passed, ($total_failed) failed"
    if $total_failed == 0 { exit 0 } else { exit 1 }
}
