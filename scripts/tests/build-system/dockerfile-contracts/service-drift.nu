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

# Service Dockerfile drift and manifest REF_KIND regression tests.

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
  assert-dockerfile-clone-source-ref-kind-contract
  assert-dockerfile-nextcloud-local-mode-cleanup
]

export def service-drift-early-tests [verbose: bool] {
  [
    (run-test "Test 39j: Real manifest - cernbox-revad v3.10.1 production mixed REF_KIND build args" {
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
    (run-test "Test 39k: env REVAD_REF override recomputes REVAD_REF_KIND to sha" {
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
    (run-test "Test 39l: Dockerfile drift - cernbox-revad passes --ref-kind on clone-source.nu calls" {
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
    (run-test "Test 39n: Dockerfile drift - revad-base passes --ref-kind on clone-source.nu calls" {
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
    (run-test "Test 39o: Dockerfile drift - gaia passes --ref-kind on clone-source.nu calls" {
      let dockerfiles = [
        "services/gaia/Dockerfile"
      ]
      let ref_kind_patterns = [(clone-source-ref-kind-env-pattern "GAIA_REF_KIND")]
      for df in $dockerfiles {
        assert-dockerfile-clone-source-ref-kind-contract $df --expected-invocations 1 --ref-kind-patterns $ref_kind_patterns
      }
      true
    } $verbose)
    (run-test "Test 39p: Dockerfile drift - nextcloud passes --ref-kind on clone-source.nu calls" {
      let dockerfiles = [
        "services/nextcloud/Dockerfile"
      ]
      let ref_kind_patterns = [(clone-source-ref-kind-env-pattern "NEXTCLOUD_REF_KIND")]
      for df in $dockerfiles {
        assert-dockerfile-clone-source-ref-kind-contract $df --expected-invocations 1 --ref-kind-patterns $ref_kind_patterns
      }
      true
    } $verbose)
    (run-test "Test 39r: Dockerfile drift - nextcloud-contacts passes --ref-kind on clone-source.nu calls" {
      let dockerfiles = [
        "services/nextcloud-contacts/Dockerfile"
      ]
      let ref_kind_patterns = [(clone-source-ref-kind-env-pattern "CONTACTS_REF_KIND")]
      for df in $dockerfiles {
        assert-dockerfile-clone-source-ref-kind-contract $df --expected-invocations 1 --ref-kind-patterns $ref_kind_patterns
      }
      true
    } $verbose)
    (run-test "Test 39v: Dockerfile drift - nextcloud-jupyterhub passes --ref-kind on clone-source.nu calls" {
      let dockerfiles = [
        "services/nextcloud-jupyterhub/Dockerfile"
      ]
      let ref_kind_patterns = [(clone-source-ref-kind-env-pattern "INTEGRATION_JUPYTERHUB_REF_KIND")]
      for df in $dockerfiles {
        assert-dockerfile-clone-source-ref-kind-contract $df --expected-invocations 1 --ref-kind-patterns $ref_kind_patterns
      }
      true
    } $verbose)
    (run-test "Test 39s: Dockerfile drift - opencloudmesh-go passes --ref-kind on clone-source.nu calls" {
      let dockerfiles = [
        "services/opencloudmesh-go/Dockerfile.development"
      ]
      let ref_kind_patterns = [(clone-source-ref-kind-env-pattern "OCM_GO_REF_KIND")]
      for df in $dockerfiles {
        assert-dockerfile-clone-source-ref-kind-contract $df --expected-invocations 1 --ref-kind-patterns $ref_kind_patterns
      }
      true
    } $verbose)
    (run-test "Test 39t: Dockerfile drift - cernbox-web passes --ref-kind on clone-source.nu calls" {
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
  ]
}

export def service-drift-late-tests [verbose: bool] {
  [
    (run-test "Test 39u: Real manifest - cernbox-web master mixed REF_KIND build args" {
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
    (run-test "Test 39q: Dockerfile drift - nextcloud local-mode cleanup removes config and data paths" {
      assert-dockerfile-nextcloud-local-mode-cleanup "services/nextcloud/Dockerfile"
      true
    } $verbose)
    (run-test "Test 39m: env REVAD_REF_KIND=ref with SHA REVAD_REF recomputes to sha" {
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
  ]
}
