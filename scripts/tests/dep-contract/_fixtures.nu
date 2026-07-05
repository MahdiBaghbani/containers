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

# Suite-local fixtures for dep-contract tests.

# Create a minimal platforms.nuon for a temporary test service.
# Must be called from repo root. Caller is responsible for cleanup.
export def create-temp-service-platforms [service: string, platform_name: string = "debian"] {
    let svc_dir = $"services/($service)"
    try { mkdir $svc_dir } catch {}
    let manifest = {
        default: $platform_name,
        platforms: [{name: $platform_name, dockerfile: $"services/($service)/Dockerfile"}]
    }
    $manifest | to nuon | save -f $"($svc_dir)/platforms.nuon"
}

# Remove a temporary test service directory.
export def remove-temp-service [service: string] {
    try { rm -rf $"services/($service)" } catch {}
}
