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
        uses: "actions/checkout@v4"
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
        uses: "docker/setup-buildx-action@v3"
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

# Generate dependency cache restore steps (up to 8)
export def step-restore-deps [] {
    1..8 | each {|i|
        {
            name: $"Restore dep($i) cache"
            if: $"steps.deps.outputs.dep($i) != ''"
            uses: "actions/cache/restore@v4"
            with: {
                path: $"/tmp/docker-images/${{ steps.deps.outputs.dep($i) }}/"
                key: $"images-${{ steps.deps.outputs.dep($i) }}-${{ github.ref }}-${{ github.sha }}"
                restore-keys: $"images-${{ steps.deps.outputs.dep($i) }}-${{ github.ref }}-"
            }
        }
    }
}

export def step-parse-deps [] {
    {
        name: "Parse dependencies"
        id: "deps"
        run: "DEPS=\"${{ inputs.dependencies }}\"
echo \"Parsing dependencies: '$DEPS'\"
IFS=',' read -ra DEP_ARRAY <<< \"$DEPS\"
COUNT=${#DEP_ARRAY[@]}
for i in {1..8}; do
  IDX=$((i - 1))
  if [ $IDX -lt $COUNT ] && [ -n \"${DEP_ARRAY[$IDX]}\" ]; then
    DEP=$(echo \"${DEP_ARRAY[$IDX]}\" | xargs)
    echo \"dep${i}=${DEP}\" >> $GITHUB_OUTPUT
  else
    echo \"dep${i}=\" >> $GITHUB_OUTPUT
  fi
done
echo \"Total dependencies: $COUNT (max 8 restored)\""
    }
}

export def step-restore-owner-cache [] {
    {
        name: "Restore Docker image cache"
        id: "cache-restore"
        uses: "actions/cache/restore@v4"
        with: {
            path: "/tmp/docker-images/${{ inputs.service }}/"
            key: "images-${{ inputs.service }}-${{ github.ref }}-${{ github.sha }}"
            restore-keys: "images-${{ inputs.service }}-${{ github.ref }}-"
        }
    }
}

export def step-cache-match-kind [] {
    {
        name: "Determine cache match kind"
        id: "cache-match"
        run: 'PRIMARY_KEY="images-${{ inputs.service }}-${{ github.ref }}-${{ github.sha }}"
MATCHED_KEY="${{ steps.cache-restore.outputs.cache-matched-key }}"
CACHE_HIT="${{ steps.cache-restore.outputs.cache-hit }}"
if [ "$CACHE_HIT" = "true" ]; then
  if [ "$MATCHED_KEY" = "$PRIMARY_KEY" ]; then
    MATCH_KIND="exact"
  else
    MATCH_KIND="fallback"
  fi
else
  MATCH_KIND="miss"
fi
echo "Cache match kind: $MATCH_KIND"
echo "match_kind=$MATCH_KIND" >> $GITHUB_OUTPUT'
    }
}

export def step-load-cached-images [] {
    {
        name: "Load cached images"
        if: "steps.cache-restore.outputs.cache-hit == 'true'"
        run: 'if [ -d "/tmp/docker-images/${{ inputs.service }}" ]; then
  echo "Loading cached images for ${{ inputs.service }}..."
  nu scripts/dockypody.nu ci load-owner --service ${{ inputs.service }}
fi'
    }
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

# Build node using artifact-based deps (new flow without actions/cache)
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

# Legacy: Build node with cache-match (for backward compatibility, not used in new workflows)
export def step-build-node [] {
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
  --cache-match=${{ steps.cache-match.outputs.match_kind }} \\
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
        uses: "actions/upload-artifact@v4"
        with: {
            name: "shard-${{ inputs.service }}-${{ matrix.version }}-${{ matrix.platform != '' && matrix.platform || 'single' }}"
            path: "/tmp/docker-images/shards/${{ inputs.service }}/"
            retention-days: "1"
            if-no-files-found: "error"
        }
    }
}
