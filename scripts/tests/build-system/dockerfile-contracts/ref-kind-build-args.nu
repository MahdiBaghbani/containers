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

# classify-source-ref-kind, extract-source-ref-kinds, and build-arg emission tests.

use ../../../lib/build/args.nu [generate-build-args]
use ../../../lib/build/config.nu [load-service-config process-sources-to-build-args detect-all-source-types]
use ../../../lib/build/sources.nu [classify-source-ref-kind extract-source-ref-kinds]
use ../../helpers.nu [setup-test-environment with-test-cleanup assert-build-args-contain]
use ../../lib.nu [run-test]

export def ref-kind-build-args-tests [verbose: bool] {
  [
    (run-test "Test 39d: classify-source-ref-kind maps full SHA to sha" {
      let source = {url: "https://example.com/repo.git", ref: "a1b2c3d4e5f6789012345678901234567890abcd"}
      let kind = (classify-source-ref-kind $source "git")
      if $kind != "sha" {
        error make {msg: $"Expected ref-kind 'sha' for 40-hex ref, got: ($kind)"}
      }
      true
    } $verbose)
    (run-test "Test 39e: classify-source-ref-kind maps branch/tag to ref" {
      let source = {url: "https://example.com/repo.git", ref: "main"}
      let kind = (classify-source-ref-kind $source "git")
      if $kind != "ref" {
        error make {msg: $"Expected ref-kind 'ref' for branch name, got: ($kind)"}
      }
      true
    } $verbose)
    (run-test "Test 39f: classify-source-ref-kind maps local path source to local" {
      let source = {path: "/tmp/local-src"}
      let kind = (classify-source-ref-kind $source "local")
      if $kind != "local" {
        error make {msg: $"Expected ref-kind 'local' for path source, got: ($kind)"}
      }
      true
    } $verbose)
    (run-test "Test 39g: extract-source-ref-kinds emits per-source REF_KIND keys" {
      let sources = {
        revad: {url: "https://example.com/revad.git", ref: "main"},
        pinned: {url: "https://example.com/pinned.git", ref: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}
      }
      let source_types = {revad: "git", pinned: "git"}
      let kinds = (extract-source-ref-kinds $sources $source_types)
      if (try { $kinds.REVAD_REF_KIND } catch { "" }) != "ref" {
        error make {msg: "Expected REVAD_REF_KIND=ref"}
      }
      if (try { $kinds.PINNED_REF_KIND } catch { "" }) != "sha" {
        error make {msg: "Expected PINNED_REF_KIND=sha for full 40-hex ref"}
      }
      true
    } $verbose)
    (run-test "Test 39h: process-sources-to-build-args emits REF_KIND for git and local" {
      let git_sources = {
        app: {url: "https://example.com/app.git", ref: "v1.0.0"}
      }
      let git_args = (process-sources-to-build-args $git_sources {app: "git"})
      if (try { $git_args.APP_REF_KIND } catch { "" }) != "ref" {
        error make {msg: "Expected APP_REF_KIND=ref in git source build args"}
      }
      let local_sources = {
        app: {path: "local/app"}
      }
      let local_args = (process-sources-to-build-args $local_sources {app: "local"})
      if (try { $local_args.APP_REF_KIND } catch { "" }) != "local" {
        error make {msg: "Expected APP_REF_KIND=local in local source build args"}
      }
      if (try { $local_args.APP_MODE } catch { "" }) != "local" {
        error make {msg: "Expected APP_MODE=local unchanged for local sources"}
      }
      true
    } $verbose)
    (run-test "Test 39i: generate-build-args includes TEST_SOURCE_REF_KIND" {
      with-test-cleanup {
        let test_env = (setup-test-environment "test-service" "v1.0.0")
        let source_types = (detect-all-source-types $test_env.merged_cfg.sources)
        let source_ref_kinds = (extract-source-ref-kinds $test_env.merged_cfg.sources $source_types)
        let build_args = (
          generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved
          $test_env.tls_meta $test_env.ssh_meta "" false {} $source_types {} "tracked" $source_ref_kinds
        )
        let _ = (assert-build-args-contain $build_args [TEST_SOURCE_REF_KIND])
        if (try { $build_args.TEST_SOURCE_REF_KIND } catch { "" }) != "ref" {
          error make {msg: $"Expected TEST_SOURCE_REF_KIND=ref for tag ref v1.0.0, got: ($build_args.TEST_SOURCE_REF_KIND)"}
        }
        true
      }
    } $verbose)
  ]
}
