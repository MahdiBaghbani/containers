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

# Dockerfile parsing and clone-source contract assertions.

use ./ref-kind-build-args.nu [ref-kind-build-args-tests]
use ./service-drift.nu [service-drift-early-tests service-drift-late-tests]
use ./opencloud.nu [opencloud-tests]
use ./ocis.nu [ocis-tests]

export def clone-source-ref-kind-tests [verbose: bool] {
  mut results = []
  $results = ($results | append (ref-kind-build-args-tests $verbose))
  $results = ($results | append (service-drift-early-tests $verbose))
  $results = ($results | append (opencloud-tests $verbose))
  $results = ($results | append (ocis-tests $verbose))
  $results = ($results | append (service-drift-late-tests $verbose))
  $results
}
