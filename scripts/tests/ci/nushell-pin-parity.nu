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

# Nushell pin parity across constants, manifests, and Dockerfiles.

use ../../lib/core/version.nu [NU_MIN NU_PIN]
use ../../lib/ci/workflow/constants.nu [NU_VERSION]
use ../lib.nu [run-test]

const EXPECTED_NU = "0.116.0"

const COMMON_TOOLS_DOCKERFILES = [
  "services/common-tools/Dockerfile.debian"
  "services/common-tools/Dockerfile.alpine"
  "services/common-tools/Dockerfile.rhel"
]

export def test-nushell-pin-parity [verbose: bool] {
  run-test "Nushell pin parity across constants, manifest, and Dockerfiles" {
    if $NU_PIN != $EXPECTED_NU {
      error make {msg: $"NU_PIN mismatch. got=($NU_PIN) expected=($EXPECTED_NU)"}
    }
    if $NU_MIN != $EXPECTED_NU {
      error make {msg: $"NU_MIN mismatch. got=($NU_MIN) expected=($EXPECTED_NU)"}
    }
    if $NU_VERSION != $EXPECTED_NU {
      error make {
        msg: $"NU_VERSION mismatch. got=($NU_VERSION) expected=($EXPECTED_NU)"
      }
    }

    let manifest = "services/common-tools/versions.nuon"
    if not ($manifest | path exists) {
      error make {msg: $"Missing manifest: ($manifest)"}
    }
    let ref = (open $manifest | get defaults.sources.nushell.ref)
    if $ref != $EXPECTED_NU {
      error make {msg: $"common-tools nushell ref mismatch. got=($ref)"}
    }

    let needle = $"ARG NUSHELL_REF=\"($EXPECTED_NU)\""
    for dockerfile in $COMMON_TOOLS_DOCKERFILES {
      if not ($dockerfile | path exists) {
        error make {msg: $"Missing Dockerfile: ($dockerfile)"}
      }
      let contents = (open --raw $dockerfile)
      if not ($contents | str contains $needle) {
        error make {
          msg: $"($dockerfile) missing expected default: ($needle)"
        }
      }
    }
    true
  } $verbose
}
