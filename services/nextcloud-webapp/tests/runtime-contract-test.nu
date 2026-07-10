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

# Runtime contract tests for nextcloud-webapp JupyterHub hook helpers.
# Run from repo root:
#   nu services/nextcloud-webapp/tests/runtime-contract-test.nu

const HOOK_USE = "use /usr/bin/lib/utils.nu [run_as, get_env_or_default]"

def service_root [] {
    $env.CURRENT_FILE | path dirname | path join ".."
}

def hook_path [] {
    service_root | path join "scripts" "hooks" "post-installation" "91-configure-integration-jupyterhub.nu"
}

def utils_path [] {
    service_root | path join ".." "nextcloud-base" "scripts" "lib" "utils.nu"
}

def assert_eq [label: string, got: any, want: any] {
    if $got != $want {
        error make {
            msg: $"FAIL [$label]: got ($got | to nuon), want ($want | to nuon)"
        }
    }
}

# The hook hardcodes a container-only utils import. Patch that path to
# nextcloud-base on the host, then evaluate hub_base_url in a child nu via
# overlay so we exercise the hook implementation without duplicating it.
def hub_base_url_from_hook [jupyter_host: string, patched_hook: string] {
    let code = [
        "source "
        ($patched_hook | to nuon)
        "; print (hub_base_url "
        ($jupyter_host | to nuon)
        ")"
    ] | str join ""
    let result = (^nu -c $code | complete)
    if $result.exit_code != 0 {
        error make {
            msg: $"hub_base_url subprocess failed: ($result.stderr | str trim)"
        }
    }
    $result.stdout | str trim
}

def patched_hook_path [] {
    let utils = (utils_path)
    let patched_use = $"use ($utils) [run_as, get_env_or_default]"
    let content = (open --raw (hook_path) | str replace $HOOK_USE $patched_use)
    let tmp = (^mktemp --suffix=.nu)
    $content | save -f $tmp
    $tmp
}

def test_hub_base_url_cases [patched_hook: string] {
    let cases = [
        {label: "bare host", host: "jupyterhub1.docker", want: "https://jupyterhub1.docker"}
        {label: "bare host trailing slash", host: "jupyterhub1.docker/", want: "https://jupyterhub1.docker"}
        {label: "https host", host: "https://jupyterhub1.docker", want: "https://jupyterhub1.docker"}
        {label: "https host trailing slash", host: "https://jupyterhub1.docker/", want: "https://jupyterhub1.docker"}
    ]

    for case in $cases {
        let got = (hub_base_url_from_hook $case.host $patched_hook)
        assert_eq $"hub_base_url ($case.label)" $got $case.want
    }
}

def main [] {
    let patched_hook = (patched_hook_path)
    try {
        test_hub_base_url_cases $patched_hook
        print "PASS: all nextcloud-webapp runtime contract tests"
    } finally {
        ^rm -f $patched_hook
    }
}
