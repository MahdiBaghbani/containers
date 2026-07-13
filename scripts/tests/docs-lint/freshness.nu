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

# Docs freshness: strip/check/extract units plus parser fixtures.

use ../../lib/docs/freshness.nu [
  strip-platform-suffix
  extract-refs-from-line
  extract-nushell-refs-from-line
  check-ref
  check-nushell-ref
  is-generic-placeholder-tag
  lint-docs-refs
  scan-docs-freshness
]
use ../lib.nu [run-test]
use ./_fixtures.nu [
  make-fixture
  cleanup-fixture
  freshness-fixture-clone-source
  freshness-fixture-placeholder
  freshness-fixture-external-url
  freshness-fixture-live-path
  freshness-fixture-stale-path
  freshness-fixture-allow-comment
  freshness-fixture-nushell-machine-ok
  freshness-fixture-nushell-machine-stale
  freshness-fixture-nushell-prose-ok
  freshness-fixture-nushell-prose-stale
]

def sample-live [] {
  {
    revad-base: {
      # "latest" mirrors build-live-index when versions[].latest is true
      versions: ["v3.10.1", "master", "ocm-webapp-share", "latest"]
      platforms: ["production", "development"]
      default_version: "v3.10.1"
      default_platform: "production"
    }
    cernbox-web: {
      versions: ["v1.0.25", "master", "latest"]
      platforms: ["debian", "alpine"]
      default_version: "v1.0.25"
      default_platform: "debian"
    }
    nextcloud: {
      versions: ["v30", "latest"]
      platforms: null
      default_version: "v30"
      default_platform: null
    }
    jupyterhub: {
      versions: ["webapp-share", "latest"]
      platforms: null
      default_version: "webapp-share"
      default_platform: null
    }
  }
}

export def freshness-tests [verbose: bool] {
  let live = (sample-live)
  [
    (run-test "freshness strip: live platform suffix removed" {
      let got = (strip-platform-suffix "v3.10.1-production" ["production", "development"])
      if $got != "v3.10.1" { error make {msg: $"expected v3.10.1 got ($got)"} }
      true
    } $verbose)
    (run-test "freshness strip: unknown platform suffix left intact" {
      let got = (strip-platform-suffix "v3.10.1-debian" ["production", "development"])
      if $got != "v3.10.1-debian" { error make {msg: $"expected intact got ($got)"} }
      true
    } $verbose)
    (run-test "freshness check: live version ok" {
      let r = (check-ref $live "revad-base" "v3.10.1")
      if not $r.ok { error make {msg: "expected live version to pass"} }
      true
    } $verbose)
    (run-test "freshness check: stale version fails" {
      let r = (check-ref $live "revad-base" "v3.3.3")
      if $r.ok { error make {msg: "expected stale version to fail"} }
      true
    } $verbose)
    (run-test "freshness check: unknown service skipped" {
      let r = (check-ref $live "my-service" "v1.0.0")
      if not $r.ok { error make {msg: "placeholder service must be skipped"} }
      true
    } $verbose)
    (run-test "freshness check: generated latest alias accepted" {
      let bare = (check-ref $live "revad-base" "latest")
      let suffixed = (check-ref $live "revad-base" "latest-production")
      if not $bare.ok { error make {msg: "expected latest to pass"} }
      if not $suffixed.ok { error make {msg: "expected latest-production to pass after strip"} }
      true
    } $verbose)
    (run-test "freshness check: generic placeholder tags skipped" {
      if not (is-generic-placeholder-tag "custom") {
        error make {msg: "custom must be a generic placeholder"}
      }
      if (is-generic-placeholder-tag "v3.3.3") {
        error make {msg: "v3.3.3 must not be treated as placeholder"}
      }
      let cases = [
        ["revad-base", "custom"]
        ["revad-base", "env-override"]
        ["cernbox-web", "testing"]
        ["cernbox-web", "testing-debian"]
        ["nextcloud", "ro"]
      ]
      for c in $cases {
        let r = (check-ref $live $c.0 $c.1)
        if not $r.ok {
          error make {msg: $"expected placeholder ($c.0):($c.1) to be skipped"}
        }
        if $r.reason != "generic-placeholder-skipped" {
          error make {msg: $"expected placeholder reason for ($c.0):($c.1), got ($r.reason)"}
        }
      }
      true
    } $verbose)
    (run-test "freshness extract: image-only backtick tag" {
      # Qualified image-only form as used in docs (no --service/--version).
      let line = "- Example: `revad-base:v3.3.3`"
      let refs = (extract-refs-from-line $line $live)
      let hit = ($refs | where kind == "image-tag" | where service == "revad-base" | where tag == "v3.3.3")
      if ($hit | is-empty) {
        error make {msg: $"expected image-only revad-base:v3.3.3, got ($refs | to nuon)"}
      }
      true
    } $verbose)
    (run-test "freshness extract: image tag and cli version" {
      let line = "build --service revad-base --version v3.3.3 # also revad-base:v3.10.1"
      let refs = (extract-refs-from-line $line $live)
      let has_stale_cli = ($refs | any {|r| ($r.kind == "cli-version") and ($r.tag == "v3.3.3")})
      let has_live_image = ($refs | any {|r| ($r.kind == "image-tag") and ($r.tag == "v3.10.1")})
      if (not $has_stale_cli) or (not $has_live_image) {
        error make {msg: $"bad extract: ($refs | to nuon)"}
      }
      true
    } $verbose)
    (run-test "freshness extract: registry-qualified image tag" {
      let line = "pull ghcr.io/open-cloud-mesh/containers/revad-base:v3.3.3 locally"
      let refs = (extract-refs-from-line $line $live)
      let hit = ($refs | where kind == "image-tag" | where service == "revad-base" | where tag == "v3.3.3")
      if ($hit | is-empty) {
        error make {msg: $"expected registry-qualified image tag, got ($refs | to nuon)"}
      }
      true
    } $verbose)
    (run-test "freshness extract: external registry image ignored" {
      # external_images.runtime.tag, not the DockyPody jupyterhub service version
      let line = "- `quay.io/jupyterhub/jupyterhub:5.3.0` (pinned in versions.nuon)"
      let refs = (extract-refs-from-line $line $live)
      if not ($refs | is-empty) {
        error make {msg: $"expected no refs from quay.io hub image, got ($refs | to nuon)"}
      }
      true
    } $verbose)
    (run-test "freshness extract: external URL does not yield service tag" {
      let line = "See https://example.com/revad-base:v3.3.3 for history."
      let refs = (extract-refs-from-line $line $live)
      if not ($refs | is-empty) {
        error make {msg: $"expected no refs from URL, got ($refs | to nuon)"}
      }
      true
    } $verbose)
    (run-test "freshness nushell: machine pin must be exact" {
      let ok = (check-nushell-ref "nushell-machine" "0.113.1")
      let bad = (check-nushell-ref "nushell-machine" "0.108.0")
      if not $ok.ok { error make {msg: "expected 0.113.1 machine pin to pass"} }
      if $bad.ok { error make {msg: "expected 0.108.0 machine pin to fail"} }
      true
    } $verbose)
    (run-test "freshness nushell: prose allows 0.113 floor" {
      let ok = (check-nushell-ref "nushell-prose" "0.113")
      let bad = (check-nushell-ref "nushell-prose" "0.80")
      if not $ok.ok { error make {msg: "expected prose 0.113 to pass"} }
      if $bad.ok { error make {msg: "expected prose 0.80 to fail"} }
      true
    } $verbose)
    (run-test "freshness extract: NUSHELL_REF machine ref" {
      let refs = (extract-nushell-refs-from-line "use NUSHELL_REF=0.108.0 here")
      let hit = ($refs | where kind == "nushell-machine" | where tag == "0.108.0")
      if ($hit | is-empty) { error make {msg: "expected NUSHELL_REF machine extract"} }
      true
    } $verbose)
    (run-test "freshness fixture: clone-source text is clean" {
      let file = (make-fixture (freshness-fixture-clone-source))
      let violations = (scan-docs-freshness [$file] $live)
      cleanup-fixture $file
      if not ($violations | is-empty) {
        error make {msg: $"clone-source fixture must not violate: ($violations | to nuon)"}
      }
      true
    } $verbose)
    (run-test "freshness fixture: placeholder service ignored" {
      let file = (make-fixture (freshness-fixture-placeholder))
      let ok = (lint-docs-refs [$file])
      cleanup-fixture $file
      if not $ok { error make {msg: "placeholder should be ignored"} }
      true
    } $verbose)
    (run-test "freshness fixture: external URL ignored" {
      let file = (make-fixture (freshness-fixture-external-url))
      let violations = (scan-docs-freshness [$file] $live)
      cleanup-fixture $file
      if not ($violations | is-empty) {
        error make {msg: $"external URL must not violate: ($violations | to nuon)"}
      }
      true
    } $verbose)
    (run-test "freshness fixture: live path passes" {
      let file = (make-fixture (freshness-fixture-live-path))
      let violations = (scan-docs-freshness [$file] $live)
      cleanup-fixture $file
      if not ($violations | is-empty) {
        error make {msg: $"live path must pass: ($violations | to nuon)"}
      }
      true
    } $verbose)
    (run-test "freshness fixture: stale image-only tag fails" {
      let file = (make-fixture (freshness-fixture-stale-path))
      let violations = (scan-docs-freshness [$file] $live)
      cleanup-fixture $file
      let hit = (
        $violations
        | where service == "revad-base"
        | where tag == "v3.3.3"
        | where kind == "image-tag"
      )
      if ($hit | is-empty) {
        error make {msg: $"stale image-only revad-base:v3.3.3 must violate, got ($violations | to nuon)"}
      }
      true
    } $verbose)
    (run-test "freshness fixture: allow comment suppresses stale tag" {
      let file = (make-fixture (freshness-fixture-allow-comment))
      let violations = (scan-docs-freshness [$file] $live)
      cleanup-fixture $file
      if not ($violations | is-empty) {
        error make {msg: $"allow comment must suppress: ($violations | to nuon)"}
      }
      true
    } $verbose)
    (run-test "freshness fixture: nushell machine ok/stale" {
      let ok_file = (make-fixture (freshness-fixture-nushell-machine-ok))
      let bad_file = (make-fixture (freshness-fixture-nushell-machine-stale))
      let ok_v = (scan-docs-freshness [$ok_file] $live)
      let bad_v = (scan-docs-freshness [$bad_file] $live)
      cleanup-fixture $ok_file
      cleanup-fixture $bad_file
      if not ($ok_v | is-empty) { error make {msg: "machine ok fixture failed"} }
      if ($bad_v | is-empty) { error make {msg: "machine stale fixture should fail"} }
      true
    } $verbose)
    (run-test "freshness fixture: nushell prose ok/stale" {
      let ok_file = (make-fixture (freshness-fixture-nushell-prose-ok))
      let bad_file = (make-fixture (freshness-fixture-nushell-prose-stale))
      let ok_v = (scan-docs-freshness [$ok_file] $live)
      let bad_v = (scan-docs-freshness [$bad_file] $live)
      cleanup-fixture $ok_file
      cleanup-fixture $bad_file
      if not ($ok_v | is-empty) { error make {msg: "prose ok fixture failed"} }
      if ($bad_v | is-empty) { error make {msg: "prose stale fixture should fail"} }
      true
    } $verbose)
  ]
}
