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

# TLS certificate and CA staging tests

use ../lib/core/repo.nu [get-repo-root]
use ../lib/tls/lib.nu [get-services-dir get-shared-ca-dir build-subject build-san-config]
use ../lib/build/context.nu [detect-ca-requirements prepare-ca-context cleanup-ca-context]
use ../lib/validate/tls.nu [validate-tls-config-merged]
use ../lib/tls/validation.nu [validate-ca cert-matches-ca]
use ../lib/tls/copy.nu [copy-tls]
use ./lib.nu [run-test print-test-summary]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a minimal temp directory that looks like a build context root
def make-temp-context [] {
    let tmp = (^mktemp -d | str trim)
    $tmp
}

def rm-temp-context [dir: string] {
    try { rm -rf $dir } catch { }
}

# Detect shell RUN chown lines that target /tls (stale pre-copy-tls pattern).
# COPY --chown=... is unrelated and is ignored.
def find-stale-inline-tls-chown [content: string] {
    $content
    | lines
    | where {|line|
        ($line | str contains "chown") and ($line | str contains "/tls") and (not ($line | str contains "--chown="))
    }
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    # ------------------------------------------------------------------
    # Existing tests preserved
    # ------------------------------------------------------------------

    let test_path = (run-test "Path resolution" {
        let repo_root = (get-repo-root)
        if not ($repo_root | path exists) {
            error make {msg: $"Repo root not found: ($repo_root)"}
        }
        if $verbose_flag { print $"    Repo root: ($repo_root)" }
        true
    } $verbose_flag)
    $results = ($results | append $test_path)

    let test_svc_dir = (run-test "Services directory" {
        let services_dir = (get-services-dir)
        if not ($services_dir | path exists) {
            error make {msg: $"Services directory not found: ($services_dir)"}
        }
        if $verbose_flag { print $"    Services dir: ($services_dir)" }
        true
    } $verbose_flag)
    $results = ($results | append $test_svc_dir)

    let test_ca_dir = (run-test "CA directory structure" {
        let ca_dir = (get-shared-ca-dir)
        let repo_root = (get-repo-root)
        let expected = ($repo_root | path join "tls" "certificate-authority")
        if $ca_dir != $expected {
            error make {msg: $"CA dir mismatch: expected ($expected), got ($ca_dir)"}
        }
        if $verbose_flag { print $"    CA dir: ($ca_dir)" }
        true
    } $verbose_flag)
    $results = ($results | append $test_ca_dir)

    let test_subject = (run-test "Subject string building" {
        let subject = (build-subject "test.example.com")
        if not ($subject | str contains "CN=test.example.com") {
            error make {msg: $"Subject missing CN: ($subject)"}
        }
        if $verbose_flag { print $"    Subject: ($subject)" }
        true
    } $verbose_flag)
    $results = ($results | append $test_subject)

    let test_san = (run-test "SAN config building" {
        let san_config = (build-san-config "test.example.com" ["DNS:extra.example.com"])
        if not ($san_config | str contains "DNS.1 = test.example.com") {
            error make {msg: "SAN config missing primary domain"}
        }
        if not ($san_config | str contains "subjectAltName") {
            error make {msg: "SAN config missing header"}
        }
        if $verbose_flag {
            print $"    SAN config preview:"
            print $"($san_config | lines | first 3 | str join '\n' | str replace -a '\n' '\n      ')"
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_san)

    # ------------------------------------------------------------------
    # detect-ca-requirements tests
    # ------------------------------------------------------------------

    let test_detect_cert_only = (run-test "detect-ca-requirements: cert-only mode always false/false" {
        let reqs = (detect-ca-requirements "COPY ./tls /tmp/tls-source/" "myca" "cert-only")
        if $reqs.needs_ca_crt or $reqs.needs_ca_key {
            error make {msg: "cert-only mode should never need CA files in context"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_detect_cert_only)

    let test_detect_disabled = (run-test "detect-ca-requirements: disabled TLS always false/false" {
        let reqs = (detect-ca-requirements "COPY ./tls /tmp/tls-source/" "myca" "disabled")
        if $reqs.needs_ca_crt or $reqs.needs_ca_key {
            error make {msg: "disabled mode should never need CA files"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_detect_disabled)

    let test_detect_copy_tls = (run-test "detect-ca-requirements: COPY ./tls -> needs_ca_crt=true" {
        let dockerfile = "FROM ubuntu\nCOPY ./tls /tmp/tls-source/\nRUN echo ok"
        let reqs = (detect-ca-requirements $dockerfile "dockypody-ca" "ca-and-cert")
        if not $reqs.needs_ca_crt {
            error make {msg: $"Expected needs_ca_crt=true for COPY ./tls, got: ($reqs)"}
        }
        if $reqs.needs_ca_key {
            error make {msg: $"Expected needs_ca_key=false when no .key reference, got: ($reqs)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_detect_copy_tls)

    let test_detect_copy_ca_dir = (run-test "detect-ca-requirements: COPY ./tls/certificate-authority -> needs_ca_crt=true" {
        let dockerfile = "FROM ubuntu\nCOPY ./tls/certificate-authority/ /tmp/ca-source/\nRUN echo ok"
        let reqs = (detect-ca-requirements $dockerfile "dockypody-ca" "ca-only")
        if not $reqs.needs_ca_crt {
            error make {msg: $"Expected needs_ca_crt=true, got: ($reqs)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_detect_copy_ca_dir)

    let test_detect_key_literal = (run-test "detect-ca-requirements: explicit .key ref -> needs_ca_key=true" {
        let ca = "dockypody-ca"
        let dockerfile = $"FROM ubuntu\nCOPY ./tls /tmp/tls-source/\nRUN cp \"/tmp/tls-source/certificate-authority/($ca).key\" /opt/ca.key"
        let reqs = (detect-ca-requirements $dockerfile $ca "ca-and-cert")
        if not $reqs.needs_ca_crt {
            error make {msg: "Expected needs_ca_crt=true"}
        }
        if not $reqs.needs_ca_key {
            error make {msg: "Expected needs_ca_key=true for explicit .key reference"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_detect_key_literal)

    let test_detect_no_tls_copy = (run-test "detect-ca-requirements: no tls copy -> false/false" {
        let dockerfile = "FROM ubuntu\nRUN apt-get install -y curl\nEXPOSE 8080"
        let reqs = (detect-ca-requirements $dockerfile "dockypody-ca" "ca-and-cert")
        if $reqs.needs_ca_crt or $reqs.needs_ca_key {
            error make {msg: $"Expected false/false for Dockerfile with no TLS copies, got: ($reqs)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_detect_no_tls_copy)

    let test_detect_copy_tls_slash = (run-test "detect-ca-requirements: COPY ./tls/ (trailing slash) -> needs_ca_crt=true" {
        let dockerfile = "FROM ubuntu\nCOPY ./tls/ /tmp/tls-source/\nRUN echo ok"
        let reqs = (detect-ca-requirements $dockerfile "dockypody-ca" "ca-and-cert")
        if not $reqs.needs_ca_crt {
            error make {msg: $"Expected needs_ca_crt=true for COPY ./tls/, got: ($reqs)"}
        }
        if $reqs.needs_ca_key {
            error make {msg: $"Expected needs_ca_key=false when no .key reference, got: ($reqs)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_detect_copy_tls_slash)

    let test_detect_key_var = (run-test "detect-ca-requirements: \${TLS_CA_NAME}.key var ref -> needs_ca_key=true" {
        let dockerfile = (
            "FROM mitmproxy/mitmproxy\n" +
            "COPY ./tls/certificate-authority/${TLS_CA_NAME}.crt /etc/ssl/certs/ca.crt\n" +
            "COPY ./tls/certificate-authority/${TLS_CA_NAME}.key /opt/mitm/ca.key"
        )
        let reqs = (detect-ca-requirements $dockerfile "dockypody-ca" "ca-and-cert")
        if not $reqs.needs_ca_crt {
            error make {msg: $"Expected needs_ca_crt=true for TLS_CA_NAME var .crt ref, got: ($reqs)"}
        }
        if not $reqs.needs_ca_key {
            error make {msg: $"Expected needs_ca_key=true for TLS_CA_NAME var .key ref, got: ($reqs)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_detect_key_var)

    let test_detect_crt_var_only = (run-test "detect-ca-requirements: \${TLS_CA_NAME}.crt only -> needs_ca_crt=true, needs_ca_key=false" {
        let dockerfile = (
            "FROM ubuntu\n" +
            "COPY ./tls/certificate-authority/${TLS_CA_NAME}.crt /usr/local/share/ca-certificates/custom.crt\n" +
            "RUN update-ca-certificates"
        )
        let reqs = (detect-ca-requirements $dockerfile "dockypody-ca" "ca-and-cert")
        if not $reqs.needs_ca_crt {
            error make {msg: $"Expected needs_ca_crt=true for TLS_CA_NAME var .crt ref, got: ($reqs)"}
        }
        if $reqs.needs_ca_key {
            error make {msg: $"Expected needs_ca_key=false when no .key reference, got: ($reqs)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_detect_crt_var_only)

    let test_detect_fail_closed = (run-test "detect-ca-requirements: TLS_CA_NAME without .crt/.key extension -> error" {
        let dockerfile = (
            "FROM ubuntu\n" +
            "COPY ./tls/certificate-authority/${TLS_CA_NAME} /etc/ca/"
        )
        let errored = (try {
            let _ = (detect-ca-requirements $dockerfile "dockypody-ca" "ca-and-cert")
            false
        } catch {
            true
        })
        if not $errored {
            error make {msg: "Expected error for TLS_CA_NAME reference without .crt/.key extension"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_detect_fail_closed)

    # ------------------------------------------------------------------
    # prepare-ca-context / cleanup-ca-context tests (hermetic, temp dir)
    # ------------------------------------------------------------------

    let test_prepare_no_reqs = (run-test "prepare-ca-context: no requirements -> no-op" {
        let ctx = (make-temp-context)
        let tls_meta = {enabled: true, mode: "ca-and-cert", cert_name: "svc", ca_name: "dockypody-ca"}
        let ca_reqs = {needs_ca_crt: false, needs_ca_key: false}
        let result = (prepare-ca-context $ctx $tls_meta $ca_reqs)
        rm-temp-context $ctx
        if $result.staged_dir {
            error make {msg: "Expected no staging when no requirements"}
        }
        if not ($result.files | is-empty) {
            error make {msg: "Expected empty files list"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_prepare_no_reqs)

    let test_prepare_crt_only = (run-test "prepare-ca-context: needs_ca_crt -> stages .crt, cleanup removes it" {
        # Stage fake CA cert in a temp shared ca dir structure
        let fake_repo = (^mktemp -d | str trim)
        let fake_ca_dir = ($fake_repo | path join "tls" "certificate-authority")
        mkdir $fake_ca_dir
        let ca_name = "test-ca"
        let fake_crt = ($fake_ca_dir | path join $"($ca_name).crt")
        "FAKE CA CERT CONTENT" | save -f $fake_crt

        # Use a fake build context
        let ctx = ($fake_repo | path join "ctx")
        mkdir $ctx

        # Temporarily change working dir isn't straightforward; instead, call
        # the helper with a crafted path via a thin wrapper that overrides the
        # source path. Since prepare-ca-context reads from "tls/certificate-authority/..."
        # relative to CWD, we work inside the fake_repo directory.
        let result = (do {
            cd $fake_repo
            let tls_meta = {enabled: true, mode: "ca-and-cert", cert_name: "svc", ca_name: $ca_name}
            let ca_reqs = {needs_ca_crt: true, needs_ca_key: false}
            prepare-ca-context $ctx $tls_meta $ca_reqs
        })

        # Verify the crt was staged
        let staged_crt = ($ctx | path join "tls" "certificate-authority" $"($ca_name).crt")
        if not ($staged_crt | path exists) {
            rm-temp-context $fake_repo
            error make {msg: $"Expected staged cert at ($staged_crt)"}
        }
        if $verbose_flag { print $"    Staged: ($staged_crt)" }

        # cleanup
        do {
            cd $fake_repo
            cleanup-ca-context $ctx $result
        }

        let cleaned = not ($staged_crt | path exists)
        rm-temp-context $fake_repo

        if not $cleaned {
            error make {msg: "cleanup-ca-context did not remove staged crt"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_prepare_crt_only)

    let test_prepare_crt_and_key = (run-test "prepare-ca-context: needs crt+key -> stages both, cleanup removes both" {
        let fake_repo = (^mktemp -d | str trim)
        let fake_ca_dir = ($fake_repo | path join "tls" "certificate-authority")
        mkdir $fake_ca_dir
        let ca_name = "test-ca"
        "FAKE CA CERT" | save -f ($fake_ca_dir | path join $"($ca_name).crt")
        "FAKE CA KEY" | save -f ($fake_ca_dir | path join $"($ca_name).key")

        let ctx = ($fake_repo | path join "ctx")
        mkdir $ctx

        let result = (do {
            cd $fake_repo
            let tls_meta = {enabled: true, mode: "ca-and-cert", cert_name: "svc", ca_name: $ca_name}
            let ca_reqs = {needs_ca_crt: true, needs_ca_key: true}
            prepare-ca-context $ctx $tls_meta $ca_reqs
        })

        let ctx_ca_dir = ($ctx | path join "tls" "certificate-authority")
        let staged_crt = ($ctx_ca_dir | path join $"($ca_name).crt")
        let staged_key = ($ctx_ca_dir | path join $"($ca_name).key")

        if not ($staged_crt | path exists) or not ($staged_key | path exists) {
            rm-temp-context $fake_repo
            error make {msg: "Expected both .crt and .key to be staged"}
        }

        do {
            cd $fake_repo
            cleanup-ca-context $ctx $result
        }

        let both_gone = not ($staged_crt | path exists) and not ($staged_key | path exists)
        rm-temp-context $fake_repo

        if not $both_gone {
            error make {msg: "cleanup-ca-context did not remove all staged CA files"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_prepare_crt_and_key)

    let test_cleanup_extra_file = (run-test "cleanup-ca-context: extra leftover file in CA dir -> entire dir removed" {
        let fake_repo = (^mktemp -d | str trim)
        let fake_ca_dir = ($fake_repo | path join "tls" "certificate-authority")
        mkdir $fake_ca_dir
        let ca_name = "test-ca"
        "FAKE CA CERT" | save -f ($fake_ca_dir | path join $"($ca_name).crt")

        let ctx = ($fake_repo | path join "ctx")
        mkdir $ctx

        let result = (do {
            cd $fake_repo
            let tls_meta = {enabled: true, mode: "ca-and-cert", cert_name: "svc", ca_name: $ca_name}
            let ca_reqs = {needs_ca_crt: true, needs_ca_key: false}
            prepare-ca-context $ctx $tls_meta $ca_reqs
        })

        # Inject an extra file that was NOT in the staged list
        let extra_file = ($ctx | path join "tls" "certificate-authority" "extra-leftover.txt")
        "leftover content" | save -f $extra_file

        do {
            cd $fake_repo
            cleanup-ca-context $ctx $result
        }

        let ca_dir_after = ($ctx | path join "tls" "certificate-authority")
        let dir_gone = not ($ca_dir_after | path exists)
        rm-temp-context $fake_repo

        if not $dir_gone {
            error make {msg: "cleanup-ca-context should remove entire CA dir including leftover files"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_cleanup_extra_file)

    # ------------------------------------------------------------------
    # clean-certs --service-ca-only: dry-run smoke test
    # ------------------------------------------------------------------

    let test_service_ca_only_dryrun = (run-test "clean-certs --service-ca-only: dry-run completes without error" {
        use ../lib/tls/clean.nu [clean-certs]
        # dry-run: should not touch filesystem and should not error
        clean-certs --service-ca-only --dry-run
        true
    } $verbose_flag)
    $results = ($results | append $test_service_ca_only_dryrun)

    # ------------------------------------------------------------------
    # validate-tls-config-merged common-tools dependency rule
    # ------------------------------------------------------------------

    let test_common_tools_required = (run-test "validate-tls-config-merged: TLS without common-tools dep -> error" {
        let cfg = {
            tls: {enabled: true, mode: "ca-and-cert", cert_name: "svc.crt"},
            dependencies: {}
        }
        let result = (validate-tls-config-merged $cfg "my-service")
        if $result.valid {
            error make {msg: "Expected validation failure when common-tools dep is missing"}
        }
        let has_common_tools_err = ($result.errors | any {|e| $e | str contains "common-tools"})
        if not $has_common_tools_err {
            error make {msg: $"Expected error mentioning 'common-tools', got: ($result.errors)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_common_tools_required)

    let test_common_tools_present = (run-test "validate-tls-config-merged: TLS with common-tools dep -> valid" {
        let cfg = {
            tls: {enabled: true, mode: "ca-and-cert", cert_name: "svc.crt"},
            dependencies: {
                ct: {service: "common-tools", build_arg: "COMMON_TOOLS_IMAGE"}
            }
        }
        let result = (validate-tls-config-merged $cfg "my-service")
        if not $result.valid {
            error make {msg: $"Expected validation to pass, got errors: ($result.errors)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_common_tools_present)

    let test_common_tools_self = (run-test "validate-tls-config-merged: common-tools itself skips dep check" {
        let cfg = {
            tls: {enabled: true, mode: "ca-only"},
            dependencies: {}
        }
        let result = (validate-tls-config-merged $cfg "common-tools")
        if not $result.valid {
            error make {msg: $"common-tools should not require a common-tools dep, got: ($result.errors)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_common_tools_self)

    let test_tls_disabled_no_dep_needed = (run-test "validate-tls-config-merged: TLS disabled -> no common-tools required" {
        let cfg = {
            tls: {enabled: false},
            dependencies: {}
        }
        let result = (validate-tls-config-merged $cfg "some-service")
        if not $result.valid {
            error make {msg: $"TLS-disabled service should not require common-tools, got: ($result.errors)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_tls_disabled_no_dep_needed)

    # ------------------------------------------------------------------
    # generate-ca --force behavior (hermetic via --ca-dir override)
    # ------------------------------------------------------------------

    let test_ca_skip_no_force = (run-test "generate-ca: existing CA without --force is preserved" {
        use ../lib/tls/ca.nu [generate-ca]
        let tmp = (^mktemp -d | str trim)
        let ca_name = "dockypody"
        let crt = ($tmp | path join $"($ca_name).crt")
        let key = ($tmp | path join $"($ca_name).key")
        "SENTINEL-CRT" | save -f $crt
        "SENTINEL-KEY" | save -f $key

        generate-ca --ca-dir $tmp --ca-name $ca_name

        let crt_after = (open --raw $crt | decode utf-8)
        rm-temp-context $tmp
        if not ($crt_after | str contains "SENTINEL-CRT") {
            error make {msg: "Existing CA cert should be untouched without --force"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_ca_skip_no_force)

    let test_ca_force_regen = (run-test "generate-ca --force regenerates an existing CA" {
        let openssl_ok = ((try { ^which openssl | complete | get exit_code } catch { 1 }) == 0)
        if not $openssl_ok {
            if $verbose_flag { print "    openssl not available; skipping regeneration assertion" }
            true
        } else {
            use ../lib/tls/ca.nu [generate-ca]
            let tmp = (^mktemp -d | str trim)
            let ca_name = "dockypody"
            let crt = ($tmp | path join $"($ca_name).crt")
            let key = ($tmp | path join $"($ca_name).key")
            "SENTINEL-CRT" | save -f $crt
            "SENTINEL-KEY" | save -f $key

            generate-ca --ca-dir $tmp --ca-name $ca_name --force

            let crt_after = (open --raw $crt | decode utf-8)
            rm-temp-context $tmp
            if ($crt_after | str contains "SENTINEL-CRT") {
                error make {msg: "--force should overwrite the existing CA cert"}
            }
            if not ($crt_after | str contains "BEGIN CERTIFICATE") {
                error make {msg: "Regenerated CA cert should be a real PEM certificate"}
            }
            true
        }
    } $verbose_flag)
    $results = ($results | append $test_ca_force_regen)

    let test_ca_force_preserves_on_failure = (run-test "generate-ca --force preserves existing CA when generation fails" {
        use ../lib/tls/ca.nu [generate-ca]
        let tmp = (^mktemp -d | str trim)
        let ca_name = "dockypody"
        let crt = ($tmp | path join $"($ca_name).crt")
        let key = ($tmp | path join $"($ca_name).key")
        "SENTINEL-CRT" | save -f $crt
        "SENTINEL-KEY" | save -f $key

        # Stub openssl that always fails, on a temp bin dir prepended to PATH.
        # This forces the generation step to fail deterministically without
        # depending on the real openssl behavior.
        let bin = (^mktemp -d | str trim)
        let stub = ($bin | path join "openssl")
        "#!/bin/sh\nexit 1\n" | save -f $stub
        ^chmod +x $stub

        let orig_path = ($env.PATH | default [])
        let patched_path = (if (($orig_path | describe) | str starts-with "list") {
            $orig_path | prepend $bin
        } else {
            [$bin $orig_path] | str join (char esep)
        })

        let errored = (with-env {PATH: $patched_path} {
            try {
                generate-ca --ca-dir $tmp --ca-name $ca_name --force
                false
            } catch {
                true
            }
        })

        let crt_after = (open --raw $crt | decode utf-8)
        let key_after = (open --raw $key | decode utf-8)
        let tmp_key_leftover = (($tmp | path join $"($ca_name).key.tmp") | path exists)
        let tmp_crt_leftover = (($tmp | path join $"($ca_name).crt.tmp") | path exists)
        rm-temp-context $tmp
        rm-temp-context $bin

        if not $errored {
            error make {msg: "Expected generate-ca to error when openssl fails"}
        }
        if not ($crt_after | str contains "SENTINEL-CRT") {
            error make {msg: "Existing CA cert must be preserved when --force regeneration fails"}
        }
        if not ($key_after | str contains "SENTINEL-KEY") {
            error make {msg: "Existing CA key must be preserved when --force regeneration fails"}
        }
        if $tmp_key_leftover or $tmp_crt_leftover {
            error make {msg: "Temp CA artifacts should be cleaned up after a failed regeneration"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_ca_force_preserves_on_failure)

    # ------------------------------------------------------------------
    # validate-ca: TLS disabled is a no-op
    # ------------------------------------------------------------------

    let test_va_disabled = (run-test "validate-ca: TLS disabled is a no-op" {
        validate-ca "some-service" {tls: {enabled: false}} "any-ca"
        true
    } $verbose_flag)
    $results = ($results | append $test_va_disabled)

    # ------------------------------------------------------------------
    # validate-ca: empty ca_name with TLS enabled -> error
    # ------------------------------------------------------------------

    let test_va_empty_ca = (run-test "validate-ca: TLS enabled but empty ca_name -> error" {
        let errored = (try {
            validate-ca "some-service" {tls: {enabled: true, mode: "ca-only"}} ""
            false
        } catch { true })
        if not $errored {
            error make {msg: "Expected error for empty ca_name with TLS enabled"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_va_empty_ca)

    # ------------------------------------------------------------------
    # validate-ca: ca-only mode but CA cert file missing -> error
    # ------------------------------------------------------------------

    let test_va_missing_ca = (run-test "validate-ca: ca-only mode missing CA cert -> error" {
        let fake_repo = (^mktemp -d | str trim)
        let ca_dir = ($fake_repo | path join "tls" "certificate-authority")
        mkdir $ca_dir
        # Intentionally do not create the .crt file

        let errored = (do {
            cd $fake_repo
            try {
                validate-ca "my-svc" {tls: {enabled: true, mode: "ca-only"}} "test-ca"
                false
            } catch { true }
        })
        rm-temp-context $fake_repo
        if not $errored {
            error make {msg: "Expected error when CA cert file is missing"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_va_missing_ca)

    # ------------------------------------------------------------------
    # validate-ca: ca-only mode with CA cert present -> ok (no cert_name needed)
    # ------------------------------------------------------------------

    let test_va_ca_only_ok = (run-test "validate-ca: ca-only mode with present CA cert -> ok" {
        let fake_repo = (^mktemp -d | str trim)
        let ca_dir = ($fake_repo | path join "tls" "certificate-authority")
        mkdir $ca_dir

        # Write a fake PEM-like cert so the path-exists check passes
        let ca_name = "test-ca"
        "-----BEGIN CERTIFICATE-----\nFAKE\n-----END CERTIFICATE-----\n" | save -f ($ca_dir | path join $"($ca_name).crt")

        let ok = (do {
            cd $fake_repo
            try {
                validate-ca "my-svc" {tls: {enabled: true, mode: "ca-only"}} $ca_name
                true
            } catch {
                false
            }
        })
        rm-temp-context $fake_repo
        if not $ok {
            error make {msg: "Expected validate-ca to succeed for ca-only mode with present CA cert"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_va_ca_only_ok)

    # ------------------------------------------------------------------
    # validate-ca: ca-and-cert mode missing CA cert -> error
    # ------------------------------------------------------------------

    let test_va_ca_and_cert_no_ca = (run-test "validate-ca: ca-and-cert mode missing CA cert -> error" {
        let fake_repo = (^mktemp -d | str trim)
        let ca_dir = ($fake_repo | path join "tls" "certificate-authority")
        mkdir $ca_dir
        # No .crt file

        let errored = (do {
            cd $fake_repo
            try {
                validate-ca "my-svc" {tls: {enabled: true, mode: "ca-and-cert", cert_name: "svc"}} "test-ca"
                false
            } catch { true }
        })
        rm-temp-context $fake_repo
        if not $errored {
            error make {msg: "Expected error for ca-and-cert with missing CA cert"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_va_ca_and_cert_no_ca)

    # ------------------------------------------------------------------
    # validate-ca: ca-and-cert mode with CA cert but missing service cert -> error
    # ------------------------------------------------------------------

    let test_va_ca_and_cert_no_service_cert = (run-test "validate-ca: ca-and-cert mode CA present but service cert missing -> error" {
        let fake_repo = (^mktemp -d | str trim)
        let ca_dir = ($fake_repo | path join "tls" "certificate-authority")
        mkdir $ca_dir
        "FAKE CA CERT" | save -f ($ca_dir | path join "test-ca.crt")
        # No service cert

        let errored = (do {
            cd $fake_repo
            try {
                validate-ca "my-svc" {tls: {enabled: true, mode: "ca-and-cert", cert_name: "svc"}} "test-ca"
                false
            } catch { true }
        })
        rm-temp-context $fake_repo
        if not $errored {
            error make {msg: "Expected error for ca-and-cert with missing service cert"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_va_ca_and_cert_no_service_cert)

    # ------------------------------------------------------------------
    # validate-ca: cert-only mode with missing service cert -> error
    # ------------------------------------------------------------------

    let test_va_cert_only_missing = (run-test "validate-ca: cert-only mode missing service cert -> error" {
        let fake_repo = (^mktemp -d | str trim)
        # No services dir, no certs

        let errored = (do {
            cd $fake_repo
            try {
                validate-ca "my-svc" {tls: {enabled: true, mode: "cert-only", cert_name: "svc"}} "test-ca"
                false
            } catch { true }
        })
        rm-temp-context $fake_repo
        if not $errored {
            error make {msg: "Expected error for cert-only with missing service cert"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_va_cert_only_missing)

    # ------------------------------------------------------------------
    # cert-matches-ca: missing files -> false (openssl fails gracefully)
    # ------------------------------------------------------------------

    let test_cm_missing_files = (run-test "cert-matches-ca: non-existent files -> false" {
        let result = (cert-matches-ca "/tmp/__nonexistent__.crt" "/tmp/__nonexistent_ca__.crt")
        if $result {
            error make {msg: "cert-matches-ca should return false for non-existent files"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_cm_missing_files)

    # ------------------------------------------------------------------
    # cert-matches-ca: mismatched and matching certs (openssl-conditional)
    # ------------------------------------------------------------------

    let test_cm_certs = (run-test "cert-matches-ca: mismatched issuer/subject -> false, self-signed -> true" {
        let openssl_ok = ((try { ^which openssl | complete | get exit_code } catch { 1 }) == 0)
        if not $openssl_ok {
            if $verbose_flag { print "    openssl not available; skipping cert-matches-ca cert test" }
            true
        } else {
            let tmp = (^mktemp -d | str trim)
            let ca1_crt = ($tmp | path join "ca1.crt")
            let ca1_key = ($tmp | path join "ca1.key")
            let ca2_crt = ($tmp | path join "ca2.crt")
            let ca2_key = ($tmp | path join "ca2.key")

            let r1 = (^openssl req -newkey rsa:2048 -days 1 -nodes -x509 -subj "/CN=TestCA1ForDockyPody" -out $ca1_crt -keyout $ca1_key | complete)
            let r2 = (^openssl req -newkey rsa:2048 -days 1 -nodes -x509 -subj "/CN=TestCA2ForDockyPody" -out $ca2_crt -keyout $ca2_key | complete)

            if $r1.exit_code != 0 or $r2.exit_code != 0 {
                rm-temp-context $tmp
                if $verbose_flag { print "    openssl cert generation failed; skipping" }
                true
            } else {
                let mismatched = (cert-matches-ca $ca1_crt $ca2_crt)
                let self_signed = (cert-matches-ca $ca1_crt $ca1_crt)
                rm-temp-context $tmp

                if $mismatched {
                    error make {msg: "cert-matches-ca should return false for mismatched issuer/subject"}
                }
                if not $self_signed {
                    error make {msg: "cert-matches-ca should return true for self-signed cert against itself"}
                }
                true
            }
        }
    } $verbose_flag)
    $results = ($results | append $test_cm_certs)

    # ------------------------------------------------------------------
    # cert-matches-ca: malformed cert content -> false (parse failure path)
    # Files exist on disk but contain non-PEM garbage; openssl fails to
    # parse them, get-cert-issuer/get-ca-subject both return "", and
    # cert-matches-ca returns false without propagating an error.
    # ------------------------------------------------------------------

    let test_cm_malformed = (run-test "cert-matches-ca: malformed cert content -> false" {
        let tmp = (^mktemp -d | str trim)
        let bad_cert = ($tmp | path join "bad.crt")
        let bad_ca = ($tmp | path join "bad-ca.crt")
        "THIS IS NOT VALID PEM CONTENT" | save -f $bad_cert
        "ALSO INVALID PEM MATERIAL" | save -f $bad_ca
        let result = (cert-matches-ca $bad_cert $bad_ca)
        rm-temp-context $tmp
        if $result {
            error make {msg: "cert-matches-ca should return false for malformed cert content"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_cm_malformed)

    # ------------------------------------------------------------------
    # validate-ca: malformed shared/service cert material -> rejected
    # Both files exist so path-exists checks pass, but openssl cannot
    # parse them; cert-matches-ca returns false and validate-ca errors.
    # ------------------------------------------------------------------

    let test_va_malformed_certs = (run-test "validate-ca: malformed shared and service cert -> rejected" {
        let fake_repo = (^mktemp -d | str trim)
        let ca_dir = ($fake_repo | path join "tls" "certificate-authority")
        let svc_dir = ($fake_repo | path join "services" "my-svc" "tls" "certificates")
        mkdir $ca_dir
        mkdir $svc_dir
        "NOT VALID CA PEM" | save -f ($ca_dir | path join "test-ca.crt")
        "NOT VALID SERVICE PEM" | save -f ($svc_dir | path join "svc.crt")

        let errored = (do {
            cd $fake_repo
            try {
                validate-ca "my-svc" {tls: {enabled: true, mode: "ca-and-cert", cert_name: "svc"}} "test-ca"
                false
            } catch { true }
        })
        rm-temp-context $fake_repo
        if not $errored {
            error make {msg: "validate-ca should reject malformed cert material that cannot match CA"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_va_malformed_certs)

    # ------------------------------------------------------------------
    # copy-tls: permission finalization and runtime-owner
    # ------------------------------------------------------------------

    let test_copy_tls_modes = (run-test "copy-tls: no runtime-owner -> key 0600, crt 0644, no chown" {
        let src = (^mktemp -d | str trim)
        let dest = (^mktemp -d | str trim)
        let cert_dir = ($src | path join "certificates")
        mkdir $cert_dir
        "FAKE CRT" | save -f ($cert_dir | path join "svc.crt")
        "FAKE KEY" | save -f ($cert_dir | path join "svc.key")

        let expected_owner = $"((^id -u | str trim)):((^id -g | str trim))"
        copy-tls --enabled "true" --mode "ca-and-cert" --ca-name "dockypody" --cert-name "svc" --source-certs $"($cert_dir)/" --dest $"($dest)/"

        let dest_key = ($dest | path join "svc.key")
        let dest_crt = ($dest | path join "svc.crt")
        let key_owner = (^stat -c '%u:%g' $dest_key | str trim)
        let crt_owner = (^stat -c '%u:%g' $dest_crt | str trim)
        let key_mode = (^stat -c '%a' $dest_key | str trim)
        let crt_mode = (^stat -c '%a' $dest_crt | str trim)
        rm-temp-context $src
        rm-temp-context $dest

        if $key_owner != $expected_owner {
            error make {msg: $"Without runtime-owner, key should stay ($expected_owner), got ($key_owner)"}
        }
        if $crt_owner != $expected_owner {
            error make {msg: $"Without runtime-owner, crt should stay ($expected_owner), got ($crt_owner)"}
        }
        if $key_mode != "600" {
            error make {msg: $"Expected key mode 600, got ($key_mode)"}
        }
        if $crt_mode != "644" {
            error make {msg: $"Expected crt mode 644, got ($crt_mode)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_copy_tls_modes)

    let test_copy_tls_owner = (run-test "copy-tls: runtime-owner set to current user -> chown succeeds, ownership matches, modes correct" {
        let src = (^mktemp -d | str trim)
        let dest = (^mktemp -d | str trim)
        let cert_dir = ($src | path join "certificates")
        mkdir $cert_dir
        "FAKE CRT" | save -f ($cert_dir | path join "svc.crt")
        "FAKE KEY" | save -f ($cert_dir | path join "svc.key")

        let owner = $"((^id -u | str trim)):((^id -g | str trim))"
        copy-tls --enabled "true" --mode "ca-and-cert" --ca-name "dockypody" --cert-name "svc" --source-certs $"($cert_dir)/" --dest $"($dest)/" --runtime-owner $owner

        let dest_key = ($dest | path join "svc.key")
        let dest_crt = ($dest | path join "svc.crt")
        let key_owner = (^stat -c '%u:%g' $dest_key | str trim)
        let key_mode = (^stat -c '%a' $dest_key | str trim)
        let crt_mode = (^stat -c '%a' $dest_crt | str trim)
        rm-temp-context $src
        rm-temp-context $dest

        if $key_owner != $owner {
            error make {msg: $"Expected owner ($owner), got ($key_owner)"}
        }
        if $key_mode != "600" {
            error make {msg: $"Expected key mode 600, got ($key_mode)"}
        }
        if $crt_mode != "644" {
            error make {msg: $"Expected crt mode 644, got ($crt_mode)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_copy_tls_owner)

    let test_copy_tls_quoted_owner = (run-test "copy-tls: Docker-style quoted runtime-owner is normalized" {
        let src = (^mktemp -d | str trim)
        let dest = (^mktemp -d | str trim)
        let cert_dir = ($src | path join "certificates")
        mkdir $cert_dir
        "FAKE CRT" | save -f ($cert_dir | path join "svc.crt")
        "FAKE KEY" | save -f ($cert_dir | path join "svc.key")

        let owner = $"((^id -u | str trim)):((^id -g | str trim))"
        let quoted_owner = $"'($owner)'"
        copy-tls --enabled "true" --mode "ca-and-cert" --ca-name "dockypody" --cert-name "svc" --source-certs $"($cert_dir)/" --dest $"($dest)/" --runtime-owner $quoted_owner

        let dest_key = ($dest | path join "svc.key")
        let dest_crt = ($dest | path join "svc.crt")
        let key_owner = (^stat -c '%u:%g' $dest_key | str trim)
        let key_mode = (^stat -c '%a' $dest_key | str trim)
        let crt_mode = (^stat -c '%a' $dest_crt | str trim)
        rm-temp-context $src
        rm-temp-context $dest

        if $key_owner != $owner {
            error make {msg: $"Quoted owner ($quoted_owner) should normalize to ($owner), got ($key_owner)"}
        }
        if $key_mode != "600" {
            error make {msg: $"Expected key mode 600, got ($key_mode)"}
        }
        if $crt_mode != "644" {
            error make {msg: $"Expected crt mode 644, got ($crt_mode)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_copy_tls_quoted_owner)

    let test_copy_tls_main_subprocess = (run-test "copy.nu main: subprocess with Docker-style quoted user:group runtime-owner" {
        let src = (^mktemp -d | str trim)
        let dest = (^mktemp -d | str trim)
        let cert_dir = ($src | path join "certificates")
        mkdir $cert_dir
        "FAKE CRT" | save -f ($cert_dir | path join "svc.crt")
        "FAKE KEY" | save -f ($cert_dir | path join "svc.key")

        let user_group = $"((^id -un | str trim)):((^id -gn | str trim))"
        let quoted_owner = $"'($user_group)'"
        let copy_script = (get-repo-root | path join "scripts" "lib" "tls" "copy.nu")
        let result = (
            ^nu $copy_script
                --enabled "'true'"
                --mode "'ca-and-cert'"
                --ca-name "'dockypody'"
                --cert-name "'svc'"
                --source-certs $"($cert_dir)/"
                --dest $"($dest)/"
                --runtime-owner $quoted_owner
            | complete
        )

        if $result.exit_code != 0 {
            rm-temp-context $src
            rm-temp-context $dest
            error make {msg: $"copy.nu subprocess failed (exit ($result.exit_code)): ($result.stderr)"}
        }

        let dest_key = ($dest | path join "svc.key")
        let dest_crt = ($dest | path join "svc.crt")
        let key_owner = (^stat -c '%U:%G' $dest_key | str trim)
        let crt_owner = (^stat -c '%U:%G' $dest_crt | str trim)
        let key_mode = (^stat -c '%a' $dest_key | str trim)
        let crt_mode = (^stat -c '%a' $dest_crt | str trim)
        rm-temp-context $src
        rm-temp-context $dest

        if $key_owner != $user_group {
            error make {msg: $"Expected key owner ($user_group), got ($key_owner)"}
        }
        if $crt_owner != $user_group {
            error make {msg: $"Expected crt owner ($user_group), got ($crt_owner)"}
        }
        if $key_mode != "600" {
            error make {msg: $"Expected key mode 600, got ($key_mode)"}
        }
        if $crt_mode != "644" {
            error make {msg: $"Expected crt mode 644, got ($crt_mode)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_copy_tls_main_subprocess)

    let test_dockerfile_runtime_owner = (run-test "Dockerfile drift: copy-tls services use expected --runtime-owner and no inline /tls chown" {
        let repo_root = (get-repo-root)
        let dockerfile_contracts = [
            {path: "services/idp/Dockerfile", runtime_owner: "--runtime-owner \"'1000:1000'\""}
            {path: "services/ocis/Dockerfile.alpine", runtime_owner: "--runtime-owner \"'1000:1000'\""}
            {path: "services/opencloud/Dockerfile.alpine", runtime_owner: "--runtime-owner \"'1000:1000'\""}
            {path: "services/cernbox-web/Dockerfile", runtime_owner: "--runtime-owner \"'nginx:nginx'\""}
        ]
        for contract in $dockerfile_contracts {
            let df = $contract.path
            let path = ($repo_root | path join $df)
            if not ($path | path exists) {
                error make {msg: $"Dockerfile not found: ($path)"}
            }
            let content = (open --raw $path | decode utf-8)
            if not ($content | str contains $contract.runtime_owner) {
                error make {msg: $"($df): expected exact ($contract.runtime_owner) in copy-tls invocation"}
            }
            let stale = (find-stale-inline-tls-chown $content)
            if not ($stale | is-empty) {
                error make {msg: $"($df): stale inline chown targeting /tls must be removed: ($stale | first | str trim)"}
            }
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_dockerfile_runtime_owner)

    print-test-summary $results

    if ($results | any {|r| not $r}) {
        exit 1
    }
}
