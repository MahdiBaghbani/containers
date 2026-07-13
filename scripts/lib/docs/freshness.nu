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

# Docs freshness lint: service:tag and --service/--version refs must match
# live versions.nuon / platforms.nuon. Machine Nushell pins must equal NU_PIN;
# prose Nushell mentions must be NU_PROSE_MIN or later. Escape hatch:
#   <!-- dockypody-docs-allow: <service>:<tag> -->
#   <!-- dockypody-docs-allow: nushell:<version> -->

use ../services/core.nu [list-service-names]
use ../manifest/core.nu [
  load-versions-manifest
  get-default-version
  check-versions-manifest-exists
]
use ../platforms/core.nu [
  check-platforms-manifest-exists
  load-platforms-manifest
  get-default-platform
]
use ../core/version.nu [NU_PIN]

# Prose floor: major.minor "0.113" (patch optional). Machine pin is NU_PIN.
const NU_PROSE_MIN = "0.113"

# Tracked markdown only (no untracked / local-plane). Differs from ASCII lint
# discovery, which may include untracked exclude-standard paths.
def discover-tracked-md-files [] {
  let repo_root_result = (try {
    ^git rev-parse --show-toplevel | complete
  } catch {
    {exit_code: 1, stdout: "", stderr: ""}
  })

  if $repo_root_result.exit_code != 0 {
    # Bounded fallback: do not glob the whole tree (can hang on large
    # vendor/build-source dirs when git is unavailable).
    return (
      (glob "docs/**/*.md")
      | append (glob "services/**/*.md")
      | append (glob "examples/**/*.md")
      | append (glob "*.md")
      | uniq
    )
  }

  let repo_root = ($repo_root_result.stdout | str trim)
  let ls_files_result = (try {
    ^git -C $repo_root ls-files --cached -- "*.md" | complete
  } catch {
    {exit_code: 1, stdout: "", stderr: ""}
  })

  if $ls_files_result.exit_code != 0 {
    return (
      (glob "docs/**/*.md")
      | append (glob "services/**/*.md")
      | append (glob "examples/**/*.md")
      | append (glob "*.md")
      | uniq
    )
  }

  $ls_files_result.stdout
  | lines
  | where {|line| not ($line | is-empty)}
  | each {|line| $repo_root | path join $line}
}

def resolve-files [files: list<string>] {
  if ($files | is-empty) {
    discover-tracked-md-files
  } else {
    $files
  }
}

# Strip http(s) URLs so path/host segments cannot look like service:tag refs.
def strip-external-urls [line: string] {
  $line | str replace --all --regex 'https?://\S+' ""
}

def version-parts [version: string] {
  let bits = ($version | split row ".")
  {
    major: ($bits.0 | into int)
    minor: ($bits.1 | into int)
    patch: (try { $bits.2 | into int } catch { 0 })
  }
}

def version-gte [current: string, minimum: string] {
  let c = (version-parts $current)
  let m = (version-parts $minimum)
  if $c.major != $m.major {
    $c.major > $m.major
  } else if $c.minor != $m.minor {
    $c.minor > $m.minor
  } else {
    $c.patch >= $m.patch
  }
}

# live = { service -> { versions, platforms, default_version, default_platform } }
# versions includes explicit version names plus generated aliases (at least
# "latest" when any versions[].latest is true).
export def build-live-index [] {
  mut live = {}
  for svc in (list-service-names) {
    if not (check-versions-manifest-exists $svc) {
      error make {msg: $"versions.nuon missing for service '($svc)'"}
    }
    let versions_manifest = (load-versions-manifest $svc)
    let version_names = ($versions_manifest.versions | get name)
    let default_version = (get-default-version $versions_manifest)

    let has_latest_alias = ($versions_manifest.versions | any {|v|
      (try { $v.latest } catch { false }) == true
    })
    let accepted_versions = if $has_latest_alias {
      ($version_names | append "latest" | uniq)
    } else {
      $version_names
    }

    let platforms_info = if (check-platforms-manifest-exists $svc) {
      let pm = (load-platforms-manifest $svc)
      {
        platforms: ($pm.platforms | get name)
        default_platform: (get-default-platform $pm)
      }
    } else {
      {platforms: null, default_platform: null}
    }

    $live = ($live | upsert $svc {
      versions: $accepted_versions
      platforms: $platforms_info.platforms
      default_version: $default_version
      default_platform: $platforms_info.default_platform
    })
  }
  $live
}

# Strip a trailing -<platform> only when that platform is live for the service.
export def strip-platform-suffix [tag: string, platforms: any] {
  if $platforms == null { return $tag }
  # Longest platform name first so compound names win over shorter prefixes.
  let ordered = ($platforms | sort-by {|p| ($p | str length)} --reverse)
  for p in $ordered {
    # Must be $"-($p)" - $"(-($p))" is parsed as unary-minus of $p.
    let suffix = $"-($p)"
    if ($tag | str ends-with $suffix) {
      return ($tag | str substring 0..<(($tag | str length) - ($suffix | str length)))
    }
  }
  $tag
}

def parse-allow-comments [text: string] {
  if not ($text | str contains "dockypody-docs-allow") {
    return []
  }
  let matches = ($text | parse --regex '<!--\s*dockypody-docs-allow:\s*(?P<service>[A-Za-z0-9._-]+):(?P<tag>[A-Za-z0-9._-]+)\s*-->')
  try { $matches } catch { [] }
}

def is-allowed [allows: list, service: string, tag: string] {
  $allows | any {|a| ($a.service == $service) and ($a.tag == $tag)}
}

def service-alt [live: record] {
  $live
  | columns
  | sort-by {|n| ($n | str length)} --reverse
  | str join "|"
}

# Extract {service, tag, kind} refs from one line.
# Optional precomputed $alt avoids rebuilding the service alternation per line.
export def extract-refs-from-line [
  line: string
  live: record
  alt: string = ""
] {
  mut refs = []
  let services = ($live | columns)
  if ($services | is-empty) {
    return []
  }

  let cleaned = (strip-external-urls $line)
  let has_cli = (
    ($cleaned | str contains "--service")
    or ($cleaned | str contains "--version")
    or ($cleaned | str contains "--versions")
  )
  let has_colon = ($cleaned | str contains ":")
  if (not $has_cli) and (not $has_colon) {
    return []
  }

  let service_alt = if ($alt | is-empty) { (service-alt $live) } else { $alt }

  # Image / prose tags: bare <service>:<tag>, or DockyPody GHCR paths
  # (.../containers/... or any ghcr.io/.../<service>:<tag>).
  # Do NOT use $"..." for named groups (Nushell treats (...) as expressions).
  # Reject path-embedded names like quay.io/jupyterhub/jupyterhub:5.3.0:
  # a leading "/" before the service name is not a bare ref, and non-ghcr
  # registries are not DockyPody image paths.
  if $has_colon {
    let bare_pat = (
      ["(?:^|[^/\\w])(?P<service>(", $service_alt, ")):(?P<tag>[A-Za-z0-9._-]+)"]
      | str join
    )
    let ghcr_pat = (
      ["ghcr\\.io/[^:\\s`\"']+/(?P<service>(", $service_alt, ")):(?P<tag>[A-Za-z0-9._-]+)"]
      | str join
    )
    let bare_matches = (try {
      $cleaned | parse --regex $bare_pat
    } catch { [] })
    let ghcr_matches = (try {
      $cleaned | parse --regex $ghcr_pat
    } catch { [] })
    for m in ($bare_matches | append $ghcr_matches) {
      $refs = ($refs | append {service: $m.service, tag: $m.tag, kind: "image-tag"})
    }
  }

  if not $has_cli {
    return $refs
  }

  # --service <svc> ... --version <ver> (same line; either order)
  if ($cleaned | str contains "--service") and ($cleaned | str contains "--version") {
    let svc_ver = (try {
      $cleaned | parse --regex '--service\s+(?P<service>[A-Za-z0-9._-]+).*?--version\s+(?P<tag>[A-Za-z0-9._-]+)'
    } catch { [] })
    for m in $svc_ver {
      if ($m.service in $services) {
        $refs = ($refs | append {service: $m.service, tag: $m.tag, kind: "cli-version"})
      }
    }
    let ver_svc = (try {
      $cleaned | parse --regex '--version\s+(?P<tag>[A-Za-z0-9._-]+).*?--service\s+(?P<service>[A-Za-z0-9._-]+)'
    } catch { [] })
    for m in $ver_svc {
      if ($m.service in $services) {
        $refs = ($refs | append {service: $m.service, tag: $m.tag, kind: "cli-version"})
      }
    }
  }

  # --service <svc> ... --versions a,b,c (same line)
  if ($cleaned | str contains "--service") and ($cleaned | str contains "--versions") {
    let svc_vers = (try {
      $cleaned | parse --regex '--service\s+(?P<service>[A-Za-z0-9._-]+).*?--versions\s+(?P<tags>[A-Za-z0-9._,-]+)'
    } catch { [] })
    for m in $svc_vers {
      if ($m.service in $services) {
        for t in ($m.tags | split row "," | each {|x| $x | str trim} | where {|x| not ($x | is-empty)}) {
          $refs = ($refs | append {service: $m.service, tag: $t, kind: "cli-versions"})
        }
      }
    }
  }

  $refs
}

# Machine pin patterns and prose Nushell version mentions.
export def extract-nushell-refs-from-line [line: string] {
  mut refs = []
  let cleaned = (strip-external-urls $line)
  let has_nushell = ($cleaned | str contains -i "nushell")
  let has_json_ref = ($cleaned | str contains '"ref"')
  if (not $has_nushell) and (not $has_json_ref) {
    return []
  }

  if $has_nushell {
    let machine_ref_env = (try {
      $cleaned | parse --regex 'NUSHELL_REF=(?P<version>[0-9]+\.[0-9]+(?:\.[0-9]+)?)'
    } catch { [] })
    for m in $machine_ref_env {
      $refs = ($refs | append {service: "nushell", tag: $m.version, kind: "nushell-machine"})
    }

    let machine_source_tag = (try {
      $cleaned | parse --regex '(?i)(?:^|[^A-Za-z0-9_-])nushell:(?P<version>[0-9]+\.[0-9]+(?:\.[0-9]+)?)'
    } catch { [] })
    for m in $machine_source_tag {
      $refs = ($refs | append {service: "nushell", tag: $m.version, kind: "nushell-machine"})
    }

    let machine_label_ref = (try {
      $cleaned | parse --regex '(?i)nushell\.ref=(?P<version>[0-9]+\.[0-9]+(?:\.[0-9]+)?)'
    } catch { [] })
    for m in $machine_label_ref {
      $refs = ($refs | append {service: "nushell", tag: $m.version, kind: "nushell-machine"})
    }

    let machine_tag_tick = (try {
      $cleaned | parse --regex 'tag\s+`(?P<version>[0-9]+\.[0-9]+(?:\.[0-9]+)?)`'
    } catch { [] })
    for m in $machine_tag_tick {
      $refs = ($refs | append {service: "nushell", tag: $m.version, kind: "nushell-machine"})
    }

    let prose = (try {
      $cleaned | parse --regex '(?i)Nushell\s+(?P<version>[0-9]+\.[0-9]+(?:\.[0-9]+)?)'
    } catch { [] })
    for m in $prose {
      $refs = ($refs | append {service: "nushell", tag: $m.version, kind: "nushell-prose"})
    }
  }

  # Bare "ref": "0.x.y" (no leading v) is the common-tools nushell pin shape.
  if $has_json_ref {
    let machine_json_ref = (try {
      $cleaned | parse --regex '"ref"\s*:\s*"(?P<version>[0-9]+\.[0-9]+(?:\.[0-9]+)?)"'
    } catch { [] })
    for m in $machine_json_ref {
      $refs = ($refs | append {service: "nushell", tag: $m.version, kind: "nushell-machine"})
    }
  }

  $refs
}

# Teaching / priority-demo tags that are not real manifest versions.
# Match only these exact bases after platform stripping; never skip vN.N.N.
export def is-generic-placeholder-tag [version: string] {
  $version in ["custom", "env-override", "testing", "ro"]
}

export def check-ref [live: record, service: string, tag: string] {
  let entry = (try { $live | get $service } catch { null })
  if $entry == null {
    return {ok: true, version: $tag, reason: "unknown-service-skipped"}
  }
  let version = (strip-platform-suffix $tag $entry.platforms)
  if (is-generic-placeholder-tag $version) {
    return {ok: true, version: $version, reason: "generic-placeholder-skipped"}
  }
  if ($version in $entry.versions) {
    {ok: true, version: $version, reason: "live"}
  } else {
    {
      ok: false
      version: $version
      reason: "unknown-version"
      live_versions: $entry.versions
    }
  }
}

export def check-nushell-ref [kind: string, version: string] {
  if $kind == "nushell-machine" {
    if $version == $NU_PIN {
      {ok: true, version: $version, reason: "machine-pin"}
    } else {
      {
        ok: false
        version: $version
        reason: "stale-machine-nushell"
        expected: $NU_PIN
      }
    }
  } else if $kind == "nushell-prose" {
    if (version-gte $version $NU_PROSE_MIN) {
      {ok: true, version: $version, reason: "prose-ok"}
    } else {
      {
        ok: false
        version: $version
        reason: "stale-prose-nushell"
        expected: $"($NU_PROSE_MIN) or later"
      }
    }
  } else {
    {ok: true, version: $version, reason: "ignored-kind"}
  }
}

export def scan-docs-freshness [
  files: list<string>
  live: record
] {
  let alt = (service-alt $live)
  mut violations = []
  for file in $files {
    if not ($file | path exists) { continue }
    let text = (open --raw $file)
    let file_allows = (parse-allow-comments $text)
    let lines = ($text | lines | enumerate)
    for line_data in $lines {
      let line_num = ($line_data.index + 1)
      let line = $line_data.item
      let line_allows = (parse-allow-comments $line)
      let allows = ($file_allows | append $line_allows)

      let refs = (extract-refs-from-line $line $live $alt)
      for r in $refs {
        if (is-allowed $allows $r.service $r.tag) { continue }
        let result = (check-ref $live $r.service $r.tag)
        if not $result.ok {
          $violations = ($violations | append {
            file: $file
            line: $line_num
            service: $r.service
            tag: $r.tag
            version: $result.version
            live: $result.live_versions
            kind: $r.kind
            reason: $result.reason
          })
        }
      }

      let nu_refs = (extract-nushell-refs-from-line $line)
      for r in $nu_refs {
        if (is-allowed $allows $r.service $r.tag) { continue }
        let result = (check-nushell-ref $r.kind $r.tag)
        if not $result.ok {
          $violations = ($violations | append {
            file: $file
            line: $line_num
            service: $r.service
            tag: $r.tag
            version: $result.version
            live: (try { [$result.expected] } catch { [] })
            kind: $r.kind
            reason: $result.reason
          })
        }
      }
    }
  }
  $violations
}

def print-violations [violations: list] {
  print $"ERROR: Found ($violations | length) docs freshness violation\(s\):"
  print ""
  for v in $violations {
    if ($v.kind | str starts-with "nushell-") {
      let expected = (try { $v.live | first } catch { "?" })
      print $"($v.file):($v.line): bad Nushell ($v.kind) version '($v.version)' \(expected: ($expected)\)"
    } else {
      let live_list = ($v.live | str join ", ")
      print $"($v.file):($v.line): unknown version '($v.version)' for service '($v.service)' \(live: ($live_list)\)"
    }
  }
}

# Returns true when clean.
export def lint-docs-refs [
  files: list<string> = []
] {
  if not ($files | is-empty) {
    let missing = ($files | where {|f| not ($f | path exists)})
    if not ($missing | is-empty) {
      for f in $missing { print $"ERROR: File not found: ($f)" }
      return false
    }
  }

  print "docs freshness: discovering tracked markdown..."
  let files_to_check = (resolve-files $files)
  print $"docs freshness: scanning ($files_to_check | length) file\(s\)..."
  let live = (build-live-index)
  let violations = (scan-docs-freshness $files_to_check $live)

  if ($violations | is-empty) {
    print "OK: No docs freshness violations found"
    return true
  }

  print-violations $violations
  print ""
  print "Escape hatch: <!-- dockypody-docs-allow: <service>:<tag> -->"
  false
}
