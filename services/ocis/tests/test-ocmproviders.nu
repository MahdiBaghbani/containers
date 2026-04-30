#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images

# oCIS service-local OCM provider generator tests

use ../scripts/lib/ocmproviders.nu [has-indexed-providers collect-providers generate-ocmproviders]
use ../../../scripts/tests/lib.nu [run-test print-test-summary]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make-temp-dir [] {
    mktemp -d | str trim
}

def rm-temp-dir [dir: string] {
    try { rm -rf $dir } catch { }
}

def single-provider-env [] {
    {
        OCM_PROVIDER_0_NAME:             "Cloud Alpha",
        OCM_PROVIDER_0_DOMAIN:           "alpha.example.com",
        OCM_PROVIDER_0_OCM_ENDPOINT:     "https://alpha.example.com/ocm",
        OCM_PROVIDER_0_OCM_PATH:         "/ocm",
        OCM_PROVIDER_0_OCM_HOST:         "alpha.example.com",
        OCM_PROVIDER_0_WEBDAV_ENDPOINT:  "https://alpha.example.com/dav/spaces/",
        OCM_PROVIDER_0_WEBDAV_PATH:      "/dav/spaces/",
        OCM_PROVIDER_0_WEBDAV_HOST:      "alpha.example.com",
    }
}

def two-provider-env [] {
    (single-provider-env) | merge {
        OCM_PROVIDER_1_NAME:             "Cloud Beta",
        OCM_PROVIDER_1_DOMAIN:           "beta.example.com",
        OCM_PROVIDER_1_OCM_ENDPOINT:     "https://beta.example.com/ocm",
        OCM_PROVIDER_1_OCM_PATH:         "/ocm",
        OCM_PROVIDER_1_OCM_HOST:         "beta.example.com",
        OCM_PROVIDER_1_WEBDAV_ENDPOINT:  "https://beta.example.com/dav/spaces/",
        OCM_PROVIDER_1_WEBDAV_PATH:      "/dav/spaces/",
        OCM_PROVIDER_1_WEBDAV_HOST:      "beta.example.com",
    }
}

# ---------------------------------------------------------------------------
# has-indexed-providers
# ---------------------------------------------------------------------------

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    let t1 = (run-test "has-indexed-providers: false when no env" {
        with-env {} {
            not (has-indexed-providers)
        }
    } $verbose_flag)
    $results = ($results | append $t1)

    let t2 = (run-test "has-indexed-providers: true when OCM_PROVIDER_0_DOMAIN set" {
        with-env {OCM_PROVIDER_0_DOMAIN: "cloud.example.com"} {
            has-indexed-providers
        }
    } $verbose_flag)
    $results = ($results | append $t2)

    let t3 = (run-test "has-indexed-providers: false when OCM_PROVIDER_0_DOMAIN empty" {
        with-env {OCM_PROVIDER_0_DOMAIN: "   "} {
            not (has-indexed-providers)
        }
    } $verbose_flag)
    $results = ($results | append $t3)

    # ---------------------------------------------------------------------------
    # collect-providers
    # ---------------------------------------------------------------------------

    let t4 = (run-test "collect-providers: returns empty list when no env" {
        with-env {} {
            let providers = (collect-providers)
            ($providers | length) == 0
        }
    } $verbose_flag)
    $results = ($results | append $t4)

    let t5 = (run-test "collect-providers: collects one provider" {
        with-env (single-provider-env) {
            let providers = (collect-providers)
            ($providers | length) == 1
        }
    } $verbose_flag)
    $results = ($results | append $t5)

    let t6 = (run-test "collect-providers: first provider has correct name and domain" {
        with-env (single-provider-env) {
            let p = (collect-providers | get 0)
            ($p.name == "Cloud Alpha") and ($p.domain == "alpha.example.com")
        }
    } $verbose_flag)
    $results = ($results | append $t6)

    let t7 = (run-test "collect-providers: first provider has two services (OCM + Webdav)" {
        with-env (single-provider-env) {
            let p = (collect-providers | get 0)
            ($p.services | length) == 2
        }
    } $verbose_flag)
    $results = ($results | append $t7)

    let t8 = (run-test "collect-providers: OCM service type name is OCM" {
        with-env (single-provider-env) {
            let svc = (collect-providers | get 0 | get services | get 0)
            $svc.endpoint.type.name == "OCM"
        }
    } $verbose_flag)
    $results = ($results | append $t8)

    let t9 = (run-test "collect-providers: Webdav service type name is Webdav" {
        with-env (single-provider-env) {
            let svc = (collect-providers | get 0 | get services | get 1)
            $svc.endpoint.type.name == "Webdav"
        }
    } $verbose_flag)
    $results = ($results | append $t9)

    let t10 = (run-test "collect-providers: collects two providers" {
        with-env (two-provider-env) {
            let providers = (collect-providers)
            ($providers | length) == 2
        }
    } $verbose_flag)
    $results = ($results | append $t10)

    let t11 = (run-test "collect-providers: second provider has correct domain" {
        with-env (two-provider-env) {
            let p = (collect-providers | get 1)
            $p.domain == "beta.example.com"
        }
    } $verbose_flag)
    $results = ($results | append $t11)

    let t12 = (run-test "collect-providers: defaults full_name to '{name} provider'" {
        with-env (single-provider-env) {
            let p = (collect-providers | get 0)
            $p.full_name == "Cloud Alpha provider"
        }
    } $verbose_flag)
    $results = ($results | append $t12)

    let t13 = (run-test "collect-providers: explicit FULL_NAME overrides default" {
        with-env ((single-provider-env) | merge {OCM_PROVIDER_0_FULL_NAME: "Alpha Cloud Storage"}) {
            let p = (collect-providers | get 0)
            $p.full_name == "Alpha Cloud Storage"
        }
    } $verbose_flag)
    $results = ($results | append $t13)

    let t14 = (run-test "collect-providers: defaults homepage to https://{domain}" {
        with-env (single-provider-env) {
            let p = (collect-providers | get 0)
            $p.homepage == "https://alpha.example.com"
        }
    } $verbose_flag)
    $results = ($results | append $t14)

    let t15 = (run-test "collect-providers: OCM host bare hostname normalized to http://" {
        with-env (single-provider-env) {
            let svc = (collect-providers | get 0 | get services | get 0)
            $svc.host == "http://alpha.example.com"
        }
    } $verbose_flag)
    $results = ($results | append $t15)

    let t16 = (run-test "collect-providers: WebDAV host bare hostname normalized to https:// with trailing slash" {
        with-env (single-provider-env) {
            let svc = (collect-providers | get 0 | get services | get 1)
            $svc.host == "https://alpha.example.com/"
        }
    } $verbose_flag)
    $results = ($results | append $t16)

    # ---------------------------------------------------------------------------
    # generate-ocmproviders
    # ---------------------------------------------------------------------------

    let t17 = (run-test "generate-ocmproviders: writes valid JSON file" {
        let tmp = (make-temp-dir)
        let dst = $"($tmp)/ocmproviders.json"
        with-env (single-provider-env) {
            generate-ocmproviders $dst
        }
        let ok = ($dst | path exists)
        rm-temp-dir $tmp
        $ok
    } $verbose_flag)
    $results = ($results | append $t17)

    let t18 = (run-test "generate-ocmproviders: output parses as list with one entry" {
        let tmp = (make-temp-dir)
        let dst = $"($tmp)/ocmproviders.json"
        with-env (single-provider-env) {
            generate-ocmproviders $dst
        }
        let data = (open $dst)
        let ok = ($data | length) == 1
        rm-temp-dir $tmp
        $ok
    } $verbose_flag)
    $results = ($results | append $t18)

    let t19 = (run-test "generate-ocmproviders: output has correct provider name" {
        let tmp = (make-temp-dir)
        let dst = $"($tmp)/ocmproviders.json"
        with-env (single-provider-env) {
            generate-ocmproviders $dst
        }
        let data = (open $dst)
        let ok = (($data | get 0 | get name) == "Cloud Alpha")
        rm-temp-dir $tmp
        $ok
    } $verbose_flag)
    $results = ($results | append $t19)

    let t20 = (run-test "generate-ocmproviders: two providers produce two-entry JSON" {
        let tmp = (make-temp-dir)
        let dst = $"($tmp)/ocmproviders.json"
        with-env (two-provider-env) {
            generate-ocmproviders $dst
        }
        let data = (open $dst)
        let ok = ($data | length) == 2
        rm-temp-dir $tmp
        $ok
    } $verbose_flag)
    $results = ($results | append $t20)

    # ---------------------------------------------------------------------------
    # Source-file structure (explicit-file precedence contract)
    # ---------------------------------------------------------------------------

    let test_dir = ($env.CURRENT_FILE | path dirname)

    let t21 = (run-test "entrypoint structure: explicit-file branch present" {
        let path = ($test_dir | path join ".." "scripts" "entrypoint-init.nu")
        let content = (open --raw $path)
        $content | str contains "OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE"
    } $verbose_flag)
    $results = ($results | append $t21)

    let t22 = (run-test "entrypoint structure: uses generate-ocmproviders for indexed env" {
        let path = ($test_dir | path join ".." "scripts" "entrypoint-init.nu")
        let content = (open --raw $path)
        $content | str contains "generate-ocmproviders"
    } $verbose_flag)
    $results = ($results | append $t22)

    let t23 = (run-test "module placement: service-local ocmproviders.nu exists" {
        let path = ($test_dir | path join ".." "scripts" "lib" "ocmproviders.nu")
        $path | path exists
    } $verbose_flag)
    $results = ($results | append $t23)

    # ---------------------------------------------------------------------------
    # OCM_ENDPOINT / WEBDAV_ENDPOINT precedence and fallback
    # ---------------------------------------------------------------------------

    let t24 = (run-test "collect-providers: OCM endpoint.path uses OCM_ENDPOINT full URL" {
        with-env (single-provider-env) {
            let svc = (collect-providers | get 0 | get services | get 0)
            $svc.endpoint.path == "https://alpha.example.com/ocm"
        }
    } $verbose_flag)
    $results = ($results | append $t24)

    let t25 = (run-test "collect-providers: WebDAV endpoint.path uses WEBDAV_ENDPOINT full URL" {
        with-env (single-provider-env) {
            let svc = (collect-providers | get 0 | get services | get 1)
            $svc.endpoint.path == "https://alpha.example.com/dav/spaces/"
        }
    } $verbose_flag)
    $results = ($results | append $t25)

    let t26 = (run-test "collect-providers: OCM endpoint.path falls back to OCM_PATH when ENDPOINT absent" {
        let env_no_ep = (single-provider-env) | reject OCM_PROVIDER_0_OCM_ENDPOINT
        with-env $env_no_ep {
            let svc = (collect-providers | get 0 | get services | get 0)
            $svc.endpoint.path == "/ocm"
        }
    } $verbose_flag)
    $results = ($results | append $t26)

    let t27 = (run-test "collect-providers: WebDAV endpoint.path falls back to WEBDAV_PATH when ENDPOINT absent" {
        let env_no_ep = (single-provider-env) | reject OCM_PROVIDER_0_WEBDAV_ENDPOINT
        with-env $env_no_ep {
            let svc = (collect-providers | get 0 | get services | get 1)
            $svc.endpoint.path == "/dav/spaces/"
        }
    } $verbose_flag)
    $results = ($results | append $t27)

    # ---------------------------------------------------------------------------
    # Host normalization
    # ---------------------------------------------------------------------------

    let t28 = (run-test "collect-providers: OCM host with scheme passes through unchanged" {
        let env_full = (single-provider-env) | merge {OCM_PROVIDER_0_OCM_HOST: "http://ocm.example.com/api"}
        with-env $env_full {
            let svc = (collect-providers | get 0 | get services | get 0)
            $svc.host == "http://ocm.example.com/api"
        }
    } $verbose_flag)
    $results = ($results | append $t28)

    let t29 = (run-test "collect-providers: WebDAV host with scheme but no trailing slash gets slash appended" {
        let env_no_slash = (single-provider-env) | merge {OCM_PROVIDER_0_WEBDAV_HOST: "https://dav.example.com"}
        with-env $env_no_slash {
            let svc = (collect-providers | get 0 | get services | get 1)
            $svc.host == "https://dav.example.com/"
        }
    } $verbose_flag)
    $results = ($results | append $t29)

    let t30 = (run-test "collect-providers: WebDAV host with scheme and trailing slash passes through unchanged" {
        let env_full = (single-provider-env) | merge {OCM_PROVIDER_0_WEBDAV_HOST: "https://dav.example.com/"}
        with-env $env_full {
            let svc = (collect-providers | get 0 | get services | get 1)
            $svc.host == "https://dav.example.com/"
        }
    } $verbose_flag)
    $results = ($results | append $t30)

    # ---------------------------------------------------------------------------
    # Fail-fast validation: required fields
    # ---------------------------------------------------------------------------

    let t31 = (run-test "collect-providers: empty NAME fails with error" {
        let env_no_name = (single-provider-env) | reject OCM_PROVIDER_0_NAME
        with-env $env_no_name {
            try {
                collect-providers
                false
            } catch {|err|
                $err.msg | str contains "NAME"
            }
        }
    } $verbose_flag)
    $results = ($results | append $t31)

    let t32 = (run-test "collect-providers: whitespace-only NAME fails with error" {
        let env_blank_name = (single-provider-env) | merge {OCM_PROVIDER_0_NAME: "   "}
        with-env $env_blank_name {
            try {
                collect-providers
                false
            } catch {|err|
                $err.msg | str contains "NAME"
            }
        }
    } $verbose_flag)
    $results = ($results | append $t32)

    let t33 = (run-test "collect-providers: all OCM service fields absent fails with error" {
        let env_no_ocm = (single-provider-env) | reject OCM_PROVIDER_0_OCM_HOST OCM_PROVIDER_0_OCM_ENDPOINT OCM_PROVIDER_0_OCM_PATH
        with-env $env_no_ocm {
            try {
                collect-providers
                false
            } catch {|err|
                $err.msg | str contains "OCM"
            }
        }
    } $verbose_flag)
    $results = ($results | append $t33)

    let t34 = (run-test "collect-providers: all WebDAV service fields absent fails with error" {
        let env_no_wdav = (single-provider-env) | reject OCM_PROVIDER_0_WEBDAV_HOST OCM_PROVIDER_0_WEBDAV_ENDPOINT OCM_PROVIDER_0_WEBDAV_PATH
        with-env $env_no_wdav {
            try {
                collect-providers
                false
            } catch {|err|
                $err.msg | str contains "WebDAV"
            }
        }
    } $verbose_flag)
    $results = ($results | append $t34)

    # ---------------------------------------------------------------------------
    # Comment-contract: ocmproviders.nu header reflects validation
    # ---------------------------------------------------------------------------

    let t35 = (run-test "ocmproviders module: NAME comment states 'required; fails if empty'" {
        let path = ($env.CURRENT_FILE | path dirname | path join ".." "scripts" "lib" "ocmproviders.nu")
        let content = (open --raw $path)
        $content | str contains "required; fails if empty"
    } $verbose_flag)
    $results = ($results | append $t35)

    let t36 = (run-test "ocmproviders module: DOMAIN comment states 'stops loop if absent'" {
        let path = ($env.CURRENT_FILE | path dirname | path join ".." "scripts" "lib" "ocmproviders.nu")
        let content = (open --raw $path)
        $content | str contains "stops loop if absent"
    } $verbose_flag)
    $results = ($results | append $t36)

    # ---------------------------------------------------------------------------
    # Summary
    # ---------------------------------------------------------------------------

    print-test-summary $results
    let failed = ($results | where {|r| not $r} | length)
    if $failed > 0 {
        exit 1
    }
}
