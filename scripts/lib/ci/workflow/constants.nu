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

# Constants and shared definitions for workflow generation

export const ORCHESTRATOR_PATH = ".github/workflows/build-orchestrator.yml"
export const BUILD_PATH = ".github/workflows/build.yml"
export const BUILD_PUSH_PATH = ".github/workflows/build-push.yml"
export const BUILD_SERVICE_PATH = ".github/workflows/build-service.yml"

export const SPDX_HEADER = "# SPDX-License-Identifier: AGPL-3.0-or-later
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
"

# Generate workflow header with description and trigger
export def gen-workflow-header [description: string, regen_cmd: string, name: string, trigger: string] {
    $SPDX_HEADER + $"
# ($description)
#
# GENERATED FILE - Do not edit manually
# Regenerate with: ($regen_cmd)

name: ($name)

($trigger)
"
}

# Convert service name to job ID
export def service-to-job-id [service: string] {
    $"build_($service | str replace -a '-' '_')"
}

# Convert list of service names to list of job IDs
export def services-to-job-ids [services: list] {
    $services | each {|svc| service-to-job-id $svc }
}

# Format job IDs as YAML needs list
export def format-needs-list [job_ids: list, indent_level: int = 2] {
    if ($job_ids | is-empty) { return "" }
    let prefix = (1..$indent_level | each {|_| "  " } | str join "")
    let items = ($job_ids | each {|id| $"($prefix)  - ($id)" } | str join "\n")
    $"($prefix)needs:\n($items)\n"
}
