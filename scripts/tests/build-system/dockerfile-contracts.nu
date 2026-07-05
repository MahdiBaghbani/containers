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

# Dockerfile parsing and clone-source contract assertions.

use ../../lib/build/args.nu [generate-build-args]
use ../../lib/build/config.nu [load-service-config process-sources-to-build-args detect-all-source-types]
use ../../lib/build/sources.nu [classify-source-ref-kind extract-source-ref-kinds]
use ../../lib/manifest/core.nu [get-version-or-null load-versions-manifest]
use ../../lib/platforms/core.nu [load-platforms-manifest]
use ../mocks.nu [detect-build]
use ../helpers.nu [setup-test-environment with-test-cleanup create-test-tls-meta assert-build-args-contain]
use ../lib.nu [run-test]

export def clone-source-ref-kind-env-pattern [env_name: string] {
  "--ref-kind " + ('"' + '$' + '{' + $env_name + '}' + '"')
}

export def script-active-trimmed-lines [content: string] {
  $content
  | lines
  | each {|line| $line | str trim}
  | where {|t| ($t | str length) > 0 and not ($t | str starts-with "#")}
}

export def dockerfile-collect-continuation-block [lines: list<string>, start_idx: int] {
  mut block_lines = []
  mut i = $start_idx
  loop {
    $block_lines = ($block_lines | append ($lines | get $i))
    let line = ($lines | get $i | str trim)
    if not ($line | str ends-with "\\") {
      break
    }
    $i = $i + 1
  }
  $block_lines | str join "\n"
}

export def dockerfile-collect-run-block-containing [lines: list<string>, needle: string] {
  let hit = (
    $lines
    | enumerate
    | where {|e| ($e.item | str trim) | str starts-with $needle}
    | last
  )
  if $hit == null {
    return ""
  }
  let hit_idx = ($hit | get index)
  mut run_idx = $hit_idx
  while $run_idx > 0 {
    let trimmed = ($lines | get $run_idx | str trim)
    if ($trimmed | str starts-with "RUN ") or ($trimmed | str starts-with "RUN\t") {
      break
    }
    $run_idx = $run_idx - 1
  }
  dockerfile-collect-continuation-block $lines $run_idx
}

def opencloud-override-binds-ref-kind-from-env [content: string, ref_kind_env: string] {
  script-active-trimmed-lines $content
  | any {|t|
    ($t | str starts-with "let ref_kind =") and ($t | str contains $"$env.($ref_kind_env)")
  }
}

def opencloud-override-clone-line-has-contract [text: string] {
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

def opencloud-override-has-guarded-sha-checkout [content: string] {
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

def opencloud-override-has-fetch-capable-checkout-sha-helper [content: string] {
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

export def assert-dockerfile-opencloud-sha-checkout-guard [block: string, dockerfile_path: string] {
  if not ($block | str contains "OPENCLOUD_MODE") {
    error make {
      msg: $"opencloud clone-source RUN block must guard SHA checkout when mode is not local in ($dockerfile_path)"
    }
  }
  let has_local_guard = (
    ($block | str contains '!= "local"') or ($block | str contains "!= 'local'")
  )
  if not $has_local_guard {
    error make {
      msg: $"opencloud clone-source RUN block must guard SHA checkout when mode is not local in ($dockerfile_path)"
    }
  }
  if not (($block | str contains "OPENCLOUD_SHA") and ($block | str contains "-n ")) {
    error make {
      msg: $"opencloud clone-source RUN block must require non-empty OPENCLOUD_SHA before checkout in ($dockerfile_path)"
    }
  }
  if not (($block | str contains "git -C /opencloud checkout") and ($block | str contains "OPENCLOUD_SHA")) {
    error make {
      msg: $"opencloud clone-source RUN block must checkout OPENCLOUD_SHA into /opencloud in ($dockerfile_path)"
    }
  }
  let fetch_retry_needles = [
    'if ! git -C /opencloud checkout "$OPENCLOUD_SHA"'
    "fetch --depth 1 origin"
    'git -C /opencloud checkout "$OPENCLOUD_SHA"'
  ]
  for needle in $fetch_retry_needles {
    if not ($block | str contains $needle) {
      error make {
        msg: $"opencloud clone-source RUN block missing SHA fetch-retry fragment '($needle)' in ($dockerfile_path)"
      }
    }
  }
}

export def assert-opencloud-dockerfile-clone-source-contract [dockerfile_path: string] {
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
    'ARG OPENCLOUD_MODE=""'
    'ARG OPENCLOUD_REF_KIND=""'
    'ARG OPENCLOUD_WEB_REF_KIND=""'
    'ARG OPENCLOUD_REVA_REF_KIND=""'
  ]
  for arg_line in $required_stage_args {
    if not ($lines | any {|l| ($l | str trim) == $arg_line}) {
      error make {
        msg: $"opencloud Dockerfile missing stage-local ($arg_line) in ($dockerfile_path)"
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
    '--mode "${OPENCLOUD_MODE:-git}"'
    '--url "${OPENCLOUD_URL}"'
    '--ref "${OPENCLOUD_REF}"'
    (clone-source-ref-kind-env-pattern "OPENCLOUD_REF_KIND")
    "--local-dir /mnt/src"
    "--cache-dir /src/opencloud-git-cache"
    "--dest /opencloud"
  ]
  for flag in $required_flags {
    if not ($block | str contains $flag) {
      error make {
        msg: $"opencloud clone-source RUN block missing '($flag)' in ($dockerfile_path)"
      }
    }
  }
  assert-dockerfile-opencloud-sha-checkout-guard $block $dockerfile_path
}

export def assert-opencloud-dockerfile-override-wiring [dockerfile_path: string] {
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
        msg: $"opencloud Dockerfile missing required override wiring line '($needle)' in ($dockerfile_path)"
      }
    }
  }
  let web_block = (dockerfile-collect-run-block-containing $lines "nu /usr/local/bin/web-override.nu")
  if ($web_block | str length) == 0 {
    error make {
      msg: $"opencloud Dockerfile missing RUN block for web-override.nu in ($dockerfile_path)"
    }
  }
  let web_mount_needles = [
    "target=/mnt/web"
    "id=opencloud-web-git-"
    "target=/src/opencloud-web-git-cache"
  ]
  for needle in $web_mount_needles {
    if not ($web_block | str contains $needle) {
      error make {
        msg: $"opencloud web-override RUN block missing mount fragment '($needle)' in ($dockerfile_path)"
      }
    }
  }
  let reva_block = (dockerfile-collect-run-block-containing $lines "nu /usr/local/bin/reva-override.nu")
  if ($reva_block | str length) == 0 {
    error make {
      msg: $"opencloud Dockerfile missing RUN block for reva-override.nu in ($dockerfile_path)"
    }
  }
  let reva_mount_needles = [
    "target=/mnt/reva"
    "id=opencloud-reva-git-"
    "target=/src/opencloud-reva-git-cache"
  ]
  for needle in $reva_mount_needles {
    if not ($reva_block | str contains $needle) {
      error make {
        msg: $"opencloud reva-override RUN block missing mount fragment '($needle)' in ($dockerfile_path)"
      }
    }
  }
}

export def assert-dockerfile-clone-source-ref-kind-contract [
  dockerfile_path: string
  --expected-invocations (-e): int = 2
  --ref-kind-patterns (-p): list<string> = []
  --invoke-prefix: string = "nu /tmp/clone-source.nu"
] {
  if not ($dockerfile_path | path exists) {
    error make {msg: $"Dockerfile not found: ($dockerfile_path)"}
  }
  let lines = (open --raw $dockerfile_path | lines)
  let invoke_indices = (
    $lines
    | enumerate
    | where {|e| ($e.item | str trim) | str starts-with $invoke_prefix }
    | get index
  )
  if ($invoke_indices | length) != $expected_invocations {
    error make {
      msg: $"Expected ($expected_invocations) clone-source.nu invocations in ($dockerfile_path), found ($invoke_indices | length)"
    }
  }
  if ($ref_kind_patterns | length) > 0 and ($ref_kind_patterns | length) != $expected_invocations {
    error make {
      msg: $"ref-kind-patterns length (($ref_kind_patterns | length)) must match expected-invocations ($expected_invocations)"
    }
  }
  for pair in ($invoke_indices | enumerate) {
    let idx = $pair.item
    let block = (dockerfile-collect-continuation-block $lines $idx)
    if not ($block | str contains "--ref-kind") {
      error make {msg: $"clone-source.nu invocation at line ($idx + 1) missing --ref-kind in ($dockerfile_path)"}
    }
    if ($ref_kind_patterns | length) > 0 {
      let pattern = ($ref_kind_patterns | get $pair.index)
      if not ($block | str contains $pattern) {
        error make {
          msg: $"clone-source.nu invocation ($pair.index + 1) missing explicit ref-kind pattern '($pattern)' in ($dockerfile_path)"
        }
      }
    }
  }
}

export def assert-opencloud-override-uses-clone-source [
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
  if not (opencloud-override-binds-ref-kind-from-env $content $ref_kind_env) {
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
  if not (opencloud-override-clone-line-has-contract $clone_line) {
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
  if not (opencloud-override-has-guarded-sha-checkout $content) {
    error make {
      msg: $"($script_path) must guard SHA checkout behind git mode and non-empty SHA"
    }
  }
  if not (opencloud-override-has-fetch-capable-checkout-sha-helper $content) {
    error make {
      msg: $"($script_path) checkout-sha helper must retry via 'git fetch --depth 1 origin \$sha' and raise a clear error if the retried checkout still fails"
    }
  }
}

export def assert-dockerfile-ocis-sha-checkout-guard [block: string, dockerfile_path: string] {
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

export def assert-ocis-dockerfile-clone-source-contract [dockerfile_path: string] {
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

export def assert-ocis-dockerfile-override-wiring [dockerfile_path: string] {
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

export def assert-dockerfile-nextcloud-local-mode-cleanup [dockerfile_path: string] {
  if not ($dockerfile_path | path exists) {
    error make {msg: $"Dockerfile not found: ($dockerfile_path)"}
  }
  let lines = (open --raw $dockerfile_path | lines)
  let invoke_indices = (
    $lines
    | enumerate
    | where {|e| ($e.item | str trim) | str starts-with "nu /tmp/clone-source.nu" }
    | get index
  )
  if ($invoke_indices | length) != 1 {
    error make {
      msg: $"Expected exactly 1 clone-source.nu invocation in ($dockerfile_path), found ($invoke_indices | length)"
    }
  }
  let idx = ($invoke_indices | first)
  mut block_lines = []
  mut i = $idx
  let line_count = ($lines | length)
  loop {
    if $i >= $line_count {
      error make {
        msg: $"nextcloud local-mode cleanup block missing 'fi' terminator after clone-source.nu at line ($idx + 1) in ($dockerfile_path)"
      }
    }
    let line = ($lines | get $i)
    $block_lines = ($block_lines | append $line)
    let trimmed = ($line | str trim)
    if ($trimmed == "fi") or ($trimmed | str ends-with "; fi") {
      break
    }
    $i = $i + 1
  }
  let local_guard = 'if [ "$NEXTCLOUD_MODE" = "local" ]'
  let config_rm = "rm -f /nextcloud-source/config/config.php"
  let data_rm = "rm -rf /nextcloud-source/data /nextcloud-source/data-autotest"
  let active_trimmed = (
    $block_lines
    | each {|line| $line | str trim }
    | where {|t| ($t | str length) > 0 and not ($t | str starts-with "#") }
  )
  for pattern in [$local_guard $config_rm $data_rm] {
    if ($active_trimmed | where {|t| $t | str contains $pattern } | length) == 0 {
      error make {
        msg: $"nextcloud local-mode cleanup block missing active line containing '($pattern)' in ($dockerfile_path)"
      }
    }
  }
  let if_line_idx = (
    $block_lines
    | enumerate
    | where {|e|
        let t = ($e.item | str trim)
        ($t | str length) > 0 and not ($t | str starts-with "#") and ($t | str contains $local_guard)
      }
    | first
    | get index
  )
  let config_line_idx = (
    $block_lines
    | enumerate
    | where {|e|
        let t = ($e.item | str trim)
        ($t | str length) > 0 and not ($t | str starts-with "#") and ($t | str contains $config_rm)
      }
    | first
    | get index
  )
  let data_line_idx = (
    $block_lines
    | enumerate
    | where {|e|
        let t = ($e.item | str trim)
        ($t | str length) > 0 and not ($t | str starts-with "#") and ($t | str contains $data_rm)
      }
    | first
    | get index
  )
  if $if_line_idx >= $config_line_idx or $if_line_idx >= $data_line_idx {
    error make {
      msg: $"nextcloud local-mode cleanup must follow NEXTCLOUD_MODE=local guard in ($dockerfile_path)"
    }
  }
}

export def clone-source-ref-kind-tests [verbose: bool] {
    mut results = []
    let test39d = (run-test "Test 39d: classify-source-ref-kind maps full SHA to sha" {
  let source = {url: "https://example.com/repo.git", ref: "a1b2c3d4e5f6789012345678901234567890abcd"}
  let kind = (classify-source-ref-kind $source "git")
  if $kind != "sha" {
    error make {msg: $"Expected ref-kind 'sha' for 40-hex ref, got: ($kind)"}
  }
  true
} $verbose)
$results = ($results | append $test39d)
let test39e = (run-test "Test 39e: classify-source-ref-kind maps branch/tag to ref" {
  let source = {url: "https://example.com/repo.git", ref: "main"}
  let kind = (classify-source-ref-kind $source "git")
  if $kind != "ref" {
    error make {msg: $"Expected ref-kind 'ref' for branch name, got: ($kind)"}
  }
  true
} $verbose)
$results = ($results | append $test39e)
let test39f = (run-test "Test 39f: classify-source-ref-kind maps local path source to local" {
  let source = {path: "/tmp/local-src"}
  let kind = (classify-source-ref-kind $source "local")
  if $kind != "local" {
    error make {msg: $"Expected ref-kind 'local' for path source, got: ($kind)"}
  }
  true
} $verbose)
$results = ($results | append $test39f)
let test39g = (run-test "Test 39g: extract-source-ref-kinds emits per-source REF_KIND keys" {
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
$results = ($results | append $test39g)
let test39h = (run-test "Test 39h: process-sources-to-build-args emits REF_KIND for git and local" {
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
$results = ($results | append $test39h)
let test39i = (run-test "Test 39i: generate-build-args includes TEST_SOURCE_REF_KIND" {
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
$results = ($results | append $test39i)
let test39j = (run-test "Test 39j: Real manifest - cernbox-revad v3.10.1 production mixed REF_KIND build args" {
  let svc = "cernbox-revad"
  let version = "v3.10.1"
  let platform = "production"
  let vm = (load-versions-manifest $svc)
  let pm = (load-platforms-manifest $svc)
  let vspec = (get-version-or-null $vm $version)
  let cfg = (load-service-config $svc $vspec $platform $pm)
  let revad_ref = (try { $cfg.sources.revad.ref } catch { "" })
  if $revad_ref != "v3.10.1" {
    error make {msg: $"Expected revad ref 'v3.10.1' from tracked manifest, got: ($revad_ref)"}
  }
  let plugins_ref = (try { $cfg.sources.revad_plugins.ref } catch { "" })
  if $plugins_ref != "39c4d38a5761629473fe553524f4c2bbb27c0b1b" {
    error make {msg: $"Expected revad_plugins pinned SHA from tracked manifest, got: ($plugins_ref)"}
  }
  let source_types = (detect-all-source-types $cfg.sources)
  let source_ref_kinds = (extract-source-ref-kinds $cfg.sources $source_types)
  let meta = (detect-build)
  let tls_meta = (create-test-tls-meta)
  let ssh_meta = {
    enabled: false,
    mode: "disabled",
    default_user: "root",
    port: 22,
    listen: "0.0.0.0"
  }
  let build_args = (
    generate-build-args $version $cfg $meta {} $tls_meta $ssh_meta "" false {} $source_types {} "tracked" $source_ref_kinds
  )
  if (try { $build_args.REVAD_REF_KIND } catch { "" }) != "ref" {
    error make {msg: $"Expected REVAD_REF_KIND=ref for tag v3.10.1, got: ($build_args.REVAD_REF_KIND?)"}
  }
  if (try { $build_args.REVAD_PLUGINS_REF_KIND } catch { "" }) != "sha" {
    error make {msg: $"Expected REVAD_PLUGINS_REF_KIND=sha for pinned commit, got: ($build_args.REVAD_PLUGINS_REF_KIND?)"}
  }
  if $verbose {
    print $"    REVAD_REF_KIND=($build_args.REVAD_REF_KIND), REVAD_PLUGINS_REF_KIND=($build_args.REVAD_PLUGINS_REF_KIND)"
  }
  true
} $verbose)
$results = ($results | append $test39j)
let test39k = (run-test "Test 39k: env REVAD_REF override recomputes REVAD_REF_KIND to sha" {
  let svc = "cernbox-revad"
  let version = "v3.10.1"
  let platform = "production"
  let vm = (load-versions-manifest $svc)
  let pm = (load-platforms-manifest $svc)
  let vspec = (get-version-or-null $vm $version)
  let cfg = (load-service-config $svc $vspec $platform $pm)
  let sha_ref = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let source_types = (detect-all-source-types $cfg.sources)
  let source_ref_kinds = (extract-source-ref-kinds $cfg.sources $source_types)
  let meta = (detect-build)
  let tls_meta = (create-test-tls-meta)
  let ssh_meta = {
    enabled: false,
    mode: "disabled",
    default_user: "root",
    port: 22,
    listen: "0.0.0.0"
  }
  let old_revad_ref = (try { $env.REVAD_REF } catch { "" })
  let old_revad_ref_kind = (try { $env.REVAD_REF_KIND } catch { "" })
  $env.REVAD_REF = $sha_ref
  try { hide-env REVAD_REF_KIND } catch { }
  try {
    let build_args = (
      generate-build-args $version $cfg $meta {} $tls_meta $ssh_meta "" false {} $source_types {} "tracked" $source_ref_kinds
    )
    if (try { $build_args.REVAD_REF } catch { "" }) != $sha_ref {
      error make {msg: $"Expected REVAD_REF from env override, got: ($build_args.REVAD_REF?)"}
    }
    if (try { $build_args.REVAD_REF_KIND } catch { "" }) != "sha" {
      error make {msg: $"Expected REVAD_REF_KIND=sha after env SHA override, got: ($build_args.REVAD_REF_KIND?)"}
    }
    if (try { $build_args.REVAD_PLUGINS_REF_KIND } catch { "" }) != "sha" {
      error make {msg: $"Expected REVAD_PLUGINS_REF_KIND unchanged at sha, got: ($build_args.REVAD_PLUGINS_REF_KIND?)"}
    }
    if $verbose {
      print $"    REVAD_REF=($build_args.REVAD_REF), REVAD_REF_KIND=($build_args.REVAD_REF_KIND)"
    }
    true
  } catch {|err|
    if ($old_revad_ref | str length) > 0 {
      $env.REVAD_REF = $old_revad_ref
    } else {
      try { hide-env REVAD_REF } catch { }
    }
    if ($old_revad_ref_kind | str length) > 0 {
      $env.REVAD_REF_KIND = $old_revad_ref_kind
    } else {
      try { hide-env REVAD_REF_KIND } catch { }
    }
    error make {msg: $err.msg}
  }
  if ($old_revad_ref | str length) > 0 {
    $env.REVAD_REF = $old_revad_ref
  } else {
    try { hide-env REVAD_REF } catch { }
  }
  if ($old_revad_ref_kind | str length) > 0 {
    $env.REVAD_REF_KIND = $old_revad_ref_kind
  } else {
    try { hide-env REVAD_REF_KIND } catch { }
  }
  true
} $verbose)
$results = ($results | append $test39k)
let test39l = (run-test "Test 39l: Dockerfile drift - cernbox-revad passes --ref-kind on clone-source.nu calls" {
  let dockerfiles = [
    "services/cernbox-revad/Dockerfile.production"
    "services/cernbox-revad/Dockerfile.development"
  ]
  let ref_kind_patterns = [
    (clone-source-ref-kind-env-pattern "REVAD_REF_KIND")
    (clone-source-ref-kind-env-pattern "REVAD_PLUGINS_REF_KIND")
  ]
  for df in $dockerfiles {
    assert-dockerfile-clone-source-ref-kind-contract $df --expected-invocations 2 --ref-kind-patterns $ref_kind_patterns
  }
  true
} $verbose)
$results = ($results | append $test39l)
let test39n = (run-test "Test 39n: Dockerfile drift - revad-base passes --ref-kind on clone-source.nu calls" {
  let dockerfiles = [
    "services/revad-base/Dockerfile.production"
    "services/revad-base/Dockerfile.development"
  ]
  let ref_kind_patterns = [(clone-source-ref-kind-env-pattern "REVAD_REF_KIND")]
  for df in $dockerfiles {
    assert-dockerfile-clone-source-ref-kind-contract $df --expected-invocations 1 --ref-kind-patterns $ref_kind_patterns
  }
  true
} $verbose)
$results = ($results | append $test39n)
let test39o = (run-test "Test 39o: Dockerfile drift - gaia passes --ref-kind on clone-source.nu calls" {
  let dockerfiles = [
    "services/gaia/Dockerfile"
  ]
  let ref_kind_patterns = [(clone-source-ref-kind-env-pattern "GAIA_REF_KIND")]
  for df in $dockerfiles {
    assert-dockerfile-clone-source-ref-kind-contract $df --expected-invocations 1 --ref-kind-patterns $ref_kind_patterns
  }
  true
} $verbose)
$results = ($results | append $test39o)
let test39p = (run-test "Test 39p: Dockerfile drift - nextcloud passes --ref-kind on clone-source.nu calls" {
  let dockerfiles = [
    "services/nextcloud/Dockerfile"
  ]
  let ref_kind_patterns = [(clone-source-ref-kind-env-pattern "NEXTCLOUD_REF_KIND")]
  for df in $dockerfiles {
    assert-dockerfile-clone-source-ref-kind-contract $df --expected-invocations 1 --ref-kind-patterns $ref_kind_patterns
  }
  true
} $verbose)
$results = ($results | append $test39p)
let test39r = (run-test "Test 39r: Dockerfile drift - nextcloud-contacts passes --ref-kind on clone-source.nu calls" {
  let dockerfiles = [
    "services/nextcloud-contacts/Dockerfile"
  ]
  let ref_kind_patterns = [(clone-source-ref-kind-env-pattern "CONTACTS_REF_KIND")]
  for df in $dockerfiles {
    assert-dockerfile-clone-source-ref-kind-contract $df --expected-invocations 1 --ref-kind-patterns $ref_kind_patterns
  }
  true
} $verbose)
$results = ($results | append $test39r)
let test39s = (run-test "Test 39s: Dockerfile drift - opencloudmesh-go passes --ref-kind on clone-source.nu calls" {
  let dockerfiles = [
    "services/opencloudmesh-go/Dockerfile.development"
  ]
  let ref_kind_patterns = [(clone-source-ref-kind-env-pattern "OCM_GO_REF_KIND")]
  for df in $dockerfiles {
    assert-dockerfile-clone-source-ref-kind-contract $df --expected-invocations 1 --ref-kind-patterns $ref_kind_patterns
  }
  true
} $verbose)
$results = ($results | append $test39s)
let test39t = (run-test "Test 39t: Dockerfile drift - cernbox-web passes --ref-kind on clone-source.nu calls" {
  let dockerfiles = [
    "services/cernbox-web/Dockerfile"
  ]
  let ref_kind_patterns = [
    (clone-source-ref-kind-env-pattern "WEB_REF_KIND")
    (clone-source-ref-kind-env-pattern "WEB_EXTENSIONS_REF_KIND")
  ]
  for df in $dockerfiles {
    assert-dockerfile-clone-source-ref-kind-contract $df --expected-invocations 2 --ref-kind-patterns $ref_kind_patterns
  }
  true
} $verbose)
$results = ($results | append $test39t)
let test39v = (run-test "Test 39v: Dockerfile drift - opencloud clone-source contract and SHA checkout guard" {
  assert-opencloud-dockerfile-clone-source-contract "services/opencloud/Dockerfile.alpine"
  true
} $verbose)
$results = ($results | append $test39v)
let test39w = (run-test "Test 39w: opencloud override scripts use clone-source.nu contract" {
  assert-opencloud-override-uses-clone-source "services/opencloud/scripts/build/web-override.nu" "/mnt/web" "OPENCLOUD_WEB_REF_KIND"
  assert-opencloud-override-uses-clone-source "services/opencloud/scripts/build/reva-override.nu" "/mnt/reva" "OPENCLOUD_REVA_REF_KIND"
  true
} $verbose)
$results = ($results | append $test39w)
let test39y = (run-test "Test 39y: Dockerfile drift - opencloud web/reva override script COPY and RUN wiring" {
  assert-opencloud-dockerfile-override-wiring "services/opencloud/Dockerfile.alpine"
  true
} $verbose)
$results = ($results | append $test39y)
let test39x = (run-test "Test 39x: Real manifest - opencloud v6.1.0 and main alpine OPENCLOUD_REF_KIND build args" {
  let svc = "opencloud"
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
  let version_tag = "v6.1.0"
  let vspec_tag = (get-version-or-null $vm $version_tag)
  let cfg_tag = (load-service-config $svc $vspec_tag $platform $pm)
  let opencloud_ref_tag = (try { $cfg_tag.sources.opencloud.ref } catch { "" })
  if $opencloud_ref_tag != "v6.1.0" {
    error make {msg: $"Expected opencloud ref 'v6.1.0' from tracked manifest, got: ($opencloud_ref_tag)"}
  }
  let source_types_tag = (detect-all-source-types $cfg_tag.sources)
  let source_ref_kinds_tag = (extract-source-ref-kinds $cfg_tag.sources $source_types_tag)
  let build_args_tag = (
    generate-build-args $version_tag $cfg_tag $meta {} $tls_meta $ssh_meta "" false {} $source_types_tag {} "tracked" $source_ref_kinds_tag
  )
  if (try { $build_args_tag.OPENCLOUD_REF_KIND } catch { "" }) != "ref" {
    error make {msg: $"Expected OPENCLOUD_REF_KIND=ref for tag v6.1.0, got: ($build_args_tag.OPENCLOUD_REF_KIND?)"}
  }
  let version_main = "main"
  let vspec_main = (get-version-or-null $vm $version_main)
  let cfg_main = (load-service-config $svc $vspec_main $platform $pm)
  let opencloud_ref_main = (try { $cfg_main.sources.opencloud.ref } catch { "" })
  if $opencloud_ref_main != "main" {
    error make {msg: $"Expected opencloud ref 'main' from tracked manifest, got: ($opencloud_ref_main)"}
  }
  let source_types_main = (detect-all-source-types $cfg_main.sources)
  let source_ref_kinds_main = (extract-source-ref-kinds $cfg_main.sources $source_types_main)
  let build_args_main = (
    generate-build-args $version_main $cfg_main $meta {} $tls_meta $ssh_meta "" false {} $source_types_main {} "tracked" $source_ref_kinds_main
  )
  if (try { $build_args_main.OPENCLOUD_REF_KIND } catch { "" }) != "ref" {
    error make {msg: $"Expected OPENCLOUD_REF_KIND=ref for branch main, got: ($build_args_main.OPENCLOUD_REF_KIND?)"}
  }
  if $verbose {
    print $"    v6.1.0 OPENCLOUD_REF_KIND=($build_args_tag.OPENCLOUD_REF_KIND)"
    print $"    main OPENCLOUD_REF_KIND=($build_args_main.OPENCLOUD_REF_KIND)"
  }
  true
} $verbose)
$results = ($results | append $test39x)
let test39z = (run-test "Test 39z: Dockerfile drift - ocis clone-source contract and SHA checkout guard" {
  assert-ocis-dockerfile-clone-source-contract "services/ocis/Dockerfile.alpine"
  true
} $verbose)
$results = ($results | append $test39z)
let test39za = (run-test "Test 39za: ocis override scripts use clone-source.nu contract" {
  assert-opencloud-override-uses-clone-source "services/ocis/scripts/build/web-override.nu" "/mnt/web" "OCIS_WEB_REF_KIND"
  assert-opencloud-override-uses-clone-source "services/ocis/scripts/build/reva-override.nu" "/mnt/reva" "OCIS_REVA_REF_KIND"
  true
} $verbose)
$results = ($results | append $test39za)
let test39zb = (run-test "Test 39zb: Dockerfile drift - ocis web/reva override script COPY and RUN wiring" {
  assert-ocis-dockerfile-override-wiring "services/ocis/Dockerfile.alpine"
  true
} $verbose)
$results = ($results | append $test39zb)
let test39zc = (run-test "Test 39zc: Real manifest - ocis v8.0.1 and master alpine OCIS_REF_KIND build args" {
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
$results = ($results | append $test39zc)
let test39u = (run-test "Test 39u: Real manifest - cernbox-web master mixed REF_KIND build args" {
  let svc = "cernbox-web"
  let version = "master"
  let vm = (load-versions-manifest $svc)
  let vspec = (get-version-or-null $vm $version)
  let cfg = (load-service-config $svc $vspec "" null)
  let web_ref = (try { $cfg.sources.web.ref } catch { "" })
  if $web_ref != "cernbox" {
    error make {msg: $"Expected web ref 'cernbox' from tracked manifest, got: ($web_ref)"}
  }
  let web_extensions_ref = (try { $cfg.sources.web_extensions.ref } catch { "" })
  if $web_extensions_ref != "dffaad6cecf755782c7ce4289f21b4f155c35e7c" {
    error make {msg: $"Expected web_extensions pinned SHA from tracked manifest, got: ($web_extensions_ref)"}
  }
  let source_types = (detect-all-source-types $cfg.sources)
  let source_ref_kinds = (extract-source-ref-kinds $cfg.sources $source_types)
  let meta = (detect-build)
  let tls_meta = (create-test-tls-meta)
  let ssh_meta = {
    enabled: false,
    mode: "disabled",
    default_user: "root",
    port: 22,
    listen: "0.0.0.0"
  }
  let build_args = (
    generate-build-args $version $cfg $meta {} $tls_meta $ssh_meta "" false {} $source_types {} "tracked" $source_ref_kinds
  )
  if (try { $build_args.WEB_REF_KIND } catch { "" }) != "ref" {
    error make {msg: $"Expected WEB_REF_KIND=ref for branch cernbox, got: ($build_args.WEB_REF_KIND?)"}
  }
  if (try { $build_args.WEB_EXTENSIONS_REF_KIND } catch { "" }) != "sha" {
    error make {msg: $"Expected WEB_EXTENSIONS_REF_KIND=sha for pinned commit, got: ($build_args.WEB_EXTENSIONS_REF_KIND?)"}
  }
  if $verbose {
    print $"    WEB_REF_KIND=($build_args.WEB_REF_KIND), WEB_EXTENSIONS_REF_KIND=($build_args.WEB_EXTENSIONS_REF_KIND)"
  }
  true
} $verbose)
$results = ($results | append $test39u)
let test39q = (run-test "Test 39q: Dockerfile drift - nextcloud local-mode cleanup removes config and data paths" {
  assert-dockerfile-nextcloud-local-mode-cleanup "services/nextcloud/Dockerfile"
  true
} $verbose)
$results = ($results | append $test39q)
let test39m = (run-test "Test 39m: env REVAD_REF_KIND=ref with SHA REVAD_REF recomputes to sha" {
  let svc = "cernbox-revad"
  let version = "v3.10.1"
  let platform = "production"
  let vm = (load-versions-manifest $svc)
  let pm = (load-platforms-manifest $svc)
  let vspec = (get-version-or-null $vm $version)
  let cfg = (load-service-config $svc $vspec $platform $pm)
  let sha_ref = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let source_types = (detect-all-source-types $cfg.sources)
  let source_ref_kinds = (extract-source-ref-kinds $cfg.sources $source_types)
  let meta = (detect-build)
  let tls_meta = (create-test-tls-meta)
  let ssh_meta = {
    enabled: false,
    mode: "disabled",
    default_user: "root",
    port: 22,
    listen: "0.0.0.0"
  }
  let old_revad_ref = (try { $env.REVAD_REF } catch { "" })
  let old_revad_ref_kind = (try { $env.REVAD_REF_KIND } catch { "" })
  $env.REVAD_REF = $sha_ref
  $env.REVAD_REF_KIND = "ref"
  try {
    let build_args = (
      generate-build-args $version $cfg $meta {} $tls_meta $ssh_meta "" false {} $source_types {} "tracked" $source_ref_kinds
    )
    if (try { $build_args.REVAD_REF } catch { "" }) != $sha_ref {
      error make {msg: $"Expected REVAD_REF from env SHA override, got: ($build_args.REVAD_REF?)"}
    }
    if (try { $build_args.REVAD_REF_KIND } catch { "" }) != "sha" {
      error make {msg: $"Expected REVAD_REF_KIND=sha after stale ref env conflict, got: ($build_args.REVAD_REF_KIND?)"}
    }
    if $verbose {
      print $"    REVAD_REF=($build_args.REVAD_REF), REVAD_REF_KIND=($build_args.REVAD_REF_KIND)"
    }
    true
  } catch {|err|
    if ($old_revad_ref | str length) > 0 {
      $env.REVAD_REF = $old_revad_ref
    } else {
      try { hide-env REVAD_REF } catch { }
    }
    if ($old_revad_ref_kind | str length) > 0 {
      $env.REVAD_REF_KIND = $old_revad_ref_kind
    } else {
      try { hide-env REVAD_REF_KIND } catch { }
    }
    error make {msg: $err.msg}
  }
  if ($old_revad_ref | str length) > 0 {
    $env.REVAD_REF = $old_revad_ref
  } else {
    try { hide-env REVAD_REF } catch { }
  }
  if ($old_revad_ref_kind | str length) > 0 {
    $env.REVAD_REF_KIND = $old_revad_ref_kind
  } else {
    try { hide-env REVAD_REF_KIND } catch { }
  }
  true
} $verbose)
$results = ($results | append $test39m)
    $results
}
