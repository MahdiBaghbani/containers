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

# Service discovery and configuration tests

use ../lib.nu [print-test-summary, run-test]
use ./config-completeness.nu [config-completeness-tests]
use ./discovery.nu [discovery-tests]
use ./hook-parse.nu [hook-parse-tests]
use ./integrity.nu [integrity-tests]

const NEXTCLOUD_RUNTIME_CONTRACT = "services/nextcloud-webapp/tests/runtime-contract-test.nu"
const JUPYTERHUB_RUNTIME_CONTRACT = "services/jupyterhub/tests/runtime-contract-test.nu"
const OCM_GO_FOREGROUND_CONTRACT = "services/opencloudmesh-go/tests/test-foreground-contracts.nu"

def run-contract-script [script: string] {
  let result = (^nu $script | complete)
  if $result.exit_code != 0 {
    let detail = (
      if ($result.stderr | str trim | is-not-empty) {
        $result.stderr | str trim
      } else {
        $result.stdout | str trim
      }
    )
    error make {msg: $detail}
  }
  true
}

def runtime-contract-tests [verbose: bool] {
  [
    (run-test "nextcloud-webapp runtime contract" {
      run-contract-script $NEXTCLOUD_RUNTIME_CONTRACT
    } $verbose)
    (run-test "jupyterhub runtime contract" {
      run-contract-script $JUPYTERHUB_RUNTIME_CONTRACT
    } $verbose)
    (run-test "opencloudmesh-go foreground contract" {
      run-contract-script $OCM_GO_FOREGROUND_CONTRACT
    } $verbose)
  ]
}

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  mut results = []

  $results = ($results | append (discovery-tests $verbose_flag))
  $results = ($results | append (config-completeness-tests $verbose_flag))
  $results = ($results | append (integrity-tests $verbose_flag))
  $results = ($results | append (hook-parse-tests $verbose_flag))
  $results = ($results | append (runtime-contract-tests $verbose_flag))

  print-test-summary $results

  if ($results | any {|r| not $r}) {
    exit 1
  }
}
