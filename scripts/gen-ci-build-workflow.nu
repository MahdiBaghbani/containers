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

# Generate CI build workflow from service dependency graph
# Produces .github/workflows/build.yml with per-service jobs and dependency inputs

use ./lib/services.nu [list-service-names]
use ./lib/ci-deps.nu [get-direct-dependency-services]

const OUTPUT_PATH = ".github/workflows/build.yml"

# Convert service name to job ID (e.g., "cernbox-revad" -> "build_cernbox_revad")
def service-to-job-id [service: string] {
    $"build_($service | str replace -a '-' '_')"
}

# Convert list of service names to list of job IDs
def services-to-job-ids [services: list] {
    $services | each {|svc| service-to-job-id $svc }
}

# Get all services with their direct dependencies
def get-services-with-deps [] {
    let services = (list-service-names)
    $services | each {|svc|
        let deps = (get-direct-dependency-services $svc)
        {
            name: $svc,
            job_id: (service-to-job-id $svc),
            direct_deps: $deps,
            needs_job_ids: (services-to-job-ids $deps)
        }
    }
}

# Generate YAML for workflow header
def gen-workflow-header [] {
    "# SPDX-License-Identifier: AGPL-3.0-or-later
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

# Build all services and versions
# Use this for build verification without pushing to registries
#
# GENERATED FILE - Do not edit manually
# Regenerate with: nu scripts/gen-ci-build-workflow.nu

name: Build All

on:
  workflow_dispatch:
    inputs:
      verbose:
        description: \"Enable verbose output\"
        required: false
        type: boolean
        default: false
"
}

# Generate YAML for a single service job
def gen-service-job [svc_info: record] {
    let job_id = $svc_info.job_id
    let name = $svc_info.name
    let deps_str = ($svc_info.direct_deps | str join ",")
    let needs_list = $svc_info.needs_job_ids

    # Build the needs clause
    let needs_yaml = (if ($needs_list | is-empty) {
        ""
    } else {
        let needs_formatted = ($needs_list | str join ", ")
        $"    needs: [($needs_formatted)]\n"
    })

    # Build the job YAML
    $"  ($job_id):
    name: Build ($name)
($needs_yaml)    uses: ./.github/workflows/build-service.yml
    with:
      service: ($name)
      push: false
      dependencies: \"($deps_str)\"
"
}

# Generate YAML for the build_complete aggregation job
def gen-build-complete-job [all_job_ids: list] {
    let needs_formatted = ($all_job_ids | str join ", ")

    $"  build_complete:
    name: Build Complete
    needs: [($needs_formatted)]
    runs-on: ubuntu-latest
    steps:
      - name: All builds completed
        run: echo \"All service builds completed successfully\"
"
}

# Generate dependency graph comment for readability
def gen-dependency-graph-comment [services_with_deps: list] {
    # Find root services (no dependencies)
    let roots = ($services_with_deps | where {|s| $s.direct_deps | is-empty} | get name)
    
    # Build a simple graph representation
    mut lines = ["# Service dependency graph:"]
    $lines = ($lines | append "#")
    
    for svc in $services_with_deps {
        let deps_str = (if ($svc.direct_deps | is-empty) {
            "(root service, no dependencies)"
        } else {
            $"depends on: ($svc.direct_deps | str join ', ')"
        })
        $lines = ($lines | append $"#   ($svc.name) - ($deps_str)")
    }
    
    $lines = ($lines | append "#")
    ($lines | str join "\n") + "\n"
}

# Main generation function
def generate-workflow [] {
    print "Generating CI build workflow..."
    
    # Get all services with their dependencies
    let services_with_deps = (get-services-with-deps)
    
    print $"Found ($services_with_deps | length) services"
    
    # Generate workflow parts
    let header = (gen-workflow-header)
    let graph_comment = (gen-dependency-graph-comment $services_with_deps)
    
    # Generate jobs section
    mut jobs_yaml = "jobs:\n"
    
    # Generate each service job
    for svc_info in $services_with_deps {
        print $"  - ($svc_info.name) \(deps: ($svc_info.direct_deps | str join ', '))"
        let job_yaml = (gen-service-job $svc_info)
        $jobs_yaml = $jobs_yaml + $job_yaml + "\n"
    }
    
    # Generate build_complete job
    let all_job_ids = ($services_with_deps | get job_id)
    let complete_job = (gen-build-complete-job $all_job_ids)
    $jobs_yaml = $jobs_yaml + $complete_job
    
    # Combine all parts
    let full_yaml = $header + $graph_comment + "\n" + $jobs_yaml
    
    $full_yaml
}

export def main [
    --dry-run  # Print to stdout instead of writing file
] {
    let yaml_content = (generate-workflow)
    
    if $dry_run {
        print "=== Generated workflow (dry-run) ==="
        print $yaml_content
    } else {
        $yaml_content | save -f $OUTPUT_PATH
        print $"Workflow written to ($OUTPUT_PATH)"
        print ""
        print "Next steps:"
        print "  1. Review the generated workflow"
        print "  2. Commit the changes"
        print "  3. Test by triggering a workflow run"
    }
}
