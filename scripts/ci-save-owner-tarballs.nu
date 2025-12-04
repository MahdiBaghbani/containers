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

# CI helper: Save built images as tarballs for caching
# Called by build-service.yml after successful build to save images to cache

use ./lib/dep-cache.nu [save-owner-tarballs]
use ./lib/registry/registry-info.nu [get-registry-info]

export def main [
    --service: string  # Service name to save tarballs for
] {
    if ($service | str length) == 0 {
        print --stderr "ERROR: --service is required"
        exit 1
    }

    let registry_info = (get-registry-info)
    let is_local = ($registry_info.ci_platform == "local")

    print $"Saving image tarballs for service: ($service)"
    save-owner-tarballs $service $registry_info $is_local

    print ""
    print "Tarball save complete."
}
