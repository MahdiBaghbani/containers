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

# Source clone compatibility validation

use ../core/repo.nu [get-repo-root]

def source-ref-is-full-sha [source: record] {
  if "path" in ($source | columns) {
    return false
  }
  let ref = (try { $source.ref } catch { "" } | str trim)
  ($ref | str replace --regex '^[0-9a-fA-F]{40}$' "MATCHED") == "MATCHED"
}

# Uppercase build-arg prefix for a manifest source key (foo_bar -> FOO_BAR).
def source-build-arg-prefix [source_key: string] {
  $source_key | str upcase
}

# Read Dockerfile text and nearby service build override scripts for clone-surface checks.
def read-clone-build-surface-text [
  merged: record,
  service: string,
  repo_root: string
] {
  mut parts = []

  let dockerfile = (try { $merged.dockerfile } catch { "" })
  if ($dockerfile | str length) > 0 {
    let df_path = ($repo_root | path join $dockerfile)
    if ($df_path | path exists) {
      $parts = ($parts | append (open -r $df_path))
    }
  }

  let service_ctx = (try { $merged.context } catch { $"services/($service)" })
  let scripts_dir = ($repo_root | path join $service_ctx "scripts" "build")
  if ($scripts_dir | path exists) {
    for script_path in (try { glob $"($scripts_dir)/*.nu" } catch { [] }) {
      $parts = ($parts | append (open -r $script_path))
    }
  }

  $parts | str join "\n"
}

# Non-comment, non-empty trimmed lines from a build surface text blob.
def surface-active-trimmed-lines [surface_text: string] {
  $surface_text
  | lines
  | each {|line| $line | str trim}
  | where {|line| ($line | str length) > 0 and not ($line | str starts-with "#")}
}

# Strip trailing shell inline comments (Docker RUN/CMD lines); full-line comments become empty.
def surface-strip-inline-shell-comment [line: string] {
  let trimmed = ($line | str trim)
  if ($trimmed | is-empty) or ($trimmed | str starts-with "#") {
    return ""
  }
  if not ($trimmed | str contains " #") {
    return $trimmed
  }
  let idx = ($trimmed | str index-of " #")
  $trimmed | str substring 0..$idx | str trim
}

# Active build lines with inline shell comments removed.
def surface-code-trimmed-lines [surface_text: string] {
  surface-active-trimmed-lines $surface_text
  | each {|line| surface-strip-inline-shell-comment $line}
  | where {|line| ($line | str length) > 0}
}

# Merge Dockerfile backslash continuations into logical blocks (comments skipped).
def surface-logical-blocks [surface_text: string] {
  let raw_lines = ($surface_text | lines)
  mut blocks = []
  mut i = 0
  while $i < ($raw_lines | length) {
    let stripped = ($raw_lines | get $i | str trim)
    if ($stripped | is-empty) or ($stripped | str starts-with "#") {
      $i = $i + 1
      continue
    }
    mut block_lines = [($raw_lines | get $i)]
    mut j = $i
    while ($block_lines | last | str trim | str ends-with "\\") {
      $j = $j + 1
      if $j >= ($raw_lines | length) {
        break
      }
      $block_lines = ($block_lines | append ($raw_lines | get $j))
    }
    $blocks = ($blocks | append ($block_lines | str join " "))
    $i = $j + 1
  }
  $blocks
}

# PREFIX_REF without matching PREFIX_REF_KIND (substring false positive).
def surface-text-mentions-exact-ref-arg [text: string, prefix: string] {
  let token = $"($prefix)_REF"
  let pattern = ($token + "(?!_KIND)")
  (($text | str replace --regex $pattern "FOUND") | str contains "FOUND")
}

def surface-text-mentions-ref-kind-arg [text: string, prefix: string] {
  $text | str contains $"($prefix)_REF_KIND"
}

# True when text passes a clone-source.nu --ref flag (not --ref-kind).
def surface-text-contains-ref-flag [text: string] {
  (($text | str replace --regex '--ref(?!-kind)' "FOUND") | str contains "FOUND")
}

# Variable name from a simple `let name = ...` binding line.
def surface-let-binding-var-name [line: string] {
  try {
    ($line | parse --regex 'let (?<name>[A-Za-z_][A-Za-z0-9_]*)' | get name.0)
  } catch {
    ""
  }
}

# Active (non-comment) build lines that mention PREFIX_REF exactly.
def surface-active-mentions-exact-ref-arg [surface_text: string, prefix: string] {
  surface-active-trimmed-lines $surface_text
  | any {|line| surface-text-mentions-exact-ref-arg $line $prefix}
}

# Active (non-comment) build lines that mention PREFIX_REF_KIND.
def surface-active-mentions-ref-kind-arg [surface_text: string, prefix: string] {
  surface-active-trimmed-lines $surface_text
  | any {|line| surface-text-mentions-ref-kind-arg $line $prefix}
}

# Logical blocks with inline shell comments stripped from each block.
def surface-code-logical-blocks [surface_text: string] {
  surface-logical-blocks $surface_text
  | each {|block| surface-strip-inline-shell-comment $block}
  | where {|block| ($block | str length) > 0}
}

# Legacy git clone --branch wiring cannot checkout a full commit SHA.
def build-surface-has-legacy-branch-clone [
  surface_text: string,
  prefix: string
] {
  surface-logical-blocks $surface_text
  | any {|block|
    (($block | str contains "git clone")
      and ($block | str contains "--branch")
      and (surface-text-mentions-exact-ref-arg $block $prefix))
  }
}

# Split a logical block into per-command clone-source.nu invocation segments.
def surface-clone-invocation-segments [block: string] {
  if not ($block | str contains "clone-source.nu") {
    return []
  }
  $block
  | str replace -a " && " "\n"
  | str replace -a " ; " "\n"
  | lines
  | each {|seg| $seg | str trim}
  | where {|seg|
      (
        ($seg | str length) > 0
        and ($seg | str contains "clone-source.nu")
        and (surface-text-contains-ref-flag $seg)
        and ($seg | str contains "--ref-kind")
      )
    }
}

# True when a clone-source.nu invocation passes PREFIX_REF and PREFIX_REF_KIND.
def build-surface-clone-block-wires-ref-kind [block: string, prefix: string] {
  surface-clone-invocation-segments $block
  | any {|segment|
      (
        (surface-text-mentions-exact-ref-arg $segment $prefix)
        and (surface-text-mentions-ref-kind-arg $segment $prefix)
      )
    }
}

# True when an override script binds PREFIX_REF and PREFIX_REF_KIND before clone-source.nu.
def build-surface-script-clone-wires-ref-kind [
  surface_text: string,
  prefix: string
] {
  let ref_env = $"($prefix)_REF"
  let ref_kind_env = $"($prefix)_REF_KIND"
  let ref_env_pattern = ($"\\$env\\.($ref_env)" + "(?!_KIND)")
  let indexed = (
    $surface_text
    | lines
    | enumerate
    | each {|e| {index: $e.index, text: ($e.item | str trim)}}
    | where {|e| ($e.text | str length) > 0 and not ($e.text | str starts-with "#")}
  )
  let ref_binding = (
    $indexed
    | where {|e|
        (
          ($e.text | str starts-with "let ")
          and (($e.text | str replace --regex $ref_env_pattern "FOUND") | str contains "FOUND")
        )
      }
    | first
  )
  let ref_kind_binding = (
    $indexed
    | where {|e|
        (
          ($e.text | str starts-with "let ")
          and ($e.text | str contains $"$env.($ref_kind_env)")
        )
      }
    | first
  )
  if $ref_binding == null or $ref_kind_binding == null {
    return false
  }
  let ref_idx = ($ref_binding | get index)
  let ref_kind_idx = ($ref_kind_binding | get index)
  let clone_entries = (
    $indexed
    | where {|e|
        (
          ($e.text | str contains "clone-source.nu")
          and ($e.index) > $ref_idx
          and ($e.index) > $ref_kind_idx
        )
      }
  )
  if ($clone_entries | is-empty) {
    return false
  }
  let ref_var = (surface-let-binding-var-name ($ref_binding | get text))
  let ref_kind_var = (surface-let-binding-var-name ($ref_kind_binding | get text))
  $clone_entries
  | any {|entry|
      let segments = (surface-clone-invocation-segments ($entry | get text))
      $segments
      | any {|segment|
          let uses_ref = (
            (surface-text-mentions-exact-ref-arg $segment $prefix)
            or (
              ($ref_var | str length) > 0
              and (surface-text-contains-ref-flag $segment)
              and ($segment | str contains $"$($ref_var)")
            )
          )
          let uses_ref_kind = (
            (surface-text-mentions-ref-kind-arg $segment $prefix)
            or (
              ($ref_kind_var | str length) > 0
              and ($segment | str contains "--ref-kind")
              and ($segment | str contains $"$($ref_kind_var)")
            )
          )
          $uses_ref and $uses_ref_kind
        }
    }
}

# Shared clone-source.nu helper with per-source REF_KIND build arg.
def build-surface-has-clone-helper-compat [
  surface_text: string,
  prefix: string
] {
  let blocks = (surface-logical-blocks $surface_text)
  if ($blocks | any {|block| build-surface-clone-block-wires-ref-kind $block $prefix}) {
    return true
  }
  build-surface-script-clone-wires-ref-kind $surface_text $prefix
}

# True when one logical block wires fetch and SHA checkout for this source.
def build-surface-block-has-inline-sha-wiring [block: string, prefix: string] {
  let sha_token = $"($prefix)_SHA"
  if not ($block | str contains $sha_token) {
    return false
  }
  let has_fetch = (
    ($block | str contains "git fetch")
    or ($block | str contains "fetch --depth")
    or ($block | str contains "FETCH_HEAD")
  )
  let has_checkout = (
    ($block | str contains "checkout") and ($block | str contains $sha_token)
  )
  $has_fetch and $has_checkout
}

# Inline Dockerfile or override SHA fetch/checkout path for one source.
def build-surface-has-inline-sha-compat [
  surface_text: string,
  prefix: string
] {
  let inline_ok = (
    surface-code-logical-blocks $surface_text
    | any {|block| build-surface-block-has-inline-sha-wiring $block $prefix}
  )
  if $inline_ok {
    return true
  }
  build-surface-script-inline-sha-wiring $surface_text $prefix
}

# True when an override script guards and runs SHA checkout for this source.
def build-surface-script-inline-sha-wiring [
  surface_text: string,
  prefix: string
] {
  let sha_env = $"($prefix)_SHA"
  let active = (surface-active-trimmed-lines $surface_text)
  let binds_sha = (
    $active
    | any {|line|
        (($line | str contains $"$env.($sha_env)") or ($line | str contains $sha_env))
      }
  )
  if not $binds_sha {
    return false
  }
  let checkout_def = (
    $active
    | enumerate
    | where {|e| $e.item | str starts-with "def checkout-sha"}
    | first
  )
  if $checkout_def == null {
    return false
  }
  let helper_body = (
    $active
    | skip ($checkout_def.index + 1)
    | take 25
  )
  let fetch_retry = (
    $helper_body
    | any {|line|
        ($line | str contains "fetch --depth") and ($line | str contains "$sha")
      }
  )
  let guarded_call = (
    $active
    | any {|line|
        (($line | str contains "checkout-sha")
          and ($line | str contains "sha")
          and (not ($line | str starts-with "def ")))
      }
  )
  $fetch_retry and $guarded_call
}

# Validate merged git sources pinned to full SHAs against Dockerfile/override clone wiring.
export def validate-source-clone-compat [
  merged: record,
  service: string,
  context: string
] {
  mut errors = []

  if not ("sources" in ($merged | columns)) {
    return {valid: true, errors: []}
  }

  let repo_root = (get-repo-root)
  let surface_text = (read-clone-build-surface-text $merged $service $repo_root)
  let dockerfile = (try { $merged.dockerfile } catch { "" })

  for source_key in ($merged.sources | columns) {
    let source = ($merged.sources | get $source_key)
    if not (source-ref-is-full-sha $source) {
      continue
    }

    let prefix = (source-build-arg-prefix $source_key)
    let ref = ($source.ref | str trim)

    # Only enforce when active build lines reference this source's REF arg.
    if not (surface-active-mentions-exact-ref-arg $surface_text $prefix) {
      continue
    }

    let helper_ok = (build-surface-has-clone-helper-compat $surface_text $prefix)
    let inline_ok = (build-surface-has-inline-sha-compat $surface_text $prefix)
    let legacy_branch = (build-surface-has-legacy-branch-clone $surface_text $prefix)

    if $legacy_branch {
      $errors = ($errors | append
        $"($context): sources.($source_key): ref '($ref)' is a full git SHA but the build surface uses legacy 'git clone --branch' for ($prefix)_REF. Migrate to clone-source.nu with ($prefix)_REF_KIND or an explicit SHA fetch/checkout path."
      )
    } else if not ($helper_ok or $inline_ok) {
      $errors = ($errors | append
        $"($context): sources.($source_key): ref '($ref)' is a full git SHA but the build surface in '($dockerfile)' lacks ($prefix)_REF_KIND / clone-source.nu or explicit SHA fetch wiring for this source."
      )
    }
  }

  {valid: ($errors | is-empty), errors: $errors}
}