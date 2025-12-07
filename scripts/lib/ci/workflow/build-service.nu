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

# Generator for build-service.yml workflow
# Uses artifact-based dependency reuse

use ./yaml.nu [indent yaml-steps]
use ./steps.nu [
    step-checkout step-install-nushell step-common-setup
    step-prepare-node-deps step-build-node-artifact-deps
    step-create-shard step-upload-shard
]
use ./constants.nu [gen-workflow-header]

const BUILD_SERVICE_TRIGGER = 'on:
  workflow_call:
    inputs:
      service:
        description: "Service name to build"
        required: true
        type: string
      push:
        description: "Push images to registry"
        required: false
        type: boolean
        default: false
      dependencies:
        description: "Comma-separated list of dependency service names for artifact loading"
        required: false
        type: string
        default: ""
      disk_monitor_mode:
        description: "Disk monitoring mode: off, basic"
        required: false
        type: string
        default: "off"
      prune_build_cache:
        description: "Enable pruning of BuildKit cache mounts"
        required: false
        type: boolean
        default: true'

def gen-setup-steps [] {
    [
        (step-checkout)
        (step-install-nushell)
        {
            name: "Generate service matrix"
            id: "matrix"
            run: "MATRIX_JSON=$(nu -c \"use scripts/lib/build/matrix.nu [generate-service-matrix]; generate-service-matrix '${{ inputs.service }}' --include-metadata=false | to json -r\")
echo \"matrix=$MATRIX_JSON\" >> $GITHUB_OUTPUT
echo \"Generated matrix for ${{ inputs.service }}:\"
echo \"$MATRIX_JSON\" | jq ."
        }
    ]
}

def gen-build-steps [] {
    let base = (step-common-setup)
    let deps = [(step-prepare-node-deps)]
    let build = [
        (step-build-node-artifact-deps)
        (step-create-shard)
        (step-upload-shard)
    ]
    
    $base | append $deps | append $build
}

export def generate [] {
    let header = (gen-workflow-header 
        "Reusable workflow for building a single service using a dynamic version+platform matrix"
        "nu scripts/dockypody.nu ci workflow --target build-service"
        "Build Service"
        $BUILD_SERVICE_TRIGGER)

    let setup_yaml = (yaml-steps (gen-setup-steps))
    let build_yaml = (yaml-steps (gen-build-steps))

    $header + "

jobs:
  setup:
    name: Setup matrix for ${{ inputs.service }}
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.matrix.outputs.matrix }}
    steps:
" + (indent $setup_yaml 3) + "

  build:
    name: ${{ matrix.version }}${{ matrix.platform != '' && format('-{0}', matrix.platform) || '' }}
    needs: [setup]
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      max-parallel: 10
      matrix: ${{ fromJson(needs.setup.outputs.matrix) }}
    steps:
" + (indent $build_yaml 3) + "
"
}
