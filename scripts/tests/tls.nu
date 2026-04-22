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

    print-test-summary $results

    if ($results | any {|r| not $r}) {
        exit 1
    }
}
