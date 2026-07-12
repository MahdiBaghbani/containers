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

# Reusable step definitions for GitHub Actions workflows

const NU_VERSION = "0.108.0"

export def step-checkout [] {
    {
        name: "Checkout"
        uses: "actions/checkout@v5"
    }
}

export def step-install-nushell [] {
    {
        name: "Install Nushell"
        env: { NU_VERSION: $NU_VERSION }
        run: 'curl -fsSL -o /tmp/nu.tar.gz "https://github.com/nushell/nushell/releases/download/${{ env.NU_VERSION }}/nu-${{ env.NU_VERSION }}-x86_64-unknown-linux-gnu.tar.gz"
mkdir -p /tmp/nu
tar -xzf /tmp/nu.tar.gz -C /tmp/nu --strip-components=1
sudo mv /tmp/nu/nu /usr/local/bin/nu
nu --version'
    }
}

export def step-install-zstd [] {
    {
        name: "Install zstd"
        run: "sudo apt-get update -qq
sudo apt-get install -y zstd"
    }
}

export def step-setup-buildx [] {
    {
        name: "Set up Docker Buildx"
        uses: "docker/setup-buildx-action@v4"
        with: { driver: "docker" }
    }
}

# Common setup steps used by most jobs
export def step-common-setup [] {
    [
        (step-checkout)
        (step-install-nushell)
        (step-install-zstd)
        (step-setup-buildx)
    ]
}

# Log in to container registry (only when push is enabled)
export def step-login-registry [] {
    {
        name: "Log in to container registry"
        if: "${{ inputs.push }}"
        env: {
            GITHUB_TOKEN: "${{ secrets.GITHUB_TOKEN }}"
            GITHUB_ACTOR: "${{ github.actor }}"
        }
        run: "nu scripts/dockypody.nu ci login-registry"
    }
}

# Prepare dependency shards from artifacts (new artifact-based CI flow)
export def step-prepare-node-deps [] {
    {
        name: "Prepare dependency shards"
        env: { GITHUB_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: 'DEPS="${{ inputs.dependencies }}"
PLATFORM="${{ matrix.platform }}"
if [ -n "$DEPS" ]; then
  PLATFORM_FLAG=""
  if [ -n "$PLATFORM" ]; then
    PLATFORM_FLAG="--platform $PLATFORM"
  fi
  nu scripts/dockypody.nu ci prepare-node-deps --service ${{ inputs.service }} --version ${{ matrix.version }} $PLATFORM_FLAG --dependencies "$DEPS"
else
  echo "No dependencies to prepare"
fi'
    }
}

# Build node using artifact-based dependency shards
export def step-build-node-artifact-deps [] {
    {
        name: "Build node"
        run: "PLATFORM_FLAG=\"\"
if [ -n \"${{ matrix.platform }}\" ]; then
  PLATFORM_FLAG=\"--platform ${{ matrix.platform }}\"
fi
nu scripts/dockypody.nu build \\
  --service ${{ inputs.service }} \\
  --version ${{ matrix.version }} \\
  $PLATFORM_FLAG \\
  --dep-cache=soft \\
  --pull=deps,externals \\
  --disk-monitor=${{ inputs.disk_monitor_mode }} \\
  ${{ inputs.prune_build_cache && '--prune-cache-mounts' || '' }} \\
  ${{ inputs.push && '--push' || '' }}"
    }
}

export def step-create-shard [] {
    {
        name: "Create cache shard"
        env: { SHARD_ROOT: "/tmp/docker-images/shards" }
        run: "nu -c \"use scripts/lib/ci/cache-shards.nu [create-node-shard]; create-node-shard '${{ inputs.service }}' '${{ matrix.version }}' '$SHARD_ROOT/${{ inputs.service }}' '${{ matrix.platform }}'\""
    }
}

export def step-upload-shard [] {
    {
        name: "Upload shard artifact"
        uses: "actions/upload-artifact@v6"
        with: {
            name: "shard-${{ inputs.service }}-${{ matrix.version }}-${{ matrix.platform != '' && matrix.platform || 'single' }}"
            path: "/tmp/docker-images/shards/${{ inputs.service }}/"
            retention-days: "1"
            if-no-files-found: "error"
        }
    }
}
