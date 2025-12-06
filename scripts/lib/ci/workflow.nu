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
const ORCHESTRATOR_PATH = ".github/workflows/build-orchestrator.yml"
const BUILD_PATH = ".github/workflows/build.yml"
const BUILD_PUSH_PATH = ".github/workflows/build-push.yml"

const SPDX_HEADER = "# SPDX-License-Identifier: AGPL-3.0-or-later
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

# Convert service name to job ID
def service-to-job-id [service: string] {
    $"build_($service | str replace -a '-' '_')"
}

# Convert list of service names to list of job IDs
def services-to-job-ids [services: list] {
    $services | each {|svc| service-to-job-id $svc }
}

# Format job IDs as YAML needs list with proper block style
def format-needs-list [job_ids: list, indent: int = 4] {
    if ($job_ids | is-empty) {
        return ""
    }
    
    let indent_str = (seq 1 $indent | each {|_| " " } | str join "")
    let items = ($job_ids | each {|id| $"($indent_str)  - ($id)" } | str join "\n")
    
    $"($indent_str)needs:\n($items)\n"
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

# Generate workflow header with description and trigger
def gen-workflow-header [description: string, regen_cmd: string, name: string, trigger: string] {
    $SPDX_HEADER + $"
# ($description)
#
# GENERATED FILE - Do not edit manually
# Regenerate with: ($regen_cmd)

name: ($name)

($trigger)
"
}

# Generate YAML for a single service job
def gen-service-job [svc_info: record] {
    let job_id = $svc_info.job_id
    let name = $svc_info.name
    let deps_str = ($svc_info.all_deps | str join ",")
    let needs_yaml = (format-needs-list $svc_info.needs_job_ids)

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
    let needs_yaml = (format-needs-list $all_job_ids)

    $"  build_complete:
    name: Build Complete
($needs_yaml)    runs-on: ubuntu-latest
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


# Generate YAML for a single service job in the orchestrator
def gen-orchestrator-service-job [svc_info: record] {
    let job_id = $svc_info.job_id
    let name = $svc_info.name
    let deps_str = ($svc_info.all_deps | str join ",")
    let needs_yaml = (format-needs-list $svc_info.needs_job_ids)

    $"  ($job_id):
($needs_yaml)    uses: ./.github/workflows/build-service.yml
    with:
      service: ($name)
      push: ${{ inputs.push }}
      dependencies: \"($deps_str)\"
      disk_monitor_mode: basic
      prune_build_cache: true
"
}



# Generate build-push entry workflow
def generate-build-push-entry-workflow [] {
    let header = (gen-workflow-header 
        "Build and push all services and versions - Manual workflow for pushing to ghcr.io"
        "nu scripts/dockypody.nu ci workflow --target build-push"
        "Build and Push All"
        "on:\n  workflow_dispatch:")
    
    $header + "
jobs:
  run_build_push_all:
    name: Build and Push All Services
    uses: ./.github/workflows/build-orchestrator.yml
    with:
      push: true
"
}

# Generate build-only entry workflow
def generate-build-entry-workflow [] {
    let header = (gen-workflow-header 
        "Build all services and versions - Use this for build verification without pushing to registries"
        "nu scripts/dockypody.nu ci workflow --target build"
        "Build All"
        "on:\n  workflow_dispatch:")
    
    $header + "
jobs:
  run_build_all:
    name: Build All Services
    uses: ./.github/workflows/build-orchestrator.yml
    with:
      push: false
"
}

# Generate the orchestrator workflow
def generate-orchestrator-workflow [] {
    let services_with_deps = (get-services-with-deps)
    
    let header = (gen-workflow-header 
        "Reusable workflow for orchestrating service builds - Called by build.yml and build-push.yml entry workflows"
        "nu scripts/dockypody.nu ci workflow --target orchestrator"
        "Build Orchestrator"
        "on:\n  workflow_call:\n    inputs:\n      push:\n        description: \"Push images to registry\"\n        required: false\n        type: boolean\n        default: false\n")
    let graph_comment = (gen-dependency-graph-comment $services_with_deps)
    
    mut jobs_yaml = "jobs:\n"
    
    for svc_info in $services_with_deps {
        let job_yaml = (gen-orchestrator-service-job $svc_info)
        $jobs_yaml = $jobs_yaml + $job_yaml + "\n"
    }
    
    let all_job_ids = ($services_with_deps | get job_id)
    let complete_job = (gen-build-complete-job $all_job_ids)
    $jobs_yaml = $jobs_yaml + $complete_job
    
    let full_yaml = $header + $graph_comment + "\n" + $jobs_yaml
    
    $full_yaml
}

# Get workflow specifications for the given target
# Returns list of records with shape { path: string, contents: string }
export def get-workflows-for-target [
    target: string  # Target: all, build, build-push, orchestrator
] {
    # Validate target
    let valid_targets = ["all" "build" "build-push" "orchestrator"]
    if not ($target in $valid_targets) {
        error make {
            msg: $"Invalid target: ($target)"
            label: {
                text: $"Must be one of: ($valid_targets | str join ', ')"
                span: (metadata $target).span
            }
        }
    }

    # Generate workflows based on target
    let orchestrator = if ($target == "orchestrator" or $target == "all") {
        [{
            path: $ORCHESTRATOR_PATH
            contents: (generate-orchestrator-workflow)
        }]
    } else {
        []
    }

    let build = if ($target == "build" or $target == "all") {
        [{
            path: $BUILD_PATH
            contents: (generate-build-entry-workflow)
        }]
    } else {
        []
    }

    let build_push = if ($target == "build-push" or $target == "all") {
        [{
            path: $BUILD_PUSH_PATH
            contents: (generate-build-push-entry-workflow)
        }]
    } else {
        []
    }

    # Combine all workflows
    $orchestrator | append $build | append $build_push
}

# Write workflows to disk or print to stdout
export def write-workflows [
    workflows: list  # List of { path, contents } records
    --dry-run        # Print to stdout instead of writing files
] {
    if $dry_run {
        for workflow in $workflows {
            print $"=== ($workflow.path) ==="
            print ""
            print $workflow.contents
            print ""
        }
    } else {
        for workflow in $workflows {
            $workflow.contents | save -f $workflow.path
            print $"Generated: ($workflow.path)"
        }
        
        print ""
        print "Next steps:"
        print "  1. Review the generated workflows"
        print "  2. Commit the changes"
        print "  3. Test by triggering a workflow run"
    }
}

# Main generation function (legacy, kept for backwards compat)
def generate-workflow [] {
    print "Generating CI build workflow..."
    
    let services_with_deps = (get-services-with-deps)
    
    print $"Found ($services_with_deps | length) services"
    
    let header = (gen-workflow-header 
        "Build all services and versions - Use this for build verification without pushing to registries"
        "nu scripts/dockypody.nu ci gen-workflow"
        "Build All"
        "on:\n  workflow_dispatch:\n    inputs:\n      verbose:\n        description: \"Enable verbose output\"\n        required: false\n        type: boolean\n        default: false\n")
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
    print "Generating CI build workflow..."
    
    let workflows = (get-workflows-for-target "all")
    write-workflows $workflows --dry-run=$dry_run
}
