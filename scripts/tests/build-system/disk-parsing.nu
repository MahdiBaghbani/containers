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

# Disk Filesystem Parsing Tests (Tests 35-38, pure, no shelling out).

use ../../lib/build/disk.nu [
    extract-root-mount extract-root-avail-gb is-low-disk filter-df-summary-lines parse-size-to-gb
]
use ../lib.nu [run-test]

export def disk-parsing-tests [verbose: bool] {
    # Sample `df -h` output used by the disk tests below.
    let df_sample = ["Filesystem      Size  Used Avail Use% Mounted on"
      "/dev/root        78G   45G   30G  61% /"
      "tmpfs           7.9G     0  7.9G   0% /dev/shm"
      "/dev/sda15      105M  6.1M   99M   6% /boot/efi"
      "overlay          78G   45G   30G  61% /var/lib/docker/overlay2"
      "tmpfs           1.6G  1.1M  1.6G   1% /run"]

    [
        (run-test "Test 35: Disk - root mount extraction from df -h" {
            let root = (extract-root-mount $df_sample)
            if $root == null {
              error make {msg: "Root mount not found"}
            }
            if $root.mount != "/" {
              error make {msg: $"Expected root mount '/', got '($root.mount)'"}
            }
            if $root.filesystem != "/dev/root" {
              error make {msg: $"Expected root filesystem '/dev/root', got '($root.filesystem)'"}
            }
            if $root.avail != "30G" {
              error make {msg: $"Expected root avail '30G', got '($root.avail)'"}
            }

            if $verbose {
              print $"    Root: ($root.filesystem) avail ($root.avail)"
            }

            true
          } $verbose)

        (run-test "Test 36: Disk - parse-size-to-gb conversions" {
            let g30 = (parse-size-to-gb "30G")
            if $g30 != 30.0 {
              error make {msg: $"30G should be 30.0, got ($g30)"}
            }
            let t1 = (parse-size-to-gb "1T")
            if $t1 != 1024.0 {
              error make {msg: $"1T should be 1024.0, got ($t1)"}
            }
            let m512 = (parse-size-to-gb "512M")
            if ($m512 < 0.49) or ($m512 > 0.51) {
              error make {msg: $"512M should be ~0.5GB, got ($m512)"}
            }
            let avail_gb = (extract-root-avail-gb $df_sample)
            if $avail_gb != 30.0 {
              error make {msg: $"Root avail GB should be 30.0, got ($avail_gb)"}
            }

            if $verbose {
              print $"    30G=($g30) 1T=($t1) 512M=($m512)"
            }

            true
          } $verbose)

        (run-test "Test 37: Disk - low-disk threshold behavior" {
            if not (is-low-disk 0.5 1.0) {
              error make {msg: "0.5GB below 1.0GB threshold should be low"}
            }
            if (is-low-disk 30.0 1.0) {
              error make {msg: "30.0GB above 1.0GB threshold should not be low"}
            }
            if (is-low-disk 0.0 1.0) {
              error make {msg: "0.0GB (unknown) should not be flagged as low"}
            }

            if $verbose {
              print "    low-disk threshold checks passed"
            }

            true
          } $verbose)

        (run-test "Test 38: Disk - filtered summary includes root filesystem" {
            let filtered = (filter-df-summary-lines $df_sample)

            let has_root = ($filtered | any {|line|
              let parts = ($line | split row -r '\s+' | where {|p| ($p | str length) > 0})
              ($parts | length) >= 6 and ($parts | get 5) == "/"
            })
            if not $has_root {
              error make {msg: $"Filtered summary missing root filesystem. Lines: ($filtered | to nuon)"}
            }

            let has_header = ($filtered | any {|line| $line | str starts-with "Filesystem"})
            if not $has_header {
              error make {msg: "Filtered summary missing header line"}
            }

            # Non-relevant mounts must be excluded
            let has_boot = ($filtered | any {|line| $line | str contains "/boot/efi"})
            if $has_boot {
              error make {msg: "Filtered summary should not include /boot/efi"}
            }

            if $verbose {
              print $"    Filtered ($filtered | length) lines, root present"
            }

            true
          } $verbose)
    ]
}
