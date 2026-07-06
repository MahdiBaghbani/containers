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

# Repo/CA path basics and subject/SAN helper coverage.

use ../../lib/core/repo.nu [get-repo-root]
use ../../lib/tls/lib.nu [get-services-dir get-shared-ca-dir build-subject build-san-config]
use ../lib.nu [run-test]

export def path-basics-tests [verbose: bool] {
    [
        (run-test "Path resolution" {
            let repo_root = (get-repo-root)
            if not ($repo_root | path exists) {
                error make {msg: $"Repo root not found: ($repo_root)"}
            }
            if $verbose { print $"    Repo root: ($repo_root)" }
            true
        } $verbose)
        (run-test "Services directory" {
            let services_dir = (get-services-dir)
            if not ($services_dir | path exists) {
                error make {msg: $"Services directory not found: ($services_dir)"}
            }
            if $verbose { print $"    Services dir: ($services_dir)" }
            true
        } $verbose)
        (run-test "CA directory structure" {
            let ca_dir = (get-shared-ca-dir)
            let repo_root = (get-repo-root)
            let expected = ($repo_root | path join "tls" "certificate-authority")
            if $ca_dir != $expected {
                error make {msg: $"CA dir mismatch: expected ($expected), got ($ca_dir)"}
            }
            if $verbose { print $"    CA dir: ($ca_dir)" }
            true
        } $verbose)
        (run-test "Subject string building" {
            let subject = (build-subject "test.example.com")
            if not ($subject | str contains "CN=test.example.com") {
                error make {msg: $"Subject missing CN: ($subject)"}
            }
            if $verbose { print $"    Subject: ($subject)" }
            true
        } $verbose)
        (run-test "SAN config building" {
            let san_config = (build-san-config "test.example.com" ["DNS:extra.example.com"])
            if not ($san_config | str contains "DNS.1 = test.example.com") {
                error make {msg: "SAN config missing primary domain"}
            }
            if not ($san_config | str contains "subjectAltName") {
                error make {msg: "SAN config missing header"}
            }
            if $verbose {
                print $"    SAN config preview:"
                print $"($san_config | lines | first 3 | str join '\n' | str replace -a '\n' '\n      ')"
            }
            true
        } $verbose)
    ]
}
