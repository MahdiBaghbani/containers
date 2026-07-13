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

# Nushell interpreter version requirements
# Part of scripts/lib/core/ - cross-cutting helpers with no domain knowledge

export const NU_PIN = "0.113.1"
export const NU_MIN = "0.113.1"

def version-below-min [current: string, minimum: string] {
  let sorted = ([$current, $minimum] | sort -n)
  ($sorted | first) == $current and $current != $minimum
}

# Fail fast when the running Nushell is older than NU_MIN.
export def assert-nushell-version [] {
  let running = (version)
  let current = $"($running.major).($running.minor).($running.patch)"
  if (version-below-min $current $NU_MIN) {
    error make {
      msg: $"Nushell ($current) is below the required minimum ($NU_MIN). Install Nushell ($NU_PIN) from https://www.nushell.sh/ and retry."
    }
  }
}
