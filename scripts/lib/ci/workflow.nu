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

# CI workflow generation facade
# Delegates to focused modules under workflow/

use ./workflow/constants.nu [
    ORCHESTRATOR_PATH BUILD_PATH BUILD_PUSH_PATH BUILD_SERVICE_PATH
]
use ./workflow/build-service.nu
use ./workflow/orchestrator.nu

# Get workflow specifications for the given target
export def get-workflows-for-target [
    target: string  # Target: all, build, build-push, orchestrator, build-service
] {
    let valid_targets = ["all" "build" "build-push" "orchestrator" "build-service"]
    if not ($target in $valid_targets) {
        error make {
            msg: $"Invalid target: ($target). Must be one of: ($valid_targets | str join ', ')"
        }
    }

    mut workflows = []

    if ($target == "orchestrator" or $target == "all") {
        $workflows = ($workflows | append {
            path: $ORCHESTRATOR_PATH
            contents: (orchestrator generate-orchestrator)
        })
    }

    if ($target == "build" or $target == "all") {
        $workflows = ($workflows | append {
            path: $BUILD_PATH
            contents: (orchestrator generate-build)
        })
    }

    if ($target == "build-push" or $target == "all") {
        $workflows = ($workflows | append {
            path: $BUILD_PUSH_PATH
            contents: (orchestrator generate-build-push)
        })
    }

    if ($target == "build-service" or $target == "all") {
        $workflows = ($workflows | append {
            path: $BUILD_SERVICE_PATH
            contents: (build-service generate)
        })
    }

    $workflows
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

# Main entry point for workflow generation
export def gen-workflow [
    --dry-run  # Print to stdout instead of writing file
] {
    let workflows = (get-workflows-for-target "all")
    write-workflows $workflows --dry-run=$dry_run
}
