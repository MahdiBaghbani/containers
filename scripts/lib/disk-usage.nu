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

# Disk usage monitoring for build diagnostics
# See docs/concepts/build-system.md for usage

use ./ci-deps.nu [get-all-dependency-services]

# Configuration constants
const TOP_N_LIMIT = 20
const DU_DEPTH = 2
const LOW_DISK_THRESHOLD_GB = 1.0

# Run df and extract filesystem summary
# Returns {lines: list, root_avail_gb: float}
def run-df-summary [] {
  let result = (try {
    ^df -h | complete
  } catch {
    {exit_code: 1, stdout: "", stderr: "df not available"}
  })
  
  if $result.exit_code != 0 {
    print "WARNING: df command failed, skipping filesystem summary"
    return {lines: [], root_avail_gb: 0.0}
  }
  
  let lines = ($result.stdout | lines)
  
  # Filter to show root filesystem and Docker-related mounts
  let patterns = ["Filesystem", " /$", " /home", "/var/lib/docker", "/tmp"]
  let filtered = ($lines | where {|line|
    $patterns | any {|pat| $line | str contains $pat}
  })
  
  # Extract available space from root filesystem for low-disk check
  let root_avail_gb = (try {
    let root_line = ($lines | where {|line| $line | str contains " /$"} | first)
    let parts = ($root_line | split row -r '\s+')
    let avail_str = ($parts | get 3)  # Available column
    parse-size-to-gb $avail_str
  } catch {
    0.0
  })
  
  {lines: $filtered, root_avail_gb: $root_avail_gb}
}

# Parse size string (e.g., "5.2G", "500M", "100K") to GB
def parse-size-to-gb [size_str: string] {
  let size_str = ($size_str | str trim)
  let last_char = ($size_str | str substring (-1..-1) | str upcase)
  let num_str = ($size_str | str substring 0..-2)
  let num = (try { $num_str | into float } catch { 0.0 })
  
  if $last_char == "G" {
    $num
  } else if $last_char == "T" {
    $num * 1024.0
  } else if $last_char == "M" {
    $num / 1024.0
  } else if $last_char == "K" {
    $num / 1024.0 / 1024.0
  } else {
    # Assume bytes
    $num / 1024.0 / 1024.0 / 1024.0
  }
}

# Run docker system df to show Docker disk usage
# Returns list of output lines, empty if Docker unavailable
def run-docker-system-df [] {
  let result = (try {
    ^docker system df | complete
  } catch {
    {exit_code: 1, stdout: "", stderr: "docker not available"}
  })
  
  if $result.exit_code != 0 {
    print "WARNING: Docker not available, skipping docker system df"
    return []
  }
  
  $result.stdout | lines
}

# Get sizes of cache directories for a service and its dependencies
# Returns {total: string, service: string, deps: list}
def get-cache-dir-sizes [service: string] {
  let cache_base = "/tmp/docker-images"
  mut result = {total: "", service: "", deps: []}
  
  # Check if cache base exists
  if not ($cache_base | path exists) {
    return $result
  }
  
  # Get total cache size
  let total_result = (try {
    ^du -sh $cache_base | complete
  } catch {
    {exit_code: 1, stdout: ""}
  })
  
  if $total_result.exit_code == 0 {
    let parts = ($total_result.stdout | str trim | split row "\t")
    $result = ($result | upsert total (try { $parts | first } catch { "" }))
  }
  
  # Get service-specific cache size
  let service_path = $"($cache_base)/($service)"
  if ($service_path | path exists) {
    let service_result = (try {
      ^du -sh $service_path | complete
    } catch {
      {exit_code: 1, stdout: ""}
    })
    
    if $service_result.exit_code == 0 {
      let parts = ($service_result.stdout | str trim | split row "\t")
      $result = ($result | upsert service (try { $parts | first } catch { "" }))
    }
  }
  
  # Get transitive dependency sizes
  let deps = (try { get-all-dependency-services $service } catch { [] })
  
  let dep_sizes = ($deps | reduce --fold [] {|dep, acc|
    let dep_path = $"($cache_base)/($dep)"
    if ($dep_path | path exists) {
      let dep_result = (try {
        ^du -sh $dep_path | complete
      } catch {
        {exit_code: 1, stdout: ""}
      })
      
      if $dep_result.exit_code == 0 {
        let parts = ($dep_result.stdout | str trim | split row "\t")
        let size = (try { $parts | first } catch { "" })
        if ($size | str length) > 0 {
          $acc | append {name: $dep, size: $size}
        } else {
          $acc
        }
      } else {
        $acc
      }
    } else {
      $acc
    }
  })
  
  $result | upsert deps $dep_sizes
}

# Get top N largest directories under a path
# Returns list of {size: string, path: string}
def get-top-n-dirs [target_path: string, depth: int = 2, limit: int = 20] {
  if not ($target_path | path exists) {
    return []
  }
  
  let result = (try {
    ^du -d $depth $target_path | complete
  } catch {
    {exit_code: 1, stdout: ""}
  })
  
  if $result.exit_code != 0 {
    return []
  }
  
  # Parse du output and sort by size
  let entries = ($result.stdout | lines | where {|line| ($line | str length) > 0} | each {|line|
    let parts = ($line | split row "\t")
    let size_kb = (try { $parts | first | into int } catch { 0 })
    let path = (try { $parts | get 1 } catch { "" })
    {size_kb: $size_kb, size: (format-size $size_kb), path: $path}
  })
  
  # Sort descending by size and take top N
  $entries | sort-by size_kb --reverse | first $limit | select size path
}

# Format size in KB to human-readable
def format-size [size_kb: int] {
  if $size_kb >= 1048576 {
    $"(($size_kb / 1048576 | math round --precision 1))G"
  } else if $size_kb >= 1024 {
    $"(($size_kb / 1024 | math round --precision 1))M"
  } else {
    $"($size_kb)K"
  }
}

# Main API: Record disk usage snapshot for a build phase
# Phases: pre, after-deps, after-version, post-build
export def record-disk-usage [service: string, phase: string, mode: string] {
  # Early return if monitoring is off
  if $mode == "off" {
    return
  }
  
  # Wrap entire function in try-catch to ensure non-fatal on any error
  try {
    print ""
    print "############################################################"
    print $"## DISK MONITOR: ($phase) | ($service)"
    print "############################################################"
    print ""
    
    # 1. Filesystem summary
    print "--- Filesystem Summary ---"
    let df_result = (run-df-summary)
    for line in $df_result.lines {
      print $line
    }
    print ""
    
    # 2. Docker disk usage
    print "--- Docker Disk Usage ---"
    let docker_lines = (run-docker-system-df)
    if ($docker_lines | is-empty) {
      print "  (Docker not available)"
    } else {
      for line in $docker_lines {
        print $line
      }
    }
    print ""
    
    # 3. CI cache directory usage
    print "--- CI Cache Directory Usage ---"
    let cache_sizes = (get-cache-dir-sizes $service)
    
    if ($cache_sizes.total | str length) > 0 {
      print $"  /tmp/docker-images total: ($cache_sizes.total)"
    } else {
      print "  /tmp/docker-images: (not found)"
    }
    
    if ($cache_sizes.service | str length) > 0 {
      print $"  /tmp/docker-images/($service): ($cache_sizes.service)"
    }
    
    if not ($cache_sizes.deps | is-empty) {
      print "  Dependencies:"
      for dep in $cache_sizes.deps {
        print $"    ($dep.name): ($dep.size)"
      }
    }
    print ""
    
    # 4. Top directories in workspace
    print $"--- Top ($TOP_N_LIMIT) Workspace Directories ---"
    let workspace_dirs = (get-top-n-dirs "." $DU_DEPTH $TOP_N_LIMIT)
    if ($workspace_dirs | is-empty) {
      print "  (unable to scan)"
    } else {
      for entry in $workspace_dirs {
        print $"  ($entry.size)\t($entry.path)"
      }
    }
    print ""
    
    # 5. Top directories in /tmp
    print $"--- Top ($TOP_N_LIMIT) /tmp Directories ---"
    let tmp_dirs = (get-top-n-dirs "/tmp" $DU_DEPTH $TOP_N_LIMIT)
    if ($tmp_dirs | is-empty) {
      print "  (unable to scan)"
    } else {
      for entry in $tmp_dirs {
        print $"  ($entry.size)\t($entry.path)"
      }
    }
    print ""
    
    # Summary line with available space
    let avail_str = ($df_result.root_avail_gb | math round --precision 2)
    print $">> Root filesystem available: ($avail_str)GB"
    
    # Low disk warning - prominent banner
    if $df_result.root_avail_gb < $LOW_DISK_THRESHOLD_GB and $df_result.root_avail_gb > 0.0 {
      print ""
      print "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      print $"!!    WARNING: LOW DISK SPACE - ONLY ($avail_str)GB FREE    !!"
      print "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      print ""
    }
    
    print "############################################################"
    print ""
  } catch {|err|
    let error_msg = (try { $err.msg } catch { "Unknown error" })
    print $"WARNING: Disk monitoring failed: ($error_msg)"
  }
}

# Prune BuildKit exec cache mounts between version builds
# Non-fatal: logs warnings but never fails the build
export def prune-build-cache [context: string, mode: string = "exec-cache"] {
  # Wrap entire function in try-catch to ensure non-fatal on any error
  try {
    print ""
    print "------------------------------------------------------------"
    print $"CI PRUNE: ($context) | mode: ($mode)"
    print "------------------------------------------------------------"
    
    if $mode == "exec-cache" {
      # Prune BuildKit exec.cachemount entries (RUN --mount=type=cache)
      let result = (try {
        ^docker builder prune --filter type=exec.cachemount -f | complete
      } catch {
        {exit_code: 1, stdout: "", stderr: "docker builder prune not available"}
      })
      
      if $result.exit_code == 0 {
        print $"CI PRUNE: exec.cachemount prune completed \(exit code 0\)"
        if ($result.stdout | str trim | str length) > 0 {
          print $result.stdout
        }
      } else {
        let stderr_msg = (try { $result.stderr | str trim } catch { "" })
        if ($stderr_msg | str length) > 0 {
          print $"WARNING: Build cache prune returned exit code ($result.exit_code): ($stderr_msg)"
        } else {
          print $"WARNING: Build cache prune returned exit code ($result.exit_code)"
        }
      }
    } else {
      print $"WARNING: Unknown prune mode '($mode)', skipping"
    }
    
    print "------------------------------------------------------------"
    print ""
  } catch {|err|
    let error_msg = (try { $err.msg } catch { "Unknown error" })
    print $"WARNING: Build cache prune failed: ($error_msg)"
  }
}
