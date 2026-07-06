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

# Hermetic temp context setup/cleanup for tls suite tests.

# Create a minimal temp directory that looks like a build context root
export def make-temp-context [] {
    ^mktemp -d | str trim
}

export def rm-temp-context [dir: string] {
    try { rm -rf $dir } catch { }
}

# Detect shell RUN chown lines that target /tls (stale pre-copy-tls pattern).
# COPY --chown=... is unrelated and is ignored.
export def find-stale-inline-tls-chown [content: string] {
    $content
    | lines
    | where {|line|
        ($line | str contains "chown") and ($line | str contains "/tls") and (not ($line | str contains "--chown="))
    }
}
