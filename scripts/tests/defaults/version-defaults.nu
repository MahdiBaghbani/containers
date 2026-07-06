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

# apply-version-defaults coverage.

use ../../lib/manifest/core.nu [apply-version-defaults]
use ../lib.nu [run-test]

export def test-apply-version-defaults-no-defaults [verbose: bool] {
  run-test "apply-version-defaults: no defaults" {
    let manifest = {
      default: "v1.0.0",
      versions: [
        {
          name: "v1.0.0",
          overrides: {
            sources: {
              revad: { ref: "v3.3.3" }
            }
          }
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)
    if ($result.overrides.sources.revad.ref) != "v3.3.3" {
      error make {msg: "Version spec should be unchanged when no defaults"}
    }
    true
  } $verbose
}

export def test-apply-version-defaults-global-defaults-only [verbose: bool] {
  run-test "apply-version-defaults: global defaults only" {
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
  } $verbose
}

export def test-apply-version-defaults-override-takes-precedence [verbose: bool] {
  run-test "apply-version-defaults: override takes precedence" {
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
  } $verbose
}

export def test-apply-version-defaults-platform-specific-defaults [verbose: bool] {
  run-test "apply-version-defaults: platform-specific defaults" {
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
  } $verbose
}

export def test-apply-version-defaults-platform-override-takes-precedence [verbose: bool] {
  run-test "apply-version-defaults: platform override takes precedence" {
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
  } $verbose
}

export def test-apply-version-defaults-empty-overrides-with-defaults-platforms [verbose: bool] {
  run-test "apply-version-defaults: empty overrides with defaults.platforms" {
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
  } $verbose
}

export def test-apply-version-defaults-version-without-overrides-field [verbose: bool] {
  run-test "apply-version-defaults: version without overrides field" {
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
  } $verbose
}

export def test-deep-merge-nested-records-merge-correctly [verbose: bool] {
  run-test "Deep merge: nested records merge correctly" {
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
  } $verbose
}
