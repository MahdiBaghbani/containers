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

# Source handling: local source context preparation and SHA extraction
# See docs/concepts/build-system.md for architecture

use ../validate/core.nu [validate-local-path]

# Check if git is available before attempting SHA extraction
export def check-git-available [] {
    try {
        let result = (^git --version | complete)
        $result.exit_code == 0
    } catch {
        false
    }
}

# Extract SHA for a single source (with caching support)
export def extract-source-sha [
    url: string,
    ref: string,
    service: string,
    source_key: string,
    cache: record = {}
] {
    # Check cache first
    let cache_key = $"($url):($ref)"
    let cached = (try { $cache | get $cache_key } catch { null })
    if $cached != null {
        return {sha: $cached, cache: $cache}
    }

    # Handle case where ref is already a SHA (7-40 hex chars)
    let sha_check = ($ref | str replace --regex '^[0-9a-f]{7,40}$' "MATCHED")
    if $sha_check == "MATCHED" {
        let short_sha = ($ref | str substring 0..6)
        let updated_cache = ($cache | upsert $cache_key $short_sha)
        return {sha: $short_sha, cache: $updated_cache}
    }

    # Check git availability
    if not (check-git-available) {
        print $"WARNING: [($service)] git not available, skipping SHA extraction for source '($source_key)' (ref: ($ref))"
        let updated_cache = ($cache | upsert $cache_key "")
        return {sha: "", cache: $updated_cache}
    }

    # Use git ls-remote for performance (no clone needed)
    try {
        let output_lines = (^git ls-remote $url $ref | lines)

        if ($output_lines | is-empty) {
            print $"WARNING: [($service)] Ref '($ref)' not found in repository ($url) for source '($source_key)'. Source revision label will indicate missing revision."
            let updated_cache = ($cache | upsert $cache_key "")
            return {sha: "", cache: $updated_cache}
        }

        # Handle multiple matches (prefer exact ref match, then peeled tag)
        # git ls-remote output format: SHA<TAB>ref or SHA<TAB>ref^{} (peeled)
        let matched_line = ($output_lines | where {|line| ($line | str contains $ref) } | first)

        if ($matched_line | str length) == 0 {
            # Fallback: use first line if no exact match
            let matched_line = ($output_lines | first)
        }

        # Parse: git ls-remote format is "SHA<TAB>ref" - SHA is always first 40 hex chars
        let sha_full = ($matched_line | str substring 0..39)

        # Validate SHA format (must be 40 hex chars)
        let sha_validation = ($sha_full | str replace --regex '^[0-9a-f]{40}$' "VALID")
        if $sha_validation != "VALID" {
            print $"WARNING: [($service)] Invalid SHA format from git ls-remote for source '($source_key)' (ref: ($ref)): ($sha_full)"
            let updated_cache = ($cache | upsert $cache_key "")
            return {sha: "", cache: $updated_cache}
        }

        let short_sha = ($sha_full | str substring 0..6)
        let updated_cache = ($cache | upsert $cache_key $short_sha)
        return {sha: $short_sha, cache: $updated_cache}
    } catch {|err|
        print $"WARNING: [($service)] Failed to extract SHA for source '($source_key)' (($url)@($ref)): ($err.msg)"
        print $"  Source revision label will indicate missing revision."
        let updated_cache = ($cache | upsert $cache_key "")
        return {sha: "", cache: $updated_cache}
    }
}

# Extract SHAs for all sources in a record
export def extract-source-shas [
    sources: record,
    service: string,
    cache: record = {}
] {
    # Use reduce to accumulate shas and cache (for loops don't work with mut variables in Nushell)
    let result = ($sources | columns | reduce --fold {shas: {}, cache: $cache} {|source_key, acc|
        let source = ($sources | get $source_key)
        
        # CRITICAL: Check for path field FIRST - skip SHA extraction for local sources
        # This provides defense-in-depth: even if validation missed a mutual exclusivity violation,
        # we still skip SHA extraction for sources with path field
        if "path" in ($source | columns) {
            # Local source - skip SHA extraction, return empty SHA
            let sha_key = ($"($source_key | str upcase)_SHA")
            {
                shas: ($acc.shas | upsert $sha_key ""),
                cache: $acc.cache
            }
        } else {
            # Git source - proceed with SHA extraction
            let url = (try { $source.url } catch { "" })
            let ref = (try { $source.ref } catch { "" })

            if ($url | str length) > 0 and ($ref | str length) > 0 {
                let sha_result = (extract-source-sha $url $ref $service $source_key $acc.cache)
                let sha_key = ($"($source_key | str upcase)_SHA")
                {
                    shas: ($acc.shas | upsert $sha_key $sha_result.sha),
                    cache: $sha_result.cache
                }
            } else {
                let ref_display = (if ($ref | str length) > 0 { $ref } else { "unknown" })
                print $"WARNING: [($service)] Source '($source_key)' missing url or ref. Skipping SHA extraction."
                let sha_key = ($"($source_key | str upcase)_SHA")
                {
                    shas: ($acc.shas | upsert $sha_key ""),
                    cache: $acc.cache
                }
            }
        }
    })

    $result
}

# Prepare local sources context by copying local source directories into build context
# Returns record mapping source_key -> resolved_path_in_context (paths relative to context root for Docker)
# Note: Copied sources are left in .build-sources/ after build for debugging (consistent with TLS helper pattern)
export def prepare-local-sources-context [
    service: string,
    context: string,
    sources: record,
    source_types: record,
    repo_root: string
] {
    # Filter to only local sources
    let local_source_keys = ($sources | columns | where {|k| ($source_types | get $k | default "git") == "local"})
    
    if ($local_source_keys | is-empty) {
        return {}
    }
    
    # Resolve context to absolute path (if relative, resolve relative to repo root)
    let resolved_context = (if ($context | path expand | str starts-with "/") {
        ($context | path expand)
    } else {
        ($repo_root | path join $context | path expand)
    })
    
    # Create .build-sources directory in context
    let build_sources_dir = ($resolved_context | path join ".build-sources")
    mkdir $build_sources_dir
    
    # Process each local source
    let resolved_paths = ($local_source_keys | reduce --fold {} {|source_key, acc|
        let source = ($sources | get $source_key)
        let path_value = (try { $source.path } catch { "" })
        
        if ($path_value | str length) == 0 {
            error make {msg: $"Local source '($source_key)' has empty path field"}
        }
        
        # Resolve path relative to repo root
        let resolved_source_path = (if ($path_value | path expand | str starts-with "/") {
            # Absolute path - validate it's within repo root
            let abs_path = ($path_value | path expand)
            let repo_root_expanded = ($repo_root | path expand)
            if not ($abs_path | str starts-with $repo_root_expanded) {
                error make {msg: $"Local source '($source_key)' path '($path_value)' is outside repository root"}
            }
            $abs_path
        } else {
            # Relative path - resolve relative to repo root
            ($repo_root | path join $path_value | path expand)
        })
        
        # Validate path exists and is directory
        let path_validation = (validate-local-path $resolved_source_path $repo_root)
        if not $path_validation.valid {
            error make {msg: ($"Local source '($source_key)' path validation failed: " + ($path_validation.errors | str join "; "))}
        }
        
        # Check directory size and warn if large (>100MB)
        let dir_size_bytes = (try {
            (ls -a $resolved_source_path | get size | math sum)
        } catch {
            0
        })
        # Convert to MB (1MB = 1,048,576 bytes) - convert to int for comparison
        let dir_size_int = ($dir_size_bytes | into int)
        let size_mb = ($dir_size_int / 1048576)
        if $size_mb > 100 {
            let size_mb_str = ($size_mb | into string | str substring 0..5)
            print $"WARNING: [($service)] Local source '($source_key)' directory is large \(($size_mb_str) MB\). This may slow down builds."
        }
        
        # Copy source directory to build context
        let target_dir = ($build_sources_dir | path join $source_key)
        # Remove target directory if it exists (cleanup from previous builds)
        try {
            if ($target_dir | path exists) {
                rm -rf $target_dir
            }
        } catch {|err|
            error make {msg: $"Failed to remove existing target directory '($target_dir)': ($err.msg)"}
        }
        # Use cp -rL to follow symlinks (matches git clone behavior)
        # Note: Nushell's cp command follows symlinks by default, but we use ^cp for explicit control
        try {
            ^cp -rL $resolved_source_path $target_dir
        } catch {|err|
            error make {msg: $"Failed to copy local source '($source_key)' from '($resolved_source_path)' to '($target_dir)': ($err.msg)"}
        }
        
        # Return resolved path relative to context root (for Docker COPY commands)
        let resolved_path_in_context = $".build-sources/($source_key)"
        $acc | upsert $source_key $resolved_path_in_context
    })
    
    $resolved_paths
}
