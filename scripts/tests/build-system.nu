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
use ./mocks.nu [detect-build build-dependency-graph-with-mocks set-mock-platform-behavior]
use ./helpers.nu [setup-test-environment setup-test-service-with-deps with-test-cleanup create-test-dependency create-test-tls-meta assert-build-args-contain assert-build-order assert-graph-structure]
use ./lib.nu [run-test print-test-summary]

use ./build-system/_fixtures.nu [
    make-temp-repo rm-temp-repo make-temp-context rm-temp-context
    with-git-file-protocol-allowed
    seed-local-git-repo seed-git-repo-with-submodule run-in-temp-repo
    seed-synth-dep-tools-fixture seed-synth-base-svc-fixture seed-synth-parent-graph-fixture
    SYNTH_DEP_TOOLS SYNTH_BASE_SVC SYNTH_PARENT_SVC SYNTH_PARENT_VERSION
]
use ./build-system/dockerfile-contracts.nu [
    clone-source-ref-kind-env-pattern
    assert-dockerfile-clone-source-ref-kind-contract
    assert-opencloud-dockerfile-clone-source-contract
    assert-opencloud-dockerfile-override-wiring
    assert-opencloud-override-uses-clone-source
    assert-ocis-dockerfile-clone-source-contract
    assert-ocis-dockerfile-override-wiring
    assert-dockerfile-nextcloud-local-mode-cleanup
]
use ./build-system/cache-busting.nu [cache-busting-tests]
use ./build-system/build-order.nu [build-order-tests]
use ./build-system/automatic-deps.nu [automatic-deps-tests]
use ./build-system/continue-on-failure.nu [continue-on-failure-tests]

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  mut results = []

  $results = ($results | append (cache-busting-tests $verbose_flag))
  $results = ($results | append (build-order-tests $verbose_flag))
  $results = ($results | append (automatic-deps-tests $verbose_flag))
  $results = ($results | append (continue-on-failure-tests $verbose_flag))

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

  let test39v = (run-test "Test 39v: Dockerfile drift - opencloud clone-source contract and SHA checkout guard" {
    assert-opencloud-dockerfile-clone-source-contract "services/opencloud/Dockerfile.alpine"
    true
  } $verbose_flag)
  $results = ($results | append $test39v)

  let test39w = (run-test "Test 39w: opencloud override scripts use clone-source.nu contract" {
    assert-opencloud-override-uses-clone-source "services/opencloud/scripts/build/web-override.nu" "/mnt/web" "OPENCLOUD_WEB_REF_KIND"
    assert-opencloud-override-uses-clone-source "services/opencloud/scripts/build/reva-override.nu" "/mnt/reva" "OPENCLOUD_REVA_REF_KIND"
    true
  } $verbose_flag)
  $results = ($results | append $test39w)

  let test39y = (run-test "Test 39y: Dockerfile drift - opencloud web/reva override script COPY and RUN wiring" {
    assert-opencloud-dockerfile-override-wiring "services/opencloud/Dockerfile.alpine"
    true
  } $verbose_flag)
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

    if $verbose_flag {
      print $"    v6.1.0 OPENCLOUD_REF_KIND=($build_args_tag.OPENCLOUD_REF_KIND)"
      print $"    main OPENCLOUD_REF_KIND=($build_args_main.OPENCLOUD_REF_KIND)"
    }

    true
  } $verbose_flag)
  $results = ($results | append $test39x)

  let test39z = (run-test "Test 39z: Dockerfile drift - ocis clone-source contract and SHA checkout guard" {
    assert-ocis-dockerfile-clone-source-contract "services/ocis/Dockerfile.alpine"
    true
  } $verbose_flag)
  $results = ($results | append $test39z)

  let test39za = (run-test "Test 39za: ocis override scripts use clone-source.nu contract" {
    assert-opencloud-override-uses-clone-source "services/ocis/scripts/build/web-override.nu" "/mnt/web" "OCIS_WEB_REF_KIND"
    assert-opencloud-override-uses-clone-source "services/ocis/scripts/build/reva-override.nu" "/mnt/reva" "OCIS_REVA_REF_KIND"
    true
  } $verbose_flag)
  $results = ($results | append $test39za)

  let test39zb = (run-test "Test 39zb: Dockerfile drift - ocis web/reva override script COPY and RUN wiring" {
    assert-ocis-dockerfile-override-wiring "services/ocis/Dockerfile.alpine"
    true
  } $verbose_flag)
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

    if $verbose_flag {
      print $"    v8.0.1 OCIS_REF_KIND=($build_args_tag.OCIS_REF_KIND)"
      print $"    master OCIS_REF_KIND=($build_args_master.OCIS_REF_KIND)"
    }

    true
  } $verbose_flag)
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