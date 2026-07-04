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

# SSOT desired-tag computation tests

use ../../lib/ci/ghcr/ssot-tags.nu [compute-desired-tags-for-service]
use ../../lib/services/core.nu [list-service-names]
use ../lib.nu [run-test]
use ./_fixtures.nu [
    ISOLATION_SVC ISOLATION_TRACKED_V1 ISOLATION_TRACKED_V2 ISOLATION_LOCAL_ONLY
    make-temp-repo rm-temp-repo run-in-temp-repo seed-tracked-plane-isolation-fixture
]

export def test-ssot-known-service [verbose: bool] {
    run-test "ssot: compute-desired-tags-for-service returns non-empty for known service" {
        let services = (list-service-names)
        use ../../lib/manifest/core.nu [check-versions-manifest-exists]
        let svc_with_manifest = ($services | where {|s| check-versions-manifest-exists $s} | first)
        let tags = (compute-desired-tags-for-service $svc_with_manifest)
        if ($tags | is-empty) {
            error make {msg: $"expected non-empty desired tags for ($svc_with_manifest)"}
        }
        true
    } $verbose
}

export def test-ssot-no-manifest [verbose: bool] {
    run-test "ssot: service without versions manifest returns empty list" {
        let tags = (compute-desired-tags-for-service "common-tools")
        ($tags | describe | str starts-with "list")
    } $verbose
}

export def test-ssot-no-registry-prefix [verbose: bool] {
    run-test "ssot: tags contain no registry prefix or service prefix" {
        use ../../lib/manifest/core.nu [check-versions-manifest-exists]
        let services = (list-service-names)
        let svc = ($services | where {|s| check-versions-manifest-exists $s} | first)
        let tags = (compute-desired-tags-for-service $svc)
        let bad = ($tags | where {|t|
            (($t | str contains "ghcr.io")
                or ($t | str contains "/"))
        })
        if not ($bad | is-empty) {
            error make {msg: $"found tags with registry prefix: ($bad | str join ', ')"}
        }
        true
    } $verbose
}

export def test-ssot-sorted-unique [verbose: bool] {
    run-test "ssot: desired tags are sorted and unique" {
        use ../../lib/manifest/core.nu [check-versions-manifest-exists]
        let services = (list-service-names)
        let svc = ($services | where {|s| check-versions-manifest-exists $s} | first)
        let tags = (compute-desired-tags-for-service $svc)
        let sorted = ($tags | sort)
        let unique = ($tags | uniq)
        if $tags != $sorted { error make {msg: "tags are not sorted"} }
        if $tags != $unique { error make {msg: "tags contain duplicates"} }
        true
    } $verbose
}

export def test-ssot-tracked-only-isolation [verbose: bool] {
    run-test "ssot: compute-desired-tags ignores local fragment versions (tracked-only isolation)" {
        let repo = (make-temp-repo)
        seed-tracked-plane-isolation-fixture $repo
        let tags = (run-in-temp-repo $repo {||
            compute-desired-tags-for-service $ISOLATION_SVC
        })
        rm-temp-repo $repo
        if $ISOLATION_LOCAL_ONLY in $tags {
            error make {msg: $"Local-only version leaked into SSOT tags: ($tags | str join ', ')"}
        }
        if not ($ISOLATION_TRACKED_V1 in $tags) {
            error make {msg: $"Tracked version tag ($ISOLATION_TRACKED_V1) missing from SSOT output"}
        }
        if not ($ISOLATION_TRACKED_V2 in $tags) {
            error make {msg: $"Tracked version tag ($ISOLATION_TRACKED_V2) missing from SSOT output"}
        }
        true
    } $verbose
}
