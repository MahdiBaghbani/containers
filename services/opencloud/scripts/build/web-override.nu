#!/usr/bin/env nu
# Web asset override for the opencloud generate stage.
# Reads OPENCLOUD_WEB_* env vars; builds web from local or git source when
# override is enabled; always runs make node-generate-prod at /opencloud.
# Makefile patching is inlined; no dependency on patch-web-makefile.nu.

# Returns first line index after the recipe block beginning at rule_idx.
def find-recipe-end [lines: list<string>, rule_idx: int]: nothing -> int {
    let total = $lines | length
    mut j = $rule_idx + 1
    while $j < $total {
        if not ($lines | get $j | str starts-with "\t") {
            return $j
        }
        $j = $j + 1
    }
    $j
}

# Returns true if line is a Makefile rule for the given target at column 0.
# Rejects variable assignments like target:= and target:= value.
def is-target-rule [line: string, target: string]: nothing -> bool {
    let prefix = $"($target):"
    if not ($line | str starts-with $prefix) {
        return false
    }
    let prefix_len = $prefix | str length
    let rest = $line | str substring $prefix_len..
    (($rest | is-empty) or ($rest | str starts-with " ") or ($rest | str starts-with "\t"))
}

# Returns true if any .PHONY line in the file already declares the target.
def has-phony-target [lines: list<string>, target: string]: nothing -> bool {
    $lines | any {|l|
        if not ($l | str starts-with ".PHONY:") {
            false
        } else {
            let phony_targets = (
                $l
                | str replace ".PHONY:" ""
                | split row " "
                | each {|t| $t | str trim}
                | where {|t| not ($t | is-empty)}
            )
            $target in $phony_targets
        }
    }
}

# Replaces or stubs one target rule in lines. Ensures .PHONY is declared.
# If the target appears multiple times, keeps exactly one stub; removes extras.
def patch-target [
    lines: list<string>
    target: string
    message: string
]: nothing -> list<string> {
    let phony_line = $".PHONY: ($target)"
    let stub = [$"($target):", $"\t@echo \"($message)\""]
    let has_phony = has-phony-target $lines $target
    let has_target = $lines | any {|l| is-target-rule $l $target}

    if not $has_target {
        mut result = $lines
        if not $has_phony {
            $result = ($result | append $phony_line)
        }
        $result = ($result | append $stub)
        return $result
    }

    mut result = []
    mut stub_placed = false
    mut i = 0
    let total = $lines | length

    while $i < $total {
        let line = $lines | get $i
        if (is-target-rule $line $target) {
            if not $stub_placed {
                if not $has_phony {
                    $result = ($result | append $phony_line)
                }
                $result = ($result | append $stub)
                $stub_placed = true
            }
            $i = find-recipe-end $lines $i
        } else {
            $result = ($result | append $line)
            $i = $i + 1
        }
    }

    $result
}

# Patches a Makefile by replacing named target recipes with no-op stubs.
def patch-makefile [
    makefile: path
    targets: list<string>
    message: string
]: nothing -> nothing {
    mut lines = open --raw $makefile | split row "\n"
    for target in $targets {
        $lines = patch-target $lines $target $message
    }
    if ($lines | is-empty) or (($lines | last) != "") {
        $lines = ($lines | append "")
    }
    $lines | str join "\n" | save --force $makefile
}

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
    let mode = $env.OPENCLOUD_WEB_MODE? | default ""
    let url = $env.OPENCLOUD_WEB_URL? | default ""
    let ref_ = $env.OPENCLOUD_WEB_REF? | default ""
    let sha = $env.OPENCLOUD_WEB_SHA? | default ""
    let ref_kind = $env.OPENCLOUD_WEB_REF_KIND? | default ""
    let node_opts = $env.OPENCLOUD_WEB_NODE_OPTIONS? | default ""

    let override_enabled = (($mode == "local") or (not ($url | is-empty)))

    if $override_enabled {
        if (not ($url | is-empty)) and ($ref_ | is-empty) {
            error make {msg: "OPENCLOUD_WEB_REF is required when OPENCLOUD_WEB_URL is set"}
        }

        let work_dir = "/tmp/opencloud-web"
        let git_cache = "/src/opencloud-web-git-cache"
        let clone_mode = (if $mode == "local" { "local" } else { "git" })

        ^rm -rf $work_dir
        ^mkdir -p $work_dir

        ^nu /usr/local/bin/clone-source.nu --mode $clone_mode --url $url --ref $ref_ --ref-kind $ref_kind --local-dir /mnt/web --cache-dir $git_cache --dest $work_dir

        if ($clone_mode == "git") and (not ($sha | is-empty)) {
            checkout-sha $work_dir $sha
        }

        if not ($node_opts | is-empty) {
            $env.NODE_OPTIONS = $node_opts
        }

        ^make -C $work_dir dist

        let assets_core = "/opencloud/services/web/assets/core"
        ^rm -rf $assets_core
        ^mkdir -p $assets_core
        ^tar xzf $"($work_dir)/release/web.tar.gz" -C $assets_core

        patch-makefile "/opencloud/services/web/Makefile" ["pull-assets", "download-assets"] "DockyPody: using preseeded OpenCloud Web assets"
    }

    ^make node-generate-prod
}
