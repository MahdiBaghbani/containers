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

# Merged end-to-end failure, inheritance, and merge behavior checks.

use ../../lib/validate/core.nu [validate-service-complete]
use ../lib.nu [run-test]
use ./_temp.nu [make-temp rm-temp]

export def service-complete-merge-tests [verbose: bool] {
  [
    (run-test "validate-service-complete: surfaces merged-config build failure" {
      let tmp = (make-temp)
      let result = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "mergefail")
        "FROM scratch" | save -f ($tmp | path join "services" "mergefail" "Dockerfile")
        {
          name: "mergefail",
          context: "services/mergefail",
          dockerfile: "services/mergefail/Dockerfile",
          merge_probe: 5
        } | save -f ($tmp | path join "services" "mergefail.nuon")
        {
          default: "v1",
          versions: [
            {name: "v1", overrides: {merge_probe: {nested: true}}}
          ]
        } | save -f ($tmp | path join "services" "mergefail" "versions.nuon")
        validate-service-complete "mergefail"
      })
      rm-temp $tmp
      if $result.valid {
        error make {msg: "Expected merged-config build failure to fail validation"}
      }
      let has_merge_err = ($result.errors | any {|e| $e | str contains "Failed to build merged config"})
      if not $has_merge_err {
        error make {msg: $"Expected 'Failed to build merged config' error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-complete: merged SSH inherits invalid port and fails via merged path" {
      let tmp = (make-temp)
      let result = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "sshmerge")
        "FROM scratch" | save -f ($tmp | path join "services" "sshmerge" "Dockerfile")
        {
          name: "sshmerge",
          context: "services/sshmerge",
          dockerfile: "services/sshmerge/Dockerfile",
          ssh: {enabled: false, port: "bad"}
        } | save -f ($tmp | path join "services" "sshmerge.nuon")
        {
          default: "v1",
          versions: [
            {name: "v1", overrides: {ssh: {enabled: true, mode: "server"}}}
          ]
        } | save -f ($tmp | path join "services" "sshmerge" "versions.nuon")
        validate-service-complete "sshmerge"
      })
      rm-temp $tmp
      if $result.valid {
        error make {msg: "Expected merged SSH (enabled + inherited bad port) to fail validation"}
      }
      let has_ssh_err = ($result.errors | any {|e| $e | str contains "ssh.port"})
      if not $has_ssh_err {
        error make {msg: $"Expected merged ssh.port error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-complete: single-platform sources from versions defaults pass after merge" {
      let tmp = (make-temp)
      let result = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "srcplace")
        "FROM scratch" | save -f ($tmp | path join "services" "srcplace" "Dockerfile")
        {
          name: "srcplace",
          context: "services/srcplace",
          dockerfile: "services/srcplace/Dockerfile"
        } | save -f ($tmp | path join "services" "srcplace.nuon")
        {
          default: "v1",
          defaults: {sources: {app: {url: "https://example.com/app.git", ref: "v1.0.0"}}},
          versions: [
            {name: "v1", overrides: {sources: {app: {ref: "v1.2.3"}}}}
          ]
        } | save -f ($tmp | path join "services" "srcplace" "versions.nuon")
        validate-service-complete "srcplace"
      })
      rm-temp $tmp
      if not $result.valid {
        error make {msg: $"Expected single-platform service with versions-supplied sources to pass, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
  ]
}
