#!/usr/bin/env nu
# Reva override for the ocis build stage.
# Reads OCIS_REVA_* env vars; clones or copies reva when override is
# enabled; applies go mod replace and runs go mod download.

def checkout-sha [work_dir: string, sha: string]: nothing -> nothing {
    let first = (^git -C $work_dir checkout $sha | complete)
    if $first.exit_code == 0 {
        return
    }
    ^git -C $work_dir fetch --depth 1 origin $sha
    let second = (^git -C $work_dir checkout $sha | complete)
    if $second.exit_code != 0 {
        error make {
            msg: $"Failed to checkout SHA ($sha) in ($work_dir). The clone may be too shallow; ensure the SHA is reachable from REF or fetch with full depth."
        }
    }
}

def main [] {
    let mode = $env.OCIS_REVA_MODE? | default ""
    let url = $env.OCIS_REVA_URL? | default ""
    let ref_ = $env.OCIS_REVA_REF? | default ""
    let sha = $env.OCIS_REVA_SHA? | default ""
    let ref_kind = $env.OCIS_REVA_REF_KIND? | default ""
    let goproxy = $env.GO_BUILD_GOPROXY? | default ""

    let override_enabled = (($mode == "local") or (not ($url | is-empty)))

    if not $override_enabled {
        return
    }

    if (not ($url | is-empty)) and ($ref_ | is-empty) {
        error make {msg: "OCIS_REVA_REF is required when OCIS_REVA_URL is set"}
    }

    let work_dir = "/src/ocis-reva"
    let git_cache = "/src/ocis-reva-git-cache"
    let clone_mode = (if $mode == "local" { "local" } else { "git" })

    ^rm -rf $work_dir
    ^mkdir -p $work_dir

    ^nu /usr/local/bin/clone-source.nu --mode $clone_mode --url $url --ref $ref_ --ref-kind $ref_kind --local-dir /mnt/reva --cache-dir $git_cache --dest $work_dir

    if ($clone_mode == "git") and (not ($sha | is-empty)) {
        checkout-sha $work_dir $sha
    }

    ^go mod edit $"-replace=github.com/owncloud/reva/v2=($work_dir)"

    if not ($goproxy | is-empty) {
        with-env {GOPROXY: $goproxy} { ^go mod download }
    } else {
        ^go mod download
    }
}
