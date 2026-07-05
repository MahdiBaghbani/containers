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
use ../lib/build/config.nu [load-service-config process-sources-to-build-args detect-all-source-types]
use ../lib/build/sources.nu [classify-source-ref-kind extract-source-ref-kinds]
use ../lib/build/context.nu [detect-clone-source-requirements prepare-clone-source-context cleanup-clone-source-context]
use ../lib/build/clone-source.nu [run-clone-source]
use ../lib/manifest/core.nu [get-version-or-null load-versions-manifest]
use ../lib/platforms/core.nu [load-platforms-manifest]
use ./mocks.nu [detect-build]
use ./helpers.nu [setup-test-environment with-test-cleanup create-test-tls-meta assert-build-args-contain]
use ./lib.nu [run-test print-test-summary]

use ./build-system/_fixtures.nu [
    make-temp-context rm-temp-context
    with-git-file-protocol-allowed
    seed-local-git-repo seed-git-repo-with-submodule
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
use ./build-system/docker-sentinel.nu [docker-sentinel-tests]
use ./build-system/synthetic-deps.nu [synthetic-deps-tests]
use ./build-system/disk-parsing.nu [disk-parsing-tests]

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  mut results = []

  $results = ($results | append (cache-busting-tests $verbose_flag))
  $results = ($results | append (build-order-tests $verbose_flag))
  $results = ($results | append (automatic-deps-tests $verbose_flag))
  $results = ($results | append (continue-on-failure-tests $verbose_flag))
  $results = ($results | append (docker-sentinel-tests $verbose_flag))
  $results = ($results | append (synthetic-deps-tests $verbose_flag))
  $results = ($results | append (disk-parsing-tests $verbose_flag))

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