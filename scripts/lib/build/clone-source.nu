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

# Clone or copy a build source into a destination directory.
# See docs/concepts/build-system.md
# Note: This file is also copied to Docker build context and run standalone.
#
# Contract (flags or equivalent env vars):
#   SOURCE_MODE=local     -> copy SOURCE_LOCAL_DIR into SOURCE_DEST
#   SOURCE_REF_KIND=ref   -> git clone --depth 1 [--recursive --shallow-submodules] --branch
#   SOURCE_REF_KIND=sha   -> git init + remote add + fetch SHA + checkout FETCH_HEAD
#   SOURCE_REF_KIND unset -> auto-detected from SOURCE_REF (full 40-hex -> sha, else ref)
#   SOURCE_CACHE_DIR      -> optional git cache dir; reuse when populated (has .git),
#                            otherwise (re)fetch into it, then copy into SOURCE_DEST
#   SOURCE_SUBMODULES     -> optional submodule update (default: recurse on)

def strip-quotes [value: string] {
    let trimmed = ($value | str trim)
    let len = ($trimmed | str length)
    if $len < 2 {
        return $trimmed
    }
    if ($trimmed | str starts-with "'") and ($trimmed | str ends-with "'") {
        return ($trimmed | str substring 1..($len - 2))
    }
    if ($trimmed | str starts-with '"') and ($trimmed | str ends-with '"') {
        return ($trimmed | str substring 1..($len - 2))
    }
    $trimmed
}

def normalize-bool [value: string, param_name: string] {
    let normalized = (strip-quotes $value | str downcase)
    if $normalized == "true" {
        return true
    }
    if $normalized == "false" or $normalized == "" {
        return false
    }
    error make {msg: $"Invalid value for ($param_name): '($value)'. Expected 'true' or 'false'."}
}

def is-full-sha [value: string] {
    ($value | str replace --regex '^[0-9a-fA-F]{40}$' "MATCHED") == "MATCHED"
}

# Infer whether a git ref is a full commit SHA or a branch/tag name.
def detect-ref-kind [ref: string] {
    if (is-full-sha ($ref | str trim)) { "sha" } else { "ref" }
}

# Copy the contents of src into dest (equivalent to `cp -a src/. dest`),
# creating dest if needed.
def copy-tree [src: string, dest: string] {
    if not ($dest | path exists) {
        mkdir $dest
    }
    ^cp -a $"($src)/." $dest
}

# Remove the contents of dir while keeping dir itself. Safe for BuildKit cache
# mounts, where the target is a mount point that cannot be removed directly.
def clear-dir [dir: string] {
    if ($dir | path exists) {
        for entry in (ls -a $dir) {
            rm -rf $entry.name
        }
    }
}

def run-git [cwd: string, args: list<string>, label: string] {
    let result = (if ($cwd | str trim | is-empty) {
        (^git ...$args | complete)
    } else {
        (^git -C $cwd ...$args | complete)
    })
    if $result.exit_code != 0 {
        let stderr = (try { $result.stderr | str trim } catch { "" })
        let stdout = (try { $result.stdout | str trim } catch { "" })
        let detail_raw = (if ($stderr | str length) > 0 { $stderr } else { $stdout })
        let detail = ($detail_raw | str replace -r '\s+' ' ' | str trim)
        error make {
            msg: $"git ($label) failed (exit ($result.exit_code)): ($detail)"
        }
    }
}

def update-submodules [dest: string, recurse: bool] {
    if not $recurse {
        return
    }
    run-git $dest ["submodule" "update" "--init" "--recursive"] "submodule update --init --recursive"
}

def clone-local [local_dir: string, dest: string] {
    if ($local_dir | str trim | is-empty) {
        error make {msg: "SOURCE_LOCAL_DIR must be provided when SOURCE_MODE=local"}
    }
    if not ($local_dir | path exists) {
        error make {msg: $"Local source directory not found: ($local_dir)"}
    }
    mkdir $dest
    ^cp -a $"($local_dir)/." $dest
    print $"OK: copied local source from ($local_dir) to ($dest)"
}

def clone-git-ref [url: string, ref: string, dest: string, recurse: bool] {
    if ($url | str trim | is-empty) {
        error make {msg: "SOURCE_URL must be provided for git sources"}
    }
    if ($ref | str trim | is-empty) {
        error make {msg: "SOURCE_REF must be provided when SOURCE_REF_KIND=ref"}
    }
    # git clone accepts a non-existent dest or an existing empty dir.
    if ($dest | path exists) {
        let entries = (try { ls -a $dest | length } catch { 0 })
        if $entries > 0 {
            error make {msg: $"Destination exists and is not empty: ($dest). Remove it before cloning."}
        }
    }
    let parent = ($dest | path dirname)
    if ($parent | str length) > 0 and not ($parent | path exists) {
        mkdir $parent
    }
    let recurse_args = (if $recurse { ["--recursive" "--shallow-submodules"] } else { [] })
    mut clone_args = (["clone" "--depth" "1"] | append $recurse_args | append ["--branch" $ref $url $dest])
    run-git "" $clone_args "clone --branch"
    update-submodules $dest $recurse
    print $"OK: cloned ($url) @ ref ($ref) into ($dest)"
}

def clone-git-sha [url: string, sha: string, dest: string, recurse: bool] {
    if ($url | str trim | is-empty) {
        error make {msg: "SOURCE_URL must be provided for git sources"}
    }
    if not (is-full-sha $sha) {
        error make {msg: $"SOURCE_REF must be a full 40-character SHA when SOURCE_REF_KIND=sha, got: '($sha)'"}
    }
    if ($dest | path exists) {
        let entries = (try { ls -a $dest | length } catch { 0 })
        if $entries > 0 {
            error make {msg: $"Destination not empty: ($dest). Remove it before cloning by SHA."}
        }
    } else {
        mkdir $dest
    }
    run-git $dest ["init"] "init"
    run-git $dest ["remote" "add" "origin" $url] "remote add origin"
    run-git $dest ["fetch" "--depth" "1" "origin" $sha] "fetch origin SHA"
    run-git $dest ["checkout" "FETCH_HEAD"] "checkout FETCH_HEAD"
    update-submodules $dest $recurse
    print $"OK: fetched ($url) @ sha ($sha) into ($dest)"
}

# Fetch a git source (branch/tag or full SHA) into target using the ref-kind.
def fetch-git-source [url: string, ref: string, ref_kind: string, target: string, recurse: bool] {
    if $ref_kind == "ref" {
        clone-git-ref $url $ref $target $recurse
    } else if $ref_kind == "sha" {
        clone-git-sha $url $ref $target $recurse
    } else {
        error make {msg: $"Invalid SOURCE_REF_KIND: '($ref_kind)'. Expected 'ref' or 'sha'."}
    }
}

export def run-clone-source [
    --mode: string,
    --ref-kind: string = "",
    --url: string = "",
    --ref: string = "",
    --local-dir: string = "",
    --cache-dir: string = "",
    --dest: string,
    --submodules: string = "true",
] {
    let mode_norm = (strip-quotes $mode | str downcase)
    let ref_kind_raw = (strip-quotes $ref_kind | str downcase)
    let url_norm = (strip-quotes $url)
    let ref_norm = (strip-quotes $ref)
    let local_dir_norm = (strip-quotes $local_dir)
    let cache_dir_norm = (strip-quotes $cache_dir)
    let dest_norm = (strip-quotes $dest)
    let recurse = (normalize-bool $submodules "SOURCE_SUBMODULES")

    if ($dest_norm | str trim | is-empty) {
        error make {msg: "SOURCE_DEST must be provided"}
    }

    if $mode_norm == "local" {
        clone-local $local_dir_norm $dest_norm
        return
    }

    # Git modes: honor an explicit ref-kind, otherwise infer it from the ref.
    let ref_kind_norm = (if ($ref_kind_raw | str trim | is-not-empty) {
        $ref_kind_raw
    } else {
        detect-ref-kind $ref_norm
    })

    if $ref_kind_norm != "ref" and $ref_kind_norm != "sha" {
        error make {
            msg: ($"Invalid SOURCE_MODE/SOURCE_REF_KIND: mode='($mode_norm)' ref_kind='($ref_kind_norm)'. " +
                  "Expected SOURCE_MODE=local or SOURCE_REF_KIND=ref|sha with git URL and ref.")
        }
    }

    # No cache: fetch straight into the destination (back-compat behavior).
    if ($cache_dir_norm | str trim | is-empty) {
        fetch-git-source $url_norm $ref_norm $ref_kind_norm $dest_norm $recurse
        return
    }

    # Cache-backed: reuse a populated cache when present, otherwise clear any
    # partial contents and (re)fetch into the cache, then copy into the
    # destination. Contents are cleared in place so a BuildKit cache mount
    # point is never removed.
    let cache_git = ($cache_dir_norm | path join ".git")
    if ($cache_git | path exists) {
        print $"OK: reusing populated cache at ($cache_dir_norm)"
    } else {
        clear-dir $cache_dir_norm
        fetch-git-source $url_norm $ref_norm $ref_kind_norm $cache_dir_norm $recurse
    }
    copy-tree $cache_dir_norm $dest_norm
    print $"OK: populated ($dest_norm) from cache ($cache_dir_norm)"
}

def main [
    --mode: string = "",
    --ref-kind: string = "",
    --url: string = "",
    --ref: string = "",
    --local-dir: string = "",
    --cache-dir: string = "",
    --dest: string = "",
    --submodules: string = "true",
] {
    let mode_val = (if ($mode | str trim | is-not-empty) { $mode } else { try { $env.SOURCE_MODE } catch { "" } })
    let ref_kind_val = (if ($ref_kind | str trim | is-not-empty) { $ref_kind } else { try { $env.SOURCE_REF_KIND } catch { "" } })
    let url_val = (if ($url | str trim | is-not-empty) { $url } else { try { $env.SOURCE_URL } catch { "" } })
    let ref_val = (if ($ref | str trim | is-not-empty) { $ref } else { try { $env.SOURCE_REF } catch { "" } })
    let local_dir_val = (if ($local_dir | str trim | is-not-empty) { $local_dir } else { try { $env.SOURCE_LOCAL_DIR } catch { "" } })
    let cache_dir_val = (if ($cache_dir | str trim | is-not-empty) { $cache_dir } else { try { $env.SOURCE_CACHE_DIR } catch { "" } })
    let dest_val = (if ($dest | str trim | is-not-empty) { $dest } else { try { $env.SOURCE_DEST } catch { "" } })
    let submodules_val = (if ($submodules | str trim | is-not-empty) { $submodules } else { try { $env.SOURCE_SUBMODULES } catch { "true" } })

    run-clone-source --mode $mode_val --ref-kind $ref_kind_val --url $url_val --ref $ref_val --local-dir $local_dir_val --cache-dir $cache_dir_val --dest $dest_val --submodules $submodules_val
}
