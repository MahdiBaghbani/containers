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

# Orchestration suite fixtures and temp-repo helpers

use ../../lib/plane/presence.nu [local-root-path local-services-path]
use ../../lib/plane/audit.nu [LOCAL_MIRROR_FILE]

export const TRACKED_SMOKE_SVC = "kasm-base"

export const ISOLATION_SVC = "test-svc"
export const ISOLATION_TRACKED_V1 = "v1"
export const ISOLATION_TRACKED_V2 = "v2"
export const ISOLATION_LOCAL_ONLY = "dev-local-only"

export const ORCH_MATRIX_SVC = "orch-matrix-svc"
export const ORCH_BASE_DEP = "orch-base-dep"
export const ORCH_V_MASTER = "master"
export const ORCH_V_TAG = "v2.0.0"
export const ORCH_ALL_SVCS = ["orch-svc-a" "orch-svc-b" "orch-svc-c" "orch-svc-d"]
export const ORCH_PROD_SVCS = ["orch-prod-a" "orch-prod-b"]

export def make-temp-repo [] {
    let tmp = (^mktemp -d | str trim)
    mkdir $tmp
    mkdir ($tmp | path join "services")
    ^git -C $tmp init -q
    $tmp
}

export def rm-temp-repo [dir: string] {
    try { rm -rf $dir } catch { }
}

export def with-temp-repo [block: closure] {
    let repo = (make-temp-repo)
    let result = (try {
        do $block $repo
    } catch {|err|
        rm-temp-repo $repo
        error make {msg: $err.msg}
    })
    rm-temp-repo $repo
    $result
}

export def seed-tracked-versions [repo: string, versions_manifest: record, name: string] {
    { name: $name } | save -f ($repo | path join $"services/($name).nuon")
    mkdir ($repo | path join $"services/($name)")
    $versions_manifest | save -f ($repo | path join $"services/($name)/versions.nuon")
}

export def save-local-fragment [repo: string, name: string, fragment: record] {
    let mirror = (local-services-path $repo | path join $name)
    mkdir $mirror
    $fragment | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
}

export def seed-minimal-service-base [repo: string, name: string] {
    {
        name: $name
        context: $"services/($name)"
        dockerfile: $"services/($name)/Dockerfile"
        sources: {
            app: { url: "https://example.com/app.git", ref: "main" }
        }
        external_images: {
            build: { name: "golang", tag: "1.25-trixie", build_arg: "BASE_BUILD_IMAGE" }
        }
    } | save -f ($repo | path join $"services/($name).nuon")
    mkdir ($repo | path join $"services/($name)")
}

export def seed-prod-dev-platforms [repo: string, name: string] {
    {
        default: "production"
        platforms: [
            {
                name: "production"
                dockerfile: $"services/($name)/Dockerfile.production"
                external_images: {
                    build: { name: "golang", build_arg: "BASE_BUILD_IMAGE" }
                }
            }
            {
                name: "development"
                dockerfile: $"services/($name)/Dockerfile.development"
                external_images: {
                    build: { name: "golang", build_arg: "BASE_BUILD_IMAGE" }
                }
            }
        ]
    } | save -f ($repo | path join $"services/($name)/platforms.nuon")
}

export def seed-debian-platforms [repo: string, name: string] {
    {
        default: "debian"
        platforms: [
            {
                name: "debian"
                dockerfile: $"services/($name)/Dockerfile.debian"
                external_images: {
                    build: { name: "golang", build_arg: "BASE_BUILD_IMAGE" }
                }
            }
            {
                name: "alpine"
                dockerfile: $"services/($name)/Dockerfile.alpine"
                external_images: {
                    build: { name: "golang", build_arg: "BASE_BUILD_IMAGE" }
                }
            }
        ]
    } | save -f ($repo | path join $"services/($name)/platforms.nuon")
}

export def seed-orchestration-matrix-fixture [repo: string] {
    seed-minimal-service-base $repo $ORCH_MATRIX_SVC
    seed-prod-dev-platforms $repo $ORCH_MATRIX_SVC
    {
        default: $ORCH_V_TAG
        defaults: {
            dependencies: {
                ($ORCH_BASE_DEP): { version: "v1.0.0-debian" }
            }
        }
        versions: [
            { name: $ORCH_V_MASTER, overrides: {} }
            { name: $ORCH_V_TAG, overrides: {} }
        ]
    } | save -f ($repo | path join $"services/($ORCH_MATRIX_SVC)/versions.nuon")

    seed-minimal-service-base $repo $ORCH_BASE_DEP
    seed-debian-platforms $repo $ORCH_BASE_DEP
    {
        default: "v1.0.0"
        versions: [{ name: "v1.0.0", overrides: {} }]
    } | save -f ($repo | path join $"services/($ORCH_BASE_DEP)/versions.nuon")
}

export def seed-orchestration-all-services-fixture [repo: string] {
    for name in $ORCH_ALL_SVCS {
        seed-minimal-service-base $repo $name
        {
            default: "v1.0.0"
            versions: [{ name: "v1.0.0", overrides: {} }]
        } | save -f ($repo | path join $"services/($name)/versions.nuon")
    }
}

export def seed-orchestration-production-fixture [repo: string] {
    for name in $ORCH_PROD_SVCS {
        seed-minimal-service-base $repo $name
        seed-prod-dev-platforms $repo $name
        {
            default: "v1.0.0"
            versions: [{ name: "v1.0.0", overrides: {} }]
        } | save -f ($repo | path join $"services/($name)/versions.nuon")
    }
}

export def seed-tracked-plane-isolation-fixture [repo: string] {
    seed-tracked-versions $repo {
        default: $ISOLATION_TRACKED_V1
        versions: [
            { name: $ISOLATION_TRACKED_V1, overrides: {} }
            { name: $ISOLATION_TRACKED_V2, overrides: {} }
        ]
    } $ISOLATION_SVC
    mkdir (local-root-path $repo)
    save-local-fragment $repo $ISOLATION_SVC {
        versions: [
            {
                name: $ISOLATION_LOCAL_ONLY
                overrides: {}
            }
            {
                name: $ISOLATION_TRACKED_V2
                overrides: {
                    sources: {
                        my_src: { path: "../local-src" }
                    }
                }
            }
        ]
    }
}

export def run-dockypody-in-repo [repo: string, entry: string, args: list<string>] {
    do -i { cd $repo; ^nu $entry ...$args } | complete
}
