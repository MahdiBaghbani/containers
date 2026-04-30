#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images

# oCIS entrypoint bootstrap hook tests
#
# The entrypoint-init.nu script uses absolute container paths in its `use`
# statements (/usr/bin/lib/...) so it cannot be imported directly. Tests here
# use two complementary strategies:
#
#   1. Contract tests - open the source file and assert expected patterns.
#   2. Unit tests for password resolution - replicate the pure helper logic
#      locally to verify the four-level precedence without needing the binary.

use ../../../scripts/tests/lib.nu [run-test print-test-summary]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Mirror of resolve-ocis-admin-password from entrypoint-init.nu.
# OCIS_ADMIN_PASSWORD -> ADMIN_PASSWORD -> IDM_ADMIN_PASSWORD -> "admin"
def resolve-password-under-test [env_snapshot: record] {
    let p1 = ($env_snapshot.OCIS_ADMIN_PASSWORD? | default "" | str trim)
    if not ($p1 | is-empty) { return $p1 }
    let p2 = ($env_snapshot.ADMIN_PASSWORD? | default "" | str trim)
    if not ($p2 | is-empty) { return $p2 }
    let p3 = ($env_snapshot.IDM_ADMIN_PASSWORD? | default "" | str trim)
    if not ($p3 | is-empty) { return $p3 }
    "admin"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    let src = ($env.CURRENT_FILE | path dirname | path join ".." "scripts" "entrypoint-init.nu")

    # ------------------------------------------------------------------
    # Contract tests: source structure
    # ------------------------------------------------------------------

    let t1 = (run-test "entrypoint-init: OCIS_INIT flag present" {
        let content = (open --raw $src)
        if not ($content | str contains "OCIS_INIT") {
            error make {msg: "OCIS_INIT not found in entrypoint-init.nu"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t1)

    let t2 = (run-test "entrypoint-init: DOCKYPODY_OCIS_INIT removed" {
        let content = (open --raw $src)
        if ($content | str contains "DOCKYPODY_OCIS_INIT") {
            error make {msg: "DOCKYPODY_OCIS_INIT must not appear in entrypoint-init.nu after rename"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t2)

    let t3 = (run-test "entrypoint-init: ocis init --insecure true present" {
        let content = (open --raw $src)
        if not ($content | str contains "ocis init --insecure true") {
            error make {msg: "ocis init --insecure true not found in entrypoint-init.nu"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t3)

    let t4 = (run-test "entrypoint-init: OCIS_ADMIN_PASSWORD present" {
        let content = (open --raw $src)
        if not ($content | str contains "OCIS_ADMIN_PASSWORD") {
            error make {msg: "OCIS_ADMIN_PASSWORD not found in entrypoint-init.nu"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t4)

    let t5 = (run-test "entrypoint-init: IDM_ADMIN_PASSWORD present as upstream fallback" {
        let content = (open --raw $src)
        if not ($content | str contains "IDM_ADMIN_PASSWORD") {
            error make {msg: "IDM_ADMIN_PASSWORD fallback not found in entrypoint-init.nu"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t5)

    let t6 = (run-test "entrypoint-init: maybe-bootstrap-ocis called in main body" {
        let content = (open --raw $src)
        let parts = ($content | split row "def --wrapped main [...args]")
        if ($parts | length) < 2 {
            error make {msg: "def --wrapped main not found in entrypoint-init.nu"}
        }
        let main_body = ($parts | last)
        if not ($main_body | str contains "\n    maybe-bootstrap-ocis\n") {
            error make {msg: "maybe-bootstrap-ocis call line not found in main body"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t6)

    let t7 = (run-test "entrypoint-init: chown appears after maybe-bootstrap-ocis" {
        let content = (open --raw $src)
        let bootstrap_pos = ($content | str index-of "maybe-bootstrap-ocis")
        let chown_pos = ($content | str index-of "chown -R 1000:1000")
        if $bootstrap_pos < 0 {
            error make {msg: "maybe-bootstrap-ocis not found"}
        }
        if $chown_pos < 0 {
            error make {msg: "chown -R 1000:1000 not found"}
        }
        if $bootstrap_pos > $chown_pos {
            error make {msg: "maybe-bootstrap-ocis must appear before chown in main"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t7)

    let t8 = (run-test "entrypoint-init: uses service-local ocmproviders at /usr/bin/lib/ocmproviders.nu" {
        let content = (open --raw $src)
        if not ($content | str contains "/usr/bin/lib/ocmproviders.nu") {
            error make {msg: "/usr/bin/lib/ocmproviders.nu import not found"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t8)

    let t9 = (run-test "entrypoint-init: explicit provider file path validated (path exists check present)" {
        let content = (open --raw $src)
        let parts = ($content | split row "OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE")
        if ($parts | length) < 2 {
            error make {msg: "OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE not found in entrypoint-init.nu"}
        }
        let after_var = ($parts | get 1)
        if not ($after_var | str contains "path exists") {
            error make {msg: "path exists check not found after OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t9)

    let t10 = (run-test "entrypoint-init: explicit provider file missing emits error make" {
        let content = (open --raw $src)
        # error make is in the message string which also contains the var name, so
        # gather all text after the first occurrence of the var before checking.
        let parts = ($content | split row "OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE")
        if ($parts | length) < 2 {
            error make {msg: "OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE not found"}
        }
        let after_first = ($parts | skip 1 | str join "")
        if not ($after_first | str contains "error make") {
            error make {msg: "error make not found after OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t10)

    let t11 = (run-test "entrypoint-init: warning string has no bare (ignored) command-substitution" {
        let content = (open --raw $src)
        # Bare (ignored) inside $"..." is parsed as a command call; must not appear.
        if ($content | str contains "failed (ignored)") {
            error make {msg: "Footgun: 'failed (ignored)' found in interpolated string - (ignored) would be run as a command"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t11)

    let t12 = (run-test "entrypoint-init: OCIS_CONFIG_FILE constant declared for idempotence check" {
        let content = (open --raw $src)
        if not ($content | str contains "OCIS_CONFIG_FILE") {
            error make {msg: "OCIS_CONFIG_FILE constant not found in entrypoint-init.nu"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t12)

    let t13 = (run-test "entrypoint-init: idempotence path exists check present in maybe-bootstrap-ocis" {
        let content = (open --raw $src)
        # Split on the function definition to check its body only.
        let parts = ($content | split row "def maybe-bootstrap-ocis")
        if ($parts | length) < 2 {
            error make {msg: "maybe-bootstrap-ocis not found in entrypoint-init.nu"}
        }
        let fn_body = ($parts | get 1)
        if not ($fn_body | str contains "OCIS_CONFIG_FILE | path exists") {
            error make {msg: "Idempotence guard 'OCIS_CONFIG_FILE | path exists' not found in maybe-bootstrap-ocis"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t13)

    let t14 = (run-test "entrypoint-init: skipping init message present for idempotence path" {
        let content = (open --raw $src)
        if not ($content | str contains "skipping init") {
            error make {msg: "Idempotence skip message 'skipping init' not found in entrypoint-init.nu"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t14)

    # ------------------------------------------------------------------
    # Unit tests: password resolution precedence
    # ------------------------------------------------------------------

    let t11 = (run-test "resolve-ocis-admin-password: OCIS_ADMIN_PASSWORD wins" {
        let snap = {OCIS_ADMIN_PASSWORD: "secret1"}
        let pw = (resolve-password-under-test $snap)
        if $pw != "secret1" {
            error make {msg: $"Expected 'secret1', got '($pw)'"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t11)

    let t12 = (run-test "resolve-ocis-admin-password: ADMIN_PASSWORD fallback when OCIS absent" {
        let snap = {ADMIN_PASSWORD: "fallback1"}
        let pw = (resolve-password-under-test $snap)
        if $pw != "fallback1" {
            error make {msg: $"Expected 'fallback1', got '($pw)'"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t12)

    let t13 = (run-test "resolve-ocis-admin-password: IDM_ADMIN_PASSWORD fallback when OCIS and ADMIN absent" {
        let snap = {IDM_ADMIN_PASSWORD: "idmpass"}
        let pw = (resolve-password-under-test $snap)
        if $pw != "idmpass" {
            error make {msg: $"Expected 'idmpass', got '($pw)'"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t13)

    let t14 = (run-test "resolve-ocis-admin-password: OCIS_ADMIN_PASSWORD beats ADMIN_PASSWORD" {
        let snap = {OCIS_ADMIN_PASSWORD: "primary", ADMIN_PASSWORD: "secondary"}
        let pw = (resolve-password-under-test $snap)
        if $pw != "primary" {
            error make {msg: $"Expected 'primary', got '($pw)'"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t14)

    let t15 = (run-test "resolve-ocis-admin-password: defaults to 'admin' when all absent" {
        let snap = {}
        let pw = (resolve-password-under-test $snap)
        if $pw != "admin" {
            error make {msg: $"Expected 'admin', got '($pw)'"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t15)

    let t16 = (run-test "resolve-ocis-admin-password: empty OCIS falls through to ADMIN_PASSWORD" {
        let snap = {OCIS_ADMIN_PASSWORD: "", ADMIN_PASSWORD: "fallback1"}
        let pw = (resolve-password-under-test $snap)
        if $pw != "fallback1" {
            error make {msg: $"Expected 'fallback1', got '($pw)'"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t16)

    let t17 = (run-test "resolve-ocis-admin-password: whitespace-only OCIS falls through to ADMIN_PASSWORD" {
        let snap = {OCIS_ADMIN_PASSWORD: "   ", ADMIN_PASSWORD: "fallback1"}
        let pw = (resolve-password-under-test $snap)
        if $pw != "fallback1" {
            error make {msg: $"Expected 'fallback1' for whitespace-only OCIS_ADMIN_PASSWORD, got '($pw)'"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t17)

    let t18 = (run-test "resolve-ocis-admin-password: empty OCIS and ADMIN fall through to IDM_ADMIN_PASSWORD" {
        let snap = {OCIS_ADMIN_PASSWORD: "", ADMIN_PASSWORD: "", IDM_ADMIN_PASSWORD: "idmpass"}
        let pw = (resolve-password-under-test $snap)
        if $pw != "idmpass" {
            error make {msg: $"Expected 'idmpass', got '($pw)'"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t18)

    let t19 = (run-test "resolve-ocis-admin-password: all empty falls through to 'admin'" {
        let snap = {OCIS_ADMIN_PASSWORD: "", ADMIN_PASSWORD: "", IDM_ADMIN_PASSWORD: ""}
        let pw = (resolve-password-under-test $snap)
        if $pw != "admin" {
            error make {msg: $"Expected 'admin', got '($pw)'"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t19)

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------

    print-test-summary $results
    let failed = ($results | where {|r| not $r} | length)
    if $failed > 0 {
        exit 1
    }
}
