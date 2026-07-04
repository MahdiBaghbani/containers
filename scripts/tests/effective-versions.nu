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

# Effective versions manifest tests (local-plane L1 foundation)

use ../lib/inspect/effective-config.nu [resolve-inspect-version-spec]
use ../lib/plane/versions.nu [
  load-effective-versions-manifest
  merge-version-universe
  resolve-tracked-source-id-universe
  describe-version-universe
  version-local-only-in-fragment
  format-version-miss-error
]
use ../lib/plane/guard.nu [PLANE_TRACKED PLANE_LOCAL guard-local-plane-presence]
use ../lib/plane/presence.nu [local-root-path local-services-path]
use ../lib/plane/audit.nu [LOCAL_MIRROR_FILE]
use ./lib.nu [run-test print-test-summary]

def make-temp-repo [] {
  let tmp = (^mktemp -d | str trim)
  mkdir $tmp
  mkdir ($tmp | path join "services")
  ^git -C $tmp init -q
  $tmp
}

def rm-temp-repo [dir: string] {
  try { rm -rf $dir } catch { }
}

def run-in-temp-repo [repo: string, block: closure] {
  do -i { cd $repo; do $block }
}

def seed-tracked-versions [
  repo: string,
  versions_manifest: record,
  name: string = "test-svc",
] {
  { name: $name } | save -f ($repo | path join $"services/($name).nuon")
  mkdir ($repo | path join $"services/($name)")
  $versions_manifest | save -f ($repo | path join $"services/($name)/versions.nuon")
}

def save-local-fragment [repo: string, name: string, fragment: record] {
  let mirror = (local-services-path $repo | path join $name)
  mkdir $mirror
  $fragment | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
}

def expect-error [block: closure, needle: string] {
  let result = (try {
    do $block
    { ok: true }
  } catch {|err|
    { ok: false, msg: $err.msg }
  })
  if $result.ok {
    error make {msg: $"Expected error containing '($needle)'"}
  }
  if not ($result.msg | str contains $needle) {
    error make {msg: $"Expected error to mention '($needle)', got: ($result.msg)"}
  }
  true
}

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  mut results = []

  let test_tracked_passthrough_null = (run-test "tracked passthrough with null plane_ctx" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    let out = (run-in-temp-repo $repo {||
      load-effective-versions-manifest "test-svc" null
    })
    if $out.default != "v1" {
      error make {msg: $"Expected default v1, got ($out.default)"}
    }
    if ($out.versions | length) != 1 {
      error make {msg: "Expected one tracked version"}
    }
    rm-temp-repo $repo
    true
  } $verbose_flag)
  $results = ($results | append $test_tracked_passthrough_null)

  let test_tracked_passthrough_plane = (run-test "tracked passthrough with tracked plane_ctx" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let out = (run-in-temp-repo $repo {||
      load-effective-versions-manifest "test-svc" $plane_ctx
    })
    if $out.default != "v1" {
      error make {msg: $"Expected default v1, got ($out.default)"}
    }
    rm-temp-repo $repo
    true
  } $verbose_flag)
  $results = ($results | append $test_tracked_passthrough_plane)

  let test_local_no_fragment = (run-test "local plane passthrough with no fragment" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    mkdir (local-root-path $repo)
    let plane_ctx = (guard-local-plane-presence $repo)
    let out = (run-in-temp-repo $repo {||
      load-effective-versions-manifest "test-svc" $plane_ctx
    })
    if $out.default != "v1" {
      error make {msg: $"Expected tracked default, got ($out.default)"}
    }
    if ($out.versions | length) != 1 {
      error make {msg: "Expected tracked versions unchanged"}
    }
    rm-temp-repo $repo
    true
  } $verbose_flag)
  $results = ($results | append $test_local_no_fragment)

  let test_replace_by_name = (run-test "local fragment replaces same-named version" {
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
  } $verbose_flag)
  $results = ($results | append $test_replace_by_name)

  let test_append_new = (run-test "local fragment appends new version names in fragment order" {
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
  } $verbose_flag)
  $results = ($results | append $test_append_new)

  let test_default_override = (run-test "local fragment default overrides tracked default" {
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
  } $verbose_flag)
  $results = ($results | append $test_default_override)

  let test_additive_id = (run-test "additive local fragment source id hard-errors" {
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
  } $verbose_flag)
  $results = ($results | append $test_additive_id)

  let test_partial_source = (run-test "partial git local fragment source hard-errors" {
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
  } $verbose_flag)
  $results = ($results | append $test_partial_source)

  let test_mixed_path_git = (run-test "mixed path and git local fragment source hard-errors" {
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
  } $verbose_flag)
  $results = ($results | append $test_mixed_path_git)

  let test_empty_path = (run-test "empty local fragment path hard-errors" {
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
  } $verbose_flag)
  $results = ($results | append $test_empty_path)

  let test_empty_source_object = (run-test "empty local fragment source object hard-errors" {
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
  } $verbose_flag)
  $results = ($results | append $test_empty_source_object)

  let test_ref_only_source = (run-test "ref-only local fragment source hard-errors" {
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
  } $verbose_flag)
  $results = ($results | append $test_ref_only_source)

  let test_fragment_missing_name = (run-test "local fragment version missing name hard-errors" {
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
  } $verbose_flag)
  $results = ($results | append $test_fragment_missing_name)

  let test_fragment_empty_name = (run-test "local fragment version empty name hard-errors" {
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
  } $verbose_flag)
  $results = ($results | append $test_fragment_empty_name)

  let test_fragment_duplicate_names = (run-test "local fragment duplicate version names hard-errors" {
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
  } $verbose_flag)
  $results = ($results | append $test_fragment_duplicate_names)

  let test_merge_unit = (run-test "merge-version-universe unit: replace and append order" {
    let tracked = [
      { name: "a" }
      { name: "b" }
    ]
    let fragment = [
      { name: "b", tag: "replaced" }
      { name: "c", tag: "new1" }
      { name: "d", tag: "new2" }
    ]
    let merged = (merge-version-universe $tracked $fragment)
    let names = ($merged | each {|v| $v.name })
    if $names != ["a" "b" "c" "d"] {
      error make {msg: $"Unexpected merge order: ($names | to json)"}
    }
    let b = ($merged | where {|v| $v.name == "b" } | first)
    if (try { $b.tag } catch { "" }) != "replaced" {
      error make {msg: "Same-named version must be fully replaced"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test_merge_unit)

  let test_source_id_universe = (run-test "resolve-tracked-source-id-universe unions defaults and version overrides" {
    let tracked = {
      defaults: { sources: { base_src: { url: "u", ref: "r" } } }
      versions: [
        { name: "v1", overrides: { sources: { ver_src: { ref: "x" } } } }
      ]
    }
    let ids = (resolve-tracked-source-id-universe $tracked)
    if $ids != ["base_src" "ver_src"] {
      error make {msg: $"Expected [base_src, ver_src], got ($ids | to json)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test_source_id_universe)

  let test_describe_universe_local_only = (run-test "describe-version-universe lists local-only names on tracked plane" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    save-local-fragment $repo "test-svc" {
      versions: [
        { name: "local-only-v" }
      ]
    }
    mkdir (local-root-path $repo)
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let universe = (run-in-temp-repo $repo {||
      describe-version-universe "test-svc" $plane_ctx
    })
    if $universe.plane != $PLANE_TRACKED {
      error make {msg: $"Expected tracked plane, got ($universe.plane)"}
    }
    if not $universe.fragment_present {
      error make {msg: "Expected fragment_present true"}
    }
    if $universe.local_only_names != ["local-only-v"] {
      error make {msg: $"Expected local_only_names [local-only-v], got ($universe.local_only_names | to json)"}
    }
    if $universe.tracked_names != ["v1"] {
      error make {msg: $"Expected tracked_names [v1], got ($universe.tracked_names | to json)"}
    }
    let expected_fragment = (local-services-path $repo | path join "test-svc" | path join $LOCAL_MIRROR_FILE)
    if ($universe.fragment_path | path expand) != ($expected_fragment | path expand) {
      error make {msg: $"Expected fragment_path ($expected_fragment), got ($universe.fragment_path)"}
    }
    rm-temp-repo $repo
    true
  } $verbose_flag)
  $results = ($results | append $test_describe_universe_local_only)

  let test_local_only_detector = (run-test "version-local-only-in-fragment detects tracked-plane local-only miss" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    save-local-fragment $repo "test-svc" {
      versions: [{ name: "devlocal" }]
    }
    mkdir (local-root-path $repo)
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let universe = (run-in-temp-repo $repo {||
      describe-version-universe "test-svc" $plane_ctx
    })
    if not (version-local-only-in-fragment $universe "devlocal") {
      error make {msg: "Expected devlocal to be local-only in fragment"}
    }
    if (version-local-only-in-fragment $universe "v1") {
      error make {msg: "Tracked version v1 must not be classified local-only"}
    }
    if (version-local-only-in-fragment $universe "missing") {
      error make {msg: "Unknown version must not be classified local-only"}
    }
    rm-temp-repo $repo
    true
  } $verbose_flag)
  $results = ($results | append $test_local_only_detector)

  let test_format_miss_local_only = (run-test "format-version-miss-error guides --plane local for tracked-plane local-only miss" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    save-local-fragment $repo "test-svc" {
      versions: [{ name: "devlocal" }]
    }
    mkdir (local-root-path $repo)
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let msg = (run-in-temp-repo $repo {||
      format-version-miss-error "test-svc" "devlocal" $plane_ctx --style build
    })
    if not ($msg | str contains "--plane local") {
      error make {msg: $"Expected --plane local guidance, got: ($msg)"}
    }
    let expected_fragment = (local-services-path $repo | path join "test-svc" | path join $LOCAL_MIRROR_FILE | path expand)
    if not ($msg | str contains ($expected_fragment | into string)) {
      error make {msg: $"Expected fragment path ($expected_fragment) in message, got: ($msg)"}
    }
    if not ($msg | str contains "local fragment") {
      error make {msg: $"Expected local fragment mention, got: ($msg)"}
    }
    rm-temp-repo $repo
    true
  } $verbose_flag)
  $results = ($results | append $test_format_miss_local_only)

  let test_format_miss_generic = (run-test "format-version-miss-error keeps generic tracked miss without local-only guidance" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let msg = (run-in-temp-repo $repo {||
      format-version-miss-error "test-svc" "nope" $plane_ctx --style short
    })
    if ($msg | str contains "--plane local") {
      error make {msg: $"Generic miss must not mention --plane local, got: ($msg)"}
    }
    if not ($msg | str contains "Available versions: v1") {
      error make {msg: $"Expected available versions list, got: ($msg)"}
    }
    rm-temp-repo $repo
    true
  } $verbose_flag)
  $results = ($results | append $test_format_miss_generic)

  let test_describe_universe_no_fragment = (run-test "describe-version-universe reports fragment_present false without mirror" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let universe = (run-in-temp-repo $repo {||
      describe-version-universe "test-svc" $plane_ctx
    })
    if $universe.fragment_present {
      error make {msg: "Expected fragment_present false when no local mirror exists"}
    }
    if $universe.local_only_names != [] {
      error make {msg: $"Expected empty local_only_names, got ($universe.local_only_names | to json)"}
    }
    if $universe.effective_names != ["v1"] {
      error make {msg: $"Expected effective_names [v1] on tracked plane, got ($universe.effective_names | to json)"}
    }
    rm-temp-repo $repo
    true
  } $verbose_flag)
  $results = ($results | append $test_describe_universe_no_fragment)

  let test_describe_universe_overlap = (run-test "describe-version-universe separates overlapping and local-only fragment names" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [
        { name: "v1" }
        { name: "v2" }
      ]
    }
    mkdir (local-root-path $repo)
    save-local-fragment $repo "test-svc" {
      versions: [
        { name: "v2", overrides: {} }
        { name: "devlocal", overrides: {} }
      ]
    }
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let universe = (run-in-temp-repo $repo {||
      describe-version-universe "test-svc" $plane_ctx
    })
    if not $universe.fragment_present {
      error make {msg: "Expected fragment_present true when mirror exists"}
    }
    if $universe.tracked_names != ["v1" "v2"] {
      error make {msg: $"Expected tracked_names [v1, v2], got ($universe.tracked_names | to json)"}
    }
    if $universe.local_only_names != ["devlocal"] {
      error make {msg: $"Expected local_only_names [devlocal], got ($universe.local_only_names | to json)"}
    }
    if $universe.effective_names != ["v1" "v2"] {
      error make {msg: $"Tracked plane effective_names must stay tracked-only, got ($universe.effective_names | to json)"}
    }
    rm-temp-repo $repo
    true
  } $verbose_flag)
  $results = ($results | append $test_describe_universe_overlap)

  let test_format_miss_fragment_generic = (run-test "format-version-miss-error does not suggest --plane local for generic miss with fragment present" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    mkdir (local-root-path $repo)
    save-local-fragment $repo "test-svc" {
      versions: [{ name: "devlocal" }]
    }
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let msg = (run-in-temp-repo $repo {||
      format-version-miss-error "test-svc" "typo" $plane_ctx --style build
    })
    if ($msg | str contains "--plane local") {
      error make {msg: $"Generic miss with fragment present must not mention --plane local, got: ($msg)"}
    }
    if not ($msg | str contains "Available versions: v1") {
      error make {msg: $"Expected available versions list, got: ($msg)"}
    }
    rm-temp-repo $repo
    true
  } $verbose_flag)
  $results = ($results | append $test_format_miss_fragment_generic)

  let test_format_miss_inspect_generic = (run-test "format-version-miss-error inspect style uses tracked-version options for generic miss" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let msg = (run-in-temp-repo $repo {||
      format-version-miss-error "test-svc" "nope" $plane_ctx --style inspect
    })
    if ($msg | str contains "--plane local") {
      error make {msg: $"Inspect generic miss must not mention --plane local, got: ($msg)"}
    }
    if not ($msg | str contains "Use one of the available tracked versions") {
      error make {msg: $"Expected inspect tracked-version option, got: ($msg)"}
    }
    if not ($msg | str contains "Available versions: v1") {
      error make {msg: $"Expected available versions list, got: ($msg)"}
    }
    rm-temp-repo $repo
    true
  } $verbose_flag)
  $results = ($results | append $test_format_miss_inspect_generic)

  let test_resolve_inspect_generic_miss = (run-test "resolve-inspect-version-spec routes generic miss through inspect formatter" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let ok = (run-in-temp-repo $repo {||
      expect-error {||
        resolve-inspect-version-spec "test-svc" "nope" $plane_ctx
      } "Use one of the available tracked versions"
    })
    rm-temp-repo $repo
    $ok
  } $verbose_flag)
  $results = ($results | append $test_resolve_inspect_generic_miss)

  let test_resolve_inspect_fragment_generic_miss = (run-test "resolve-inspect-version-spec generic miss with fragment does not suggest --plane local" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    mkdir (local-root-path $repo)
    save-local-fragment $repo "test-svc" {
      versions: [{ name: "devlocal" }]
    }
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let result = (run-in-temp-repo $repo {||
      try {
        resolve-inspect-version-spec "test-svc" "typo" $plane_ctx
        { ok: true }
      } catch {|err|
        { ok: false, msg: $err.msg }
      }
    })
    rm-temp-repo $repo
    if $result.ok {
      error make {msg: "Expected resolve-inspect-version-spec to fail for generic miss"}
    }
    if ($result.msg | str contains "--plane local") {
      error make {msg: $"Generic inspect miss with fragment must not mention --plane local, got: ($result.msg)"}
    }
    if not ($result.msg | str contains "Available versions: v1") {
      error make {msg: $"Expected available versions in inspect miss, got: ($result.msg)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test_resolve_inspect_fragment_generic_miss)

  print-test-summary $results
  if ($results | where {|r| not $r} | is-empty) {
    exit 0
  } else {
    exit 1
  }
}
