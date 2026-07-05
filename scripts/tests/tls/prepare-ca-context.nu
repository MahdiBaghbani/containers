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

# prepare-ca-context / cleanup-ca-context staging behavior.

use ../../lib/build/context.nu [prepare-ca-context cleanup-ca-context]
use ../lib.nu [run-test]
use ./_temp.nu [make-temp-context rm-temp-context]

export def prepare-ca-context-tests [verbose: bool] {
    [
        (run-test "prepare-ca-context: no requirements -> no-op" {
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
        } $verbose)
        (run-test "prepare-ca-context: needs_ca_crt -> stages .crt, cleanup removes it" {
            let fake_repo = (^mktemp -d | str trim)
            let fake_ca_dir = ($fake_repo | path join "tls" "certificate-authority")
            mkdir $fake_ca_dir
            let ca_name = "test-ca"
            let fake_crt = ($fake_ca_dir | path join $"($ca_name).crt")
            "FAKE CA CERT CONTENT" | save -f $fake_crt

            let ctx = ($fake_repo | path join "ctx")
            mkdir $ctx

            let result = (do {
                cd $fake_repo
                let tls_meta = {enabled: true, mode: "ca-and-cert", cert_name: "svc", ca_name: $ca_name}
                let ca_reqs = {needs_ca_crt: true, needs_ca_key: false}
                prepare-ca-context $ctx $tls_meta $ca_reqs
            })

            let staged_crt = ($ctx | path join "tls" "certificate-authority" $"($ca_name).crt")
            if not ($staged_crt | path exists) {
                rm-temp-context $fake_repo
                error make {msg: $"Expected staged cert at ($staged_crt)"}
            }
            if $verbose { print $"    Staged: ($staged_crt)" }

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
        } $verbose)
        (run-test "prepare-ca-context: needs crt+key -> stages both, cleanup removes both" {
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
        } $verbose)
        (run-test "cleanup-ca-context: extra leftover file in CA dir -> entire dir removed" {
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
        } $verbose)
    ]
}
