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

# Temp fixture helpers for docs-lint suite tests.

# Write raw content to a fresh temp .md file and return its path.
export def make-fixture [content: string] {
    let dir = (mktemp -d)
    let file = ($dir | path join "doc.md")
    $content | save -f $file
    $file
}

# Remove a fixture file and its temp directory.
export def cleanup-fixture [file: string] {
    let dir = ($file | path dirname)
    rm -rf $dir
}

export def make-git-discovery-fixture [] {
    let dir = (mktemp -d)

    mkdir ($dir | path join "docs")
    mkdir ($dir | path join ".build-sources/vendor")
    mkdir ($dir | path join "node_modules/pkg")

    "# Repo doc\n\nclean ascii\n" | save -f ($dir | path join "README.md")
    "# Guide\n\nclean ascii\n" | save -f ($dir | path join "docs/guide.md")
    $"ignored \u{2014} generated\n" | save -f ($dir | path join ".build-sources/vendor/README.md")
    $"ignored \u{2014} vendor\n" | save -f ($dir | path join "node_modules/pkg/README.md")

    ".build-sources/\nnode_modules/\n" | save -f ($dir | path join ".gitignore")

    let init = (^git -C $dir init --quiet | complete)
    if $init.exit_code != 0 {
        rm -rf $dir
        error make {msg: $"git init failed: ($init.stderr)"}
    }

    let add = (^git -C $dir add README.md docs/guide.md .gitignore | complete)
    if $add.exit_code != 0 {
        rm -rf $dir
        error make {msg: $"git add failed: ($add.stderr)"}
    }

    $dir
}

# Parser fixture bodies for docs freshness (service/version + Nushell refs).
export def freshness-fixture-clone-source [] {
    $"
# Clone source docs

Copy `scripts/lib/clone-source.nu` into the build context.

```dockerfile
COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu
RUN nu /tmp/clone-source.nu --mode local --local-dir .build-sources/reva
```

Local dirs land under `.build-sources/{source_key}/`.
"
}

export def freshness-fixture-placeholder [] {
    "nu scripts/dockypody.nu build --service my-service --version v1.0.0\n"
}

export def freshness-fixture-external-url [] {
    "See upstream https://example.com/revad-base:v3.3.3 for history.\n"
}

export def freshness-fixture-live-path [live_tag: string = "v3.10.1"] {
    $"# Live\n\nImage `revad-base:($live_tag)` is current.\n"
}

export def freshness-fixture-stale-path [stale_tag: string = "v3.3.3"] {
    # Image-only qualified tag (no --service/--version). Must be detected.
    $"# Stale\n\n- Example: `revad-base:($stale_tag)`\n"
}

export def freshness-fixture-allow-comment [stale_tag: string = "v3.3.3"] {
    $"<!-- dockypody-docs-allow: revad-base:($stale_tag) -->\n# Historical\n\nKept for context: `revad-base:($stale_tag)`.\n"
}

export def freshness-fixture-nushell-machine-ok [] {
    "Pin with `NUSHELL_REF=0.113.1` and `\"ref\": \"0.113.1\"`.\n"
}

export def freshness-fixture-nushell-machine-stale [] {
    "Pin with `NUSHELL_REF=0.108.0`.\n"
}

export def freshness-fixture-nushell-prose-ok [] {
    "Requires Nushell 0.113 or later.\n"
}

export def freshness-fixture-nushell-prose-stale [] {
    "Requires Nushell 0.80 or later.\n"
}

