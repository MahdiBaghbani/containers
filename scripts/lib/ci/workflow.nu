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

use ../services/core.nu [list-service-names]
use ./deps.nu [get-direct-dependency-services get-all-dependency-services]

const OUTPUT_PATH = ".github/workflows/build.yml"

# Convert service name to job ID
def service-to-job-id [service: string] {
    $"build_($service | str replace -a '-' '_')"
}

# Convert list of service names to list of job IDs
def services-to-job-ids [services: list] {
    $services | each {|svc| service-to-job-id $svc }
}

# Get all services with their dependencies
def get-services-with-deps [] {
    let services = (list-service-names)
    $services | each {|svc|
        let direct_deps = (get-direct-dependency-services $svc)
        let all_deps = (get-all-dependency-services $svc)
        {
            name: $svc,
            job_id: (service-to-job-id $svc),
            direct_deps: $direct_deps,
            all_deps: $all_deps,
            needs_job_ids: (services-to-job-ids $direct_deps)
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
# Regenerate with: nu scripts/dockypody.nu ci gen-workflow

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
    let deps_str = ($svc_info.all_deps | str join ",")
    let needs_list = $svc_info.needs_job_ids

    let needs_yaml = (if ($needs_list | is-empty) {
        ""
    } else {
        let needs_formatted = ($needs_list | str join ", ")
        $"    needs: [($needs_formatted)]\n"
    })

    $"  ($job_id):
($needs_yaml)    uses: ./.github/workflows/build-service.yml
    with:
      service: ($name)
      push: false
      dependencies: \"($deps_str)\"
      disk_monitor_mode: basic
      prune_build_cache: true
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

# Generate dependency graph comment
def gen-dependency-graph-comment [services_with_deps: list] {
    let roots = ($services_with_deps | where {|s| $s.direct_deps | is-empty} | get name)
    
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
    
    let services_with_deps = (get-services-with-deps)
    
    print $"Found ($services_with_deps | length) services"
    
    let header = (gen-workflow-header)
    let graph_comment = (gen-dependency-graph-comment $services_with_deps)
    
    mut jobs_yaml = "jobs:\n"
    
    for svc_info in $services_with_deps {
        print $"  - ($svc_info.name) \(deps: ($svc_info.direct_deps | str join ', ')\)"
        let job_yaml = (gen-service-job $svc_info)
        $jobs_yaml = $jobs_yaml + $job_yaml + "\n"
    }
    
    let all_job_ids = ($services_with_deps | get job_id)
    let complete_job = (gen-build-complete-job $all_job_ids)
    $jobs_yaml = $jobs_yaml + $complete_job
    
    let full_yaml = $header + $graph_comment + "\n" + $jobs_yaml
    
    $full_yaml
}

export def gen-workflow [
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
