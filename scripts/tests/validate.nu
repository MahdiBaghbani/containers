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

# Validation domain test suite
# Contract tests for validator and schema correctness: source validation,
# SSH/TLS placement, local-path boundaries, and the latest-version rule.

use ../lib/validate/core.nu [
  validate-local-path
  validate-version-defaults
  validate-version-manifest
  validate-version-overrides-structure
  validate-service-config
  validate-merged-config
  validate-tls-config-merged
  validate-platforms-manifest
  validate-service-complete
  validate-service-file
  validate-manifest-file
]
use ../lib/core/repo.nu [get-repo-root]
use ./lib.nu [run-test print-test-summary]

# Create a hermetic temp directory tree
def make-temp [] {
  ^mktemp -d | str trim
}

def rm-temp [dir: string] {
  try { rm -rf $dir } catch { }
}

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  mut results = []

  # ------------------------------------------------------------------
  # validate-local-path: boundary contract
  # ------------------------------------------------------------------

  let t_path_valid = (run-test "validate-local-path: accepts directory inside repo root" {
    let repo_root = (get-repo-root)
    let result = (validate-local-path "services" $repo_root)
    if not $result.valid {
      error make {msg: $"Expected 'services' to be valid, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_path_valid)

  let t_path_missing = (run-test "validate-local-path: rejects non-existent path" {
    let repo_root = (get-repo-root)
    let result = (validate-local-path "does-not-exist-xyz" $repo_root)
    if $result.valid {
      error make {msg: "Expected non-existent path to be rejected"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_path_missing)

  let t_path_outside = (run-test "validate-local-path: rejects path outside repo root" {
    # repo_root whose parent is NOT named 'repos' -> no sibling allowance
    let tmp = (make-temp)
    let repo_root = ($tmp | path join "standalone")
    mkdir $repo_root
    mkdir ($tmp | path join "outside")
    let result = (validate-local-path "../outside" $repo_root)
    rm-temp $tmp
    if $result.valid {
      error make {msg: "Expected ../outside to be rejected when repo root has no repos/ parent"}
    }
    let has_outside_err = ($result.errors | any {|e| $e | str contains "outside repository root"})
    if not $has_outside_err {
      error make {msg: $"Expected 'outside repository root' message, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_path_outside)

  let t_path_sibling = (run-test "validate-local-path: accepts sibling clone under a repos/ parent" {
    # repo_root lives under a directory named 'repos' -> sibling repos allowed
    let tmp = (make-temp)
    let repos_dir = ($tmp | path join "repos")
    let repo_root = ($repos_dir | path join "myrepo")
    let sibling = ($repos_dir | path join "sibling")
    mkdir $repo_root
    mkdir $sibling
    let result = (validate-local-path "../sibling" $repo_root)
    rm-temp $tmp
    if not $result.valid {
      error make {msg: $"Expected sibling repos clone to be accepted, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_path_sibling)

  let t_path_file = (run-test "validate-local-path: rejects a file (not a directory)" {
    let tmp = (make-temp)
    let repo_root = ($tmp | path join "repo")
    mkdir $repo_root
    "content" | save -f ($repo_root | path join "afile.txt")
    let result = (validate-local-path "afile.txt" $repo_root)
    rm-temp $tmp
    if $result.valid {
      error make {msg: "Expected a file path to be rejected (not a directory)"}
    }
    let has_dir_err = ($result.errors | any {|e| $e | str contains "is not a directory"})
    if not $has_dir_err {
      error make {msg: $"Expected 'is not a directory' message, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_path_file)

  let t_path_abs_inside = (run-test "validate-local-path: accepts absolute path inside repo root" {
    let tmp = (make-temp)
    let repo_root = ($tmp | path join "repo")
    let inner = ($repo_root | path join "sub")
    mkdir $inner
    let result = (validate-local-path $inner $repo_root)
    rm-temp $tmp
    if not $result.valid {
      error make {msg: $"Expected absolute path inside repo to be valid, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_path_abs_inside)

  let t_path_abs_outside = (run-test "validate-local-path: rejects absolute path outside repo root" {
    let tmp = (make-temp)
    let repo_root = ($tmp | path join "repo")
    let outside = ($tmp | path join "elsewhere")
    mkdir $repo_root
    mkdir $outside
    let result = (validate-local-path $outside $repo_root)
    rm-temp $tmp
    if $result.valid {
      error make {msg: "Expected absolute path outside repo root to be rejected"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_path_abs_outside)

  # ------------------------------------------------------------------
  # latest-version rule: explicit message
  # ------------------------------------------------------------------

  let t_latest_single = (run-test "validate-version-manifest: single latest is accepted" {
    let manifest = {
      default: "v1.0.0",
      versions: [
        {name: "v1.0.0", latest: true},
        {name: "v2.0.0"}
      ]
    }
    let result = (validate-version-manifest $manifest null)
    if not $result.valid {
      error make {msg: $"Expected single-latest manifest to be valid, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_latest_single)

  let t_latest_multiple = (run-test "validate-version-manifest: multiple latest emits explicit message" {
    let manifest = {
      default: "v1.0.0",
      versions: [
        {name: "v1.0.0", latest: true},
        {name: "v2.0.0", latest: true}
      ]
    }
    let result = (validate-version-manifest $manifest null)
    if $result.valid {
      error make {msg: "Expected multiple latest versions to be rejected"}
    }
    let has_msg = ($result.errors | any {|e| $e | str contains "Only one version can have 'latest: true'"})
    if not $has_msg {
      error make {msg: $"Expected explicit multiple-latest message, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_latest_multiple)

  # ------------------------------------------------------------------
  # TLS forbidden in version defaults and defaults.platforms.*
  # ------------------------------------------------------------------

  let t_tls_global_defaults = (run-test "validate-version-defaults: rejects TLS in global defaults" {
    let defaults = {tls: {enabled: true, mode: "ca-only"}}
    let result = (validate-version-defaults $defaults)
    if $result.valid {
      error make {msg: "Expected TLS in version defaults to be rejected"}
    }
    let has_tls_err = ($result.errors | any {|e| $e | str contains "tls: Section forbidden"})
    if not $has_tls_err {
      error make {msg: $"Expected 'tls: Section forbidden' message, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_tls_global_defaults)

  let t_tls_platform_defaults = (run-test "validate-version-defaults: rejects TLS in defaults.platforms.*" {
    let defaults = {platforms: {alpine: {tls: {enabled: true, mode: "ca-only"}}}}
    let result = (validate-version-defaults $defaults)
    if $result.valid {
      error make {msg: "Expected TLS in defaults.platforms.* to be rejected"}
    }
    let has_tls_err = ($result.errors | any {|e| $e | str contains "tls: Section forbidden"})
    if not $has_tls_err {
      error make {msg: $"Expected 'tls: Section forbidden' message, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_tls_platform_defaults)

  let t_defaults_ssh_ok = (run-test "validate-version-defaults: accepts valid SSH in defaults" {
    let defaults = {ssh: {enabled: false, mode: "disabled"}}
    let result = (validate-version-defaults $defaults)
    if not $result.valid {
      error make {msg: $"Expected valid SSH defaults to pass, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_defaults_ssh_ok)

  let t_defaults_ssh_bad = (run-test "validate-version-defaults: rejects invalid SSH in defaults" {
    let defaults = {ssh: {enabled: true, mode: "not-a-mode"}}
    let result = (validate-version-defaults $defaults)
    if $result.valid {
      error make {msg: "Expected invalid SSH mode in defaults to be rejected"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_defaults_ssh_bad)

  # SSH is allowed in defaults.platforms.<platform>; exercise that path through
  # validate-version-defaults (the main validator entry), not validate-ssh-config
  # directly, so the "version defaults where SSH is allowed" branch stays covered.
  let t_defaults_platform_ssh_ok = (run-test "validate-version-defaults: accepts valid defaults.platforms.*.ssh" {
    let defaults = {platforms: {alpine: {ssh: {enabled: true, mode: "server", port: 22}}}}
    let result = (validate-version-defaults $defaults)
    if not $result.valid {
      error make {msg: $"Expected valid platform SSH defaults to pass, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_defaults_platform_ssh_ok)

  let t_defaults_platform_ssh_bad = (run-test "validate-version-defaults: rejects invalid defaults.platforms.*.ssh" {
    let defaults = {platforms: {alpine: {ssh: {enabled: true, mode: "not-a-mode"}}}}
    let result = (validate-version-defaults $defaults)
    if $result.valid {
      error make {msg: "Expected invalid platform SSH mode in defaults to be rejected"}
    }
    let has_ssh_err = ($result.errors | any {|e| $e | str contains "ssh.mode"})
    if not $has_ssh_err {
      error make {msg: $"Expected ssh.mode error from defaults.platforms.*, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_defaults_platform_ssh_bad)

  # ------------------------------------------------------------------
  # SSH validation wired into base service config
  # ------------------------------------------------------------------

  let t_base_ssh_ok = (run-test "validate-service-config: accepts valid base SSH config" {
    let config = {
      name: "svc",
      context: "services/svc",
      ssh: {enabled: true, mode: "server", default_user: "root", port: 22}
    }
    let result = (validate-service-config $config true "svc")
    if not $result.valid {
      error make {msg: $"Expected base SSH config to be valid, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_base_ssh_ok)

  let t_base_ssh_bad = (run-test "validate-service-config: rejects invalid base SSH config" {
    let config = {
      name: "svc",
      context: "services/svc",
      ssh: {enabled: true, mode: "bogus"}
    }
    let result = (validate-service-config $config true "svc")
    if $result.valid {
      error make {msg: "Expected invalid base SSH mode to be rejected"}
    }
    let has_ssh_err = ($result.errors | any {|e| $e | str contains "ssh.mode"})
    if not $has_ssh_err {
      error make {msg: $"Expected ssh.mode error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_base_ssh_bad)

  # ------------------------------------------------------------------
  # SSH wired through the real platforms-manifest entrypoint
  # (not just validate-platform-ssh directly)
  # ------------------------------------------------------------------

  let t_platforms_manifest_ssh = (run-test "validate-platforms-manifest: rejects invalid platform SSH via entrypoint" {
    let manifest = {
      default: "alpine",
      platforms: [
        {name: "alpine", dockerfile: "services/svc/Dockerfile.alpine", ssh: {enabled: true, mode: "bogus"}}
      ]
    }
    let result = (validate-platforms-manifest $manifest)
    if $result.valid {
      error make {msg: "Expected invalid platform SSH mode to be rejected via validate-platforms-manifest"}
    }
    let has_ssh_err = ($result.errors | any {|e| $e | str contains "ssh.mode"})
    if not $has_ssh_err {
      error make {msg: $"Expected ssh.mode error from platforms manifest entrypoint, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_platforms_manifest_ssh)

  # ------------------------------------------------------------------
  # Centralized source validation: base, overrides, merged
  # ------------------------------------------------------------------

  let t_src_base_bad_key = (run-test "validate-service-config: rejects non-lowercase source key (base)" {
    let config = {
      name: "svc",
      context: "services/svc",
      dockerfile: "services/svc/Dockerfile",
      sources: {"Bad-Key": {url: "https://example.com/x", ref: "v1"}}
    }
    let result = (validate-service-config $config false "svc")
    if $result.valid {
      error make {msg: "Expected invalid source key to be rejected"}
    }
    let has_key_err = ($result.errors | any {|e| $e | str contains "lowercase alphanumeric"})
    if not $has_key_err {
      error make {msg: $"Expected lowercase-key error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_src_base_bad_key)

  let t_src_base_build_arg = (run-test "validate-service-config: rejects forbidden source build_arg (base)" {
    let config = {
      name: "svc",
      context: "services/svc",
      dockerfile: "services/svc/Dockerfile",
      sources: {good: {url: "https://example.com/x", ref: "v1", build_arg: "X_REF"}}
    }
    let result = (validate-service-config $config false "svc")
    if $result.valid {
      error make {msg: "Expected forbidden source build_arg to be rejected"}
    }
    let has_ba_err = ($result.errors | any {|e| ($e | str contains "build_arg") and ($e | str contains "forbidden")})
    if not $has_ba_err {
      error make {msg: $"Expected build_arg forbidden error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_src_base_build_arg)

  let t_src_merged_missing_ref = (run-test "validate-merged-config: rejects git source missing ref (complete required)" {
    let merged = {sources: {svc: {url: "https://example.com/x"}}}
    let result = (validate-merged-config $merged "svc" false "")
    if $result.valid {
      error make {msg: "Expected merged git source missing ref to be rejected"}
    }
    let has_ref_err = ($result.errors | any {|e| $e | str contains "Missing required field 'ref'"})
    if not $has_ref_err {
      error make {msg: $"Expected missing-ref error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_src_merged_missing_ref)

  let t_src_override_partial_ok = (run-test "validate-version-overrides-structure: accepts partial source fragment" {
    let overrides = {sources: {svc: {ref: "main"}}}
    let result = (validate-version-overrides-structure $overrides "v1")
    if not $result.valid {
      error make {msg: $"Expected partial source override (ref-only) to be valid, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_src_override_partial_ok)

  let t_src_override_bad_key = (run-test "validate-version-overrides-structure: rejects non-lowercase source key" {
    let overrides = {sources: {"Bad": {ref: "main"}}}
    let result = (validate-version-overrides-structure $overrides "v1")
    if $result.valid {
      error make {msg: "Expected invalid source key in overrides to be rejected"}
    }
    let has_key_err = ($result.errors | any {|e| $e | str contains "lowercase alphanumeric"})
    if not $has_key_err {
      error make {msg: $"Expected lowercase-key error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_src_override_bad_key)

  # ------------------------------------------------------------------
  # Nested SSH validation in overrides.platforms.<platform>.ssh
  # ------------------------------------------------------------------

  let t_override_platform_ssh_ok = (run-test "validate-version-overrides-structure: accepts valid platforms.*.ssh override" {
    let overrides = {platforms: {alpine: {ssh: {enabled: true, mode: "server", port: 22}}}}
    let result = (validate-version-overrides-structure $overrides "v1")
    if not $result.valid {
      error make {msg: $"Expected valid platform SSH override to pass, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_override_platform_ssh_ok)

  let t_override_platform_ssh_bad = (run-test "validate-version-overrides-structure: rejects invalid platforms.*.ssh override" {
    let overrides = {platforms: {alpine: {ssh: {enabled: true, mode: "bogus"}}}}
    let result = (validate-version-overrides-structure $overrides "v1")
    if $result.valid {
      error make {msg: "Expected invalid platform SSH override mode to be rejected"}
    }
    let has_ssh_err = ($result.errors | any {|e| $e | str contains "ssh.mode"})
    if not $has_ssh_err {
      error make {msg: $"Expected ssh.mode error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_override_platform_ssh_bad)

  # ------------------------------------------------------------------
  # TLS forbidden in overrides.platforms.<platform> (base-config only).
  # Existing tests cover TLS rejection in defaults and SSH in platform
  # overrides; this guards the platform-override TLS path specifically so
  # overrides.platforms.*.tls cannot survive into the merged config.
  # ------------------------------------------------------------------

  let t_override_platform_tls_bad = (run-test "validate-version-overrides-structure: rejects platforms.*.tls override" {
    let overrides = {platforms: {alpine: {tls: {enabled: true, mode: "ca-only"}}}}
    let result = (validate-version-overrides-structure $overrides "v1")
    if $result.valid {
      error make {msg: "Expected TLS in overrides.platforms.* to be rejected"}
    }
    let has_tls_err = ($result.errors | any {|e| $e | str contains "tls: Section forbidden"})
    if not $has_tls_err {
      error make {msg: $"Expected 'tls: Section forbidden' message, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_override_platform_tls_bad)

  # ------------------------------------------------------------------
  # Infrastructure fields still forbidden in version overrides
  # (regression guard after removing the dead --allow-infrastructure flag)
  # ------------------------------------------------------------------

  let t_override_infra_name = (run-test "validate-version-overrides-structure: forbids external_images.*.name" {
    let overrides = {external_images: {build: {name: "golang"}}}
    let result = (validate-version-overrides-structure $overrides "v1")
    if $result.valid {
      error make {msg: "Expected external_images.*.name in overrides to be rejected"}
    }
    let has_name_err = ($result.errors | any {|e| $e | str contains "external_images.build.name"})
    if not $has_name_err {
      error make {msg: $"Expected external_images name forbidden error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_override_infra_name)

  let t_override_infra_dep = (run-test "validate-version-overrides-structure: forbids dependencies.*.service" {
    let overrides = {dependencies: {ct: {service: "common-tools"}}}
    let result = (validate-version-overrides-structure $overrides "v1")
    if $result.valid {
      error make {msg: "Expected dependencies.*.service in overrides to be rejected"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_override_infra_dep)

  # ------------------------------------------------------------------
  # Merged-config TLS dependency contract: a TLS-enabled service MUST end up
  # with a 'common-tools' dependency after version/platform merge. These
  # exercise the merged validation path directly with explicit payloads instead
  # of relying on a broad pass/fail smoke over the real common-tools service.
  # ------------------------------------------------------------------

  let t_tls_merged_dep_present = (run-test "validate-tls-config-merged: TLS-enabled passes when common-tools supplied via merge" {
    # common-tools arrives only through merged version/platform data, not base.
    let merged = {
      tls: {enabled: true, mode: "ca-only"},
      dependencies: {ct: {service: "common-tools", build_arg: "COMMON_TOOLS_REF"}}
    }
    let result = (validate-tls-config-merged $merged "svc")
    if not $result.valid {
      error make {msg: $"Expected TLS-enabled service with merged common-tools dep to pass, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_tls_merged_dep_present)

  let t_tls_merged_dep_missing = (run-test "validate-tls-config-merged: TLS-enabled fails when common-tools absent after merge" {
    let merged = {tls: {enabled: true, mode: "ca-only"}}
    let result = (validate-tls-config-merged $merged "svc")
    if $result.valid {
      error make {msg: "Expected TLS-enabled service without common-tools dep to fail"}
    }
    let has_ct_err = ($result.errors | any {|e| ($e | str contains "common-tools") and ($e | str contains "missing")})
    if not $has_ct_err {
      error make {msg: $"Expected missing common-tools dependency error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_tls_merged_dep_missing)

  # ------------------------------------------------------------------
  # SSH override advisory warnings must survive through the manifest validator
  # (validate-version-overrides-ssh -> validate-version-manifest results),
  # not be silently dropped.
  # ------------------------------------------------------------------

  let t_override_ssh_warning_surfaced = (run-test "validate-version-manifest: surfaces SSH override warning through results" {
    let manifest = {
      default: "v1",
      versions: [
        {name: "v1", overrides: {ssh: {enabled: true, mode: "server", port: 22}}}
      ]
    }
    let result = (validate-version-manifest $manifest null)
    if not $result.valid {
      error make {msg: $"Expected manifest with valid SSH override to be valid, got: ($result.errors | str join ', ')"}
    }
    if not ("warnings" in ($result | columns)) {
      error make {msg: "Expected validate-version-manifest result to include a warnings field"}
    }
    let has_warn = ($result.warnings | any {|w| $w | str contains "Version-level SSH overrides"})
    if not $has_warn {
      error make {msg: $"Expected SSH override warning to be surfaced, got: ($result.warnings | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_override_ssh_warning_surfaced)

  # ------------------------------------------------------------------
  # End-to-end service validation still green for a known service
  # ------------------------------------------------------------------

  let t_complete_shape = (run-test "validate-service-complete returns valid/errors shape" {
    let result = (validate-service-complete "common-tools")
    ("valid" in ($result | columns)) and ("errors" in ($result | columns))
  } $verbose_flag)
  $results = ($results | append $t_complete_shape)

  let t_complete_pass = (run-test "validate-service-complete passes for common-tools" {
    let result = (validate-service-complete "common-tools")
    if not $result.valid {
      error make {msg: $"Expected common-tools complete validation to pass, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_complete_pass)

  let t_service_file = (run-test "validate-service-file runs for common-tools" {
    let result = (validate-service-file "common-tools")
    ("valid" in ($result | columns)) and ("errors" in ($result | columns))
  } $verbose_flag)
  $results = ($results | append $t_service_file)

  let t_manifest_file = (run-test "validate-manifest-file runs for common-tools" {
    let result = (validate-manifest-file "common-tools")
    ("valid" in ($result | columns)) and ("errors" in ($result | columns))
  } $verbose_flag)
  $results = ($results | append $t_manifest_file)

  # ------------------------------------------------------------------
  # validate-service-complete surfaces merge/build failures from the merged
  # config wrapper (validate-service-merged-configs). A base field whose type
  # conflicts with a version override forces deep-merge to throw inside
  # merge-version-overrides; the wrapper must report it as a user-facing
  # "Failed to build merged config" error instead of crashing. This proves the
  # wrapper path end-to-end, not just a lower-level merge helper.
  # ------------------------------------------------------------------

  let t_complete_merge_failure = (run-test "validate-service-complete: surfaces merged-config build failure" {
    let tmp = (make-temp)
    let result = (do {
      # git-init so get-repo-root resolves to the temp tree; this keeps the
      # case hermetic (config reads and Dockerfile-path checks stay in $tmp).
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "mergefail")
      "FROM scratch" | save -f ($tmp | path join "services" "mergefail" "Dockerfile")
      # Base declares merge_probe as an int; the override declares it as a
      # record. Structural validators accept both (unknown field), but
      # deep-merge throws when merging a record into a non-record.
      {
        name: "mergefail",
        context: "services/mergefail",
        dockerfile: "services/mergefail/Dockerfile",
        merge_probe: 5
      } | save -f ($tmp | path join "services" "mergefail.nuon")
      {
        default: "v1",
        versions: [
          {name: "v1", overrides: {merge_probe: {nested: true}}}
        ]
      } | save -f ($tmp | path join "services" "mergefail" "versions.nuon")
      validate-service-complete "mergefail"
    })
    rm-temp $tmp
    if $result.valid {
      error make {msg: "Expected merged-config build failure to fail validation"}
    }
    let has_merge_err = ($result.errors | any {|e| $e | str contains "Failed to build merged config"})
    if not $has_merge_err {
      error make {msg: $"Expected 'Failed to build merged config' error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_complete_merge_failure)

  # ------------------------------------------------------------------
  # Merged SSH validation must run on the FINAL merged config, not only on the
  # pre-merge base/override inputs. Base SSH is disabled with an invalid port
  # (disabled SSH skips the port check, so base validation passes), and the
  # version override enables SSH. After merge the SSH config is enabled and
  # inherits the invalid base port, so validate-service-complete must fail with
  # an SSH error sourced from the merged validation path.
  # ------------------------------------------------------------------

  let t_complete_merged_ssh = (run-test "validate-service-complete: merged SSH inherits invalid port and fails via merged path" {
    let tmp = (make-temp)
    let result = (do {
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "sshmerge")
      "FROM scratch" | save -f ($tmp | path join "services" "sshmerge" "Dockerfile")
      # Base SSH is disabled with a bad port; disabled SSH skips the port check,
      # so base validation passes here.
      {
        name: "sshmerge",
        context: "services/sshmerge",
        dockerfile: "services/sshmerge/Dockerfile",
        ssh: {enabled: false, port: "bad"}
      } | save -f ($tmp | path join "services" "sshmerge.nuon")
      # Override enables SSH with a valid mode; override validation passes too.
      # Merge inherits the base port, producing an enabled SSH config with a
      # non-integer port.
      {
        default: "v1",
        versions: [
          {name: "v1", overrides: {ssh: {enabled: true, mode: "server"}}}
        ]
      } | save -f ($tmp | path join "services" "sshmerge" "versions.nuon")
      validate-service-complete "sshmerge"
    })
    rm-temp $tmp
    if $result.valid {
      error make {msg: "Expected merged SSH (enabled + inherited bad port) to fail validation"}
    }
    let has_ssh_err = ($result.errors | any {|e| $e | str contains "ssh.port"})
    if not $has_ssh_err {
      error make {msg: $"Expected merged ssh.port error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_complete_merged_ssh)

  # ------------------------------------------------------------------
  # Single-platform source placement: a service with no base 'sources' is valid
  # when versions.nuon supplies a complete source via defaults. Sources are not
  # required in base config for single-platform services; the merged config must
  # be complete (git source has url+ref) after the defaults merge, and the
  # version override refines the ref. validate-service-complete must pass
  # end-to-end through the merged path.
  # ------------------------------------------------------------------

  let t_complete_merged_sources = (run-test "validate-service-complete: single-platform sources from versions defaults pass after merge" {
    let tmp = (make-temp)
    let result = (do {
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "srcplace")
      "FROM scratch" | save -f ($tmp | path join "services" "srcplace" "Dockerfile")
      # Base has no 'sources'; allowed for single-platform services.
      {
        name: "srcplace",
        context: "services/srcplace",
        dockerfile: "services/srcplace/Dockerfile"
      } | save -f ($tmp | path join "services" "srcplace.nuon")
      # versions defaults supply a complete git source; the override refines ref.
      {
        default: "v1",
        defaults: {sources: {app: {url: "https://example.com/app.git", ref: "v1.0.0"}}},
        versions: [
          {name: "v1", overrides: {sources: {app: {ref: "v1.2.3"}}}}
        ]
      } | save -f ($tmp | path join "services" "srcplace" "versions.nuon")
      validate-service-complete "srcplace"
    })
    rm-temp $tmp
    if not $result.valid {
      error make {msg: $"Expected single-platform service with versions-supplied sources to pass, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_complete_merged_sources)

  # ------------------------------------------------------------------
  # Merged clone-source compatibility: full SHA refs require helper or
  # explicit SHA fetch wiring; legacy git clone --branch surfaces fail.
  # ------------------------------------------------------------------

  let t_clone_compat_sha_legacy_fail = (run-test "validate-service-complete: SHA source with legacy git clone --branch fails" {
    let tmp = (make-temp)
    let sha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    let result = (do {
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "clonfail")
      $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
RUN git clone --branch \"\${APP_REF}\" --depth 1 \${APP_URL} /src/app
" | save -f ($tmp | path join "services" "clonfail" "Dockerfile")
      {
        name: "clonfail",
        context: "services/clonfail",
        dockerfile: "services/clonfail/Dockerfile"
      } | save -f ($tmp | path join "services" "clonfail.nuon")
      {
        default: "v1",
        defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
        versions: [{name: "v1"}]
      } | save -f ($tmp | path join "services" "clonfail" "versions.nuon")
      validate-service-complete "clonfail"
    })
    rm-temp $tmp
    if $result.valid {
      error make {msg: "Expected SHA + legacy git clone --branch to fail clone compat validation"}
    }
    let legacy_err = ($result.errors | where {|e| $e | str contains "clone --branch"} | length)
    if $legacy_err == 0 {
      error make {msg: $"Expected legacy clone --branch error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_clone_compat_sha_legacy_fail)

  let t_clone_compat_sha_legacy_continuation_fail = (run-test "validate-service-complete: legacy git clone --branch with line continuation fails" {
    let tmp = (make-temp)
    let sha = "aeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeae"
    let result = (do {
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "clonlegacycont")
      $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
RUN git clone \\
  --branch \"\${APP_REF}\" \\
  --depth 1 \${APP_URL} /src/app
" | save -f ($tmp | path join "services" "clonlegacycont" "Dockerfile")
      {
        name: "clonlegacycont",
        context: "services/clonlegacycont",
        dockerfile: "services/clonlegacycont/Dockerfile"
      } | save -f ($tmp | path join "services" "clonlegacycont.nuon")
      {
        default: "v1",
        defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
        versions: [{name: "v1"}]
      } | save -f ($tmp | path join "services" "clonlegacycont" "versions.nuon")
      validate-service-complete "clonlegacycont"
    })
    rm-temp $tmp
    if $result.valid {
      error make {msg: "Expected multiline legacy git clone --branch to fail clone compat validation"}
    }
    let legacy_err = ($result.errors | where {|e| $e | str contains "clone --branch"} | length)
    if $legacy_err == 0 {
      error make {msg: $"Expected legacy clone --branch error for continuation Dockerfile, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_clone_compat_sha_legacy_continuation_fail)

  let t_clone_compat_sha_helper_pass = (run-test "validate-service-complete: SHA source with clone-source helper passes" {
    let tmp = (make-temp)
    let sha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    let result = (do {
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "clonok")
      $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_REF_KIND=\"\"
COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu
RUN nu /tmp/clone-source.nu --mode git --url \"\${APP_URL}\" --ref \"\${APP_REF}\" --ref-kind \"\${APP_REF_KIND}\" --cache-dir /cache --dest /src/app
" | save -f ($tmp | path join "services" "clonok" "Dockerfile")
      {
        name: "clonok",
        context: "services/clonok",
        dockerfile: "services/clonok/Dockerfile"
      } | save -f ($tmp | path join "services" "clonok.nuon")
      {
        default: "v1",
        defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
        versions: [{name: "v1"}]
      } | save -f ($tmp | path join "services" "clonok" "versions.nuon")
      validate-service-complete "clonok"
    })
    rm-temp $tmp
    if not $result.valid {
      error make {msg: $"Expected SHA + clone-source helper to pass, got: ($result.errors | str join ', ')"}
    }
    let lacks_wiring = ($result.errors | any {|e| $e | str contains "lacks"})
    if $lacks_wiring {
      error make {msg: $"Expected clone-source helper wiring to satisfy compat, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_clone_compat_sha_helper_pass)

  let t_clone_compat_sha_inline_pass = (run-test "validate-service-complete: SHA source with inline fetch/checkout passes" {
    let tmp = (make-temp)
    let sha = "cccccccccccccccccccccccccccccccccccccccc"
    let result = (do {
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "cloninline")
      $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_SHA=\"\"
RUN git clone --depth 1 \${APP_URL} /src/app && if ! git -C /src/app checkout \"\${APP_SHA}\"; then git -C /src/app fetch --depth 1 origin \"\${APP_SHA}\" && git -C /src/app checkout \"\${APP_SHA}\"; fi
" | save -f ($tmp | path join "services" "cloninline" "Dockerfile")
      {
        name: "cloninline",
        context: "services/cloninline",
        dockerfile: "services/cloninline/Dockerfile"
      } | save -f ($tmp | path join "services" "cloninline.nuon")
      {
        default: "v1",
        defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
        versions: [{name: "v1"}]
      } | save -f ($tmp | path join "services" "cloninline" "versions.nuon")
      validate-service-complete "cloninline"
    })
    rm-temp $tmp
    if not $result.valid {
      error make {msg: $"Expected inline SHA fetch/checkout to pass, got: ($result.errors | str join ', ')"}
    }
    let lacks_err = ($result.errors | any {|e| $e | str contains "lacks"})
    if $lacks_err {
      error make {msg: $"Expected inline SHA path to satisfy compat, got: ($result.errors | str join ', ')"}
    }
    let legacy_err = ($result.errors | any {|e| $e | str contains "clone --branch"})
    if $legacy_err {
      error make {msg: $"Expected inline SHA path to avoid legacy clone error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_clone_compat_sha_inline_pass)

  let t_clone_compat_inline_decoupled_fail = (run-test "validate-service-complete: decoupled inline fetch and checkout fails" {
    let tmp = (make-temp)
    let sha = "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd"
    let result = (do {
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "clondecouple")
      $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_SHA=\"\"
RUN git -C /src/other fetch --depth 1 origin main
RUN git -C /src/app checkout \"\${APP_SHA}\"
" | save -f ($tmp | path join "services" "clondecouple" "Dockerfile")
      {
        name: "clondecouple",
        context: "services/clondecouple",
        dockerfile: "services/clondecouple/Dockerfile"
      } | save -f ($tmp | path join "services" "clondecouple.nuon")
      {
        default: "v1",
        defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
        versions: [{name: "v1"}]
      } | save -f ($tmp | path join "services" "clondecouple" "versions.nuon")
      validate-service-complete "clondecouple"
    })
    rm-temp $tmp
    if $result.valid {
      error make {msg: "Expected decoupled inline fetch/checkout to fail clone compat validation"}
    }
    let lacks_err = ($result.errors | any {|e| $e | str contains "lacks"})
    if not $lacks_err {
      error make {msg: $"Expected lacks-wiring error for decoupled inline path, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_clone_compat_inline_decoupled_fail)

  let t_clone_compat_inline_comment_fail = (run-test "validate-service-complete: inline SHA comment does not satisfy compat" {
    let tmp = (make-temp)
    let sha = "abababababababababababababababababababab"
    let result = (do {
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "cloncomment")
      $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
RUN echo building # git fetch APP_SHA and git checkout APP_SHA here
" | save -f ($tmp | path join "services" "cloncomment" "Dockerfile")
      {
        name: "cloncomment",
        context: "services/cloncomment",
        dockerfile: "services/cloncomment/Dockerfile"
      } | save -f ($tmp | path join "services" "cloncomment.nuon")
      {
        default: "v1",
        defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
        versions: [{name: "v1"}]
      } | save -f ($tmp | path join "services" "cloncomment" "versions.nuon")
      validate-service-complete "cloncomment"
    })
    rm-temp $tmp
    if $result.valid {
      error make {msg: "Expected inline SHA comment decoy to fail clone compat validation"}
    }
    let lacks_err = ($result.errors | any {|e| (($e | str contains "lacks") and ($e | str contains "app"))})
    if not $lacks_err {
      error make {msg: $"Expected final lacks-wiring rejection for app, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_clone_compat_inline_comment_fail)

  let t_clone_compat_sha_no_wiring_fail = (run-test "validate-service-complete: SHA source without clone wiring fails" {
    let tmp = (make-temp)
    let sha = "dddddddddddddddddddddddddddddddddddddddd"
    let result = (do {
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "clonnowire")
      $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_REF_KIND=\"\"
# git fetch APP_SHA and checkout would go here
RUN echo building
" | save -f ($tmp | path join "services" "clonnowire" "Dockerfile")
      {
        name: "clonnowire",
        context: "services/clonnowire",
        dockerfile: "services/clonnowire/Dockerfile"
      } | save -f ($tmp | path join "services" "clonnowire.nuon")
      {
        default: "v1",
        defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
        versions: [{name: "v1"}]
      } | save -f ($tmp | path join "services" "clonnowire" "versions.nuon")
      validate-service-complete "clonnowire"
    })
    rm-temp $tmp
    if $result.valid {
      error make {msg: "Expected SHA source without wiring to fail clone compat validation"}
    }
    let lacks_err = ($result.errors | any {|e| $e | str contains "lacks"})
    if not $lacks_err {
      error make {msg: $"Expected final lacks-wiring error, got: ($result.errors | str join ', ')"}
    }
    let legacy_err = ($result.errors | any {|e| $e | str contains "clone --branch"})
    if $legacy_err {
      error make {msg: $"Expected lacks-wiring branch, not legacy clone error, got: ($result.errors | str join ', ')"}
    }
    let app_err = ($result.errors | any {|e| ($e | str contains "sources.app") and ($e | str contains "lacks")})
    if not $app_err {
      error make {msg: $"Expected sources.app lacks-wiring error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_clone_compat_sha_no_wiring_fail)

  let t_clone_compat_helper_false_positive = (run-test "validate-service-complete: scattered REF_KIND without clone wiring fails" {
    let tmp = (make-temp)
    let sha = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    let result = (do {
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "clonscatter" "scripts" "build")
      $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_REF_KIND=\"\"
ARG PLUGIN_REF=\"\"
ARG PLUGIN_REF_KIND=\"\"
COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu
RUN nu /tmp/clone-source.nu --mode git --url \"\${APP_URL}\" --ref \"\${APP_REF}\" --ref-kind \"\${APP_REF_KIND}\" --cache-dir /cache --dest /src/app
" | save -f ($tmp | path join "services" "clonscatter" "Dockerfile")
      $"
# PLUGIN_REF_KIND mentioned but not wired to clone-source.nu
let ref_kind = $env.PLUGIN_REF_KIND? | default \"\"
" | save -f ($tmp | path join "services" "clonscatter" "scripts" "build" "unused.nu")
      {
        name: "clonscatter",
        context: "services/clonscatter",
        dockerfile: "services/clonscatter/Dockerfile"
      } | save -f ($tmp | path join "services" "clonscatter.nuon")
      {
        default: "v1",
        defaults: {
          sources: {
            app: {url: "https://example.com/app.git", ref: $sha},
            plugin: {url: "https://example.com/plugin.git", ref: "ffffffffffffffffffffffffffffffffffffffff"}
          }
        },
        versions: [{name: "v1"}]
      } | save -f ($tmp | path join "services" "clonscatter" "versions.nuon")
      validate-service-complete "clonscatter"
    })
    rm-temp $tmp
    if $result.valid {
      error make {msg: "Expected plugin SHA without clone wiring to fail"}
    }
    let plugin_err = ($result.errors | any {|e|
      ($e | str contains "plugin") and ($e | str contains "lacks")
    })
    if not $plugin_err {
      error make {msg: $"Expected plugin lacks-wiring error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_clone_compat_helper_false_positive)

  let t_clone_compat_helper_coblock_fail = (run-test "validate-service-complete: co-block PLUGIN tokens without clone wiring fails" {
    let tmp = (make-temp)
    let sha = "fdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfd"
    let result = (do {
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "cloncoblock")
      $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_REF_KIND=\"\"
ARG PLUGIN_REF=\"\"
ARG PLUGIN_REF_KIND=\"\"
COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu
RUN nu /tmp/clone-source.nu --mode git --url \"\${APP_URL}\" --ref \"\${APP_REF}\" --ref-kind \"\${APP_REF_KIND}\" --cache-dir /cache --dest /src/app && echo PLUGIN_REF_KIND \${PLUGIN_REF}
" | save -f ($tmp | path join "services" "cloncoblock" "Dockerfile")
      {
        name: "cloncoblock",
        context: "services/cloncoblock",
        dockerfile: "services/cloncoblock/Dockerfile"
      } | save -f ($tmp | path join "services" "cloncoblock.nuon")
      {
        default: "v1",
        defaults: {
          sources: {
            app: {url: "https://example.com/app.git", ref: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
            plugin: {url: "https://example.com/plugin.git", ref: $sha}
          }
        },
        versions: [{name: "v1"}]
      } | save -f ($tmp | path join "services" "cloncoblock" "versions.nuon")
      validate-service-complete "cloncoblock"
    })
    rm-temp $tmp
    if $result.valid {
      error make {msg: "Expected PLUGIN SHA with co-block token echo to fail clone compat validation"}
    }
    let plugin_err = ($result.errors | any {|e|
      ($e | str contains "sources.plugin") and ($e | str contains "lacks")
    })
    if not $plugin_err {
      error make {msg: $"Expected sources.plugin lacks-wiring error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_clone_compat_helper_coblock_fail)

  let t_clone_compat_ref_kind_not_ref = (run-test "validate-service-complete: REF_KIND alone does not satisfy REF participation" {
    let tmp = (make-temp)
    let sha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    let result = (do {
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "clonrefkind" "scripts" "build")
      $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_REF_KIND=\"\"
ARG PLUGIN_REF_KIND=\"\"
COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu
RUN nu /tmp/clone-source.nu --mode git --url \"\${APP_URL}\" --ref \"\${APP_REF}\" --ref-kind \"\${APP_REF_KIND}\" --cache-dir /cache --dest /src/app
" | save -f ($tmp | path join "services" "clonrefkind" "Dockerfile")
      $"
# ref_kind binding only; plugin REF arg not used in clone wiring
let ref_kind = $env.PLUGIN_REF_KIND? | default \"\"
" | save -f ($tmp | path join "services" "clonrefkind" "scripts" "build" "unused.nu")
      {
        name: "clonrefkind",
        context: "services/clonrefkind",
        dockerfile: "services/clonrefkind/Dockerfile"
      } | save -f ($tmp | path join "services" "clonrefkind.nuon")
      {
        default: "v1",
        defaults: {
          sources: {
            app: {url: "https://example.com/app.git", ref: $sha},
            plugin: {url: "https://example.com/plugin.git", ref: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
          }
        },
        versions: [{name: "v1"}]
      } | save -f ($tmp | path join "services" "clonrefkind" "versions.nuon")
      validate-service-complete "clonrefkind"
    })
    rm-temp $tmp
    if not $result.valid {
      error make {msg: $"REF_KIND without REF should not enforce plugin wiring, got: ($result.errors | str join ', ')"}
    }
    let plugin_err = ($result.errors | any {|e| $e | str contains "plugin"})
    if $plugin_err {
      error make {msg: $"PLUGIN_REF_KIND alone must not count as PLUGIN_REF participation, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_clone_compat_ref_kind_not_ref)

  let t_clone_compat_block_ref_kind_only_fail = (run-test "validate-service-complete: clone block with REF_KIND but not REF fails" {
    let tmp = (make-temp)
    let sha = "cccccccccccccccccccccccccccccccccccccccc"
    let result = (do {
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "clonblockhole")
      $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_REF_KIND=\"\"
RUN nu /tmp/clone-source.nu --mode git --url \"\${APP_URL}\" --ref-kind \"\${APP_REF_KIND}\" --cache-dir /cache --dest /src/app
" | save -f ($tmp | path join "services" "clonblockhole" "Dockerfile")
      {
        name: "clonblockhole",
        context: "services/clonblockhole",
        dockerfile: "services/clonblockhole/Dockerfile"
      } | save -f ($tmp | path join "services" "clonblockhole.nuon")
      {
        default: "v1",
        defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
        versions: [{name: "v1"}]
      } | save -f ($tmp | path join "services" "clonblockhole" "versions.nuon")
      validate-service-complete "clonblockhole"
    })
    rm-temp $tmp
    if $result.valid {
      error make {msg: "Expected clone block with REF_KIND but no REF to fail clone compat validation"}
    }
    let lacks_err = ($result.errors | any {|e| $e | str contains "lacks"})
    if not $lacks_err {
      error make {msg: $"Expected lacks-wiring error, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_clone_compat_block_ref_kind_only_fail)

  let t_clone_compat_override_script_pass = (run-test "validate-service-complete: override script under scripts/build passes" {
    let tmp = (make-temp)
    let sha = "1111111111111111111111111111111111111111"
    let outcome = (do {
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "clonoverride" "scripts" "build")
      let dockerfile_path = ($tmp | path join "services" "clonoverride" "Dockerfile")
      $"
FROM scratch
ARG OCIS_REVA_REF=\"\"
ARG OCIS_REVA_URL=\"\"
RUN nu /usr/local/bin/reva-override.nu
" | save -f $dockerfile_path
      $"
def checkout-sha [work_dir: string, sha: string]: nothing -> nothing {
    ^git -C $work_dir fetch --depth 1 origin $sha
    ^git -C $work_dir checkout $sha
}

def main [] {
    let url = $env.OCIS_REVA_URL? | default \"\"
    let ref_ = $env.OCIS_REVA_REF? | default \"\"
    let sha = $env.OCIS_REVA_SHA? | default \"\"
    let ref_kind = $env.OCIS_REVA_REF_KIND? | default \"\"
    ^nu /usr/local/bin/clone-source.nu --mode git --url $url --ref $ref_ --ref-kind $ref_kind --cache-dir /cache --dest /src/reva
    if not ($sha | is-empty) {
        checkout-sha /src/reva $sha
    }
}
" | save -f ($tmp | path join "services" "clonoverride" "scripts" "build" "reva-override.nu")
      {
        name: "clonoverride",
        context: "services/clonoverride",
        dockerfile: "services/clonoverride/Dockerfile"
      } | save -f ($tmp | path join "services" "clonoverride.nuon")
      {
        default: "v1",
        defaults: {
          sources: {
            ocis_reva: {url: "https://example.com/reva.git", ref: $sha}
          }
        },
        versions: [{name: "v1"}]
      } | save -f ($tmp | path join "services" "clonoverride" "versions.nuon")
      {
        result: (validate-service-complete "clonoverride"),
        dockerfile_text: (open -r $dockerfile_path)
      }
    })
    rm-temp $tmp
    let result = ($outcome.result)
    if not $result.valid {
      error make {msg: $"Expected override-script clone wiring to pass, got: ($result.errors | str join ', ')"}
    }
    let lacks_err = ($result.errors | any {|e| $e | str contains "lacks"})
    if $lacks_err {
      error make {msg: $"Expected scripts/build override to satisfy compat, got: ($result.errors | str join ', ')"}
    }
    let dockerfile_text = ($outcome.dockerfile_text)
    if ($dockerfile_text | str contains "clone-source.nu") {
      error make {msg: "Expected clone wiring to live only under scripts/build, not Dockerfile"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_clone_compat_override_script_pass)

  let t_clone_compat_tag_legacy_pass = (run-test "validate-service-complete: tag ref with legacy git clone --branch passes" {
    let tmp = (make-temp)
    let result = (do {
      cd $tmp
      (^git init | complete | ignore)
      mkdir ($tmp | path join "services" "clontag")
      $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
RUN git clone --branch \"\${APP_REF}\" --depth 1 \${APP_URL} /src/app
" | save -f ($tmp | path join "services" "clontag" "Dockerfile")
      {
        name: "clontag",
        context: "services/clontag",
        dockerfile: "services/clontag/Dockerfile"
      } | save -f ($tmp | path join "services" "clontag.nuon")
      {
        default: "v1",
        defaults: {sources: {app: {url: "https://example.com/app.git", ref: "v1.0.0"}}},
        versions: [{name: "v1"}]
      } | save -f ($tmp | path join "services" "clontag" "versions.nuon")
      validate-service-complete "clontag"
    })
    rm-temp $tmp
    if not $result.valid {
      error make {msg: $"Expected tag ref + legacy clone to pass, got: ($result.errors | str join ', ')"}
    }
    let clone_compat_err = ($result.errors | any {|e|
      ($e | str contains "clone --branch") or ($e | str contains "lacks")
    })
    if $clone_compat_err {
      error make {msg: $"Tag ref should skip SHA clone compat enforcement, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_clone_compat_tag_legacy_pass)

  let t_clone_compat_cernbox = (run-test "validate-service-complete: cernbox-revad passes with pinned SHA revad_plugins" {
    let result = (validate-service-complete "cernbox-revad")
    if not $result.valid {
      error make {msg: $"Expected cernbox-revad complete validation to pass, got: ($result.errors | str join ', ')"}
    }
    let clone_compat_err = ($result.errors | any {|e|
      ($e | str contains "lacks") or ($e | str contains "clone --branch")
    })
    if $clone_compat_err {
      error make {msg: $"Expected cernbox-revad clone compat to pass, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $t_clone_compat_cernbox)

  print-test-summary $results

  let failed = ($results | where {|r| not $r} | length)
  if $failed > 0 {
    exit 1
  }
}
