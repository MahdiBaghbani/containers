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

# Tag generation tests

use ../lib/build-ops.nu [generate-tags]
use ./lib.nu [run-test print-test-summary]

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  mut results = []
  
  # Mock registry info for all tests (simulates GitHub CI by default)
  let registry_info = {
    ci_platform: "github",
    forgejo_registry: "registry.example.com",
    forgejo_path: "ocm",
    github_registry: "ghcr.io",
    github_path: "ocm"
  }
  
  # Test 1: Single-platform service (no change expected)
  let test1 = (run-test "Single-platform service (no change)" {
    let version_spec = {name: "v1.0.0", latest: true, tags: ["v1.0", "v1"]}
    let tags = (generate-tags "my-service" $version_spec true $registry_info "" "")
    let expected = ["my-service:v1.0.0", "my-service:latest", "my-service:v1.0", "my-service:v1"]
    if $tags != $expected {
      error make {msg: $"Tag mismatch. Expected: ($expected | to json), Got: ($tags | to json)"}
    }
  } $verbose_flag)
  $results = ($results | append $test1)
  
  # Test 2: Multi-platform default platform
  let test2 = (run-test "Multi-platform default platform (unprefixed tags)" {
    let version_spec = {name: "v2.0.0", latest: true, tags: ["v2.0", "v2"]}
    let tags = (generate-tags "my-service" $version_spec true $registry_info "debian" "debian")
    let expected = ["my-service:v2.0.0-debian", "my-service:v2.0.0", "my-service:latest-debian", "my-service:latest", "my-service:v2.0-debian", "my-service:v2.0", "my-service:v2-debian", "my-service:v2"]
    if $tags != $expected {
      error make {msg: $"Tag mismatch. Expected: ($expected | to json), Got: ($tags | to json)"}
    }
  } $verbose_flag)
  $results = ($results | append $test2)
  
  # Test 3: Multi-platform non-default platform
  let test3 = (run-test "Multi-platform non-default platform (platform-suffixed only)" {
    let version_spec = {name: "v2.0.0", latest: true, tags: ["v2.0", "v2"]}
    let tags = (generate-tags "my-service" $version_spec true $registry_info "alpine" "debian")
    let expected = ["my-service:v2.0.0-alpine", "my-service:latest-alpine", "my-service:v2.0-alpine", "my-service:v2-alpine"]
    if $tags != $expected {
      error make {msg: $"Tag mismatch. Expected: ($expected | to json), Got: ($tags | to json)"}
    }
  } $verbose_flag)
  $results = ($results | append $test3)
  
  # Test 4: Version without custom tags (latest: false)
  let test4 = (run-test "Version without custom tags (latest: false)" {
    let version_spec = {name: "v1.0.0"}
    let tags_default = (generate-tags "my-service" $version_spec true $registry_info "debian" "debian")
    let tags_other = (generate-tags "my-service" $version_spec true $registry_info "alpine" "debian")
    let expected_default = ["my-service:v1.0.0-debian", "my-service:v1.0.0"]
    let expected_other = ["my-service:v1.0.0-alpine"]
    if $tags_default != $expected_default {
      error make {msg: $"Default platform tag mismatch. Expected: ($expected_default | to json), Got: ($tags_default | to json)"}
    }
    if $tags_other != $expected_other {
      error make {msg: $"Other platform tag mismatch. Expected: ($expected_other | to json), Got: ($tags_other | to json)"}
    }
  } $verbose_flag)
  $results = ($results | append $test4)
  
  # Test 5: Version without custom tags (latest: true)
  let test5 = (run-test "Version without custom tags (latest: true)" {
    let version_spec = {name: "v1.0.0", latest: true}
    let tags_default = (generate-tags "my-service" $version_spec true $registry_info "debian" "debian")
    let tags_other = (generate-tags "my-service" $version_spec true $registry_info "alpine" "debian")
    let expected_default = ["my-service:v1.0.0-debian", "my-service:v1.0.0", "my-service:latest-debian", "my-service:latest"]
    let expected_other = ["my-service:v1.0.0-alpine", "my-service:latest-alpine"]
    if $tags_default != $expected_default {
      error make {msg: $"Default platform tag mismatch. Expected: ($expected_default | to json), Got: ($tags_default | to json)"}
    }
    if $tags_other != $expected_other {
      error make {msg: $"Other platform tag mismatch. Expected: ($expected_other | to json), Got: ($tags_other | to json)"}
    }
  } $verbose_flag)
  $results = ($results | append $test5)
  
  # Test 6: Remote registry tag format (single platform per CI)
  # GitHub CI should only generate GHCR tags
  let test6 = (run-test "Remote registry tag format (GitHub CI - GHCR only)" {
    let version_spec = {name: "v1.0.0", latest: true}
    let tags = (generate-tags "my-service" $version_spec false $registry_info "debian" "debian")
    # Should include only GHCR tags (not Forgejo) when ci_platform is "github"
    let ghcr_tags = ($tags | where {|t| $t | str starts-with "ghcr.io"})
    let forgejo_tags = ($tags | where {|t| $t | str starts-with "registry.example.com"})
    if ($ghcr_tags | length) == 0 {
      error make {msg: "No GHCR registry tags found"}
    }
    if ($forgejo_tags | length) > 0 {
      error make {msg: "Forgejo tags should not be generated in GitHub CI"}
    }
    # Verify expected GHCR tags are present
    let expected_base_tags = ["v1.0.0-debian", "v1.0.0", "latest-debian", "latest"]
    for base_tag in $expected_base_tags {
      let ghcr_tag = $"ghcr.io/ocm/my-service:($base_tag)"
      if not ($ghcr_tag in $ghcr_tags) {
        error make {msg: $"Missing GHCR tag: ($ghcr_tag)"}
      }
    }
  } $verbose_flag)
  $results = ($results | append $test6)
  
  # Test 6b: Forgejo CI should only generate Forgejo tags
  let test6b = (run-test "Remote registry tag format (Forgejo CI - Forgejo only)" {
    let forgejo_registry_info = {
      ci_platform: "forgejo",
      forgejo_registry: "registry.example.com",
      forgejo_path: "ocm",
      github_registry: "ghcr.io",
      github_path: "ocm"
    }
    let version_spec = {name: "v1.0.0", latest: true}
    let tags = (generate-tags "my-service" $version_spec false $forgejo_registry_info "debian" "debian")
    # Should include only Forgejo tags (not GHCR) when ci_platform is "forgejo"
    let forgejo_tags = ($tags | where {|t| $t | str starts-with "registry.example.com"})
    let ghcr_tags = ($tags | where {|t| $t | str starts-with "ghcr.io"})
    if ($forgejo_tags | length) == 0 {
      error make {msg: "No Forgejo registry tags found"}
    }
    if ($ghcr_tags | length) > 0 {
      error make {msg: "GHCR tags should not be generated in Forgejo CI"}
    }
    # Verify expected Forgejo tags are present
    let expected_base_tags = ["v1.0.0-debian", "v1.0.0", "latest-debian", "latest"]
    for base_tag in $expected_base_tags {
      let forgejo_tag = $"registry.example.com/ocm/my-service:($base_tag)"
      if not ($forgejo_tag in $forgejo_tags) {
        error make {msg: $"Missing Forgejo tag: ($forgejo_tag)"}
      }
    }
  } $verbose_flag)
  $results = ($results | append $test6b)
  
  # Test 7: Tag ordering (prefixed first, then unprefixed)
  let test7 = (run-test "Tag ordering (prefixed first, then unprefixed)" {
    let version_spec = {name: "v1.0.0", latest: true, tags: ["stable"]}
    let tags = (generate-tags "my-service" $version_spec true $registry_info "debian" "debian")
    let expected = ["my-service:v1.0.0-debian", "my-service:v1.0.0", "my-service:latest-debian", "my-service:latest", "my-service:stable-debian", "my-service:stable"]
    if $tags != $expected {
      error make {msg: $"Tag order mismatch. Expected: ($expected | to json), Got: ($tags | to json)"}
    }
  } $verbose_flag)
  $results = ($results | append $test7)
  
  # Test 8: Empty tags array
  let test8 = (run-test "Empty tags array" {
    let version_spec = {name: "v1.0.0", latest: true, tags: []}
    let tags = (generate-tags "my-service" $version_spec true $registry_info "debian" "debian")
    let expected = ["my-service:v1.0.0-debian", "my-service:v1.0.0", "my-service:latest-debian", "my-service:latest"]
    if $tags != $expected {
      error make {msg: $"Tag mismatch. Expected: ($expected | to json), Got: ($tags | to json)"}
    }
  } $verbose_flag)
  $results = ($results | append $test8)
  
  # Test 9: Missing tags field
  let test9 = (run-test "Missing tags field" {
    let version_spec = {name: "v1.0.0", latest: true}
    # No tags field
    let tags = (generate-tags "my-service" $version_spec true $registry_info "debian" "debian")
    let expected = ["my-service:v1.0.0-debian", "my-service:v1.0.0", "my-service:latest-debian", "my-service:latest"]
    if $tags != $expected {
      error make {msg: $"Tag mismatch. Expected: ($expected | to json), Got: ($tags | to json)"}
    }
  } $verbose_flag)
  $results = ($results | append $test9)
  
  # Test 10: Single platform in platforms.nuon
  let test10 = (run-test "Single platform in platforms.nuon (still gets unprefixed tags)" {
    let version_spec = {name: "v1.0.0", latest: true, tags: ["v1.0"]}
    let tags = (generate-tags "my-service" $version_spec true $registry_info "debian" "debian")
    let expected = ["my-service:v1.0.0-debian", "my-service:v1.0.0", "my-service:latest-debian", "my-service:latest", "my-service:v1.0-debian", "my-service:v1.0"]
    if $tags != $expected {
      error make {msg: $"Tag mismatch. Expected: ($expected | to json), Got: ($tags | to json)"}
    }
  } $verbose_flag)
  $results = ($results | append $test10)
  
  print-test-summary $results
}
