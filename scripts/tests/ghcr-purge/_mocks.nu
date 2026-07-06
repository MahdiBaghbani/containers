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

# GHCR purge suite mocks (private to ghcr-purge/)

# Build a mock GHCR version record matching the API response shape.
# Optional --updated-at and --created-at flags add the corresponding timestamp
# fields so ts-extraction logic in decide-versions-to-delete can be exercised.
export def mock-version [
    id: int
    tags: list<string>
    --updated-at: string = ""
    --created-at: string = ""
] {
    mut record = {
        id: $id
        name: $"sha256:abc($id)"
        metadata: {
            package_type: "container"
            container: {
                tags: $tags
            }
        }
    }
    if ($updated_at | str length) > 0 {
        $record = ($record | insert updated_at $updated_at)
    }
    if ($created_at | str length) > 0 {
        $record = ($record | insert created_at $created_at)
    }
    $record
}

# Build a successful list-package-versions result wrapping the given versions.
export def mock-list-ok [versions: list] {
    {
        ok: true
        base_path: "/orgs/acme/packages/container/repo%2Fsvc"
        versions: $versions
        not_found: false
        permission_denied: false
        error: ""
    }
}

# Always-succeed delete closure.
export def delete-fn-ok [] {
    {|base_path, version_id| {ok: true, error: ""} }
}

# Delete closure that fails for a specific version id.
export def delete-fn-fail-id [bad_id: int] {
    {|base_path, version_id|
        if $version_id == $bad_id {
            {ok: false, error: "HTTP 500 simulated failure"}
        } else {
            {ok: true, error: ""}
        }
    }
}
