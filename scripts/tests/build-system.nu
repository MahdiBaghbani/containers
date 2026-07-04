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

# Build system tests

use ../lib/build/args.nu [generate-build-args]
use ../lib/build/order.nu [topological-sort-dfs build-dependency-graph]
use ../lib/build/docker.nu [normalize-docker-label]
use ../lib/build/dependencies.nu [resolve-dep-node resolve-dep-platforms]
use ../lib/build/config.nu [load-service-config process-sources-to-build-args detect-all-source-types]
use ../lib/build/sources.nu [classify-source-ref-kind extract-source-ref-kinds]
use ../lib/build/disk.nu [extract-root-mount extract-root-avail-gb is-low-disk filter-df-summary-lines parse-size-to-gb]
use ../lib/build/context.nu [detect-clone-source-requirements prepare-clone-source-context cleanup-clone-source-context]
use ../lib/build/clone-source.nu [run-clone-source]
use ../lib/manifest/core.nu [get-default-version get-version-or-null load-versions-manifest]
use ../lib/platforms/core.nu [get-default-platform load-platforms-manifest]
use ./mocks.nu [detect-build get-mock-service-config build-mock-version-manifest build-mock-platform-manifest check-platforms-manifest-exists check-versions-manifest-exists build-dependency-graph-with-mocks get-default-platform set-mock-platform-behavior]
use ./helpers.nu [setup-test-environment setup-test-service-with-deps cleanup-test-environment with-test-cleanup create-test-dependency create-test-deps-resolved create-test-tls-meta create-test-registry-info assert-cache-bust-format assert-cache-bust-value assert-build-args-contain assert-build-order assert-graph-structure]
use ./lib.nu [run-test print-test-summary]

const SYNTH_DEP_TOOLS = "synth-dep-tools"
const SYNTH_BASE_SVC = "synth-base-svc"
const SYNTH_PARENT_SVC = "synth-parent-svc"
const SYNTH_PARENT_VERSION = "v2.0.0"

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

def make-temp-context [] {
  let tmp = (^mktemp -d | str trim)
  mkdir $tmp
  $tmp
}

def rm-temp-context [dir: string] {
  try { rm -rf $dir } catch { }
}

def with-git-file-protocol-allowed [block: closure] {
  let saved = {
    count: (try { $env.GIT_CONFIG_COUNT } catch { "" })
    key0: (try { $env.GIT_CONFIG_KEY_0 } catch { "" })
    val0: (try { $env.GIT_CONFIG_VALUE_0 } catch { "" })
  }
  $env.GIT_CONFIG_COUNT = "1"
  $env.GIT_CONFIG_KEY_0 = "protocol.file.allow"
  $env.GIT_CONFIG_VALUE_0 = "always"
  let result = (try { do $block } catch {|err|
    if ($saved.count | str length) > 0 {
      $env.GIT_CONFIG_COUNT = $saved.count
    } else {
      hide-env GIT_CONFIG_COUNT
    }
    if ($saved.key0 | str length) > 0 {
      $env.GIT_CONFIG_KEY_0 = $saved.key0
    } else {
      hide-env GIT_CONFIG_KEY_0
    }
    if ($saved.val0 | str length) > 0 {
      $env.GIT_CONFIG_VALUE_0 = $saved.val0
    } else {
      hide-env GIT_CONFIG_VALUE_0
    }
    error make {msg: $err.msg}
  })
  if ($saved.count | str length) > 0 {
    $env.GIT_CONFIG_COUNT = $saved.count
  } else {
    hide-env GIT_CONFIG_COUNT
  }
  if ($saved.key0 | str length) > 0 {
    $env.GIT_CONFIG_KEY_0 = $saved.key0
  } else {
    hide-env GIT_CONFIG_KEY_0
  }
  if ($saved.val0 | str length) > 0 {
    $env.GIT_CONFIG_VALUE_0 = $saved.val0
  } else {
    hide-env GIT_CONFIG_VALUE_0
  }
  $result
}

def clone-source-ref-kind-env-pattern [env_name: string] {
  "--ref-kind " + ('"' + '$' + '{' + $env_name + '}' + '"')
}

def assert-dockerfile-clone-source-ref-kind-contract [
  dockerfile_path: string
  --expected-invocations (-e): int = 2
  --ref-kind-patterns (-p): list<string> = []
] {
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
    mut block_lines = []
    mut i = $idx
    loop {
      $block_lines = ($block_lines | append ($lines | get $i))
      let line = ($lines | get $i | str trim)
      if not ($line | str ends-with "\\") {
        break
      }
      $i = $i + 1
    }
    let block = ($block_lines | str join "\n")
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

def assert-dockerfile-nextcloud-local-mode-cleanup [dockerfile_path: string] {
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

def seed-local-git-repo [repo: string] {
  mkdir $repo
  "fixture" | save -f ($repo | path join "README.md")
  ^git -C $repo init -q
  ^git -C $repo config user.email "test@example.com"
  ^git -C $repo config user.name "Test User"
  ^git -C $repo add README.md
  ^git -C $repo commit -q -m "init"
  ^git -C $repo rev-parse HEAD
}

def seed-git-repo-with-submodule [base: string] {
  let sub = ($base | path join "submodule")
  let origin = ($base | path join "origin")

  mkdir $sub
  "submodule fixture" | save -f ($sub | path join "sub-marker.txt")
  ^git -C $sub init -q
  ^git -C $sub config user.email "test@example.com"
  ^git -C $sub config user.name "Test User"
  ^git -C $sub add sub-marker.txt
  ^git -C $sub commit -q -m "sub init"

  mkdir $origin
  "parent fixture" | save -f ($origin | path join "README.md")
  ^git -C $origin init -q
  ^git -C $origin config user.email "test@example.com"
  ^git -C $origin config user.name "Test User"
  ^git -C $origin add README.md
  ^git -C $origin commit -q -m "parent init"

  let sub_url = "../submodule"
  ^git -c protocol.file.allow=always -C $origin submodule add -q $sub_url submodule
  ^git -C $origin commit -q -m "add submodule"

  let head = (^git -C $origin rev-parse HEAD | str trim)
  let branch = (^git -C $origin branch --show-current | str trim)
  {
    origin: $origin
    sub: $sub
    head: $head
    branch: $branch
    url: $"file://($origin)"
  }
}

def run-in-temp-repo [repo: string, block: closure] {
  do -i { cd $repo; do $block }
}

def seed-minimal-service-base [repo: string, name: string] {
  {
    name: $name
    context: $"services/($name)"
    dockerfile: $"services/($name)/Dockerfile"
    sources: {
      app: { url: "https://example.com/app.git", ref: "main" }
    }
    external_images: {
      build: { name: "golang", tag: "1.25-trixie", build_arg: "BASE_BUILD_IMAGE" }
    }
  } | save -f ($repo | path join $"services/($name).nuon")
  mkdir ($repo | path join $"services/($name)")
}

def seed-debian-platforms [repo: string, name: string] {
  {
    default: "debian"
    platforms: [
      {
        name: "debian"
        dockerfile: $"services/($name)/Dockerfile.debian"
        external_images: {
          build: { name: "golang", build_arg: "BASE_BUILD_IMAGE" }
        }
      }
      {
        name: "alpine"
        dockerfile: $"services/($name)/Dockerfile.alpine"
        external_images: {
          build: { name: "golang", build_arg: "BASE_BUILD_IMAGE" }
        }
      }
    ]
  } | save -f ($repo | path join $"services/($name)/platforms.nuon")
}

def seed-prod-dev-platforms [repo: string, name: string] {
  {
    default: "production"
    platforms: [
      {
        name: "production"
        dockerfile: $"services/($name)/Dockerfile.production"
        external_images: {
          build: { name: "golang", build_arg: "BASE_BUILD_IMAGE" }
        }
      }
      {
        name: "development"
        dockerfile: $"services/($name)/Dockerfile.development"
        external_images: {
          build: { name: "golang", build_arg: "BASE_BUILD_IMAGE" }
        }
      }
    ]
  } | save -f ($repo | path join $"services/($name)/platforms.nuon")
}

def seed-synth-dep-tools-fixture [repo: string] {
  seed-minimal-service-base $repo $SYNTH_DEP_TOOLS
  seed-debian-platforms $repo $SYNTH_DEP_TOOLS
  {
    default: "v1.0.0"
    versions: [{ name: "v1.0.0", overrides: {} }]
  } | save -f ($repo | path join $"services/($SYNTH_DEP_TOOLS)/versions.nuon")
}

def seed-synth-base-svc-fixture [repo: string] {
  seed-minimal-service-base $repo $SYNTH_BASE_SVC
  seed-prod-dev-platforms $repo $SYNTH_BASE_SVC
  {
    default: "master"
    versions: [{ name: "master", overrides: {} }]
  } | save -f ($repo | path join $"services/($SYNTH_BASE_SVC)/versions.nuon")
}

def seed-synth-parent-graph-fixture [repo: string] {
  seed-synth-dep-tools-fixture $repo
  seed-minimal-service-base $repo $SYNTH_PARENT_SVC
  seed-prod-dev-platforms $repo $SYNTH_PARENT_SVC
  {
    default: $SYNTH_PARENT_VERSION
    defaults: {
      dependencies: {
        ($SYNTH_DEP_TOOLS): { version: "v1.0.0-debian" }
      }
    }
    versions: [{ name: $SYNTH_PARENT_VERSION, overrides: {} }]
  } | save -f ($repo | path join $"services/($SYNTH_PARENT_SVC)/versions.nuon")
}

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  mut results = []
  
  # Cache Busting Tests
  
  # Test 1: Per-service cache bust computation
  # Validates that cache bust is computed per-service from sources and is consistent
  let test1 = (run-test "Test 1: Cache Busting - Per-service computation" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
      
      # Generate build args without override
      let build_args1 = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" false)
      let cache_bust1 = (try { $build_args1.CACHEBUST } catch { "" })
      
      # Verify CACHEBUST is present and has correct format (16 chars for source refs hash)
      let _ = (assert-cache-bust-format $cache_bust1 16 "hash")
      
      # Verify hash is consistent (same sources = same hash)
      let build_args2 = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" false)
      let cache_bust2 = (try { $build_args2.CACHEBUST } catch { "" })
      
      let _ = (assert-cache-bust-value $cache_bust1 $cache_bust2)
      
      if $verbose_flag {
        print $"    CACHEBUST: ($cache_bust1)"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test1)
  
  # Test 2: Global cache bust override
  # Validates that --cache-bust flag overrides per-service computation
  let test2 = (run-test "Test 2: Cache Busting - Global override" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
      let override_value = "custom-cache-bust-123"
    
      # Generate build args with override
      let build_args = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta $override_value false)
      let cache_bust = (try { $build_args.CACHEBUST } catch { "" })
    
      assert-cache-bust-value $cache_bust $override_value
    
      if $verbose_flag {
        print $"    Override value: ($override_value)"
        print $"    CACHEBUST: ($cache_bust)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test2)
  
  # Test 3: --no-cache flag
  # Validates that --no-cache generates random UUID for cache bust
  let test3 = (run-test "Test 3: Cache Busting - --no-cache flag" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Generate build args with --no-cache
      let build_args = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" true)
      let cache_bust = (try { $build_args.CACHEBUST } catch { "" })
    
      # Verify it's a UUID format (36 chars with dashes)
      assert-cache-bust-format $cache_bust 36 "uuid"
    
      if $verbose_flag {
        print $"    Generated UUID: ($cache_bust)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test3)
  
  # Test 4: Git SHA fallback
  # Validates that cache bust falls back to Git SHA when service has no sources
  let test4 = (run-test "Test 4: Cache Busting - Git SHA fallback" {
    with-test-cleanup {
      # Create test environment with no sources (override config)
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Override config to remove sources (test Git SHA fallback)
      mut merged_cfg = $test_env.merged_cfg
      $merged_cfg = ($merged_cfg | upsert sources {})
    
      # Generate build args without override
      let build_args = (generate-build-args "test" $merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" false)
      let cache_bust = (try { $build_args.CACHEBUST } catch { "" })
    
      # Should be Git SHA (variable length) or "local"
      if ($cache_bust | str length) == 0 {
        error make {msg: "CACHEBUST not generated"}
      }
    
      if $cache_bust == "local" {
        if $verbose_flag {
          print $"    Using 'local' fallback \(no Git\)"
        }
      } else {
        if $verbose_flag {
          print $"    Using Git SHA: ($cache_bust)"
        }
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test4)
  
  # Test 5: Environment variable override
  # Validates that CACHEBUST environment variable overrides per-service computation
  let test5 = (run-test "Test 5: Cache Busting - Environment variable override" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
      let env_value = "env-cache-bust-456"
    
      # Set environment variable
      let old_env = (try { $env.CACHEBUST } catch { "" })
      $env.CACHEBUST = $env_value
    
      try {
        # Generate build args without override or --no-cache
        let build_args = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" false)
        let cache_bust = (try { $build_args.CACHEBUST } catch { "" })
      
        assert-cache-bust-value $cache_bust $env_value
      
        if $verbose_flag {
          print $"    Env value: ($env_value)"
          print $"    CACHEBUST: ($cache_bust)"
        }
      } catch {
        # Restore environment on error
        if ($old_env | str length) > 0 {
          $env.CACHEBUST = $old_env
        } else {
          hide-env CACHEBUST
        }
        error make {msg: $in}
      }
    
      # Restore environment
      if ($old_env | str length) > 0 {
        $env.CACHEBUST = $old_env
      } else {
        hide-env CACHEBUST
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test5)
  
  # Test 6: Hash consistency
  # Validates that cache bust is deterministic (same sources = same hash)
  let test6 = (run-test "Test 6: Cache Busting - Hash consistency" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Generate build args multiple times
      let build_args1 = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" false)
      let build_args2 = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" false)
      let build_args3 = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" false)
    
      let cache_bust1 = (try { $build_args1.CACHEBUST } catch { "" })
      let cache_bust2 = (try { $build_args2.CACHEBUST } catch { "" })
      let cache_bust3 = (try { $build_args3.CACHEBUST } catch { "" })
    
      # All should be identical
      let _ = (assert-cache-bust-value $cache_bust1 $cache_bust2)
      let _ = (assert-cache-bust-value $cache_bust2 $cache_bust3)
    
      if $verbose_flag {
        print $"    Consistent CACHEBUST: ($cache_bust1)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test6)
  
  # Build Order Resolution Tests
  
  # Test 7: Simple dependency chain
  # Validates that dependency graph correctly represents A -> B -> C chain
  let test7 = (run-test "Test 7: Build Order - Simple dependency chain" {
    with-test-cleanup {
      # Create service A that depends on B
      let dep_b = (create-test-dependency "service-b" "v1.0.0" "B_IMAGE")
      let test_env = (setup-test-service-with-deps "service-a" {b: $dep_b} "v1.0.0")
    
      # Setup service B that depends on C
      let dep_c = (create-test-dependency "service-c" "v1.0.0" "C_IMAGE")
      let test_env_b = (setup-test-service-with-deps "service-b" {c: $dep_c} "v1.0.0")
    
      # Build dependency graph
      let graph = (build-dependency-graph-with-mocks "service-a" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      # Perform topological sort
      let build_order = (topological-sort-dfs $graph)
    
      # Verify build order: C -> B -> A (or at least that all services are present)
      if ($build_order | length) < 3 {
        error make {msg: $"Expected at least 3 nodes in build order, got ($build_order | length)"}
      }
    
      # Verify all services are in build order
      let has_a = ($build_order | any {|node| ($node | str contains "service-a")})
      let has_b = ($build_order | any {|node| ($node | str contains "service-b")})
      let has_c = ($build_order | any {|node| ($node | str contains "service-c")})
    
      if not ($has_a and $has_b and $has_c) {
        error make {msg: $"Missing services in build order: A=($has_a), B=($has_b), C=($has_c)"}
      }
    
      if $verbose_flag {
        print $"    Nodes: ($graph.nodes | length)"
        print $"    Edges: ($graph.edges | length)"
        print $"    Build order: ($build_order | str join ' -> ')"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test7)
  
  # Test 8: Circular dependency detection
  # Validates that topological sort detects and reports circular dependencies
  let test8 = (run-test "Test 8: Build Order - Circular dependency detection" {
    with-test-cleanup {
      # Create a mock graph with circular dependency
      let mock_graph = {
        nodes: ["A", "B"],
        edges: [
          {from: "A", to: "B"},
          {from: "B", to: "A"}
        ]
      }
    
      # Topological sort should detect cycle
      let result = (try {
        topological-sort-dfs $mock_graph
        {has_cycle: false, cycles: []}
      } catch {|err|
        {has_cycle: true, error: $err.msg}
      })
    
      # Verify cycle was detected
      if not $result.has_cycle {
        error make {msg: "Circular dependency not detected"}
      }
    
      if $verbose_flag {
        print $"    Cycle detected: ($result.error)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test8)
  
  # Test 9: Version-aware graph
  # Validates that graph construction includes version in node keys
  let test9 = (run-test "Test 9: Build Order - Version-aware graph" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v3.3.3")
    
      # Build dependency graph
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      # Verify graph contains version in node keys
      let expected_nodes = ["test-service:v3.3.3"]
      let expected_edges = []
      assert-graph-structure $graph $expected_nodes $expected_edges
    
      if $verbose_flag {
        print $"    Version: ($test_env.version_spec.name)"
        print $"    Nodes: ($graph.nodes | str join ', ')"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test9)
  
  # Test 10: Platform inheritance
  # Validates that dependencies inherit platform from parent when parent is multi-platform
  let test10 = (run-test "Test 10: Build Order - Platform inheritance" {
    with-test-cleanup {
      # Create parent with multiple platforms
      let parent_platforms = (build-mock-platform-manifest "debian" [
        {name: "debian", dockerfile: "Dockerfile.debian", external_images: {build: {name: "golang", tag: "1.25-trixie", build_arg: "BASE_BUILD_IMAGE"}}},
        {name: "alpine", dockerfile: "Dockerfile.alpine", external_images: {build: {name: "golang", tag: "1.25-trixie", build_arg: "BASE_BUILD_IMAGE"}}}
      ])
      set-mock-platform-behavior "parent-service" true
      
      # Create child with multiple platforms (inherits from parent)
      let child_platforms = (build-mock-platform-manifest "debian" [
        {name: "debian", dockerfile: "Dockerfile.debian", external_images: {build: {name: "golang", tag: "1.25-trixie", build_arg: "BASE_BUILD_IMAGE"}}},
        {name: "alpine", dockerfile: "Dockerfile.alpine", external_images: {build: {name: "golang", tag: "1.25-trixie", build_arg: "BASE_BUILD_IMAGE"}}}
      ])
      set-mock-platform-behavior "child-service" true
      
      # Create dependency from parent to child
      let dep = (create-test-dependency "child-service" "v1.0.0" "CHILD_IMAGE")
      let test_env = (setup-test-service-with-deps "parent-service" {child: $dep} "v1.0.0")
      
      # Build graph with platform
      let platform = "debian"
      let graph = (build-dependency-graph-with-mocks "parent-service" $test_env.version_spec $test_env.merged_cfg $platform $parent_platforms $test_env.registry_info.is_local $test_env.registry_info)
      # Verify graph construction succeeded
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph has no nodes"}
      }
    
      if $verbose_flag {
        print $"    Platform: ($platform)"
        print $"    Nodes: ($graph.nodes | length)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test10)
  
  # Test 11: --show-build-order flag
  # Validates that build order can be computed and displayed
  let test11 = (run-test "Test 11: Build Order - --show-build-order flag" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Build dependency graph and get order
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
      let build_order = (topological-sort-dfs $graph)
    
      # Verify build order is valid
      let expected_order = ["test-service:v1.0.0"]
      assert-build-order $build_order $expected_order
    
      if $verbose_flag {
        print $"    Build order: ($build_order | str join ' -> ')"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test11)
  
  # Automatic Dependency Building Tests
  
  # Test 12: Auto-build missing dependency
  # Validates that dependency graph includes all dependencies for auto-build
  let test12 = (run-test "Test 12: Auto-Build - Missing dependency" {
    with-test-cleanup {
      let dep = (create-test-dependency "dep-service" "v1.0.0" "DEP_IMAGE")
      let test_env = (setup-test-service-with-deps "test-service" {dep: $dep} "v1.0.0")
    
      # Build dependency graph
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      # Verify graph has dependencies
      let expected_nodes = ["test-service:v1.0.0", "dep-service:v1.0.0"]
      let expected_edges = [{from: "test-service:v1.0.0", to: "dep-service:v1.0.0"}]
      assert-graph-structure $graph $expected_nodes $expected_edges
    
      if $verbose_flag {
        print $"    Nodes: ($graph.nodes | length)"
        print $"    Edges: ($graph.edges | length)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test12)
  
  # Test 13: Skip existing dependency
  # Validates that graph construction works (Docker image existence check is in build.nu)
  let test13 = (run-test "Test 13: Auto-Build - Skip existing dependency" {
    with-test-cleanup {
      let dep = (create-test-dependency "dep-service" "v1.0.0" "DEP_IMAGE")
      let test_env = (setup-test-service-with-deps "test-service" {dep: $dep} "v1.0.0")
    
      # Build dependency graph (this is what auto-build uses)
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      # Verify graph is valid
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print $"    Graph construction successful \(would check Docker for existing images in actual build\)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test13)
  
  # Test 14: Recursive dependencies
  # Validates that graph handles recursive dependencies correctly
  let test14 = (run-test "Test 14: Auto-Build - Recursive dependencies" {
    with-test-cleanup {
      # Create A -> B -> C chain
      let dep_c = (create-test-dependency "service-c" "v1.0.0" "C_IMAGE")
      let test_env_c = (setup-test-service-with-deps "service-c" {} "v1.0.0")
    
      let dep_b = (create-test-dependency "service-b" "v1.0.0" "B_IMAGE")
      let test_env_b = (setup-test-service-with-deps "service-b" {c: $dep_c} "v1.0.0")
    
      let dep_a = (create-test-dependency "service-a" "v1.0.0" "A_IMAGE")
      let test_env = (setup-test-service-with-deps "service-a" {b: $dep_b} "v1.0.0")
    
      # Build dependency graph
      let graph = (build-dependency-graph-with-mocks "service-a" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      # Get build order
      let build_order = (topological-sort-dfs $graph)
    
      # Verify build order respects dependencies
      if ($build_order | length) == 0 {
        error make {msg: "Build order is empty"}
      }
    
      # Verify all services are in order
      let has_a = ($build_order | any {|node| ($node | str contains "service-a")})
      let has_b = ($build_order | any {|node| ($node | str contains "service-b")})
      let has_c = ($build_order | any {|node| ($node | str contains "service-c")})
    
      if not ($has_a and $has_b and $has_c) {
        error make {msg: $"Missing services in build order"}
      }
    
      if $verbose_flag {
        print $"    Build order: ($build_order | str join ' -> ')"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test14)
  
  # Test 15: --dep-cache=strict flag
  # Validates that graph construction works (flag is handled in build.nu)
  let test15 = (run-test "Test 15: Auto-Build - --dep-cache=strict flag" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Graph construction works regardless of dep-cache mode
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print "    Graph construction works (--dep-cache mode is handled in build.nu)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test15)
  
  # Test 16: Build order display
  # Validates that build order can be computed and formatted for display
  let test16 = (run-test "Test 16: Auto-Build - Build order display" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Build dependency graph and get order
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
      let build_order = (topological-sort-dfs $graph)
    
      # Verify build order can be formatted
      let formatted = ($build_order | str join " -> ")
      if ($formatted | str length) == 0 {
        error make {msg: "Formatted build order is empty"}
      }
    
      let expected_order = ["test-service:v1.0.0"]
      assert-build-order $build_order $expected_order
    
      if $verbose_flag {
        print $"    Formatted order: ($formatted)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test16)
  
  # Test 17: Flag propagation (push-deps)
  # Validates that graph construction works (flag propagation is handled in build.nu)
  let test17 = (run-test "Test 17: Auto-Build - Flag propagation (push-deps)" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Graph construction works regardless of flags
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print $"    Graph construction works \(flag propagation is handled in build.nu\)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test17)
  
  # Test 18: Flag propagation (tag-deps)
  # Validates that graph construction works (flag propagation is handled in build.nu)
  let test18 = (run-test "Test 18: Auto-Build - Flag propagation (tag-deps)" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Graph construction works regardless of flags
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print $"    Graph construction works \(flag propagation is handled in build.nu\)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test18)
  
  # Test 19: Version/platform selection
  # Validates that graph construction works with specific version/platform
  let test19 = (run-test "Test 19: Continue-on-Failure - Version/platform selection" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v3.3.3")
    
      # Build dependency graph
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      # Verify graph contains version in node keys
      let expected_nodes = ["test-service:v3.3.3"]
      let expected_edges = []
      assert-graph-structure $graph $expected_nodes $expected_edges
    
      if $verbose_flag {
        print $"    Version: ($test_env.version_spec.name)"
        print $"    Nodes: ($graph.nodes | str join ', ')"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test19)
  
  # Continue-on-Failure Tests
  
  # Test 20: Single build fail fast
  # Validates that graph construction works (fail-fast is handled in build.nu)
  let test20 = (run-test "Test 20: Continue-on-Failure - Single build fail fast" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Graph construction works regardless of fail-fast setting
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print $"    Graph construction works \(fail-fast is handled in build.nu\)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test20)
  
  # Test 21: Multi-version continue-on-failure
  # Validates that graph construction works (continue-on-failure is handled in build.nu)
  let test21 = (run-test "Test 21: Continue-on-Failure - Multi-version continue-on-failure" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Build dependency graph
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print $"    Graph construction works \(continue-on-failure is handled in build.nu\)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test21)
  
  # Test 22: --fail-fast flag
  # Validates that graph construction works (--fail-fast is handled in build.nu)
  let test22 = (run-test "Test 22: Continue-on-Failure - --fail-fast flag" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Graph construction works regardless of fail-fast flag
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print "    Graph construction works (--fail-fast is handled in build.nu)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test22)
  
  # Test 23: Build summary format
  # Validates that build order can be computed (summary format is handled in build.nu)
  let test23 = (run-test "Test 23: Continue-on-Failure - Build summary format" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Build dependency graph and get order
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
      let build_order = (topological-sort-dfs $graph)
    
      # Verify build order can be used for summary
      let expected_order = ["test-service:v1.0.0"]
      assert-build-order $build_order $expected_order
    
      if $verbose_flag {
        print $"    Build order computed \(summary format is handled in build.nu\)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test23)
  
  # Test 24: Exit codes
  # Validates that graph construction works (exit codes are handled in build.nu)
  let test24 = (run-test "Test 24: Continue-on-Failure - Exit codes" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Graph construction works
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print "    Graph construction works (exit codes are handled in build.nu)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test24)
  
  # Test 25: Dependency failure handling
  # Validates that graph construction works (dependency failure handling is in build.nu)
  let test25 = (run-test "Test 25: Continue-on-Failure - Dependency failure handling" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Graph construction works
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print $"    Graph construction works \(dependency failure handling is in build.nu\)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test25)
  
  # Test 26: Dependency from version overrides
  # Validates that dependencies defined in version overrides are detected correctly
  let test26 = (run-test "Test 26: Build Order - Dependency from version overrides" {
    with-test-cleanup {
      # Create parent service with dependency override in version
      let dep = (create-test-dependency "dep-service" "v1.0.0" "DEP_IMAGE")
      let version_overrides = {
        dependencies: {
          dep: $dep
        }
      }
      let test_env = (setup-test-environment "parent-service" "v1.0.0" false $version_overrides)
      
      # Setup dependency service
      let dep_env = (setup-test-environment "dep-service" "v1.0.0")
      
      # Build dependency graph
      let graph = (build-dependency-graph-with-mocks "parent-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
      
      # Verify dependency edge exists
      let has_edge = ($graph.edges | any {|edge| 
        $edge.from == "parent-service:v1.0.0" and $edge.to == "dep-service:v1.0.0"
      })
      
      if not $has_edge {
        error make {msg: "Dependency edge not found in graph from version override"}
      }
      
      # Verify topological order: dependency before dependent
      let build_order = (topological-sort-dfs $graph)
      let dep_idx = ($build_order | enumerate | where {|item| $item.item == "dep-service:v1.0.0"} | first | get index)
      let parent_idx = ($build_order | enumerate | where {|item| $item.item == "parent-service:v1.0.0"} | first | get index)
      
      if $dep_idx >= $parent_idx {
        error make {msg: $"Dependency order incorrect: dep-service at ($dep_idx), parent-service at ($parent_idx). Dependency should come first."}
      }
      
      if $verbose_flag {
        print $"    Build order: ($build_order | str join ' -> ')"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test26)
  
  # Test 27: Dependency from platform config
  # Validates that dependencies defined in platform configs are detected correctly
  let test27 = (run-test "Test 27: Build Order - Dependency from platform config" {
    with-test-cleanup {
      # Create platform config with dependency (use "debian" as default platform name)
      let dep = (create-test-dependency "dep-service" "v1.0.0" "DEP_IMAGE")
      let platform_configs = [
        {
          name: "debian",
          dockerfile: "Dockerfile.debian",
          dependencies: {
            dep: $dep
          }
        }
      ]
      let test_env = (setup-test-environment "parent-service" "v1.0.0" true {} $platform_configs)
      
      # Setup dependency service
      let dep_env = (setup-test-environment "dep-service" "v1.0.0")
      
      # Build dependency graph for debian platform
      let graph = (build-dependency-graph-with-mocks "parent-service" $test_env.version_spec $test_env.merged_cfg "debian" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
      
      # Verify dependency edge exists (dependency inherits platform from parent)
      let has_edge = ($graph.edges | any {|edge| 
        $edge.from == "parent-service:v1.0.0:debian" and $edge.to == "dep-service:v1.0.0:debian"
      })
      
      if not $has_edge {
        error make {msg: $"Dependency edge not found in graph from platform config. Edges: ($graph.edges | to nuon)"}
      }
      
      # Verify topological order: dependency before dependent
      let build_order = (topological-sort-dfs $graph)
      let dep_idx = ($build_order | enumerate | where {|item| $item.item == "dep-service:v1.0.0:debian"} | first | get index)
      let parent_idx = ($build_order | enumerate | where {|item| $item.item == "parent-service:v1.0.0:debian"} | first | get index)
      
      if $dep_idx >= $parent_idx {
        error make {msg: $"Dependency order incorrect: dep-service at ($dep_idx), parent-service at ($parent_idx). Dependency should come first."}
      }
      
      if $verbose_flag {
        print $"    Build order: ($build_order | str join ' -> ')"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test27)
  
  # Test 28: Dependency key vs service name resolution
  # Validates that dependency keys can differ from service names (e.g., common-tools-builder -> common-tools)
  let test28 = (run-test "Test 28: Build Order - Dependency key vs service name" {
    with-test-cleanup {
      # Create dependency with different key and service name
      let dep = {
        service: "actual-service",
        build_arg: "DEP_IMAGE"
      }
      let test_env = (setup-test-service-with-deps "parent-service" {dep_key: $dep} "v1.0.0")
      
      # Setup actual service (not dep_key)
      let dep_env = (setup-test-environment "actual-service" "v1.0.0")
      
      # Build dependency graph
      let graph = (build-dependency-graph-with-mocks "parent-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
      
      # Verify edge uses actual service name, not dependency key
      let has_correct_edge = ($graph.edges | any {|edge| 
        $edge.from == "parent-service:v1.0.0" and $edge.to == "actual-service:v1.0.0"
      })
      let has_wrong_edge = ($graph.edges | any {|edge| 
        $edge.from == "parent-service:v1.0.0" and $edge.to == "dep_key:v1.0.0"
      })
      
      if not $has_correct_edge {
        error make {msg: "Dependency edge not found with correct service name"}
      }
      if $has_wrong_edge {
        error make {msg: "Dependency edge found with wrong dependency key instead of service name"}
      }
      
      if $verbose_flag {
        print $"    Edges: ($graph.edges | to nuon)"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test28)
  
  # Test 29: Platform-specific dependency resolution
  # Validates that dependencies with platform suffixes (v1.0.0-debian) resolve correctly
  # Note: Using "debian" instead of "rhel" to match mock platform manifest default
  let test29 = (run-test "Test 29: Build Order - Platform-specific dependency resolution" {
    with-test-cleanup {
      # Create dependency with platform suffix in version override (using "debian" to match mock)
      let dep = (create-test-dependency "dep-service" "v1.0.0-debian" "DEP_IMAGE")
      let version_overrides = {
        dependencies: {
          dep: $dep
        }
      }
      let test_env = (setup-test-environment "parent-service" "v1.0.0" false $version_overrides)
      
      # Setup dependency service with platforms manifest
      set-mock-platform-behavior "dep-service" true
      let dep_env = (setup-test-environment "dep-service" "v1.0.0" true)
      
      # Register dependency service dependencies (empty, but needed for graph construction)
      use ./mocks.nu [register-mock-service-dependencies]
      register-mock-service-dependencies "dep-service" "v1.0.0" {}
      
      # Build dependency graph
      let graph = (build-dependency-graph-with-mocks "parent-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
      
      # Verify edge uses resolved platform (dep-service:v1.0.0:debian)
      let has_edge = ($graph.edges | any {|edge| 
        $edge.from == "parent-service:v1.0.0" and $edge.to == "dep-service:v1.0.0:debian"
      })
      
      if not $has_edge {
        error make {msg: $"Platform-specific dependency edge not found. Expected 'dep-service:v1.0.0:debian'. Edges: ($graph.edges | to nuon)"}
      }
      
      # Verify topological order: dependency before dependent
      let build_order = (topological-sort-dfs $graph)
      let dep_idx = ($build_order | enumerate | where {|item| ($item.item | str contains "dep-service:v1.0.0:debian")} | first | get index)
      let parent_idx = ($build_order | enumerate | where {|item| $item.item == "parent-service:v1.0.0"} | first | get index)
      
      if $dep_idx >= $parent_idx {
        error make {msg: $"Dependency order incorrect: dep-service at ($dep_idx), parent-service at ($parent_idx). Dependency should come first."}
      }
      
      if $verbose_flag {
        print $"    Build order: ($build_order | str join ' -> ')"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test29)
  
  # Test 30: Topological sort ordering (dependencies before dependents)
  # Validates that topological sort correctly orders dependencies before dependents
  let test30 = (run-test "Test 30: Build Order - Topological sort ordering" {
    with-test-cleanup {
      # Create simple graph: A depends on B
      let mock_graph = {
        nodes: ["A", "B"],
        edges: [
          {from: "A", to: "B"}
        ]
      }
      
      # Topological sort should return B before A
      let build_order = (topological-sort-dfs $mock_graph)
      
      let b_idx = ($build_order | enumerate | where {|item| $item.item == "B"} | first | get index)
      let a_idx = ($build_order | enumerate | where {|item| $item.item == "A"} | first | get index)
      
      if $b_idx >= $a_idx {
        error make {msg: $"Topological sort order incorrect: B at ($b_idx), A at ($a_idx). Dependency B should come before dependent A."}
      }
      
      # Verify exact order
      let expected_order = ["B", "A"]
      assert-build-order $build_order $expected_order
      
      if $verbose_flag {
        print $"    Build order: ($build_order | str join ' -> ')"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test30)
  
  # Docker Sentinel Normalization Tests

  # Test 31: Docker sentinel string treated as empty/missing label
  # Validates that "<no value>" returned by Docker for absent labels is
  # normalized to empty string, preventing it from being treated as a real hash.
  let test31 = (run-test "Test 31: Docker sentinel <no value> normalizes to empty string" {
    let sentinel = ("<no value>" | normalize-docker-label)
    if ($sentinel | str length) != 0 {
      error make {msg: $"Expected empty string for sentinel, got: '($sentinel)'"}
    }

    let normal_label = ("abc12345deadbeef" | normalize-docker-label)
    if $normal_label != "abc12345deadbeef" {
      error make {msg: $"Normal label should pass through unchanged, got: '($normal_label)'"}
    }

    let padded_sentinel = ("  <no value>  " | normalize-docker-label)
    if ($padded_sentinel | str length) != 0 {
      error make {msg: $"Whitespace-padded sentinel should normalize to empty, got: '($padded_sentinel)'"}
    }

    let empty_label = ("" | normalize-docker-label)
    if ($empty_label | str length) != 0 {
      error make {msg: $"Empty string should pass through as empty, got: '($empty_label)'"}
    }

    if $verbose_flag {
      print "    Sentinel '<no value>' -> ''"
      print "    Normal label passes through unchanged"
    }

    true
  } $verbose_flag)
  $results = ($results | append $test31)

  # Test 32: Hash shortening is safe for odd strings including Docker sentinel
  # Validates that the short-hash diagnostic logic does not crash on strings
  # like "<no value>" and that short strings are returned as-is.
  let test32 = (run-test "Test 32: Hash shortening is safe for odd strings including sentinel" {
    # Inline the same logic used by the private short-hash helper in version.nu
    let shorten = {|s: string|
      if ($s | str length) <= 8 { $s } else { $s | str substring 0..7 }
    }

    let cases = [
      {input: "<no value>", expected_max: 8},
      {input: "", expected_max: 8},
      {input: "abc", expected_max: 8},
      {input: "abcdefgh", expected_max: 8},
      {input: "abcdefghi", expected_max: 8},
      {input: "abc123456789abcdef0123456789abcdef0123456789abcdef0123456789abcd", expected_max: 8},
    ]

    for case in $cases {
      let result = (do $shorten $case.input)
      if ($result | str length) > $case.expected_max {
        error make {msg: $"Shortening produced ($result | str length) chars for '($case.input)', max is ($case.expected_max)"}
      }
    }

    # Confirm sentinel "<no value>" (10 chars) shortens without crashing
    let sentinel_short = (do $shorten "<no value>")
    if ($sentinel_short | str length) > 8 {
      error make {msg: $"Sentinel short result too long: '($sentinel_short)'"}
    }

    if $verbose_flag {
      let sentinel_short = (do $shorten "<no value>")
      print $"    '<no value>' shortens to: '($sentinel_short)'"
    }

    true
  } $verbose_flag)
  $results = ($results | append $test32)

  # Synthetic Dependency Resolution Regression Tests
  # Exercise resolve-dep-node and build-dependency-graph against seeded
  # temp-repo manifests so tests do not depend on live service names.

  # Test 33: parent production depends on dep-tools:v1.0.0:debian
  # The dependency version "v1.0.0-debian" carries an explicit platform suffix
  # for dep-tools (which has platforms.nuon), so the node key must split the
  # debian platform out: dep-tools:v1.0.0:debian.
  let test33 = (run-test "Test 33: Synthetic fixture - prod dep dep-tools:v1.0.0:debian" {
    let repo = (make-temp-repo)
    seed-synth-dep-tools-fixture $repo
    let resolved = (try {
      run-in-temp-repo $repo {||
        let dep_config = { version: "v1.0.0-debian" }
        resolve-dep-node $dep_config $SYNTH_DEP_TOOLS $SYNTH_PARENT_VERSION "production" true
      }
    } catch {|err|
      rm-temp-repo $repo
      error make {msg: $err.msg}
    })
    rm-temp-repo $repo

    if $resolved.node_key != $"($SYNTH_DEP_TOOLS):v1.0.0:debian" {
      error make {msg: $"Expected '($SYNTH_DEP_TOOLS):v1.0.0:debian', got '($resolved.node_key)'"}
    }

    if $verbose_flag {
      print $"    parent prod -> ($resolved.node_key)"
    }

    true
  } $verbose_flag)
  $results = ($results | append $test33)

  # Test 34: consumer production depends on base-svc:master:production
  # The production platform override sets base-svc version "master-production",
  # which has a platform suffix for base-svc (production/development), so the
  # node key must be base-svc:master:production.
  let test34 = (run-test "Test 34: Synthetic fixture - prod dep base-svc:master:production" {
    let repo = (make-temp-repo)
    seed-synth-base-svc-fixture $repo
    let resolved = (try {
      run-in-temp-repo $repo {||
        let dep_config = { version: "master-production" }
        resolve-dep-node $dep_config $SYNTH_BASE_SVC "master" "production" true
      }
    } catch {|err|
      rm-temp-repo $repo
      error make {msg: $err.msg}
    })
    rm-temp-repo $repo

    if $resolved.node_key != $"($SYNTH_BASE_SVC):master:production" {
      error make {msg: $"Expected '($SYNTH_BASE_SVC):master:production', got '($resolved.node_key)'"}
    }

    if $verbose_flag {
      print $"    consumer prod -> ($resolved.node_key)"
    }

    true
  } $verbose_flag)
  $results = ($results | append $test34)

  # Test 39: Synthetic integration - build-dependency-graph for parent-svc
  # production proves the platform-suffixed node key (dep-tools:v1.0.0:debian)
  # lands in graph nodes and edges. build-dependency-graph does no docker I/O.
  let test39 = (run-test "Test 39: Synthetic integration - build-dependency-graph parent prod contains dep-tools:v1.0.0:debian" {
    let repo = (make-temp-repo)
    seed-synth-parent-graph-fixture $repo
    let graph = (try {
      run-in-temp-repo $repo {||
        let vm = (load-versions-manifest $SYNTH_PARENT_SVC)
        let pm = (load-platforms-manifest $SYNTH_PARENT_SVC)
        let vspec = (get-version-or-null $vm $SYNTH_PARENT_VERSION)
        let cfg = (load-service-config $SYNTH_PARENT_SVC $vspec "production" $pm)
        build-dependency-graph $SYNTH_PARENT_SVC $vspec $cfg "production" $pm false {}
      }
    } catch {|err|
      rm-temp-repo $repo
      error make {msg: $err.msg}
    })
    rm-temp-repo $repo

    let parent_node = $"($SYNTH_PARENT_SVC):($SYNTH_PARENT_VERSION):production"
    let dep_node = $"($SYNTH_DEP_TOOLS):v1.0.0:debian"

    if not ($parent_node in $graph.nodes) {
      error make {msg: $"Expected parent node '($parent_node)' in graph, got: ($graph.nodes | to nuon)"}
    }
    if not ($dep_node in $graph.nodes) {
      error make {msg: $"Expected dependency node '($dep_node)' in graph, got: ($graph.nodes | to nuon)"}
    }

    let has_edge = ($graph.edges | any {|e| $e.from == $parent_node and $e.to == $dep_node})
    if not $has_edge {
      error make {msg: $"Expected edge ($parent_node) -> ($dep_node), got: ($graph.edges | to nuon)"}
    }

    if $verbose_flag {
      print $"    graph nodes: ($graph.nodes | str join ', ')"
    }

    true
  } $verbose_flag)
  $results = ($results | append $test39)

  # Bounded tracked-manifest smoke: one live service proves build-dependency-graph
  # still matches resolve-dep-node for current defaults (no hardcoded version tags).
  let test39_tracked = (run-test "Test 39-tracked: Real manifest - kasm-base default graph contains common-tools dep" {
    let svc = "kasm-base"
    let vm = (load-versions-manifest $svc)
    let pm = (load-platforms-manifest $svc)
    let version = (get-default-version $vm)
    let platform = (get-default-platform $pm)
    let vspec = (get-version-or-null $vm $version)
    let cfg = (load-service-config $svc $vspec $platform $pm)

    let dep_config = ($cfg.dependencies | get "common-tools")
    let dep_service = (try { $dep_config.service } catch { "common-tools" })
    let resolved = (resolve-dep-node $dep_config $dep_service $version $platform true)

    let graph = (build-dependency-graph $svc $vspec $cfg $platform $pm false {})

    let parent_node = $"($svc):($version):($platform)"
    let dep_node = $resolved.node_key

    if not ($parent_node in $graph.nodes) {
      error make {msg: $"Expected parent node '($parent_node)' in graph, got: ($graph.nodes | to nuon)"}
    }
    if not ($dep_node in $graph.nodes) {
      error make {msg: $"Expected dependency node '($dep_node)' in graph, got: ($graph.nodes | to nuon)"}
    }

    let has_edge = ($graph.edges | any {|e| $e.from == $parent_node and $e.to == $dep_node})
    if not $has_edge {
      error make {msg: $"Expected edge ($parent_node) -> ($dep_node), got: ($graph.edges | to nuon)"}
    }

    if $verbose_flag {
      print $"    kasm-base ($version)/($platform) -> ($dep_node)"
    }

    true
  } $verbose_flag)
  $results = ($results | append $test39_tracked)

  # Test 39-tracked-master-production: cernbox-revad master + production
  # Platform override merge yields revad-base dep version "master-production";
  # graph must contain revad-base:master:production via load-service-config.
  let test39_tracked_mp = (run-test "Test 39-tracked-master-production: Real manifest - cernbox-revad master production revad-base dep" {
    let svc = "cernbox-revad"
    let version = "master"
    let platform = "production"
    let vm = (load-versions-manifest $svc)
    let pm = (load-platforms-manifest $svc)
    let vspec = (get-version-or-null $vm $version)
    let cfg = (load-service-config $svc $vspec $platform $pm)

    let dep_config = ($cfg.dependencies | get "revad-base")
    if ($dep_config.version? | default "") != "master-production" {
      error make {msg: $"Expected merged revad-base version 'master-production', got: ($dep_config | to nuon)"}
    }

    let dep_service = (try { $dep_config.service } catch { "revad-base" })
    let resolved = (resolve-dep-node $dep_config $dep_service $version $platform true)

    let graph = (build-dependency-graph $svc $vspec $cfg $platform $pm false {})

    let parent_node = $"($svc):($version):($platform)"
    let dep_node = $resolved.node_key

    if $dep_node != "revad-base:master:production" {
      error make {msg: $"Expected dep node 'revad-base:master:production', got '($dep_node)'"}
    }
    if not ($parent_node in $graph.nodes) {
      error make {msg: $"Expected parent node '($parent_node)' in graph, got: ($graph.nodes | to nuon)"}
    }
    if not ($dep_node in $graph.nodes) {
      error make {msg: $"Expected dependency node '($dep_node)' in graph, got: ($graph.nodes | to nuon)"}
    }

    let has_edge = ($graph.edges | any {|e| $e.from == $parent_node and $e.to == $dep_node})
    if not $has_edge {
      error make {msg: $"Expected edge ($parent_node) -> ($dep_node), got: ($graph.edges | to nuon)"}
    }

    if $verbose_flag {
      print $"    cernbox-revad ($version)/($platform) -> ($dep_node)"
    }

    true
  } $verbose_flag)
  $results = ($results | append $test39_tracked_mp)

  # Test 40: Fail-closed dependency platforms-manifest load
  # Regression guard: when a dependency reports check-platforms-manifest-exists
  # == true but its platforms manifest fails to load, resolution must error
  # (fail-closed) rather than silently degrade to single-platform, which would
  # drop the platform suffix and produce a wrong node key. Exercised via the
  # pure resolve-dep-platforms helper with the manifest load injected as a
  # closure so no real malformed manifest is needed on disk.
  let test40 = (run-test "Test 40: Dependency resolution - fail-closed on platforms manifest load failure" {
    # Branch under test: dep_has_platforms == true and the loader throws.
    let failed = (try {
      resolve-dep-platforms "dep-service" true {|| error make {msg: "simulated parse failure"} }
      false
    } catch {|err|
      # Must be the fail-closed refusal, not a silent single-platform degrade.
      if not ($err.msg | str contains "Refusing to silently treat") {
        error make {msg: $"Expected fail-closed error, got: ($err.msg)"}
      }
      true
    })

    if not $failed {
      error make {msg: "Expected resolve-dep-platforms to fail-closed when the platforms manifest load fails, but it returned a value"}
    }

    # When a dependency declares platforms and the load succeeds, the loaded
    # manifest is returned unchanged.
    let manifest = {default: "debian", platforms: [{name: "debian"}]}
    let loaded = (resolve-dep-platforms "dep-service" true {|| $manifest })
    if $loaded != $manifest {
      error make {msg: $"Expected loaded manifest to pass through unchanged, got: ($loaded | to nuon)"}
    }

    # A dependency with no platforms manifest resolves to null (single-platform)
    # without invoking the loader.
    let none = (resolve-dep-platforms "dep-service" false {|| error make {msg: "loader must not run when dep_has_platforms is false"} })
    if $none != null {
      error make {msg: $"Expected null for single-platform dependency, got: ($none | to nuon)"}
    }

    if $verbose_flag {
      print "    fail-closed error raised; success and single-platform paths verified"
    }

    true
  } $verbose_flag)
  $results = ($results | append $test40)

  # Disk Filesystem Parsing Tests (pure, no shelling out)

  # Sample `df -h` output used by the disk tests below.
  let df_sample = ["Filesystem      Size  Used Avail Use% Mounted on"
    "/dev/root        78G   45G   30G  61% /"
    "tmpfs           7.9G     0  7.9G   0% /dev/shm"
    "/dev/sda15      105M  6.1M   99M   6% /boot/efi"
    "overlay          78G   45G   30G  61% /var/lib/docker/overlay2"
    "tmpfs           1.6G  1.1M  1.6G   1% /run"]

  # Test 35: Root mount extraction matches the mount column exactly as "/"
  let test35 = (run-test "Test 35: Disk - root mount extraction from df -h" {
    let root = (extract-root-mount $df_sample)
    if $root == null {
      error make {msg: "Root mount not found"}
    }
    if $root.mount != "/" {
      error make {msg: $"Expected root mount '/', got '($root.mount)'"}
    }
    if $root.filesystem != "/dev/root" {
      error make {msg: $"Expected root filesystem '/dev/root', got '($root.filesystem)'"}
    }
    if $root.avail != "30G" {
      error make {msg: $"Expected root avail '30G', got '($root.avail)'"}
    }

    if $verbose_flag {
      print $"    Root: ($root.filesystem) avail ($root.avail)"
    }

    true
  } $verbose_flag)
  $results = ($results | append $test35)

  # Test 36: parse-size-to-gb converts df size strings to GB
  let test36 = (run-test "Test 36: Disk - parse-size-to-gb conversions" {
    let g30 = (parse-size-to-gb "30G")
    if $g30 != 30.0 {
      error make {msg: $"30G should be 30.0, got ($g30)"}
    }
    let t1 = (parse-size-to-gb "1T")
    if $t1 != 1024.0 {
      error make {msg: $"1T should be 1024.0, got ($t1)"}
    }
    let m512 = (parse-size-to-gb "512M")
    if ($m512 < 0.49) or ($m512 > 0.51) {
      error make {msg: $"512M should be ~0.5GB, got ($m512)"}
    }
    let avail_gb = (extract-root-avail-gb $df_sample)
    if $avail_gb != 30.0 {
      error make {msg: $"Root avail GB should be 30.0, got ($avail_gb)"}
    }

    if $verbose_flag {
      print $"    30G=($g30) 1T=($t1) 512M=($m512)"
    }

    true
  } $verbose_flag)
  $results = ($results | append $test36)

  # Test 37: low-disk threshold behavior (0.0 means unknown, not low)
  let test37 = (run-test "Test 37: Disk - low-disk threshold behavior" {
    if not (is-low-disk 0.5 1.0) {
      error make {msg: "0.5GB below 1.0GB threshold should be low"}
    }
    if (is-low-disk 30.0 1.0) {
      error make {msg: "30.0GB above 1.0GB threshold should not be low"}
    }
    if (is-low-disk 0.0 1.0) {
      error make {msg: "0.0GB (unknown) should not be flagged as low"}
    }

    if $verbose_flag {
      print "    low-disk threshold checks passed"
    }

    true
  } $verbose_flag)
  $results = ($results | append $test37)

  # Test 38: Filtered summary includes the root filesystem and header
  let test38 = (run-test "Test 38: Disk - filtered summary includes root filesystem" {
    let filtered = (filter-df-summary-lines $df_sample)

    let has_root = ($filtered | any {|line|
      let parts = ($line | split row -r '\s+' | where {|p| ($p | str length) > 0})
      ($parts | length) >= 6 and ($parts | get 5) == "/"
    })
    if not $has_root {
      error make {msg: $"Filtered summary missing root filesystem. Lines: ($filtered | to nuon)"}
    }

    let has_header = ($filtered | any {|line| $line | str starts-with "Filesystem"})
    if not $has_header {
      error make {msg: "Filtered summary missing header line"}
    }

    # Non-relevant mounts must be excluded
    let has_boot = ($filtered | any {|line| $line | str contains "/boot/efi"})
    if $has_boot {
      error make {msg: "Filtered summary should not include /boot/efi"}
    }

    if $verbose_flag {
      print $"    Filtered ($filtered | length) lines, root present"
    }

    true
  } $verbose_flag)
  $results = ($results | append $test38)

  # Test 39: clone-source helper not staged when Dockerfile does not reference it
  let test39 = (run-test "Test 39: clone-source helper skipped when Dockerfile omits it" {
    let dockerfile_text = "FROM debian:bookworm\nRUN echo hello"
    let clone_reqs = (detect-clone-source-requirements $dockerfile_text)
    if $clone_reqs.needs_clone_helper {
      error make {msg: "Expected no clone-source helper requirement for generic Dockerfile"}
    }

    let ctx = (make-temp-context)
    let staged = (prepare-clone-source-context "test-service" $ctx $clone_reqs)
    if $staged.staged {
      rm-temp-context $ctx
      error make {msg: "Expected helper not staged when Dockerfile omits clone-source.nu"}
    }

    let helper_dest = ($ctx | path join "scripts" "lib" "clone-source.nu")
    if ($helper_dest | path exists) {
      rm-temp-context $ctx
      error make {msg: "Expected no clone-source.nu in build context when not required"}
    }

    rm-temp-context $ctx
    true
  } $verbose_flag)
  $results = ($results | append $test39)

  # Test 39b: clone-source helper staging matches live source and cleans up
  let test39b = (run-test "Test 39b: clone-source helper staging fidelity and cleanup" {
    let helper_src = "scripts/lib/build/clone-source.nu"
    let live_content = (open $helper_src)
    let dockerfile_text = "COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu"
    let clone_reqs = (detect-clone-source-requirements $dockerfile_text)
    if not $clone_reqs.needs_clone_helper {
      error make {msg: "Expected clone-source helper requirement when Dockerfile copies it"}
    }

    let ctx = (make-temp-context)
    let staged = (prepare-clone-source-context "test-service" $ctx $clone_reqs)

    let helper_dest = ($ctx | path join "scripts" "lib" "clone-source.nu")
    if not ($helper_dest | path exists) {
      rm-temp-context $ctx
      error make {msg: "Expected clone-source.nu staged into build context"}
    }

    let staged_content = (open $helper_dest)
    if $staged_content != $live_content {
      rm-temp-context $ctx
      error make {msg: "Staged clone-source.nu does not match live helper source"}
    }

    cleanup-clone-source-context $ctx $staged
    if ($helper_dest | path exists) {
      rm-temp-context $ctx
      error make {msg: "Expected clone-source.nu removed after cleanup"}
    }

    rm-temp-context $ctx
    true
  } $verbose_flag)
  $results = ($results | append $test39b)

  # Test 39c: comment-only clone-source mention does not trigger staging
  let test39c = (run-test "Test 39c: comment-only clone-source mention does not trigger staging" {
    let dockerfile_text = (
      "FROM debian:bookworm\n" +
      "# The build uses clone-source.nu for git clones\n" +
      "# COPY ./scripts/lib/clone-source.nu would stage the helper\n" +
      "RUN echo hello\n"
    )
    let clone_reqs = (detect-clone-source-requirements $dockerfile_text)
    if $clone_reqs.needs_clone_helper {
      error make {msg: "Expected no clone-source helper requirement for comment-only mentions"}
    }

    let ctx = (make-temp-context)
    let staged = (prepare-clone-source-context "test-service" $ctx $clone_reqs)
    if $staged.staged {
      rm-temp-context $ctx
      error make {msg: "Expected helper not staged for comment-only clone-source mentions"}
    }

    let helper_dest = ($ctx | path join "scripts" "lib" "clone-source.nu")
    if ($helper_dest | path exists) {
      rm-temp-context $ctx
      error make {msg: "Expected no clone-source.nu in build context for comment-only mentions"}
    }

    rm-temp-context $ctx
    true
  } $verbose_flag)
  $results = ($results | append $test39c)

  # Source ref-kind classification (host-side build-arg pipeline)

  let test39d = (run-test "Test 39d: classify-source-ref-kind maps full SHA to sha" {
    let source = {url: "https://example.com/repo.git", ref: "a1b2c3d4e5f6789012345678901234567890abcd"}
    let kind = (classify-source-ref-kind $source "git")
    if $kind != "sha" {
      error make {msg: $"Expected ref-kind 'sha' for 40-hex ref, got: ($kind)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test39d)

  let test39e = (run-test "Test 39e: classify-source-ref-kind maps branch/tag to ref" {
    let source = {url: "https://example.com/repo.git", ref: "main"}
    let kind = (classify-source-ref-kind $source "git")
    if $kind != "ref" {
      error make {msg: $"Expected ref-kind 'ref' for branch name, got: ($kind)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test39e)

  let test39f = (run-test "Test 39f: classify-source-ref-kind maps local path source to local" {
    let source = {path: "/tmp/local-src"}
    let kind = (classify-source-ref-kind $source "local")
    if $kind != "local" {
      error make {msg: $"Expected ref-kind 'local' for path source, got: ($kind)"}
    }
    true
  } $verbose_flag)
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
  } $verbose_flag)
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
  } $verbose_flag)
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
  } $verbose_flag)
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

    if $verbose_flag {
      print $"    REVAD_REF_KIND=($build_args.REVAD_REF_KIND), REVAD_PLUGINS_REF_KIND=($build_args.REVAD_PLUGINS_REF_KIND)"
    }

    true
  } $verbose_flag)
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

      if $verbose_flag {
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
  } $verbose_flag)
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
  } $verbose_flag)
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
  } $verbose_flag)
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
  } $verbose_flag)
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
  } $verbose_flag)
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
  } $verbose_flag)
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
  } $verbose_flag)
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
  } $verbose_flag)
  $results = ($results | append $test39t)

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

    if $verbose_flag {
      print $"    WEB_REF_KIND=($build_args.WEB_REF_KIND), WEB_EXTENSIONS_REF_KIND=($build_args.WEB_EXTENSIONS_REF_KIND)"
    }

    true
  } $verbose_flag)
  $results = ($results | append $test39u)

  let test39q = (run-test "Test 39q: Dockerfile drift - nextcloud local-mode cleanup removes config and data paths" {
    assert-dockerfile-nextcloud-local-mode-cleanup "services/nextcloud/Dockerfile"
    true
  } $verbose_flag)
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

      if $verbose_flag {
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
  } $verbose_flag)
  $results = ($results | append $test39m)

  # Test 40: clone-source local mode copies directory contents
  let test40 = (run-test "Test 40: clone-source local mode copies directory contents" {
    let src = (^mktemp -d | str trim)
    let dest = (^mktemp -d | str trim)
    "local fixture" | save -f ($src | path join "marker.txt")

    run-clone-source --mode local --local-dir $src --dest $dest

    if not (($dest | path join "marker.txt") | path exists) {
      rm-temp-context $src
      rm-temp-context $dest
      error make {msg: "Expected marker.txt copied into destination"}
    }

    rm-temp-context $src
    rm-temp-context $dest
    true
  } $verbose_flag)
  $results = ($results | append $test40)

  # Test 41: clone-source ref mode clones a local git repository
  let test41 = (run-test "Test 41: clone-source ref mode clones local git repository" {
    let base = (^mktemp -d | str trim)
    let origin = ($base | path join "origin")
    let head = (seed-local-git-repo $origin)
    let branch = (^git -C $origin branch --show-current | str trim)
    let dest = ($base | path join "checkout")
    let url = $"file://($origin)"

    run-clone-source --mode git --ref-kind ref --url $url --ref $branch --dest $dest

    let cloned_head = (^git -C $dest rev-parse HEAD | str trim)
    if $cloned_head != $head {
      rm-temp-context $base
      error make {msg: $"Expected cloned HEAD ($cloned_head) to match origin ($head)"}
    }

    rm-temp-context $base
    true
  } $verbose_flag)
  $results = ($results | append $test41)

  # Test 42: clone-source sha mode fetches a local git repository by full SHA
  let test42 = (run-test "Test 42: clone-source sha mode fetches local git repository" {
    let base = (^mktemp -d | str trim)
    let origin = ($base | path join "origin")
    let head = (seed-local-git-repo $origin)
    let dest = ($base | path join "checkout")
    let url = $"file://($origin)"

    run-clone-source --mode git --ref-kind sha --url $url --ref $head --dest $dest

    let cloned_head = (^git -C $dest rev-parse HEAD | str trim)
    if $cloned_head != $head {
      rm-temp-context $base
      error make {msg: $"Expected cloned HEAD ($cloned_head) to match SHA ($head)"}
    }

    rm-temp-context $base
    true
  } $verbose_flag)
  $results = ($results | append $test42)

  # Test 43: clone-source ref mode skips submodule checkout when disabled
  let test43 = (run-test "Test 43: clone-source ref mode skips submodules when disabled" {
    let base = (^mktemp -d | str trim)
    let fixture = (seed-git-repo-with-submodule $base)
    let dest = ($base | path join "checkout")

    run-clone-source --mode git --ref-kind ref --url $fixture.url --ref $fixture.branch --dest $dest --submodules "false"

    let sub_marker = ($dest | path join "submodule" "sub-marker.txt")
    if ($sub_marker | path exists) {
      rm-temp-context $base
      error make {msg: "Expected submodule content absent when SOURCE_SUBMODULES=false"}
    }

    rm-temp-context $base
    true
  } $verbose_flag)
  $results = ($results | append $test43)

  # Test 44: clone-source ref mode recurses submodules by default
  let test44 = (run-test "Test 44: clone-source ref mode recurses submodules by default" {
    let base = (^mktemp -d | str trim)
    let fixture = (seed-git-repo-with-submodule $base)
    let dest = ($base | path join "checkout")

    with-git-file-protocol-allowed {
      run-clone-source --mode git --ref-kind ref --url $fixture.url --ref $fixture.branch --dest $dest
    }

    let sub_marker = ($dest | path join "submodule" "sub-marker.txt")
    if not ($sub_marker | path exists) {
      rm-temp-context $base
      error make {msg: "Expected submodule content present when SOURCE_SUBMODULES defaults to true"}
    }

    rm-temp-context $base
    true
  } $verbose_flag)
  $results = ($results | append $test44)

  # Test 45: clone-source sha mode recurses submodules by default
  let test45 = (run-test "Test 45: clone-source sha mode recurses submodules by default" {
    let base = (^mktemp -d | str trim)
    let fixture = (seed-git-repo-with-submodule $base)
    let dest = ($base | path join "checkout")

    with-git-file-protocol-allowed {
      run-clone-source --mode git --ref-kind sha --url $fixture.url --ref $fixture.head --dest $dest
    }

    let sub_marker = ($dest | path join "submodule" "sub-marker.txt")
    if not ($sub_marker | path exists) {
      rm-temp-context $base
      error make {msg: "Expected submodule content present when SOURCE_SUBMODULES defaults to true in sha mode"}
    }

    rm-temp-context $base
    true
  } $verbose_flag)
  $results = ($results | append $test45)

  # Test 46: clone-source main entrypoint rejects invalid inputs
  let test46 = (run-test "Test 46: clone-source main entrypoint rejects invalid inputs" {
    let helper = "scripts/lib/build/clone-source.nu"
    let dest = (^mktemp -d | str trim)

    let bad_sha = (^nu $helper --mode git --ref-kind sha --url "https://example.com/repo.git" --ref "not-a-sha" --dest $dest | complete)
    if $bad_sha.exit_code == 0 {
      rm-temp-context $dest
      error make {msg: "Expected non-zero exit for invalid SHA at main entrypoint"}
    }
    let bad_sha_out = ($bad_sha.stderr | str join "") + ($bad_sha.stdout | str join "")
    if not ($bad_sha_out | str contains "40-character SHA") {
      rm-temp-context $dest
      error make {msg: $"Expected SHA validation error, got: ($bad_sha_out)"}
    }

    let bad_kind = (^nu $helper --mode git --ref-kind bogus --url "https://example.com/repo.git" --ref "main" --dest $dest | complete)
    if $bad_kind.exit_code == 0 {
      rm-temp-context $dest
      error make {msg: "Expected non-zero exit for invalid ref-kind at main entrypoint"}
    }
    let bad_kind_out = ($bad_kind.stderr | str join "") + ($bad_kind.stdout | str join "")
    if not ($bad_kind_out | str contains "Invalid SOURCE_MODE/SOURCE_REF_KIND") {
      rm-temp-context $dest
      error make {msg: $"Expected ref-kind validation error, got: ($bad_kind_out)"}
    }

    let no_dest = (^nu $helper --mode git --ref-kind ref --url "https://example.com/repo.git" --ref "main" | complete)
    if $no_dest.exit_code == 0 {
      rm-temp-context $dest
      error make {msg: "Expected non-zero exit when SOURCE_DEST is missing at main entrypoint"}
    }
    let no_dest_out = ($no_dest.stderr | str join "") + ($no_dest.stdout | str join "")
    if not ($no_dest_out | str contains "SOURCE_DEST must be provided") {
      rm-temp-context $dest
      error make {msg: $"Expected missing-dest validation error, got: ($no_dest_out)"}
    }

    rm-temp-context $dest
    true
  } $verbose_flag)
  $results = ($results | append $test46)

  # Test 48: clone-source cache-dir git mode populates cache then destination
  let test48 = (run-test "Test 48: clone-source cache-dir ref mode populates cache and dest" {
    let base = (^mktemp -d | str trim)
    let origin = ($base | path join "origin")
    let head = (seed-local-git-repo $origin)
    let branch = (^git -C $origin branch --show-current | str trim)
    let cache = ($base | path join "cache")
    let dest = ($base | path join "checkout")
    let url = $"file://($origin)"

    run-clone-source --mode git --ref-kind ref --url $url --ref $branch --cache-dir $cache --dest $dest

    if not (($cache | path join ".git") | path exists) {
      rm-temp-context $base
      error make {msg: "Expected cache-dir to be populated with .git"}
    }
    let dest_head = (^git -C $dest rev-parse HEAD | str trim)
    if $dest_head != $head {
      rm-temp-context $base
      error make {msg: $"Expected dest HEAD ($dest_head) to match origin ($head)"}
    }

    rm-temp-context $base
    true
  } $verbose_flag)
  $results = ($results | append $test48)

  # Test 49: clone-source reuses a populated cache without refetching
  let test49 = (run-test "Test 49: clone-source reuses populated cache without refetching" {
    let base = (^mktemp -d | str trim)
    let origin = ($base | path join "origin")
    let head = (seed-local-git-repo $origin)
    let branch = (^git -C $origin branch --show-current | str trim)
    let cache = ($base | path join "cache")
    let dest1 = ($base | path join "checkout1")
    let dest2 = ($base | path join "checkout2")
    let url = $"file://($origin)"

    run-clone-source --mode git --ref-kind ref --url $url --ref $branch --cache-dir $cache --dest $dest1

    # Second run uses a bogus URL. It must succeed by reusing the populated
    # cache; a refetch would fail against the nonexistent remote.
    run-clone-source --mode git --ref-kind ref --url "file:///nonexistent/repo.git" --ref $branch --cache-dir $cache --dest $dest2

    let dest2_head = (^git -C $dest2 rev-parse HEAD | str trim)
    if $dest2_head != $head {
      rm-temp-context $base
      error make {msg: $"Expected reused-cache dest HEAD ($dest2_head) to match origin ($head)"}
    }

    rm-temp-context $base
    true
  } $verbose_flag)
  $results = ($results | append $test49)

  # Test 50: clone-source auto-detects ref-kind from the ref when unset
  let test50 = (run-test "Test 50: clone-source auto-detects ref-kind from ref" {
    let base = (^mktemp -d | str trim)
    let origin = ($base | path join "origin")
    let head = (seed-local-git-repo $origin)
    let branch = (^git -C $origin branch --show-current | str trim)
    let url = $"file://($origin)"

    # Empty ref-kind with a full 40-hex SHA -> sha path.
    let dest_sha = ($base | path join "by-sha")
    run-clone-source --mode git --url $url --ref $head --dest $dest_sha
    let sha_head = (^git -C $dest_sha rev-parse HEAD | str trim)
    if $sha_head != $head {
      rm-temp-context $base
      error make {msg: $"Expected auto-detected sha HEAD ($sha_head) to match ($head)"}
    }

    # Empty ref-kind with a branch name -> ref path.
    let dest_ref = ($base | path join "by-ref")
    run-clone-source --mode git --url $url --ref $branch --dest $dest_ref
    let ref_head = (^git -C $dest_ref rev-parse HEAD | str trim)
    if $ref_head != $head {
      rm-temp-context $base
      error make {msg: $"Expected auto-detected ref HEAD ($ref_head) to match ($head)"}
    }

    rm-temp-context $base
    true
  } $verbose_flag)
  $results = ($results | append $test50)

  # Test 50b: clone-source main entrypoint accepts omitted --ref-kind
  let test50b = (run-test "Test 50b: clone-source main entrypoint auto-detects when --ref-kind is omitted" {
    let base = (^mktemp -d | str trim)
    let origin = ($base | path join "origin")
    let head = (seed-local-git-repo $origin)
    let dest = ($base | path join "checkout")
    let url = $"file://($origin)"
    let helper = "scripts/lib/build/clone-source.nu"

    let out = (^nu $helper --mode git --url $url --ref $head --dest $dest | complete)
    if $out.exit_code != 0 {
      rm-temp-context $base
      let detail = (($out.stderr | str join "") + ($out.stdout | str join ""))
      error make {msg: $"Expected CLI entrypoint to accept omitted --ref-kind, got: ($detail)"}
    }

    let cloned_head = (^git -C $dest rev-parse HEAD | str trim)
    if $cloned_head != $head {
      rm-temp-context $base
      error make {msg: $"Expected cloned HEAD ($cloned_head) to match origin ($head) when --ref-kind is omitted"}
    }

    rm-temp-context $base
    true
  } $verbose_flag)
  $results = ($results | append $test50b)

  # Test 51: clone-source local mode ignores cache-dir
  let test51 = (run-test "Test 51: clone-source local mode ignores cache-dir" {
    let base = (^mktemp -d | str trim)
    let src = ($base | path join "src")
    mkdir $src
    "local fixture" | save -f ($src | path join "marker.txt")
    let cache = ($base | path join "cache")
    let dest = ($base | path join "dest")

    run-clone-source --mode local --local-dir $src --cache-dir $cache --dest $dest

    if not (($dest | path join "marker.txt") | path exists) {
      rm-temp-context $base
      error make {msg: "Expected marker.txt copied into destination in local mode"}
    }
    if ($cache | path exists) {
      rm-temp-context $base
      error make {msg: "Expected cache-dir untouched in local mode"}
    }

    rm-temp-context $base
    true
  } $verbose_flag)
  $results = ($results | append $test51)

  print-test-summary $results
  
  let failed = ($results | where {|r| not $r} | length)
  if $failed > 0 {
    exit 1
  } else {
    exit 0
  }
}
