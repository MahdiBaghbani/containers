# SPDX-License-Identifier: AGPL-3.0-or-later
# Open Cloud Mesh Containers: container build scripts and images
# Copyright (C) 2025 Open Cloud Mesh Contributors
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

# Source repository SHA extraction utilities

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
