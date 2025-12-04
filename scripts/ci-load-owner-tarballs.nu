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

# CI helper: Load cached tarballs for an owner service
# Called by build-service.yml after cache restore to load images into Docker daemon

use ./lib/dep-cache.nu [load-owner-tarballs]

export def main [
    --service: string  # Service name to load tarballs for
] {
    if ($service | str length) == 0 {
        print --stderr "ERROR: --service is required"
        exit 1
    }

    print $"Loading cached images for service: ($service)"
    let metrics = (load-owner-tarballs $service)

    print ""
    print "=== Load Summary ==="
    print $"Loaded: ($metrics.loaded)"
    print $"Skipped (already present): ($metrics.skipped)"
    print $"Failed: ($metrics.failed)"

    if $metrics.failed > 0 {
        print ""
        print "WARNING: Some images failed to load. Build will proceed but may need to rebuild."
    }
}
