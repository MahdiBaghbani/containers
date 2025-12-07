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

use ./yaml.nu [indent yaml-steps]
use ./steps.nu [
    step-checkout step-install-nushell step-common-setup
    step-parse-deps step-restore-deps step-restore-owner-cache
    step-cache-match-kind step-load-cached-images
    step-build-node step-create-shard step-upload-shard
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
        description: "Comma-separated list of dependency service names for cache restore"
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
            run: 'MATRIX_JSON=$(nu -c "use scripts/lib/build/matrix.nu [generate-service-matrix]; generate-service-matrix ''${{ inputs.service }}'' --include-metadata=false | to json -r")
echo "matrix=$MATRIX_JSON" >> $GITHUB_OUTPUT
echo "Generated matrix for ${{ inputs.service }}:"
echo "$MATRIX_JSON" | jq .'
        }
    ]
}

def gen-build-steps [] {
    let base = (step-common-setup)
    let deps = [(step-parse-deps)] | append (step-restore-deps)
    let cache = [
        (step-restore-owner-cache)
        (step-cache-match-kind)
        (step-load-cached-images)
    ]
    let build = [
        (step-build-node)
        (step-create-shard)
        (step-upload-shard)
    ]
    
    $base | append $deps | append $cache | append $build
}

def gen-update-cache-steps [] {
    (step-common-setup) | append [
        {
            name: "Download all shard artifacts"
            uses: "actions/download-artifact@v4"
            with: {
                pattern: "shard-${{ inputs.service }}-*"
                path: "/tmp/docker-images/shards/${{ inputs.service }}/"
                merge-multiple: "true"
            }
        }
        {
            name: "List downloaded shards"
            run: 'echo "Downloaded shards:"
ls -la /tmp/docker-images/shards/${{ inputs.service }}/ || echo "No shards directory"
find /tmp/docker-images/shards/ -name "*.nuon" -o -name "*.tar.zst" 2>/dev/null || true'
        }
        {
            name: "Merge cache shards"
            run: 'nu scripts/dockypody.nu ci merge-cache-shards --service ${{ inputs.service }} --ref ${{ github.ref }} --sha ${{ github.sha }}'
        }
        {
            name: "Save Docker image cache"
            uses: "actions/cache/save@v4"
            with: {
                path: "/tmp/docker-images/${{ inputs.service }}/"
                key: "images-${{ inputs.service }}-${{ github.ref }}-${{ github.sha }}"
            }
        }
        {
            name: "Delete shard artifacts"
            if: "always()"
            uses: "geekyeggo/delete-artifact@v5"
            with: {
                name: "shard-${{ inputs.service }}-*"
                failOnError: "false"
            }
        }
    ]
}

export def generate [] {
    let header = (gen-workflow-header 
        "Reusable workflow for building a single service using a dynamic version+platform matrix"
        "nu scripts/dockypody.nu ci workflow --target build-service"
        "Build Service"
        $BUILD_SERVICE_TRIGGER)

    let setup_yaml = (yaml-steps (gen-setup-steps))
    let build_yaml = (yaml-steps (gen-build-steps))
    let update_yaml = (yaml-steps (gen-update-cache-steps))

    $header + '

jobs:
  setup:
    name: Setup matrix for ${{ inputs.service }}
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.matrix.outputs.matrix }}
    steps:
' + (indent $setup_yaml 3) + '

  build:
    name: Build ${{ inputs.service }} (${{ matrix.version }}${{ matrix.platform != '''' && format(''-{0}'', matrix.platform) || '''' }})
    needs: [setup]
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      max-parallel: 10
      matrix: ${{ fromJson(needs.setup.outputs.matrix) }}
    steps:
' + (indent $build_yaml 3) + '

  update_cache:
    name: Update cache for ${{ inputs.service }}
    needs: [setup, build]
    if: always() && needs.setup.result == ''success''
    runs-on: ubuntu-latest
    steps:
' + (indent $update_yaml 3) + '
'
}
