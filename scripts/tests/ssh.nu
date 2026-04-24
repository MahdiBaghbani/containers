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

# SSH access configuration and build context tests

use ../lib/core/repo.nu [get-repo-root]
use ../lib/validate/ssh.nu [
    validate-ssh-config validate-version-overrides-ssh validate-platform-ssh
    validate-ssh-config-merged
]
use ../lib/build/context.nu [extract-ssh-metadata prepare-ssh-context cleanup-ssh-context]
use ./lib.nu [run-test print-test-summary]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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
    # validate-ssh-config tests
    # ------------------------------------------------------------------

    let test_valid_disabled = (run-test "validate-ssh-config: disabled mode valid" {
        let config = { enabled: false, mode: "disabled", default_user: "root", port: 22 }
        validate-ssh-config $config "test-service"
        true
    } $verbose_flag)
    $results = ($results | append $test_valid_disabled)

    let test_valid_client = (run-test "validate-ssh-config: client mode valid" {
        let config = { enabled: true, mode: "client", default_user: "root", port: 22 }
        validate-ssh-config $config "test-service"
        true
    } $verbose_flag)
    $results = ($results | append $test_valid_client)

    let test_valid_server = (run-test "validate-ssh-config: server mode valid" {
        let config = { enabled: true, mode: "server", default_user: "root", port: 22 }
        validate-ssh-config $config "test-service"
        true
    } $verbose_flag)
    $results = ($results | append $test_valid_server)

    let test_valid_both = (run-test "validate-ssh-config: client-and-server mode valid" {
        let config = { enabled: true, mode: "client-and-server", default_user: "root", port: 22 }
        validate-ssh-config $config "test-service"
        true
    } $verbose_flag)
    $results = ($results | append $test_valid_both)

    let test_invalid_mode = (run-test "validate-ssh-config: invalid mode rejected" {
        let config = { enabled: true, mode: "invalid", default_user: "root", port: 22 }
        let result = (validate-ssh-config $config "test-service")
        if $result.valid {
            error make {msg: "Expected validation to fail for invalid SSH mode"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_invalid_mode)

    let test_invalid_port = (run-test "validate-ssh-config: invalid port rejected" {
        let config = { enabled: true, mode: "server", default_user: "root", port: 99999 }
        let result = (validate-ssh-config $config "test-service")
        if $result.valid {
            error make {msg: "Expected validation to fail for invalid SSH port"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_invalid_port)

    let test_missing_mode = (run-test "validate-ssh-config: missing mode when enabled rejected" {
        let config = { enabled: true, default_user: "root", port: 22 }
        let result = (validate-ssh-config $config "test-service")
        if $result.valid {
            error make {msg: "Expected validation to fail for missing mode when enabled"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_missing_mode)

    # ------------------------------------------------------------------
    # validate-ssh-config-merged tests
    # ------------------------------------------------------------------

    let test_merged_valid = (run-test "validate-ssh-config-merged: valid merged config" {
        let merged = { ssh: { enabled: true, mode: "server", default_user: "root", port: 22 } }
        validate-ssh-config-merged $merged "test-service"
        true
    } $verbose_flag)
    $results = ($results | append $test_merged_valid)

    let test_merged_disabled = (run-test "validate-ssh-config-merged: disabled SSH valid" {
        let merged = { ssh: { enabled: false, mode: "disabled", default_user: "root", port: 22 } }
        validate-ssh-config-merged $merged "test-service"
        true
    } $verbose_flag)
    $results = ($results | append $test_merged_disabled)

    let test_merged_invalid = (run-test "validate-ssh-config-merged: invalid merged config rejected" {
        let merged = { ssh: { enabled: true, mode: "bad-mode", default_user: "root", port: 22 } }
        let result = (validate-ssh-config-merged $merged "test-service")
        if $result.valid {
            error make {msg: "Expected validation to fail for invalid merged SSH config"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_merged_invalid)

    # ------------------------------------------------------------------
    # extract-ssh-metadata tests
    # ------------------------------------------------------------------

    let test_extract_disabled = (run-test "extract-ssh-metadata: disabled returns defaults" {
        let merged = { ssh: { enabled: false, mode: "disabled", default_user: "root", port: 22 } }
        let meta = (extract-ssh-metadata $merged)
        if $meta.enabled != false {
            error make {msg: "Expected enabled=false"}
        }
        if $meta.mode != "disabled" {
            error make {msg: "Expected mode=disabled"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_extract_disabled)

    let test_extract_server = (run-test "extract-ssh-metadata: server mode extracts correctly" {
        let merged = { ssh: { enabled: true, mode: "server", default_user: "admin", port: 2222 } }
        let meta = (extract-ssh-metadata $merged)
        if $meta.enabled != true {
            error make {msg: "Expected enabled=true"}
        }
        if $meta.mode != "server" {
            error make {msg: "Expected mode=server"}
        }
        if $meta.default_user != "admin" {
            error make {msg: "Expected default_user=admin"}
        }
        if $meta.port != 2222 {
            error make {msg: "Expected port=2222"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_extract_server)

    # ------------------------------------------------------------------
    # prepare-ssh-context / cleanup-ssh-context tests
    # ------------------------------------------------------------------

    let test_prepare_disabled = (run-test "prepare-ssh-context: disabled -> dir created, no files" {
        let ctx = (make-temp-context)
        let result = (prepare-ssh-context "test-service" $ctx false "disabled")
        if not $result.dir_created {
            rm-temp-context $ctx
            error make {msg: "Expected dir_created=true for disabled SSH (directory always created)"}
        }
        if $result.copied {
            rm-temp-context $ctx
            error make {msg: "Expected copied=false for disabled SSH"}
        }
        if not ($result.files | is-empty) {
            rm-temp-context $ctx
            error make {msg: "Expected empty files list for disabled SSH"}
        }
        let ssh_dir = ($ctx | path join "ssh")
        if not ($ssh_dir | path exists) {
            rm-temp-context $ctx
            error make {msg: "Expected ssh dir to exist even when SSH disabled"}
        }
        rm-temp-context $ctx
        true
    } $verbose_flag)
    $results = ($results | append $test_prepare_disabled)

    let test_prepare_server = (run-test "prepare-ssh-context: server mode -> public key staged, private key NOT staged" {
        let fake_repo = (^mktemp -d | str trim)
        let fake_ssh_dir = ($fake_repo | path join "ssh")
        mkdir $fake_ssh_dir
        # ssh.json SSOT drives key_name; key files must match.
        '{"key_name":"dockypody","comment":"docky@pody","default_user":"root"}' | save -f ($fake_ssh_dir | path join "ssh.json")
        let fake_key = ($fake_ssh_dir | path join "dockypody")
        let fake_pub = ($fake_ssh_dir | path join "dockypody.pub")
        "FAKE PRIVATE KEY" | save -f $fake_key
        "FAKE PUBLIC KEY" | save -f $fake_pub

        # Provide the shared sshd module required by prepare-ssh-context.
        let sshd_mod_dir = ($fake_repo | path join "scripts" "lib" "ssh")
        mkdir $sshd_mod_dir
        "# fake sshd module" | save -f ($sshd_mod_dir | path join "sshd.nu")

        let ctx = ($fake_repo | path join "ctx")
        mkdir $ctx

        let result = (do {
            cd $fake_repo
            prepare-ssh-context "test-service" $ctx true "server"
        })

        if not $result.dir_created {
            rm-temp-context $fake_repo
            error make {msg: "Expected dir_created=true when SSH enabled"}
        }

        let ssh_dir = ($ctx | path join "ssh")
        if not ($ssh_dir | path exists) {
            rm-temp-context $fake_repo
            error make {msg: "Expected ssh dir to be created in build context"}
        }

        let staged_key = ($ctx | path join "ssh" "dockypody")
        let staged_pub = ($ctx | path join "ssh" "dockypody.pub")

        if ($staged_key | path exists) {
            rm-temp-context $fake_repo
            error make {msg: "Private key must NOT be staged in server mode"}
        }
        if not ($staged_pub | path exists) {
            rm-temp-context $fake_repo
            error make {msg: "Expected public key staged in server mode"}
        }

        let staged_module = ($ctx | path join "scripts" "lib" "sshd.nu")
        if not ($staged_module | path exists) {
            rm-temp-context $fake_repo
            error make {msg: "Expected sshd shared module staged in server mode"}
        }

        do {
            cd $fake_repo
            cleanup-ssh-context $ctx $result
        }

        if ($staged_pub | path exists) {
            rm-temp-context $fake_repo
            error make {msg: "Expected public key removed after cleanup"}
        }
        if ($staged_module | path exists) {
            rm-temp-context $fake_repo
            error make {msg: "Expected sshd shared module removed after cleanup"}
        }

        rm-temp-context $fake_repo
        true
    } $verbose_flag)
    $results = ($results | append $test_prepare_server)

    let test_prepare_client = (run-test "prepare-ssh-context: client mode -> full keypair staged" {
        let fake_repo = (^mktemp -d | str trim)
        let fake_ssh_dir = ($fake_repo | path join "ssh")
        mkdir $fake_ssh_dir
        # ssh.json SSOT drives key_name; key files must match.
        '{"key_name":"dockypody","comment":"docky@pody","default_user":"root"}' | save -f ($fake_ssh_dir | path join "ssh.json")
        let fake_key = ($fake_ssh_dir | path join "dockypody")
        let fake_pub = ($fake_ssh_dir | path join "dockypody.pub")
        "FAKE PRIVATE KEY" | save -f $fake_key
        "FAKE PUBLIC KEY" | save -f $fake_pub

        # Provide the shared sshd module required by prepare-ssh-context.
        let sshd_mod_dir = ($fake_repo | path join "scripts" "lib" "ssh")
        mkdir $sshd_mod_dir
        "# fake sshd module" | save -f ($sshd_mod_dir | path join "sshd.nu")

        let ctx = ($fake_repo | path join "ctx")
        mkdir $ctx

        let result = (do {
            cd $fake_repo
            prepare-ssh-context "test-service" $ctx true "client"
        })

        if not $result.dir_created {
            rm-temp-context $fake_repo
            error make {msg: "Expected dir_created=true when SSH enabled"}
        }

        let staged_key = ($ctx | path join "ssh" "dockypody")
        let staged_pub = ($ctx | path join "ssh" "dockypody.pub")

        if not ($staged_key | path exists) {
            rm-temp-context $fake_repo
            error make {msg: "Expected private key staged in client mode"}
        }
        if not ($staged_pub | path exists) {
            rm-temp-context $fake_repo
            error make {msg: "Expected public key staged in client mode"}
        }

        do {
            cd $fake_repo
            cleanup-ssh-context $ctx $result
        }

        if ($staged_key | path exists) {
            rm-temp-context $fake_repo
            error make {msg: "Expected private key removed after cleanup"}
        }

        rm-temp-context $fake_repo
        true
    } $verbose_flag)
    $results = ($results | append $test_prepare_client)

    let test_sshd_module_staged = (run-test "prepare-ssh-context: sshd shared module always staged even when disabled" {
        let fake_repo = (^mktemp -d | str trim)

        # Provide the shared sshd module required by prepare-ssh-context.
        let sshd_mod_dir = ($fake_repo | path join "scripts" "lib" "ssh")
        mkdir $sshd_mod_dir
        "# fake sshd module" | save -f ($sshd_mod_dir | path join "sshd.nu")

        let ctx = ($fake_repo | path join "ctx")
        mkdir $ctx

        let result = (do {
            cd $fake_repo
            prepare-ssh-context "test-service" $ctx false "disabled"
        })

        let staged_module = ($ctx | path join "scripts" "lib" "sshd.nu")
        if not ($staged_module | path exists) {
            rm-temp-context $fake_repo
            error make {msg: "Expected sshd shared module staged even when SSH disabled"}
        }

        do {
            cd $fake_repo
            cleanup-ssh-context $ctx $result
        }

        if ($staged_module | path exists) {
            rm-temp-context $fake_repo
            error make {msg: "Expected sshd shared module removed after cleanup"}
        }

        rm-temp-context $fake_repo
        true
    } $verbose_flag)
    $results = ($results | append $test_sshd_module_staged)

    # ------------------------------------------------------------------
    # validate-version-overrides-ssh tests
    # ------------------------------------------------------------------

    let test_version_valid = (run-test "validate-version-overrides-ssh: valid version override" {
        let version = { version: "v1.0.0", ssh: { enabled: true, mode: "client", default_user: "root", port: 22 } }
        validate-version-overrides-ssh $version "test-service"
        true
    } $verbose_flag)
    $results = ($results | append $test_version_valid)

    let test_version_warns = (run-test "validate-version-overrides-ssh: warns on version override" {
        let version = { version: "v1.0.0", ssh: { enabled: true, mode: "client", default_user: "root", port: 22 } }
        let result = (validate-version-overrides-ssh $version "test-service")
        if not $result.valid {
            error make {msg: "Expected validation to pass with warning"}
        }
        if ($result.warnings | is-empty) {
            error make {msg: "Expected warning for version-level SSH override"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_version_warns)

    # ------------------------------------------------------------------
    # validate-platform-ssh tests
    # ------------------------------------------------------------------

    let test_platform_valid = (run-test "validate-platform-ssh: valid platform override" {
        let platform = { name: "dev", ssh: { enabled: true, mode: "server", default_user: "root", port: 22 } }
        validate-platform-ssh $platform "test-service"
        true
    } $verbose_flag)
    $results = ($results | append $test_platform_valid)

    let test_platform_invalid = (run-test "validate-platform-ssh: invalid platform override rejected" {
        let platform = { name: "dev", ssh: { enabled: true, mode: "bad", default_user: "root", port: 22 } }
        let result = (validate-platform-ssh $platform "test-service")
        if $result.valid {
            error make {msg: "Expected validation to fail for invalid platform SSH override"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_platform_invalid)

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------

    print-test-summary $results
    let failed = ($results | where {|r| not $r} | length)
    if $failed > 0 {
        exit 1
    }
}
