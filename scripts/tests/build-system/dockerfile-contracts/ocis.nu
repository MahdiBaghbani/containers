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

# ocis Dockerfile contract, override script, and manifest tests.

use ../../../lib/build/args.nu [generate-build-args]
use ../../../lib/build/config.nu [load-service-config detect-all-source-types]
use ../../../lib/build/sources.nu [extract-source-ref-kinds]
use ../../../lib/manifest/core.nu [get-version-or-null load-versions-manifest]
use ../../../lib/platforms/core.nu [load-platforms-manifest]
use ../../mocks.nu [detect-build]
use ../../helpers.nu [create-test-tls-meta]
use ../../lib.nu [run-test]
use ./_helpers.nu [
  clone-source-ref-kind-env-pattern
  dockerfile-collect-continuation-block
  dockerfile-collect-run-block-containing
  script-active-trimmed-lines
]

def ocis-override-binds-ref-kind-from-env [content: string, ref_kind_env: string] {
  script-active-trimmed-lines $content
  | any {|t|
    ($t | str starts-with "let ref_kind =") and ($t | str contains $"$env.($ref_kind_env)")
  }
}

def ocis-override-clone-line-has-contract [text: string] {
  let required = [
    "--mode $clone_mode"
    "--url $url"
    "--ref $ref_"
    "--ref-kind $ref_kind"
    "--cache-dir $git_cache"
    "--dest $work_dir"
  ]
  $required | all {|needle| $text | str contains $needle}
}

def ocis-override-has-guarded-sha-checkout [content: string] {
  let guard_needles = ['($clone_mode == "git")', "not ($sha | is-empty)"]
  let checkout_needles = [
    "checkout-sha $work_dir $sha"
  ]
  let active = (script-active-trimmed-lines $content)
  let same_line = (
    $active
    | any {|line|
        (
          ($guard_needles | all {|n| $line | str contains $n})
          and ($checkout_needles | any {|n| $line | str contains $n})
        )
      }
  )
  if $same_line {
    return true
  }
  let indexed = (
    $content
    | lines
    | enumerate
    | each {|e| {index: $e.index, text: ($e.item | str trim)}}
    | where {|e| ($e.text | str length) > 0 and not ($e.text | str starts-with "#")}
  )
  let guard_entries = (
    $indexed
    | where {|e| $guard_needles | all {|n| $e.text | str contains $n}}
  )
  if ($guard_entries | length) == 0 {
    return false
  }
  for guard in $guard_entries {
    let guard_idx = $guard.index
    let checkout_after = (
      $indexed
      | where {|e|
          (
            $e.index >= $guard_idx
            and ($checkout_needles | any {|n| $e.text | str contains $n})
          )
        }
    )
    if ($checkout_after | length) > 0 {
      return true
    }
  }
  false
}

def ocis-override-has-fetch-capable-checkout-sha-helper [content: string] {
  let active = (script-active-trimmed-lines $content)
  let def_entry = (
    $active
    | enumerate
    | where {|e| $e.item | str starts-with "def checkout-sha"}
    | first
  )
  if $def_entry == null {
    return false
  }
  let def_idx = ($def_entry | get index)
  let helper_body = ($active | skip ($def_idx + 1) | take 20)
  let has_first_attempt = (
    $helper_body
    | any {|t|
        (
          ($t | str contains "^git -C $work_dir checkout $sha")
          and ($t | str contains "| complete")
        )
      }
  )
  let has_early_return = (
    ($helper_body | any {|t| $t | str contains "$first.exit_code == 0"})
    and ($helper_body | any {|t| $t | str contains "return"})
  )
  let has_fetch_retry = (
    $helper_body
    | any {|t|
        ($t | str contains "fetch --depth 1 origin") and ($t | str contains "$sha")
      }
  )
  let checkout_attempts = (
    $helper_body | where {|t| $t | str contains "^git -C $work_dir checkout $sha"} | length
  )
  let has_error = ($helper_body | any {|t| $t | str contains "error make"})
  (
    $has_first_attempt
    and $has_early_return
    and $has_fetch_retry
    and ($checkout_attempts >= 2)
    and $has_error
  )
}

def assert-dockerfile-ocis-sha-checkout-guard [block: string, dockerfile_path: string] {
  if not ($block | str contains "OCIS_MODE") {
    error make {
      msg: $"ocis clone-source RUN block must guard SHA checkout when mode is not local in ($dockerfile_path)"
    }
  }
  let has_local_guard = (
    ($block | str contains '!= "local"') or ($block | str contains "!= 'local'")
  )
  if not $has_local_guard {
    error make {
      msg: $"ocis clone-source RUN block must guard SHA checkout when mode is not local in ($dockerfile_path)"
    }
  }
  if not (($block | str contains "OCIS_SHA") and ($block | str contains "-n ")) {
    error make {
      msg: $"ocis clone-source RUN block must require non-empty OCIS_SHA before checkout in ($dockerfile_path)"
    }
  }
  if not (($block | str contains "git -C /ocis checkout") and ($block | str contains "OCIS_SHA")) {
    error make {
      msg: $"ocis clone-source RUN block must checkout OCIS_SHA into /ocis in ($dockerfile_path)"
    }
  }
  let fetch_retry_needles = [
    'if ! git -C /ocis checkout "$OCIS_SHA"'
    "fetch --depth 1 origin"
    'git -C /ocis checkout "$OCIS_SHA"'
  ]
  for needle in $fetch_retry_needles {
    if not ($block | str contains $needle) {
      error make {
        msg: $"ocis clone-source RUN block missing SHA fetch-retry fragment '($needle)' in ($dockerfile_path)"
      }
    }
  }
}

def assert-ocis-dockerfile-clone-source-contract [dockerfile_path: string] {
  if not ($dockerfile_path | path exists) {
    error make {msg: $"Dockerfile not found: ($dockerfile_path)"}
  }
  let copy_needle = "COPY --chmod=755 ./scripts/lib/clone-source.nu /usr/local/bin/clone-source.nu"
  let lines = (open --raw $dockerfile_path | lines)
  let copy_count = ($lines | where {|l| ($l | str trim) == $copy_needle} | length)
  if $copy_count != 2 {
    error make {
      msg: $"Expected 2 clone-source.nu COPY lines in ($dockerfile_path), found ($copy_count)"
    }
  }
  let required_stage_args = [
    'ARG OCIS_MODE=""'
    'ARG OCIS_REF_KIND=""'
    'ARG OCIS_WEB_REF_KIND=""'
    'ARG OCIS_REVA_REF_KIND=""'
  ]
  for arg_line in $required_stage_args {
    if not ($lines | any {|l| ($l | str trim) == $arg_line}) {
      error make {
        msg: $"ocis Dockerfile missing stage-local ($arg_line) in ($dockerfile_path)"
      }
    }
  }
  let invoke_prefix = "nu /usr/local/bin/clone-source.nu"
  let invoke_indices = (
    $lines
    | enumerate
    | where {|e| ($e.item | str trim) | str starts-with $invoke_prefix }
    | get index
  )
  if ($invoke_indices | length) != 1 {
    error make {
      msg: $"Expected 1 clone-source.nu invocation in ($dockerfile_path), found ($invoke_indices | length)"
    }
  }
  let block = (dockerfile-collect-continuation-block $lines ($invoke_indices | first))
  let required_flags = [
    '--mode "${OCIS_MODE:-git}"'
    '--url "${OCIS_URL}"'
    '--ref "${OCIS_REF}"'
    (clone-source-ref-kind-env-pattern "OCIS_REF_KIND")
    "--local-dir /mnt/src"
    "--cache-dir /src/ocis-git-cache"
    "--dest /ocis"
  ]
  for flag in $required_flags {
    if not ($block | str contains $flag) {
      error make {
        msg: $"ocis clone-source RUN block missing '($flag)' in ($dockerfile_path)"
      }
    }
  }
  assert-dockerfile-ocis-sha-checkout-guard $block $dockerfile_path
}

def assert-ocis-dockerfile-override-wiring [dockerfile_path: string] {
  if not ($dockerfile_path | path exists) {
    error make {msg: $"Dockerfile not found: ($dockerfile_path)"}
  }
  let lines = (open --raw $dockerfile_path | lines)
  let trimmed = ($lines | each {|l| $l | str trim})
  let required = [
    "COPY --chmod=755 ./scripts/build/web-override.nu /usr/local/bin/web-override.nu"
    "COPY --chmod=755 ./scripts/build/reva-override.nu /usr/local/bin/reva-override.nu"
    "nu /usr/local/bin/web-override.nu"
    "nu /usr/local/bin/reva-override.nu"
  ]
  for needle in $required {
    if not ($trimmed | any {|l| $l == $needle}) {
      error make {
        msg: $"ocis Dockerfile missing required override wiring line '($needle)' in ($dockerfile_path)"
      }
    }
  }
  let web_block = (dockerfile-collect-run-block-containing $lines "nu /usr/local/bin/web-override.nu")
  if ($web_block | str length) == 0 {
    error make {
      msg: $"ocis Dockerfile missing RUN block for web-override.nu in ($dockerfile_path)"
    }
  }
  let web_mount_needles = [
    "target=/mnt/web"
    "id=ocis-web-git-"
    "target=/src/ocis-web-git-cache"
  ]
  for needle in $web_mount_needles {
    if not ($web_block | str contains $needle) {
      error make {
        msg: $"ocis web-override RUN block missing mount fragment '($needle)' in ($dockerfile_path)"
      }
    }
  }
  let reva_block = (dockerfile-collect-run-block-containing $lines "nu /usr/local/bin/reva-override.nu")
  if ($reva_block | str length) == 0 {
    error make {
      msg: $"ocis Dockerfile missing RUN block for reva-override.nu in ($dockerfile_path)"
    }
  }
  let reva_mount_needles = [
    "target=/mnt/reva"
    "id=ocis-reva-git-"
    "target=/src/ocis-reva-git-cache"
  ]
  for needle in $reva_mount_needles {
    if not ($reva_block | str contains $needle) {
      error make {
        msg: $"ocis reva-override RUN block missing mount fragment '($needle)' in ($dockerfile_path)"
      }
    }
  }
}

def assert-ocis-override-uses-clone-source [
  script_path: string
  local_mount: string
  ref_kind_env: string
] {
  if not ($script_path | path exists) {
    error make {msg: $"Script not found: ($script_path)"}
  }
  let content = (open --raw $script_path)
  let active = (script-active-trimmed-lines $content)
  if not ($active | any {|t| $t | str contains "/usr/local/bin/clone-source.nu"}) {
    error make {msg: $"($script_path) must call /usr/local/bin/clone-source.nu"}
  }
  let git_clone_lines = ($active | where {|t| $t | str starts-with "^git clone"})
  if ($git_clone_lines | length) > 0 {
    error make {msg: $"($script_path) must not use inline git clone"}
  }
  let indexed_active = (
    $content
    | lines
    | enumerate
    | each {|e| {index: $e.index, text: ($e.item | str trim)}}
    | where {|e| ($e.text | str length) > 0 and not ($e.text | str starts-with "#")}
  )
  if not (ocis-override-binds-ref-kind-from-env $content $ref_kind_env) {
    error make {
      msg: $"($script_path) must bind ref_kind from ($ref_kind_env) before clone-source.nu"
    }
  }
  let binding_idx = (
    $indexed_active
    | where {|e| ($e.text | str starts-with "let ref_kind =") and ($e.text | str contains $"$env.($ref_kind_env)")}
    | first
    | get index
  )
  let clone_entries = (
    $indexed_active | where {|e| $e.text | str contains "/usr/local/bin/clone-source.nu"}
  )
  if ($clone_entries | length) == 0 {
    error make {msg: $"($script_path) must call /usr/local/bin/clone-source.nu"}
  }
  let clone_entry = ($clone_entries | first)
  let clone_idx = ($clone_entry | get index)
  let clone_line = ($clone_entry | get text)
  if $binding_idx >= $clone_idx {
    error make {
      msg: $"($script_path) must bind ref_kind from ($ref_kind_env) before clone-source.nu invocation"
    }
  }
  if not (ocis-override-clone-line-has-contract $clone_line) {
    error make {
      msg: $"($script_path) clone-source.nu line must include --mode, --url, --ref, --ref-kind $ref_kind, --cache-dir, and --dest"
    }
  }
  let local_dir_flag = $"--local-dir ($local_mount)"
  if not ($clone_line | str contains $local_dir_flag) {
    error make {
      msg: $"($script_path) must pass ($local_dir_flag) to clone-source.nu"
    }
  }
  let mount_copy = (
    $active
    | where {|t| ($t | str starts-with "^cp -a") and ($t | str contains $local_mount)}
  )
  if ($mount_copy | length) > 0 {
    error make {
      msg: $"($script_path) must use clone-source.nu for local copy from ($local_mount)"
    }
  }
  let direct_cache_copy = (
    $active
    | where {|t|
        ($t | str starts-with "^cp -a") and (
          ($t | str contains "git_cache") or ($t | str contains '$"($git_cache)')
        )
      }
  )
  if ($direct_cache_copy | length) > 0 {
    error make {
      msg: $"($script_path) must not copy directly from git cache to work dir"
    }
  }
  let cache_path_copy = (
    $active
    | where {|t| ($t | str contains '$"($git_cache)/."') and not ($t | str contains "clone-source.nu")}
  )
  if ($cache_path_copy | length) > 0 {
    error make {
      msg: $"($script_path) must not copy directly from git cache to work dir"
    }
  }
  if not (ocis-override-has-guarded-sha-checkout $content) {
    error make {
      msg: $"($script_path) must guard SHA checkout behind git mode and non-empty SHA"
    }
  }
  if not (ocis-override-has-fetch-capable-checkout-sha-helper $content) {
    error make {
      msg: $"($script_path) checkout-sha helper must retry via 'git fetch --depth 1 origin \$sha' and raise a clear error if the retried checkout still fails"
    }
  }
}

export def ocis-tests [verbose: bool] {
  [
    (run-test "Test 39z: Dockerfile drift - ocis clone-source contract and SHA checkout guard" {
      assert-ocis-dockerfile-clone-source-contract "services/ocis/Dockerfile.alpine"
      true
    } $verbose)
    (run-test "Test 39za: ocis override scripts use clone-source.nu contract" {
      assert-ocis-override-uses-clone-source "services/ocis/scripts/build/web-override.nu" "/mnt/web" "OCIS_WEB_REF_KIND"
      assert-ocis-override-uses-clone-source "services/ocis/scripts/build/reva-override.nu" "/mnt/reva" "OCIS_REVA_REF_KIND"
      true
    } $verbose)
    (run-test "Test 39zb: Dockerfile drift - ocis web/reva override script COPY and RUN wiring" {
      assert-ocis-dockerfile-override-wiring "services/ocis/Dockerfile.alpine"
      true
    } $verbose)
    (run-test "Test 39zc: Real manifest - ocis v8.0.1 and master alpine OCIS_REF_KIND build args" {
      let svc = "ocis"
      let platform = "alpine"
      let vm = (load-versions-manifest $svc)
      let pm = (load-platforms-manifest $svc)
      let meta = (detect-build)
      let tls_meta = (create-test-tls-meta)
      let ssh_meta = {
        enabled: false,
        mode: "disabled",
        default_user: "root",
        port: 22,
        listen: "0.0.0.0"
      }
      let version_tag = "v8.0.1"
      let vspec_tag = (get-version-or-null $vm $version_tag)
      let cfg_tag = (load-service-config $svc $vspec_tag $platform $pm)
      let ocis_ref_tag = (try { $cfg_tag.sources.ocis.ref } catch { "" })
      if $ocis_ref_tag != "v8.0.1" {
        error make {msg: $"Expected ocis ref 'v8.0.1' from tracked manifest, got: ($ocis_ref_tag)"}
      }
      let source_types_tag = (detect-all-source-types $cfg_tag.sources)
      let source_ref_kinds_tag = (extract-source-ref-kinds $cfg_tag.sources $source_types_tag)
      let build_args_tag = (
        generate-build-args $version_tag $cfg_tag $meta {} $tls_meta $ssh_meta "" false {} $source_types_tag {} "tracked" $source_ref_kinds_tag
      )
      if (try { $build_args_tag.OCIS_REF_KIND } catch { "" }) != "ref" {
        error make {msg: $"Expected OCIS_REF_KIND=ref for tag v8.0.1, got: ($build_args_tag.OCIS_REF_KIND?)"}
      }
      let version_master = "master"
      let vspec_master = (get-version-or-null $vm $version_master)
      let cfg_master = (load-service-config $svc $vspec_master $platform $pm)
      let ocis_ref_master = (try { $cfg_master.sources.ocis.ref } catch { "" })
      if $ocis_ref_master != "master" {
        error make {msg: $"Expected ocis ref 'master' from tracked manifest, got: ($ocis_ref_master)"}
      }
      let source_types_master = (detect-all-source-types $cfg_master.sources)
      let source_ref_kinds_master = (extract-source-ref-kinds $cfg_master.sources $source_types_master)
      let build_args_master = (
        generate-build-args $version_master $cfg_master $meta {} $tls_meta $ssh_meta "" false {} $source_types_master {} "tracked" $source_ref_kinds_master
      )
      if (try { $build_args_master.OCIS_REF_KIND } catch { "" }) != "ref" {
        error make {msg: $"Expected OCIS_REF_KIND=ref for branch master, got: ($build_args_master.OCIS_REF_KIND?)"}
      }
      if $verbose {
        print $"    v8.0.1 OCIS_REF_KIND=($build_args_tag.OCIS_REF_KIND)"
        print $"    master OCIS_REF_KIND=($build_args_master.OCIS_REF_KIND)"
      }
      true
    } $verbose)
  ]
}
