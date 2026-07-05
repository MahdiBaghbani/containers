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

# Env-path, inspect, materialization, and effective-config guard-order tests.

use ../../lib/plane/guard.nu [guard-local-plane-presence PLANE_LOCAL]
use ../../lib/plane/effective-config.nu [apply-local-plane-effective-sources]
use ../../lib/build/config.nu [load-service-config detect-all-source-types]
use ../../lib/build/args.nu [generate-build-args]
use ../../lib/manifest/core.nu [load-versions-manifest apply-version-defaults]
use ../../lib/plane/presence.nu [local-root-path]
use ../lib.nu [run-test]
use ./_fixtures.nu [
  make-temp-repo rm-temp-repo seed-service-with-git-source run-in-temp-repo
  run-dockypody-in-repo dockypody-entry expect-effective-config-error
]

export def test-env-only-source-path-materializes [verbose: bool] {
  run-test "env-only SOURCE_PATH materializes with empty legal topology" {
    let repo = (make-temp-repo)
    seed-service-with-git-source $repo
    mkdir (local-root-path $repo)
    mkdir ($repo | path join "local-src")
    let plane_ctx = (guard-local-plane-presence $repo)
    let merged = {
      sources: {
        my_src: {
          url: "https://example.com/repo.git"
          ref: "main"
        }
      }
    }
    let expected_path = ($repo | path join "local-src" | path expand)
    let out = (run-in-temp-repo $repo {||
      $env.MY_SRC_PATH = ($env.PWD | path join "local-src")
      apply-local-plane-effective-sources $merged "test-svc" { name: "v1" } $plane_ctx
    })
    let materialized = (try { $out.sources.my_src.path | path expand } catch { "" })
    if $materialized != $expected_path {
      error make {msg: $"Expected exact env path ($expected_path), got: ($materialized)"}
    }
    if ("url" in ($out.sources.my_src | columns)) or ("ref" in ($out.sources.my_src | columns)) {
      error make {msg: "Env-only materialization must replace git fields with path only"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-invalid-env-source-path [verbose: bool] {
  run-test "invalid env SOURCE_PATH hard-errors" {
    let repo = (make-temp-repo)
    seed-service-with-git-source $repo
    mkdir (local-root-path $repo)
    let plane_ctx = (guard-local-plane-presence $repo)
    let merged = {
      sources: {
        my_src: {
          url: "https://example.com/repo.git"
          ref: "main"
        }
      }
    }
    let ok = (run-in-temp-repo $repo {||
      $env.MY_SRC_PATH = "/etc/passwd"
      expect-effective-config-error {||
        apply-local-plane-effective-sources $merged "test-svc" { name: "v1" } $plane_ctx
      } "invalid path"
    })
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-load-service-config-env-materialization [verbose: bool] {
  run-test "load-service-config env-only materialization under local plane" {
    let repo = (make-temp-repo)
    seed-service-with-git-source $repo
    mkdir (local-root-path $repo)
    mkdir ($repo | path join "local-src")
    let plane_ctx = (guard-local-plane-presence $repo)
    let manifest = (run-in-temp-repo $repo {|| load-versions-manifest "test-svc" })
    let version_spec = (apply-version-defaults $manifest { name: "v1", overrides: {} })
    let expected_path = ($repo | path join "local-src" | path expand)
    let out = (run-in-temp-repo $repo {||
      $env.MY_SRC_PATH = ($env.PWD | path join "local-src")
      load-service-config "test-svc" $version_spec "" null $plane_ctx
    })
    let materialized = (try { $out.sources.my_src.path | path expand } catch { "" })
    if $materialized != $expected_path {
      error make {msg: $"Expected load-service-config env path ($expected_path), got: ($materialized)"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-build-args-ignore-post-guard-env [verbose: bool] {
  run-test "local plane build args ignore post-guard env PATH and MODE overrides" {
    let repo = (make-temp-repo)
    seed-service-with-git-source $repo
    mkdir (local-root-path $repo)
    mkdir ($repo | path join "local-src")
    let plane_ctx = (guard-local-plane-presence $repo)
    let manifest = (run-in-temp-repo $repo {|| load-versions-manifest "test-svc" })
    let version_spec = (apply-version-defaults $manifest { name: "v1", overrides: {} })
    let cfg = (run-in-temp-repo $repo {||
      $env.MY_SRC_PATH = ($env.PWD | path join "local-src")
      load-service-config "test-svc" $version_spec "" null $plane_ctx
    })
    let guarded_path = (try { $cfg.sources.my_src.path } catch { "" })
    let build_args = (run-in-temp-repo $repo {||
      $env.MY_SRC_PATH = "/etc/passwd"
      $env.MY_SRC_MODE = "git"
      let source_types = (detect-all-source-types $cfg.sources $PLANE_LOCAL)
      generate-build-args "v1" $cfg {sha: "abc", is_local: true, platforms: []} {} {enabled: false} {enabled: false} "" false {} $source_types {} $PLANE_LOCAL
    })
    let arg_path = (try { $build_args.MY_SRC_PATH } catch { "" })
    if $arg_path != $guarded_path {
      error make {msg: $"Expected build arg path to match guard-owned path '($guarded_path)', got: '($arg_path)'"}
    }
    let arg_mode = (try { $build_args.MY_SRC_MODE } catch { "" })
    if $arg_mode != "local" {
      error make {msg: $"Expected build arg mode 'local', got: '($arg_mode)'"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-inspect-effective-config-success [verbose: bool] {
  run-test "inspect effective-config returns guard-owned merged config on local plane" {
    let repo = (make-temp-repo)
    seed-service-with-git-source $repo
    mkdir (local-root-path $repo)
    mkdir ($repo | path join "local-src")
    let expected_path = ($repo | path join "local-src" | path expand)
    let entry = (dockypody-entry)
    let out = (run-in-temp-repo $repo {||
      $env.MY_SRC_PATH = ($env.PWD | path join "local-src")
      ^nu $entry inspect effective-config --service test-svc --plane local | complete
    })
    if $out.exit_code != 0 {
      error make {msg: $"Expected inspect success, exit ($out.exit_code): ($out.stderr)"}
    }
    let cfg = (try {
      $out.stdout | from json
    } catch {
      error make {msg: $"Expected JSON stdout, got: ($out.stdout)"}
    })
    let materialized = (try { $cfg.sources.my_src.path | path expand } catch { "" })
    if $materialized != $expected_path {
      error make {msg: $"Expected inspect env path ($expected_path), got: ($materialized)"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-missing-root-presence-contract [verbose: bool] {
  run-test "missing root failure names presence contract before topology audit" {
    let repo = (make-temp-repo)
    let result = (try {
      guard-local-plane-presence $repo
      { ok: true }
    } catch {|err|
      { ok: false, msg: $err.msg }
    })
    rm-temp-repo $repo
    if $result.ok {
      error make {msg: "Expected guard to fail when local root is missing"}
    }
    if not ($result.msg | str contains "requires local root directory") {
      error make {msg: $"Expected presence contract error, got: ($result.msg)"}
    }
    for forbidden in ["Unsupported local root", "Unknown local service mirror", "Incomplete local service mirror"] {
      if ($result.msg | str contains $forbidden) {
        error make {msg: $"Missing root must not surface topology audit error '($forbidden)': ($result.msg)"}
      }
    }
    true
  } $verbose
}

export def test-inspect-routes-through-guard [verbose: bool] {
  run-test "inspect effective-config routes through guard on local plane" {
    let repo = (make-temp-repo)
    seed-service-with-git-source $repo
    let out = (run-dockypody-in-repo $repo ["inspect" "effective-config" "--service" "test-svc" "--plane" "local"])
    rm-temp-repo $repo
    if $out.exit_code == 0 {
      error make {msg: "Expected inspect to fail when local root is missing"}
    }
    if not (($out.stderr | str join " ") | str contains ".dockypody.local") {
      error make {msg: $"Expected guard error mentioning .dockypody.local, got: ($out.stderr)"}
    }
    true
  } $verbose
}
