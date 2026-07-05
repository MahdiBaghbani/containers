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

# copy-tls permission, owner, and subprocess behavior.

use ../../lib/core/repo.nu [get-repo-root]
use ../../lib/tls/copy.nu [copy-tls]
use ../lib.nu [run-test]
use ./_temp.nu [rm-temp-context]

export def copy-tls-tests [verbose: bool] {
    [
        (run-test "copy-tls: no runtime-owner -> key 0600, crt 0644, no chown" {
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
        } $verbose)
        (run-test "copy-tls: runtime-owner set to current user -> chown succeeds, ownership matches, modes correct" {
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
        } $verbose)
        (run-test "copy-tls: Docker-style quoted runtime-owner is normalized" {
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
        } $verbose)
        (run-test "copy.nu main: subprocess with Docker-style quoted user:group runtime-owner" {
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
        } $verbose)
    ]
}
