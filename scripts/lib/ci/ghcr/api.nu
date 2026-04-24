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

# GHCR package version API helpers.
# Uses gh CLI (picks up GITHUB_TOKEN from env automatically).

# Check that GITHUB_TOKEN and gh CLI are available.
# Returns {ok: bool, reason: string}
export def check-gh-prereqs [] {
    let token = (try { $env.GITHUB_TOKEN } catch { "" })
    if ($token | str length) == 0 {
        return {ok: false, reason: "GITHUB_TOKEN is not set"}
    }

    let gh_check = (try { ^gh --version | complete } catch { null })
    if $gh_check == null or $gh_check.exit_code != 0 {
        return {ok: false, reason: "gh CLI is not available"}
    }

    {ok: true, reason: ""}
}

# Internal: call gh api GET; return {ok, status, body, error}
def gh-api-get [path: string, debug: bool] {
    if $debug {
        print --stderr $"DEBUG: ghcr GET ($path)"
    }
    try {
        let cmd = (^gh api $path | complete)
        if $cmd.exit_code == 0 {
            {ok: true, status: 200, body: ($cmd.stdout | from json), error: ""}
        } else {
            let stderr = (try { $cmd.stderr } catch { "" })
            let status = (
                if ($stderr | str contains "HTTP 404") { 404 }
                else if ($stderr | str contains "HTTP 401") { 401 }
                else if ($stderr | str contains "HTTP 403") { 403 }
                else { 0 }
            )
            {ok: false, status: $status, body: null, error: $stderr}
        }
    } catch {|err|
        {ok: false, status: 0, body: null, error: (try { $err.msg } catch { "gh command failed" })}
    }
}

# Internal: fetch all pages from a paginated GHCR list endpoint.
# Loops page=1.. with per_page=100 until the response is empty.
# Safety cap: stops after 50 pages (~5000 versions) and prints a warning.
# Returns {ok, status, body, error} where body is the full concatenated list.
def gh-api-get-paginated [base_path: string, debug: bool] {
    let max_pages = 50
    mut all_items = []
    mut page = 1
    mut had_error = false
    mut error_result = {ok: false, status: 0, body: null, error: ""}

    loop {
        if $page > $max_pages {
            print --stderr $"WARNING: GHCR listing capped at ($max_pages) pages for ($base_path); some versions may be missing"
            break
        }

        let path = $"($base_path)/versions?per_page=100&page=($page)"
        let r = (gh-api-get $path $debug)

        if not $r.ok {
            $error_result = $r
            $had_error = true
            break
        }

        let items = ($r.body | default [])
        if ($items | is-empty) {
            break
        }

        $all_items = ($all_items | append $items)

        if ($items | length) < 100 {
            break
        }

        $page = $page + 1
    }

    if $had_error {
        $error_result
    } else {
        {ok: true, status: 200, body: $all_items, error: ""}
    }
}

# List all GHCR package versions for a service, paginating until exhausted.
# Tries org endpoint first; falls back to user endpoint on 404.
# Returns {ok, base_path, versions, not_found, permission_denied, error}
export def list-package-versions [
    owner: string
    repo: string
    service: string
    debug: bool = false
] {
    let pkg_name = ($"($repo)/($service)" | str replace "/" "%2F")
    let org_base = $"/orgs/($owner)/packages/container/($pkg_name)"
    let r = (gh-api-get-paginated $org_base $debug)

    if $r.ok {
        return {ok: true, base_path: $org_base, versions: $r.body, not_found: false, permission_denied: false, error: ""}
    }

    if $r.status == 404 {
        let user_base = $"/users/($owner)/packages/container/($pkg_name)"
        let r2 = (gh-api-get-paginated $user_base $debug)

        if $r2.ok {
            return {ok: true, base_path: $user_base, versions: $r2.body, not_found: false, permission_denied: false, error: ""}
        }
        if $r2.status == 404 {
            return {ok: true, base_path: "", versions: [], not_found: true, permission_denied: false, error: ""}
        }
        if ($r2.status == 401 or $r2.status == 403) {
            return {ok: false, base_path: "", versions: [], not_found: false, permission_denied: true, error: $r2.error}
        }
        return {ok: false, base_path: "", versions: [], not_found: false, permission_denied: false, error: $r2.error}
    }

    if ($r.status == 401 or $r.status == 403) {
        return {ok: false, base_path: "", versions: [], not_found: false, permission_denied: true, error: $r.error}
    }

    {ok: false, base_path: "", versions: [], not_found: false, permission_denied: false, error: $r.error}
}

# Delete a GHCR package version by numeric ID.
# Uses the base_path from list-package-versions to target org or user endpoint.
# Returns {ok: bool, error: string}
export def delete-package-version [
    base_path: string
    version_id: int
    debug: bool = false
] {
    let del_path = $"($base_path)/versions/($version_id)"

    if $debug {
        print --stderr $"DEBUG: ghcr DELETE ($del_path)"
    }

    try {
        let cmd = (^gh api -X DELETE $del_path | complete)
        if $cmd.exit_code == 0 {
            {ok: true, error: ""}
        } else {
            let stderr = (try { $cmd.stderr } catch { "" })
            if ($stderr | str contains "HTTP 404") {
                # Already deleted - treat as success
                {ok: true, error: ""}
            } else {
                {ok: false, error: $stderr}
            }
        }
    } catch {|err|
        {ok: false, error: (try { $err.msg } catch { "Delete failed" })}
    }
}
