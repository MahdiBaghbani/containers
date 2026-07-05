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

# SSH access configuration and build context tests

use ./lib.nu [print-test-summary]
use ./ssh/validate-config.nu [validate-config-tests]
use ./ssh/validate-merged.nu [validate-merged-tests]
use ./ssh/extract-metadata.nu [extract-metadata-tests]
use ./ssh/prepare-context.nu [prepare-context-tests]
use ./ssh/version-overrides.nu [version-overrides-tests]
use ./ssh/platform-overrides.nu [platform-overrides-tests]
use ./ssh/sshd-content.nu [sshd-content-tests]
use ./ssh/dockerfile-drift.nu [dockerfile-drift-tests]

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })

    let results = (
        (validate-config-tests $verbose_flag)
        | append (validate-merged-tests $verbose_flag)
        | append (extract-metadata-tests $verbose_flag)
        | append (prepare-context-tests $verbose_flag)
        | append (version-overrides-tests $verbose_flag)
        | append (platform-overrides-tests $verbose_flag)
        | append (sshd-content-tests $verbose_flag)
        | append (dockerfile-drift-tests $verbose_flag)
    )

    print-test-summary $results

    if ($results | any {|r| not $r}) {
        exit 1
    }
}
