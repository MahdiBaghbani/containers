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
  
  # Test 19: Source replacement - Git source overridden with local source
  let test19 = (run-test "Source replacement: Git source to local source" {
    let manifest = {
      default: "local",
      defaults: {
        sources: {
          gaia: {
            url: "https://github.com/example/gaia",
            ref: "v1.0.0"
          }
        }
      },
      versions: [
        {
          name: "local",
          overrides: {
            sources: {
              gaia: {
                path: ".repos/gaia"
              }
            }
          }
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    let gaia_source = ($result.overrides.sources.gaia)
    
    # Verify path is present
    if not ("path" in ($gaia_source | columns)) {
      error make {msg: "path field should be present in overridden source"}
    }
    if ($gaia_source.path) != ".repos/gaia" {
      error make {msg: $"path should be '.repos/gaia', got '($gaia_source.path)'"}
    }
    
    # Verify url and ref are NOT present (replaced, not merged)
    if "url" in ($gaia_source | columns) {
      error make {msg: "url field should not be present (source should be replaced, not merged)"}
    }
    if "ref" in ($gaia_source | columns) {
      error make {msg: "ref field should not be present (source should be replaced, not merged)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test19)
  
  # Test 20: Source preservation - omitted sources from defaults preserved
  let test20 = (run-test "Source preservation: omitted sources preserved from defaults" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        sources: {
          gaia: {
            url: "https://github.com/example/gaia",
            ref: "v1.0.0"
          },
          nushell: {
            url: "https://github.com/nushell/nushell",
            ref: "0.108.0"
          }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {
            sources: {
              gaia: {
                path: ".repos/gaia"
              }
              # nushell omitted - should be preserved from defaults
            }
          }
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    
    # Verify gaia is replaced
    if not ("path" in ($result.overrides.sources.gaia | columns)) {
      error make {msg: "gaia source should have path field"}
    }
    
    # Verify nushell is preserved from defaults
    if not ("nushell" in ($result.overrides.sources | columns)) {
      error make {msg: "nushell source should be preserved from defaults"}
    }
    if ($result.overrides.sources.nushell.url) != "https://github.com/nushell/nushell" {
      error make {msg: $"nushell source should preserve url from defaults, got '($result.overrides.sources.nushell.url)'"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test20)
  
  # Test 21: Empty overrides with source defaults - sources inherited
  let test21 = (run-test "Empty overrides: source defaults inherited" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        sources: {
          gaia: {
            url: "https://github.com/example/gaia",
            ref: "v1.0.0"
          }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {}  # Empty overrides
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    
    # Verify sources are inherited from defaults
    if not ("sources" in ($result.overrides | columns)) {
      error make {msg: "sources should be inherited from defaults when overrides are empty"}
    }
    if ($result.overrides.sources.gaia.url) != "https://github.com/example/gaia" {
      error make {msg: $"gaia source should inherit url from defaults, got '($result.overrides.sources.gaia.url)'"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test21)
  
  # Test 22: Other fields merge normally (dependencies, external_images)
  let test22 = (run-test "Other fields merge: dependencies and external_images use deep-merge" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        sources: {
          gaia: { url: "https://github.com/example/gaia", ref: "v1.0.0" }
        },
        dependencies: {
          common-tools: { service: "common-tools", version: "v1.0.0" }
        },
        external_images: {
          build: { tag: "1.25-trixie" },
          runtime: { tag: "3.22" }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {
            sources: {
              gaia: { path: ".repos/gaia" }  # Source replaced
            },
            dependencies: {
              common-tools: { service: "common-tools", version: "v1.1.0" }  # Dependency merged/overridden
            },
            external_images: {
              build: { tag: "1.26-trixie" }  # External image merged (runtime should be preserved)
            }
          }
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    
    # Verify source is replaced (not merged)
    if "url" in ($result.overrides.sources.gaia | columns) {
      error make {msg: "source should be replaced, not merged"}
    }
    
    # Verify dependencies are merged/overridden (not replaced)
    if ($result.overrides.dependencies.common-tools.version) != "v1.1.0" {
      error make {msg: $"dependency version should be overridden, got '($result.overrides.dependencies.common-tools.version)'"}
    }
    
    # Verify external_images are merged (runtime preserved from defaults)
    if ($result.overrides.external_images.build.tag) != "1.26-trixie" {
      error make {msg: $"build tag should be overridden, got '($result.overrides.external_images.build.tag)'"}
    }
    if ($result.overrides.external_images.runtime.tag) != "3.22" {
      error make {msg: $"runtime tag should be preserved from defaults, got '($result.overrides.external_images.runtime.tag)'"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test22)
  
  # Test 23: Platform-specific source replacement
  let test23 = (run-test "Platform-specific source replacement" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        sources: {
          gaia: {
            url: "https://github.com/example/gaia",
            ref: "v1.0.0"
          }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {
            platforms: {
              debian: {
                sources: {
                  gaia: {
                    path: ".repos/gaia"
                  }
                }
              }
            }
          }
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    
    # Verify platform source is replaced
    let platform_source = ($result.overrides.platforms.debian.sources.gaia)
    if not ("path" in ($platform_source | columns)) {
      error make {msg: "platform source should have path field"}
    }
    if "url" in ($platform_source | columns) {
      error make {msg: "platform source should not have url field (replaced, not merged)"}
    }
    
    # Verify global defaults unchanged (platform override doesn't affect global)
    # Note: In this case, global defaults are in defaults, not in overrides
    # The global overrides.sources should still have the default if no global override
    true
  } $verbose_flag)
  $results = ($results | append $test23)
  
  # Test 24: Platform-specific sources in defaults
  let test24 = (run-test "Platform-specific sources in defaults" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        sources: {
          gaia: {
            url: "https://github.com/example/gaia",
            ref: "v1.0.0"
          }
        },
        platforms: {
          debian: {
            sources: {
              gaia: {
                url: "https://github.com/example/gaia-debian",
                ref: "v1.0.0-debian"
              }
            }
          }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {
            platforms: {
              debian: {
                sources: {
                  gaia: {
                    path: ".repos/gaia-debian"
                  }
                }
              }
            }
          }
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    
    # Verify platform source is replaced (not merged with platform defaults)
    let platform_source = ($result.overrides.platforms.debian.sources.gaia)
    if not ("path" in ($platform_source | columns)) {
      error make {msg: "platform source should have path field"}
    }
    if ($platform_source.path) != ".repos/gaia-debian" {
      error make {msg: $"platform path should be '.repos/gaia-debian', got '($platform_source.path)'"}
    }
    if "url" in ($platform_source | columns) {
      error make {msg: "platform source should not have url field (replaced, not merged)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test24)
  
  # Test 25: Mixed global and platform-specific source overrides
  let test25 = (run-test "Mixed: global and platform-specific source overrides" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        sources: {
          gaia: {
            url: "https://github.com/example/gaia",
            ref: "v1.0.0"
          },
          nushell: {
            url: "https://github.com/nushell/nushell",
            ref: "0.108.0"
          }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {
            sources: {
              gaia: {
                path: ".repos/gaia"
              }
            },
            platforms: {
              debian: {
                sources: {
                  nushell: {
                    path: ".repos/nushell-debian"
                  }
                }
              }
            }
          }
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    
    # Verify global gaia is replaced
    if not ("path" in ($result.overrides.sources.gaia | columns)) {
      error make {msg: "global gaia source should have path field"}
    }
    
    # Verify global nushell is preserved (not in global overrides)
    if ($result.overrides.sources.nushell.url) != "https://github.com/nushell/nushell" {
      error make {msg: "global nushell should be preserved from defaults"}
    }
    
    # Verify platform nushell is replaced
    let platform_source = ($result.overrides.platforms.debian.sources.nushell)
    if not ("path" in ($platform_source | columns)) {
      error make {msg: "platform nushell source should have path field"}
    }
    if ($platform_source.path) != ".repos/nushell-debian" {
      error make {msg: $"platform nushell path should be '.repos/nushell-debian', got '($platform_source.path)'"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test25)
  
  print-test-summary $results
}
