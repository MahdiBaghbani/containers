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

# Suite-local temp repo/context helpers and seeders.

export const SYNTH_DEP_TOOLS = "synth-dep-tools"
export const SYNTH_BASE_SVC = "synth-base-svc"
export const SYNTH_PARENT_SVC = "synth-parent-svc"
export const SYNTH_PARENT_VERSION = "v2.0.0"

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

export def make-temp-context [] {
  let tmp = (^mktemp -d | str trim)
  mkdir $tmp
  $tmp
}

export def rm-temp-context [dir: string] {
  try { rm -rf $dir } catch { }
}

export def with-git-file-protocol-allowed [block: closure] {
  let saved = {
    count: (try { $env.GIT_CONFIG_COUNT } catch { "" })
    key0: (try { $env.GIT_CONFIG_KEY_0 } catch { "" })
    val0: (try { $env.GIT_CONFIG_VALUE_0 } catch { "" })
  }
  $env.GIT_CONFIG_COUNT = "1"
  $env.GIT_CONFIG_KEY_0 = "protocol.file.allow"
  $env.GIT_CONFIG_VALUE_0 = "always"
  let result = (try { do $block } catch {|err|
    if ($saved.count | str length) > 0 {
      $env.GIT_CONFIG_COUNT = $saved.count
    } else {
      hide-env GIT_CONFIG_COUNT
    }
    if ($saved.key0 | str length) > 0 {
      $env.GIT_CONFIG_KEY_0 = $saved.key0
    } else {
      hide-env GIT_CONFIG_KEY_0
    }
    if ($saved.val0 | str length) > 0 {
      $env.GIT_CONFIG_VALUE_0 = $saved.val0
    } else {
      hide-env GIT_CONFIG_VALUE_0
    }
    error make {msg: $err.msg}
  })
  if ($saved.count | str length) > 0 {
    $env.GIT_CONFIG_COUNT = $saved.count
  } else {
    hide-env GIT_CONFIG_COUNT
  }
  if ($saved.key0 | str length) > 0 {
    $env.GIT_CONFIG_KEY_0 = $saved.key0
  } else {
    hide-env GIT_CONFIG_KEY_0
  }
  if ($saved.val0 | str length) > 0 {
    $env.GIT_CONFIG_VALUE_0 = $saved.val0
  } else {
    hide-env GIT_CONFIG_VALUE_0
  }
  $result
}

export def seed-local-git-repo [repo: string] {
  mkdir $repo
  "fixture" | save -f ($repo | path join "README.md")
  ^git -C $repo init -q
  ^git -C $repo config user.email "test@example.com"
  ^git -C $repo config user.name "Test User"
  ^git -C $repo add README.md
  ^git -C $repo commit -q -m "init"
  ^git -C $repo rev-parse HEAD
}

export def seed-git-repo-with-submodule [base: string] {
  let sub = ($base | path join "submodule")
  let origin = ($base | path join "origin")

  mkdir $sub
  "submodule fixture" | save -f ($sub | path join "sub-marker.txt")
  ^git -C $sub init -q
  ^git -C $sub config user.email "test@example.com"
  ^git -C $sub config user.name "Test User"
  ^git -C $sub add sub-marker.txt
  ^git -C $sub commit -q -m "sub init"

  mkdir $origin
  "parent fixture" | save -f ($origin | path join "README.md")
  ^git -C $origin init -q
  ^git -C $origin config user.email "test@example.com"
  ^git -C $origin config user.name "Test User"
  ^git -C $origin add README.md
  ^git -C $origin commit -q -m "parent init"

  let sub_url = "../submodule"
  ^git -c protocol.file.allow=always -C $origin submodule add -q $sub_url submodule
  ^git -C $origin commit -q -m "add submodule"

  let head = (^git -C $origin rev-parse HEAD | str trim)
  let branch = (^git -C $origin branch --show-current | str trim)
  {
    origin: $origin
    sub: $sub
    head: $head
    branch: $branch
    url: $"file://($origin)"
  }
}

export def run-in-temp-repo [repo: string, block: closure] {
  do -i { cd $repo; do $block }
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

export def seed-synth-dep-tools-fixture [repo: string] {
  seed-minimal-service-base $repo $SYNTH_DEP_TOOLS
  seed-debian-platforms $repo $SYNTH_DEP_TOOLS
  {
    default: "v1.0.0"
    versions: [{ name: "v1.0.0", overrides: {} }]
  } | save -f ($repo | path join $"services/($SYNTH_DEP_TOOLS)/versions.nuon")
}

export def seed-synth-base-svc-fixture [repo: string] {
  seed-minimal-service-base $repo $SYNTH_BASE_SVC
  seed-prod-dev-platforms $repo $SYNTH_BASE_SVC
  {
    default: "master"
    versions: [{ name: "master", overrides: {} }]
  } | save -f ($repo | path join $"services/($SYNTH_BASE_SVC)/versions.nuon")
}

export def seed-synth-parent-graph-fixture [repo: string] {
  seed-synth-dep-tools-fixture $repo
  seed-minimal-service-base $repo $SYNTH_PARENT_SVC
  seed-prod-dev-platforms $repo $SYNTH_PARENT_SVC
  {
    default: $SYNTH_PARENT_VERSION
    defaults: {
      dependencies: {
        ($SYNTH_DEP_TOOLS): { version: "v1.0.0-debian" }
      }
    }
    versions: [{ name: $SYNTH_PARENT_VERSION, overrides: {} }]
  } | save -f ($repo | path join $"services/($SYNTH_PARENT_SVC)/versions.nuon")
}

export const ALL_SERVICES_A = "all-svc-a"
export const ALL_SERVICES_B = "all-svc-b"
export const ALL_SERVICES_C = "all-svc-c"
export const ALL_SERVICES_D = "all-svc-d"

export def make-temp-build-repo [] {
  let tmp = (make-temp-repo)
  mkdir ($tmp | path join "scripts" "lib" "ssh")
  "# test stub for prepare-ssh-context" | save -f ($tmp | path join "scripts" "lib" "ssh" "sshd.nu")
  $tmp
}

export def seed-build-service-for-all-services [
  repo: string,
  name: string,
  dependencies: record = {},
  parent_defaults: record = {}
] {
  mkdir ($repo | path join "services" $name)
  "FROM scratch" | save -f ($repo | path join "services" $name "Dockerfile")

  mut manifest = {
    name: $name
    context: $"services/($name)"
    dockerfile: $"services/($name)/Dockerfile"
  }
  if not ($dependencies | is-empty) {
    $manifest = ($manifest | insert dependencies $dependencies)
  }
  $manifest | save -f ($repo | path join "services" $"($name).nuon")

  mut versions = {
    default: "v1"
    versions: [{ name: "v1", latest: true }]
  }
  if not ($parent_defaults | is-empty) {
    $versions = ($versions | insert defaults $parent_defaults)
  }
  $versions | save -f ($repo | path join "services" $name "versions.nuon")
}

export def seed-all-services-continue-fixture [repo: string] {
  seed-build-service-for-all-services $repo $ALL_SERVICES_A
  seed-build-service-for-all-services $repo $ALL_SERVICES_B {
    ($ALL_SERVICES_A): { build_arg: "A_IMAGE" }
  } {
    dependencies: {
      ($ALL_SERVICES_A): { version: "v1" }
    }
  }
  seed-build-service-for-all-services $repo $ALL_SERVICES_C {
    ($ALL_SERVICES_B): { build_arg: "B_IMAGE" }
  } {
    dependencies: {
      ($ALL_SERVICES_B): { version: "v1" }
    }
  }
  seed-build-service-for-all-services $repo $ALL_SERVICES_D
}

export def seed-all-services-dep-cache-fixture [repo: string] {
  seed-build-service-for-all-services $repo $ALL_SERVICES_A
  seed-build-service-for-all-services $repo $ALL_SERVICES_B {
    ($ALL_SERVICES_A): { build_arg: "A_IMAGE" }
  } {
    dependencies: {
      ($ALL_SERVICES_A): { version: "v1" }
    }
  }
  seed-build-service-for-all-services $repo $ALL_SERVICES_D
}

export def make-docker-stub-fail-on [log_file: string, fail_pattern: string] {
  let stub_dir = (^mktemp -d | str trim)
  let script = (
    "#!/bin/sh\n"
    + $"printf '%s\\n' \"$*\" >> '($log_file)'\n"
    + $"case \"$*\" in\n"
    + $"  *($fail_pattern)*) exit 1 ;;\n"
    + $"  *) exit 0 ;;\n"
    + $"esac\n"
  )
  $script | save -f ($stub_dir | path join "docker")
  ^chmod +x ($stub_dir | path join "docker")
  $stub_dir
}

export def run-dockypody-in-repo [repo: string, entry: string, args: list<string>] {
  do -i { cd $repo; ^nu $entry ...$args } | complete
}
