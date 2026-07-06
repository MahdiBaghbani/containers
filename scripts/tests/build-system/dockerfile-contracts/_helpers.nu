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

# Shared Dockerfile parsing and generic clone-source contract assertions.

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
