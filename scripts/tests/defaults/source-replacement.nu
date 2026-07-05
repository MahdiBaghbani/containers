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

# Global source replacement, preservation, and merge semantics.

use ../../lib/manifest/core.nu [apply-version-defaults]
use ../lib.nu [run-test]

export def test-source-replacement-git-source-to-local-source [verbose: bool] {
  run-test "Source replacement: Git source to local source" {
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

    if not ("path" in ($gaia_source | columns)) {
      error make {msg: "path field should be present in overridden source"}
    }
    if ($gaia_source.path) != ".repos/gaia" {
      error make {msg: $"path should be '.repos/gaia', got '($gaia_source.path)'"}
    }

    if "url" in ($gaia_source | columns) {
      error make {msg: "url field should not be present (source should be replaced, not merged)"}
    }
    if "ref" in ($gaia_source | columns) {
      error make {msg: "ref field should not be present (source should be replaced, not merged)"}
    }
    true
  } $verbose
}

export def test-source-preservation-omitted-sources-preserved-from-defaults [verbose: bool] {
  run-test "Source preservation: omitted sources preserved from defaults" {
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

    if not ("path" in ($result.overrides.sources.gaia | columns)) {
      error make {msg: "gaia source should have path field"}
    }

    if not ("nushell" in ($result.overrides.sources | columns)) {
      error make {msg: "nushell source should be preserved from defaults"}
    }
    if ($result.overrides.sources.nushell.url) != "https://github.com/nushell/nushell" {
      error make {msg: $"nushell source should preserve url from defaults, got '($result.overrides.sources.nushell.url)'"}
    }
    true
  } $verbose
}

export def test-empty-overrides-source-defaults-inherited [verbose: bool] {
  run-test "Empty overrides: source defaults inherited" {
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

    if not ("sources" in ($result.overrides | columns)) {
      error make {msg: "sources should be inherited from defaults when overrides are empty"}
    }
    if ($result.overrides.sources.gaia.url) != "https://github.com/example/gaia" {
      error make {msg: $"gaia source should inherit url from defaults, got '($result.overrides.sources.gaia.url)'"}
    }
    true
  } $verbose
}

export def test-other-fields-merge-dependencies-and-external-images [verbose: bool] {
  run-test "Other fields merge: dependencies and external_images use deep-merge" {
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

    if "url" in ($result.overrides.sources.gaia | columns) {
      error make {msg: "source should be replaced, not merged"}
    }

    if ($result.overrides.dependencies.common-tools.version) != "v1.1.0" {
      error make {msg: $"dependency version should be overridden, got '($result.overrides.dependencies.common-tools.version)'"}
    }

    if ($result.overrides.external_images.build.tag) != "1.26-trixie" {
      error make {msg: $"build tag should be overridden, got '($result.overrides.external_images.build.tag)'"}
    }
    if ($result.overrides.external_images.runtime.tag) != "3.22" {
      error make {msg: $"runtime tag should be preserved from defaults, got '($result.overrides.external_images.runtime.tag)'"}
    }
    true
  } $verbose
}

export def test-partial-git-source-override-ref-only [verbose: bool] {
  run-test "Partial Git source override: ref only preserves url from defaults" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        sources: {
          server: {
            url: "https://github.com/nextcloud/server",
            ref: "v32.0.2"
          }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {
            sources: {
              server: {
                ref: "master"  # Only ref, no url
              }
            }
          }
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)

    if not ("url" in ($result.overrides.sources.server | columns)) {
      error make {msg: "url should be preserved from defaults when override only has ref"}
    }
    if ($result.overrides.sources.server.url) != "https://github.com/nextcloud/server" {
      error make {msg: $"url should be 'https://github.com/nextcloud/server', got '($result.overrides.sources.server.url)'"}
    }

    if ($result.overrides.sources.server.ref) != "master" {
      error make {msg: $"ref should be 'master', got '($result.overrides.sources.server.ref)'"}
    }
    true
  } $verbose
}

export def test-partial-git-source-override-url-only [verbose: bool] {
  run-test "Partial Git source override: url only preserves ref from defaults" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        sources: {
          reva: {
            url: "https://github.com/cs3org/reva",
            ref: "v3.3.3"
          }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {
            sources: {
              reva: {
                url: "https://github.com/MahdiBaghbani/reva-opencloud"  # Only url, no ref
              }
            }
          }
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)

    if ($result.overrides.sources.reva.url) != "https://github.com/MahdiBaghbani/reva-opencloud" {
      error make {msg: $"url should be 'https://github.com/MahdiBaghbani/reva-opencloud', got '($result.overrides.sources.reva.url)'"}
    }

    if not ("ref" in ($result.overrides.sources.reva | columns)) {
      error make {msg: "ref should be preserved from defaults when override only has url"}
    }
    if ($result.overrides.sources.reva.ref) != "v3.3.3" {
      error make {msg: $"ref should be 'v3.3.3', got '($result.overrides.sources.reva.ref)'"}
    }
    true
  } $verbose
}

export def test-complete-git-source-override [verbose: bool] {
  run-test "Complete Git source override: both url and ref override wins" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        sources: {
          reva: {
            url: "https://github.com/cs3org/reva",
            ref: "v3.3.3"
          }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {
            sources: {
              reva: {
                url: "https://github.com/cs3org/reva",
                ref: "master"  # Both url and ref present
              }
            }
          }
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)

    if ($result.overrides.sources.reva.url) != "https://github.com/cs3org/reva" {
      error make {msg: $"url should be 'https://github.com/cs3org/reva', got '($result.overrides.sources.reva.url)'"}
    }
    if ($result.overrides.sources.reva.ref) != "master" {
      error make {msg: $"ref should be 'master', got '($result.overrides.sources.reva.ref)'"}
    }
    true
  } $verbose
}

export def test-empty-source-override-preserves-all-fields-from-defaults [verbose: bool] {
  run-test "Empty source override preserves all fields from defaults" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        sources: {
          server: {
            url: "https://github.com/nextcloud/server",
            ref: "v32.0.2"
          }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {
            sources: {
              server: {}  # Empty override
            }
          }
        }
      ]
    }
    let version_spec = $manifest.versions.0
    let result = (apply-version-defaults $manifest $version_spec)

    if not ("url" in ($result.overrides.sources.server | columns)) {
      error make {msg: "url should be preserved from defaults when override is empty"}
    }
    if ($result.overrides.sources.server.url) != "https://github.com/nextcloud/server" {
      error make {msg: $"url should be 'https://github.com/nextcloud/server', got '($result.overrides.sources.server.url)'"}
    }
    if not ("ref" in ($result.overrides.sources.server | columns)) {
      error make {msg: "ref should be preserved from defaults when override is empty"}
    }
    if ($result.overrides.sources.server.ref) != "v32.0.2" {
      error make {msg: $"ref should be 'v32.0.2', got '($result.overrides.sources.server.ref)'"}
    }
    true
  } $verbose
}
