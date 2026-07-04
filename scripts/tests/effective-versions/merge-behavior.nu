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

# Local fragment merge behavior tests.

use ../../lib/plane/versions.nu [load-effective-versions-manifest]
use ../../lib/plane/guard.nu [guard-local-plane-presence]
use ../../lib/plane/presence.nu [local-root-path]
use ../lib.nu [run-test]
use ./fixtures.nu [
  make-temp-repo rm-temp-repo run-in-temp-repo
  seed-tracked-versions save-local-fragment
]

export def test-replace-by-name [verbose: bool] {
  run-test "local fragment replaces same-named version" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      defaults: {
        sources: {
          my_src: { url: "https://example.com/repo.git", ref: "main" }
        }
      }
      versions: [
        { name: "v1", overrides: {} }
        { name: "v2", overrides: { sources: { my_src: { ref: "v2-tag" } } } }
      ]
    }
    mkdir (local-root-path $repo)
    save-local-fragment $repo "test-svc" {
      versions: [{
        name: "v2"
        overrides: {
          sources: {
            my_src: { path: "../local-src" }
          }
        }
      }]
    }
    let plane_ctx = (guard-local-plane-presence $repo)
    let out = (run-in-temp-repo $repo {||
      load-effective-versions-manifest "test-svc" $plane_ctx
    })
    if ($out.versions | length) != 2 {
      error make {msg: $"Expected two versions, got ($out.versions | length)"}
    }
    let v2 = ($out.versions | where {|v| $v.name == "v2" } | first)
    let path = (try { $v2.overrides.sources.my_src.path } catch { "" })
    if $path != "../local-src" {
      error make {msg: $"Expected local path replacement, got ($path)"}
    }
    let tracked_ref = (try { $v2.overrides.sources.my_src.ref } catch { null })
    if $tracked_ref != null {
      error make {msg: $"Replaced version must not keep tracked ref, got ($tracked_ref)"}
    }
    let v1 = ($out.versions | where {|v| $v.name == "v1" } | first)
    if $v1 == null {
      error make {msg: "Tracked v1 must remain after replace-by-name"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-append-new [verbose: bool] {
  run-test "local fragment appends new version names in fragment order" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      defaults: {
        sources: {
          my_src: { url: "https://example.com/repo.git", ref: "main" }
        }
      }
      versions: [{ name: "v1", overrides: {} }]
    }
    mkdir (local-root-path $repo)
    save-local-fragment $repo "test-svc" {
      versions: [
        {
          name: "dev"
          overrides: {
            sources: { my_src: { path: "../dev-src" } }
          }
        }
        {
          name: "beta"
          overrides: {
            sources: { my_src: { path: "../beta-src" } }
          }
        }
      ]
    }
    let plane_ctx = (guard-local-plane-presence $repo)
    let out = (run-in-temp-repo $repo {||
      load-effective-versions-manifest "test-svc" $plane_ctx
    })
    let names = ($out.versions | each {|v| $v.name })
    if $names != ["v1" "dev" "beta"] {
      error make {msg: $"Expected [v1, dev, beta], got ($names | to json)"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-default-override [verbose: bool] {
  run-test "local fragment default overrides tracked default" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      defaults: {
        sources: {
          my_src: { url: "https://example.com/repo.git", ref: "main" }
        }
      }
      versions: [
        { name: "v1", overrides: {} }
        { name: "dev", overrides: {} }
      ]
    }
    mkdir (local-root-path $repo)
    save-local-fragment $repo "test-svc" {
      default: "dev"
      versions: [{
        name: "dev"
        overrides: {
          sources: { my_src: { path: "../dev-src" } }
        }
      }]
    }
    let plane_ctx = (guard-local-plane-presence $repo)
    let out = (run-in-temp-repo $repo {||
      load-effective-versions-manifest "test-svc" $plane_ctx
    })
    if $out.default != "dev" {
      error make {msg: $"Expected default dev, got ($out.default)"}
    }
    let tracked_defaults = (try { $out.defaults.sources.my_src.url } catch { "" })
    if $tracked_defaults != "https://example.com/repo.git" {
      error make {msg: "Merged manifest must keep tracked defaults"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}
