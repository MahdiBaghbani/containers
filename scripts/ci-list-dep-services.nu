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

# CI helper: List dependency services for a consumer service
# Outputs one dependency service name per line on stdout (for CI parsing)
# All logs and errors go to stderr to keep stdout clean

use ./lib/ci-deps.nu [get-direct-dependency-services get-all-dependency-services]

export def main [
    --service: string  # Service name to list dependencies for
    --transitive       # Include transitive dependencies (default: direct only)
    --debug            # Enable verbose output on stderr
] {
    if ($service | str length) == 0 {
        print --stderr "ERROR: --service is required"
        exit 1
    }

    let mode = (if $transitive { "transitive" } else { "direct" })
    if $debug {
        print --stderr $"DEBUG: Getting ($mode) dependencies for service: ($service)"
    }

    let dep_services = (if $transitive {
        get-all-dependency-services $service
    } else {
        get-direct-dependency-services $service
    })

    if $debug {
        print --stderr $"DEBUG: Found ($dep_services | length) ($mode) dependencies"
    }

    # Output each dependency on its own line (clean stdout for CI parsing)
    for dep in $dep_services {
        print $dep
    }
}
