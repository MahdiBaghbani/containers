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

# TLS certificate and CA staging tests

use ../lib.nu [print-test-summary]
use ./path-basics.nu [path-basics-tests]
use ./detect-ca-requirements.nu [detect-ca-requirements-tests]
use ./prepare-ca-context.nu [prepare-ca-context-tests]
use ./clean-certs.nu [clean-certs-tests]
use ./merged-dep-rules.nu [merged-dep-rules-tests]
use ./generate-ca.nu [generate-ca-tests]
use ./validate-ca.nu [validate-ca-tests]
use ./cert-matches-ca.nu [cert-matches-ca-tests]
use ./copy-tls.nu [copy-tls-tests]
use ./dockerfile-drift.nu [dockerfile-drift-tests]

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })

    let results = (
        (path-basics-tests $verbose_flag)
        | append (detect-ca-requirements-tests $verbose_flag)
        | append (prepare-ca-context-tests $verbose_flag)
        | append (clean-certs-tests $verbose_flag)
        | append (merged-dep-rules-tests $verbose_flag)
        | append (generate-ca-tests $verbose_flag)
        | append (validate-ca-tests $verbose_flag)
        | append (cert-matches-ca-tests $verbose_flag)
        | append (copy-tls-tests $verbose_flag)
        | append (dockerfile-drift-tests $verbose_flag)
    )

    print-test-summary $results

    if ($results | any {|r| not $r}) {
        exit 1
    }
}
