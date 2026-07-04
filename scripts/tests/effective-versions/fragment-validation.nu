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

# Local fragment validation error tests.

use ../../lib/plane/versions.nu [load-effective-versions-manifest]
use ../../lib/plane/guard.nu [guard-local-plane-presence]
use ../../lib/plane/presence.nu [local-root-path]
use ../lib.nu [run-test]
use ./fixtures.nu [
  make-temp-repo rm-temp-repo run-in-temp-repo
  seed-tracked-versions save-local-fragment expect-error
]

export def test-additive-id [verbose: bool] {
  run-test "additive local fragment source id hard-errors" {
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
      versions: [{
        name: "dev"
        overrides: {
          sources: { extra_src: { path: "../local-src" } }
        }
      }]
    }
    let plane_ctx = (guard-local-plane-presence $repo)
    let ok = (run-in-temp-repo $repo {||
      expect-error {||
        load-effective-versions-manifest "test-svc" $plane_ctx
      } "Additive source id"
    })
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-partial-source [verbose: bool] {
  run-test "partial git local fragment source hard-errors" {
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
      versions: [{
        name: "dev"
        overrides: {
          sources: { my_src: { url: "https://example.com/repo.git" } }
        }
      }]
    }
    let plane_ctx = (guard-local-plane-presence $repo)
    let ok = (run-in-temp-repo $repo {||
      expect-error {||
        load-effective-versions-manifest "test-svc" $plane_ctx
      } "Partial git source"
    })
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-mixed-path-git [verbose: bool] {
  run-test "mixed path and git local fragment source hard-errors" {
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
      versions: [{
        name: "dev"
        overrides: {
          sources: {
            my_src: {
              path: "local-src"
              url: "https://example.com/repo.git"
              ref: "main"
            }
          }
        }
      }]
    }
    let plane_ctx = (guard-local-plane-presence $repo)
    let ok = (run-in-temp-repo $repo {||
      expect-error {||
        load-effective-versions-manifest "test-svc" $plane_ctx
      } "Cannot have both 'path' and 'url'/'ref'"
    })
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-empty-path [verbose: bool] {
  run-test "empty local fragment path hard-errors" {
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
      versions: [{
        name: "dev"
        overrides: {
          sources: { my_src: { path: "" } }
        }
      }]
    }
    let plane_ctx = (guard-local-plane-presence $repo)
    let ok = (run-in-temp-repo $repo {||
      expect-error {||
        load-effective-versions-manifest "test-svc" $plane_ctx
      } "'path' field is empty"
    })
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-empty-source-object [verbose: bool] {
  run-test "empty local fragment source object hard-errors" {
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
      versions: [{
        name: "dev"
        overrides: {
          sources: { my_src: {} }
        }
      }]
    }
    let plane_ctx = (guard-local-plane-presence $repo)
    let ok = (run-in-temp-repo $repo {||
      expect-error {||
        load-effective-versions-manifest "test-svc" $plane_ctx
      } "Source entry must be a full local"
    })
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-ref-only-source [verbose: bool] {
  run-test "ref-only local fragment source hard-errors" {
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
      versions: [{
        name: "dev"
        overrides: {
          sources: { my_src: { ref: "main" } }
        }
      }]
    }
    let plane_ctx = (guard-local-plane-presence $repo)
    let ok = (run-in-temp-repo $repo {||
      expect-error {||
        load-effective-versions-manifest "test-svc" $plane_ctx
      } "Partial git source"
    })
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-fragment-missing-name [verbose: bool] {
  run-test "local fragment version missing name hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1", overrides: {} }]
    }
    mkdir (local-root-path $repo)
    save-local-fragment $repo "test-svc" {
      versions: [{ overrides: {} }]
    }
    let plane_ctx = (guard-local-plane-presence $repo)
    let ok = (run-in-temp-repo $repo {||
      expect-error {||
        load-effective-versions-manifest "test-svc" $plane_ctx
      } "missing required field: 'name'"
    })
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-fragment-empty-name [verbose: bool] {
  run-test "local fragment version empty name hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1", overrides: {} }]
    }
    mkdir (local-root-path $repo)
    save-local-fragment $repo "test-svc" {
      versions: [{ name: "", overrides: {} }]
    }
    let plane_ctx = (guard-local-plane-presence $repo)
    let ok = (run-in-temp-repo $repo {||
      expect-error {||
        load-effective-versions-manifest "test-svc" $plane_ctx
      } "missing required field: 'name'"
    })
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-fragment-duplicate-names [verbose: bool] {
  run-test "local fragment duplicate version names hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1", overrides: {} }]
    }
    mkdir (local-root-path $repo)
    save-local-fragment $repo "test-svc" {
      versions: [
        { name: "dev", overrides: {} }
        { name: "dev", overrides: {} }
      ]
    }
    let plane_ctx = (guard-local-plane-presence $repo)
    let ok = (run-in-temp-repo $repo {||
      expect-error {||
        load-effective-versions-manifest "test-svc" $plane_ctx
      } "Duplicate version name: 'dev'"
    })
    rm-temp-repo $repo
    $ok
  } $verbose
}
