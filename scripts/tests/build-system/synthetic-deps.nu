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

# Synthetic Dependency Resolution Regression Tests (Tests 33-34, 39, 39-tracked, 40).

use ../../lib/build/order.nu [build-dependency-graph]
use ../../lib/build/dependencies.nu [resolve-dep-node resolve-dep-platforms]
use ../../lib/build/config.nu [load-service-config]
use ../../lib/manifest/core.nu [get-default-version get-version-or-null load-versions-manifest]
use ../../lib/platforms/core.nu [get-default-platform load-platforms-manifest]
use ./_fixtures.nu [
    make-temp-repo rm-temp-repo run-in-temp-repo
    seed-synth-dep-tools-fixture seed-synth-base-svc-fixture seed-synth-parent-graph-fixture
    SYNTH_DEP_TOOLS SYNTH_BASE_SVC SYNTH_PARENT_SVC SYNTH_PARENT_VERSION
]
use ../lib.nu [run-test]

export def synthetic-deps-tests [verbose: bool] {
    [
        (run-test "Test 33: Synthetic fixture - prod dep dep-tools:v1.0.0:debian" {
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

            if $verbose {
              print $"    parent prod -> ($resolved.node_key)"
            }

            true
          } $verbose)

        (run-test "Test 34: Synthetic fixture - prod dep base-svc:master:production" {
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

            if $verbose {
              print $"    consumer prod -> ($resolved.node_key)"
            }

            true
          } $verbose)

        (run-test "Test 39: Synthetic integration - build-dependency-graph parent prod contains dep-tools:v1.0.0:debian" {
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

            if $verbose {
              print $"    graph nodes: ($graph.nodes | str join ', ')"
            }

            true
          } $verbose)

        (run-test "Test 39-tracked: Real manifest - kasm-base default graph contains common-tools dep" {
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

            if $verbose {
              print $"    kasm-base ($version)/($platform) -> ($dep_node)"
            }

            true
          } $verbose)

        (run-test "Test 39-tracked-master-production: Real manifest - cernbox-revad master production revad-base dep" {
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

            if $verbose {
              print $"    cernbox-revad ($version)/($platform) -> ($dep_node)"
            }

            true
          } $verbose)

        (run-test "Test 40: Dependency resolution - fail-closed on platforms manifest load failure" {
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

            if $verbose {
              print "    fail-closed error raised; success and single-platform paths verified"
            }

            true
          } $verbose)
    ]
}
