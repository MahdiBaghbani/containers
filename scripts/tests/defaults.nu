#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# Open Cloud Mesh Containers: container build scripts and images
# Copyright (C) 2025 Open Cloud Mesh Contributors
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

# Comprehensive tests for top-level defaults feature

use ../lib/manifest.nu [apply-version-defaults get-version-spec load-versions-manifest]
use ../lib/platforms.nu [apply-platform-defaults get-platform-spec load-platforms-manifest expand-version-to-platforms get-default-platform]
use ../lib/validate.nu [validate-version-manifest validate-platforms-manifest]
use ./lib.nu [run-test print-test-summary]

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  mut results = []
  
  # Test 1: apply-version-defaults with no defaults
  let test1 = (run-test "apply-version-defaults: no defaults" {
    let manifest = {
      default: "v1.0.0",
      versions: [
        {
          name: "v1.0.0",
          overrides: {
            sources: {
              revad: { ref: "v3.3.2" }
            }
          }
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    if ($result.overrides.sources.revad.ref) != "v3.3.2" {
      error make {msg: "Version spec should be unchanged when no defaults"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test1)
  
  # Test 2: apply-version-defaults with global defaults only
  let test2 = (run-test "apply-version-defaults: global defaults only" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        external_images: {
          build: { tag: "1.25-trixie" }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {}
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    if ($result.overrides.external_images.build.tag) != "1.25-trixie" {
      error make {msg: $"Expected '1.25-trixie', got '($result.overrides.external_images.build.tag)'"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test2)
  
  # Test 3: apply-version-defaults with override
  let test3 = (run-test "apply-version-defaults: override takes precedence" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        external_images: {
          build: { tag: "1.25-trixie" }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {
            external_images: {
              build: { tag: "1.26-trixie" }
            }
          }
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    if ($result.overrides.external_images.build.tag) != "1.26-trixie" {
      error make {msg: $"Override should win: expected '1.26-trixie', got '($result.overrides.external_images.build.tag)'"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test3)
  
  # Test 4: apply-version-defaults with platform-specific defaults
  let test4 = (run-test "apply-version-defaults: platform-specific defaults" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        external_images: {
          build: { tag: "1.25-trixie" }
        },
        platforms: {
          production: {
            external_images: {
              runtime: { tag: "nonroot" }
            }
          },
          development: {
            external_images: {
              runtime: { tag: "trixie-slim" }
            }
          }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {}
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    if ($result.overrides.platforms.production.external_images.runtime.tag) != "nonroot" {
      error make {msg: $"Expected 'nonroot', got '($result.overrides.platforms.production.external_images.runtime.tag)'"}
    }
    if ($result.overrides.platforms.development.external_images.runtime.tag) != "trixie-slim" {
      error make {msg: $"Expected 'trixie-slim', got '($result.overrides.platforms.development.external_images.runtime.tag)'"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test4)
  
  # Test 5: apply-version-defaults with platform override
  let test5 = (run-test "apply-version-defaults: platform override takes precedence" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        platforms: {
          production: {
            external_images: {
              runtime: { tag: "nonroot" }
            }
          }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {
            platforms: {
              production: {
                external_images: {
                  runtime: { tag: "custom-runtime" }
                }
              }
            }
          }
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    if ($result.overrides.platforms.production.external_images.runtime.tag) != "custom-runtime" {
      error make {msg: $"Platform override should win: expected 'custom-runtime', got '($result.overrides.platforms.production.external_images.runtime.tag)'"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test5)
  
  # Test 6: apply-version-defaults with empty overrides but defaults.platforms
  let test6 = (run-test "apply-version-defaults: empty overrides with defaults.platforms" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        external_images: {
          build: { tag: "1.25-trixie" }
        },
        platforms: {
          production: {
            external_images: {
              runtime: { tag: "nonroot" }
            }
          }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {}
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    if not ("platforms" in ($result.overrides | columns)) {
      error make {msg: "Platforms should be preserved from defaults when overrides is empty"}
    }
    if ($result.overrides.platforms.production.external_images.runtime.tag) != "nonroot" {
      error make {msg: $"Expected 'nonroot', got '($result.overrides.platforms.production.external_images.runtime.tag)'"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test6)
  
  # Test 7: apply-version-defaults with version without overrides field
  let test7 = (run-test "apply-version-defaults: version without overrides field" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        external_images: {
          build: { tag: "1.25-trixie" }
        }
      },
      versions: [
        {
          name: "v1.0.0"
          # No overrides field
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    if not ("overrides" in ($result | columns)) {
      error make {msg: "Overrides field should be created from defaults"}
    }
    if ($result.overrides.external_images.build.tag) != "1.25-trixie" {
      error make {msg: $"Expected '1.25-trixie', got '($result.overrides.external_images.build.tag)'"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test7)
  
  # Test 8: apply-platform-defaults with no defaults
  let test8 = (run-test "apply-platform-defaults: no defaults" {
    let platforms = {
      default: "production",
      platforms: [
        {
          name: "production",
          dockerfile: "Dockerfile.production",
          external_images: {
            build: {
              name: "golang",
              build_arg: "BASE_BUILD_IMAGE"
            }
          }
        }
      ]
    }
    let platform_spec = $platforms.platforms.0
    let result = (apply-platform-defaults $platforms $platform_spec)
    if ($result.external_images.build.name) != "golang" {
      error make {msg: "Platform spec should be unchanged when no defaults"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test8)
  
  # Test 9: apply-platform-defaults with defaults
  let test9 = (run-test "apply-platform-defaults: with defaults" {
    let platforms = {
      default: "production",
      defaults: {
        external_images: {
          build: {
            name: "golang",
            build_arg: "BASE_BUILD_IMAGE"
          }
        }
      },
      platforms: [
        {
          name: "production",
          dockerfile: "Dockerfile.production"
        }
      ]
    }
    let platform_spec = $platforms.platforms.0
    let result = (apply-platform-defaults $platforms $platform_spec)
    if ($result.external_images.build.name) != "golang" {
      error make {msg: $"Expected 'golang', got '($result.external_images.build.name)'"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test9)
  
  # Test 10: apply-platform-defaults with override
  let test10 = (run-test "apply-platform-defaults: override takes precedence" {
    let platforms = {
      default: "production",
      defaults: {
        external_images: {
          build: {
            name: "golang",
            build_arg: "BASE_BUILD_IMAGE"
          }
        }
      },
      platforms: [
        {
          name: "production",
          dockerfile: "Dockerfile.production",
          external_images: {
            build: {
              name: "custom-golang",
              build_arg: "BASE_BUILD_IMAGE"
            }
          }
        }
      ]
    }
    let platform_spec = $platforms.platforms.0
    let result = (apply-platform-defaults $platforms $platform_spec)
    if ($result.external_images.build.name) != "custom-golang" {
      error make {msg: $"Platform override should win: expected 'custom-golang', got '($result.external_images.build.name)'"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test10)
  
  # Test 11: get-version-spec applies defaults automatically
  let test11 = (run-test "get-version-spec: applies defaults automatically" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        external_images: {
          build: { tag: "1.25-trixie" }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {}
        }
      ]
    }
    let result = (get-version-spec $manifest "v1.0.0")
    if ($result.overrides.external_images.build.tag) != "1.25-trixie" {
      error make {msg: $"get-version-spec should apply defaults: expected '1.25-trixie', got '($result.overrides.external_images.build.tag)'"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test11)
  
  # Test 12: get-platform-spec applies defaults automatically
  let test12 = (run-test "get-platform-spec: applies defaults automatically" {
    let platforms = {
      default: "production",
      defaults: {
        external_images: {
          build: {
            name: "golang",
            build_arg: "BASE_BUILD_IMAGE"
          }
        }
      },
      platforms: [
        {
          name: "production",
          dockerfile: "Dockerfile.production"
        }
      ]
    }
    let result = (get-platform-spec $platforms "production")
    if ($result.external_images.build.name) != "golang" {
      error make {msg: $"get-platform-spec should apply defaults: expected 'golang', got '($result.external_images.build.name)'"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test12)
  
  # Test 13: expand-version-to-platforms with defaults
  let test13 = (run-test "expand-version-to-platforms: works with defaults" {
    let platforms = {
      default: "production",
      platforms: [
        { name: "production" },
        { name: "development" }
      ]
    }
    let manifest = {
      default: "v1.0.0",
      defaults: {
        external_images: {
          build: { tag: "1.25-trixie" }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {}
        }
      ]
    }
    let version_spec = (get-version-spec $manifest "v1.0.0")
    let default_platform = (get-default-platform $platforms)
    let expanded = (expand-version-to-platforms $version_spec $platforms $default_platform)
    if ($expanded | length) != 2 {
      error make {msg: $"Expected 2 platforms, got ($expanded | length)"}
    }
    for exp in $expanded {
      let tag = (try { $exp.overrides.external_images.build.tag } catch { "missing" })
      if $tag != "1.25-trixie" {
        error make {msg: $"Default should be applied in expanded version: got '($tag)'"}
      }
    }
    true
  } $verbose_flag)
  $results = ($results | append $test13)
  
  # Test 14: Validation - valid defaults
  let test14 = (run-test "Validation: valid defaults structure" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        external_images: {
          build: { tag: "1.25-trixie" }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {}
        }
      ]
    }
    let validation = (validate-version-manifest $manifest null)
    if not $validation.valid {
      error make {msg: $"Valid defaults should pass validation: ($validation.errors | str join ', ')"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test14)
  
  # Test 15: Validation - invalid defaults (forbidden field)
  let test15 = (run-test "Validation: invalid defaults (forbidden field)" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        external_images: {
          build: {
            name: "golang"  # Forbidden in version defaults
          }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {}
        }
      ]
    }
    let validation = (validate-version-manifest $manifest null)
    if $validation.valid {
      error make {msg: "Invalid defaults should fail validation"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test15)
  
  # Test 16: Validation - platform defaults (forbidden sources)
  let test16 = (run-test "Validation: platform defaults forbid sources" {
    let platforms = {
      default: "production",
      defaults: {
        sources: {
          revad: { ref: "v3.3.2" }  # Forbidden in platform defaults
        }
      },
      platforms: [
        {
          name: "production",
          dockerfile: "Dockerfile.production"
        }
      ]
    }
    let validation = (validate-platforms-manifest $platforms)
    if $validation.valid {
      error make {msg: "Platform defaults with sources should fail validation"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test16)
  
  # Test 17: Backward compatibility - existing service without defaults
  let test17 = (run-test "Backward compatibility: existing service without defaults" {
    let versions = (load-versions-manifest "revad-base")
    let platforms = (load-platforms-manifest "revad-base")
    let v_validation = (validate-version-manifest $versions $platforms)
    let p_validation = (validate-platforms-manifest $platforms)
    if not ($v_validation.valid and $p_validation.valid) {
      error make {msg: "Existing service should validate without defaults"}
    }
    let version_spec = (get-version-spec $versions "v3.3.2")
    if not ("overrides" in ($version_spec | columns)) {
      error make {msg: "Version spec should have overrides field"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test17)
  
  # Test 18: Deep merge semantics
  let test18 = (run-test "Deep merge: nested records merge correctly" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        external_images: {
          build: { tag: "1.25-trixie" },
          runtime: { tag: "3.22" }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {
            external_images: {
              build: { tag: "1.26-trixie" }  # Override build, keep runtime
            }
          }
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    if ($result.overrides.external_images.build.tag) != "1.26-trixie" {
      error make {msg: $"Build tag should be overridden: got '($result.overrides.external_images.build.tag)'"}
    }
    if ($result.overrides.external_images.runtime.tag) != "3.22" {
      error make {msg: $"Runtime tag should come from defaults: got '($result.overrides.external_images.runtime.tag)'"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test18)
  
  print-test-summary $results
}
