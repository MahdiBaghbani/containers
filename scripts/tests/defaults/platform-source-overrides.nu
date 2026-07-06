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

# Platform-specific source override cases.

use ../../lib/manifest/core.nu [apply-version-defaults]
use ../lib.nu [run-test]

export def test-platform-specific-source-replacement [verbose: bool] {
  run-test "Platform-specific source replacement" {
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

    let platform_source = ($result.overrides.platforms.debian.sources.gaia)
    if not ("path" in ($platform_source | columns)) {
      error make {msg: "platform source should have path field"}
    }
    if "url" in ($platform_source | columns) {
      error make {msg: "platform source should not have url field (replaced, not merged)"}
    }

    true
  } $verbose
}

export def test-platform-specific-sources-in-defaults [verbose: bool] {
  run-test "Platform-specific sources in defaults" {
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
  } $verbose
}

export def test-mixed-global-and-platform-specific-source-overrides [verbose: bool] {
  run-test "Mixed: global and platform-specific source overrides" {
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

    if not ("path" in ($result.overrides.sources.gaia | columns)) {
      error make {msg: "global gaia source should have path field"}
    }

    if ($result.overrides.sources.nushell.url) != "https://github.com/nushell/nushell" {
      error make {msg: "global nushell should be preserved from defaults"}
    }

    let platform_source = ($result.overrides.platforms.debian.sources.nushell)
    if not ("path" in ($platform_source | columns)) {
      error make {msg: "platform nushell source should have path field"}
    }
    if ($platform_source.path) != ".repos/nushell-debian" {
      error make {msg: $"platform nushell path should be '.repos/nushell-debian', got '($platform_source.path)'"}
    }
    true
  } $verbose
}

export def test-platform-specific-partial-git-source-override [verbose: bool] {
  run-test "Platform-specific partial Git source override: ref only preserves url" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        sources: {
          server: {
            url: "https://github.com/nextcloud/server",
            ref: "v32.0.2"
          }
        },
        platforms: {
          debian: {
            sources: {
              server: {
                url: "https://github.com/nextcloud/server",
                ref: "v32.0.2"
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
                  server: {
                    ref: "master"  # Only ref, no url
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

    let platform_source = ($result.overrides.platforms.debian.sources.server)
    if not ("url" in ($platform_source | columns)) {
      error make {msg: "platform source url should be preserved from defaults when override only has ref"}
    }
    if ($platform_source.url) != "https://github.com/nextcloud/server" {
      error make {msg: $"platform url should be 'https://github.com/nextcloud/server', got '($platform_source.url)'"}
    }

    if ($platform_source.ref) != "master" {
      error make {msg: $"platform ref should be 'master', got '($platform_source.ref)'"}
    }
    true
  } $verbose
}
