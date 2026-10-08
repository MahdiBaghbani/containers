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

# Parse-check every tracked Nushell script; resolve image-staged imports in memory.

use ../../lib/core/repo.nu [get-repo-root]
use ../lib.nu [run-test]

const STAGED_IMPORT_FILES = [
  "services/mitmproxy/scripts/entrypoint-init.nu"
  "services/nextcloud-base/scripts/entrypoint-init.nu"
  "services/revad-base/scripts/entrypoint-init.nu"
  "services/ocis/scripts/entrypoint-init.nu"
  "services/opencloud/scripts/entrypoint-init.nu"
  "services/nextcloud/scripts/hooks/00-start-log-tailing.nu"
  "services/nextcloud-contacts/scripts/hooks/before-starting/90-ensure-contacts.nu"
  "services/nextcloud-contacts/scripts/hooks/post-installation/90-enable-contacts.nu"
  "services/nextcloud-contacts/scripts/hooks/post-installation/91-enable-contacts-ocm-invites.nu"
  "services/nextcloud-webapp/scripts/hooks/before-starting/90-ensure-integration-jupyterhub.nu"
  "services/nextcloud-webapp/scripts/hooks/before-starting/91-ensure-ocmremotewebapp.nu"
  "services/nextcloud-webapp/scripts/hooks/post-installation/90-enable-integration-jupyterhub.nu"
  "services/nextcloud-webapp/scripts/hooks/post-installation/91-configure-integration-jupyterhub.nu"
  "services/nextcloud-webapp/scripts/hooks/post-installation/92-enable-ocmremotewebapp.nu"
]

const REGRESSION_GLOB = "scripts/tests/services/hook-parse-regression/*.nu"

def list-tracked-nu-files [repo_root: string] {
  let git_result = (
    ^git -C $repo_root ls-files "*.nu"
    | lines
    | where {|p| ($p | str trim) != "" }
  )
  let regression = (
    glob ($repo_root | path join $REGRESSION_GLOB)
    | each {|p| $p | path relative-to $repo_root }
  )
  ($git_result | append $regression | uniq | sort)
}

def list-parse-pass-nu-files [repo_root: string] {
  list-tracked-nu-files $repo_root
  | where {|p|
    not ($p | str starts-with "scripts/tests/services/hook-parse-regression/")
  }
}

def collect-ide-check-errors [stdout: string, stderr: string] {
  let combined = ([$stdout, $stderr] | str join "\n")
  mut errors = []
  for line in ($combined | lines | where {|l| ($l | str trim) != ""}) {
    let rec = (try { $line | from json } catch { null })
    if $rec == null {
      error make {msg: $"Malformed ide-check JSONL: ($line)"}
    }
    let typ = ($rec.type? | default "")
    if $typ == "error" {
      $errors = ($errors | append ($rec.message? | default $line))
    } else if $typ == "diagnostic" and ($rec.severity? | default "") == "Error" {
      $errors = ($errors | append ($rec.message? | default $line))
    }
  }
  $errors
}

def ordinary-parse-check [abs_file: string] {
  let result = (^nu --no-config-file --no-history --ide-check 100 $abs_file | complete)
  let errors = (collect-ide-check-errors $result.stdout $result.stderr)
  if $result.exit_code != 0 {
    error make {
      msg: $"($abs_file): ide-check exit ($result.exit_code): ($errors | str join '; ')"
    }
  }
  if not ($errors | is-empty) {
    error make {msg: $"($abs_file): ($errors | str join '; ')"}
  }
  true
}

def apply-staged-import-subs [repo_root: string, rel_path: string]: string -> string {
  let content = $in
  let sshd_host = ($repo_root | path join "scripts/lib/ssh/sshd.nu")
  let utils_host = ($repo_root | path join "services/nextcloud-base/scripts/lib/utils.nu")
  let log_tailing_host = (
    $repo_root | path join "services/nextcloud-base/scripts/lib/log-tailing.nu"
  )
  let ocis_ocm_host = ($repo_root | path join "services/ocis/scripts/lib/ocmproviders.nu")
  let opencloud_ocm_host = (
    $repo_root | path join "services/opencloud/scripts/lib/ocmproviders.nu"
  )

  mut c = $content
  match $rel_path {
    "services/mitmproxy/scripts/entrypoint-init.nu"
    | "services/nextcloud-base/scripts/entrypoint-init.nu"
    | "services/revad-base/scripts/entrypoint-init.nu" => {
      $c = ($c | str replace -a "use ./lib/sshd.nu [" $"use ($sshd_host) [")
    }
    "services/ocis/scripts/entrypoint-init.nu" => {
      $c = ($c | str replace -a "use /usr/bin/lib/sshd.nu [" $"use ($sshd_host) [")
      $c = ($c | str replace -a "use /usr/bin/lib/ocmproviders.nu [" $"use ($ocis_ocm_host) [")
    }
    "services/opencloud/scripts/entrypoint-init.nu" => {
      $c = ($c | str replace -a "use /usr/bin/lib/sshd.nu [" $"use ($sshd_host) [")
      $c = ($c | str replace -a "use /usr/bin/lib/ocmproviders.nu [" $"use ($opencloud_ocm_host) [")
    }
    "services/nextcloud/scripts/hooks/00-start-log-tailing.nu" => {
      $c = ($c | str replace -a "use /usr/bin/lib/log-tailing.nu [" $"use ($log_tailing_host) [")
    }
    "services/nextcloud-contacts/scripts/hooks/before-starting/90-ensure-contacts.nu"
    | "services/nextcloud-contacts/scripts/hooks/post-installation/90-enable-contacts.nu"
    | "services/nextcloud-contacts/scripts/hooks/post-installation/91-enable-contacts-ocm-invites.nu"
    | "services/nextcloud-webapp/scripts/hooks/before-starting/90-ensure-integration-jupyterhub.nu"
    | "services/nextcloud-webapp/scripts/hooks/before-starting/91-ensure-ocmremotewebapp.nu"
    | "services/nextcloud-webapp/scripts/hooks/post-installation/90-enable-integration-jupyterhub.nu"
    | "services/nextcloud-webapp/scripts/hooks/post-installation/91-configure-integration-jupyterhub.nu"
    | "services/nextcloud-webapp/scripts/hooks/post-installation/92-enable-ocmremotewebapp.nu" => {
      $c = ($c | str replace -a "use /usr/bin/lib/utils.nu [" $"use ($utils_host) [")
    }
    _ => {
      error make {msg: $"No staged-import substitution map for ($rel_path)"}
    }
  }

  $c
}

def staged-str-replace-steps [repo_root: string, rel_path: string] {
  let sshd_host = ($repo_root | path join "scripts/lib/ssh/sshd.nu")
  let utils_host = ($repo_root | path join "services/nextcloud-base/scripts/lib/utils.nu")
  let log_tailing_host = (
    $repo_root | path join "services/nextcloud-base/scripts/lib/log-tailing.nu"
  )
  let ocis_ocm_host = ($repo_root | path join "services/ocis/scripts/lib/ocmproviders.nu")
  let opencloud_ocm_host = (
    $repo_root | path join "services/opencloud/scripts/lib/ocmproviders.nu"
  )
  match $rel_path {
    "services/mitmproxy/scripts/entrypoint-init.nu"
    | "services/nextcloud-base/scripts/entrypoint-init.nu"
    | "services/revad-base/scripts/entrypoint-init.nu" => {
      [{needle: "use ./lib/sshd.nu [", replacement: $"use ($sshd_host) ["}]
    }
    "services/ocis/scripts/entrypoint-init.nu" => {
      [
        {needle: "use /usr/bin/lib/sshd.nu [", replacement: $"use ($sshd_host) ["}
        {needle: "use /usr/bin/lib/ocmproviders.nu [", replacement: $"use ($ocis_ocm_host) ["}
      ]
    }
    "services/opencloud/scripts/entrypoint-init.nu" => {
      [
        {needle: "use /usr/bin/lib/sshd.nu [", replacement: $"use ($sshd_host) ["}
        {needle: "use /usr/bin/lib/ocmproviders.nu [", replacement: $"use ($opencloud_ocm_host) ["}
      ]
    }
    "services/nextcloud/scripts/hooks/00-start-log-tailing.nu" => {
      [
        {
          needle: "use /usr/bin/lib/log-tailing.nu ["
          replacement: $"use ($log_tailing_host) ["
        }
      ]
    }
    "services/nextcloud-contacts/scripts/hooks/before-starting/90-ensure-contacts.nu"
    | "services/nextcloud-contacts/scripts/hooks/post-installation/90-enable-contacts.nu"
    | "services/nextcloud-contacts/scripts/hooks/post-installation/91-enable-contacts-ocm-invites.nu"
    | "services/nextcloud-webapp/scripts/hooks/before-starting/90-ensure-integration-jupyterhub.nu"
    | "services/nextcloud-webapp/scripts/hooks/before-starting/91-ensure-ocmremotewebapp.nu"
    | "services/nextcloud-webapp/scripts/hooks/post-installation/90-enable-integration-jupyterhub.nu"
    | "services/nextcloud-webapp/scripts/hooks/post-installation/91-configure-integration-jupyterhub.nu"
    | "services/nextcloud-webapp/scripts/hooks/post-installation/92-enable-ocmremotewebapp.nu" => {
      [{needle: "use /usr/bin/lib/utils.nu [", replacement: $"use ($utils_host) ["}]
    }
    _ => {
      error make {msg: $"No staged-import substitution map for ($rel_path)"}
    }
  }
}

def build-staged-inner-cmd [repo_root: string, rel_path: string, check_name: string] {
  mut cmd = $"open '($check_name)' | into string"
  for step in (staged-str-replace-steps $repo_root $rel_path) {
    let needle = ($step.needle | str replace "\"" "\\\"")
    let replacement = ($step.replacement | str replace "\"" "\\\"")
    $cmd = $cmd + $" | str replace -a \"($needle)\" \"($replacement)\""
  }
  $cmd + $" | nu-check --debug '($check_name)'"
}

def assert-staged-hosts-exist [repo_root: string, rel_path: string] {
  let sshd_host = ($repo_root | path join "scripts/lib/ssh/sshd.nu")
  let utils_host = ($repo_root | path join "services/nextcloud-base/scripts/lib/utils.nu")
  let log_tailing_host = (
    $repo_root | path join "services/nextcloud-base/scripts/lib/log-tailing.nu"
  )
  let ocis_ocm_host = ($repo_root | path join "services/ocis/scripts/lib/ocmproviders.nu")
  let opencloud_ocm_host = (
    $repo_root | path join "services/opencloud/scripts/lib/ocmproviders.nu"
  )
  let required = (match $rel_path {
    "services/mitmproxy/scripts/entrypoint-init.nu"
    | "services/nextcloud-base/scripts/entrypoint-init.nu"
    | "services/revad-base/scripts/entrypoint-init.nu" => [$sshd_host]
    "services/ocis/scripts/entrypoint-init.nu" => [$sshd_host $ocis_ocm_host]
    "services/opencloud/scripts/entrypoint-init.nu" => [$sshd_host $opencloud_ocm_host]
    "services/nextcloud/scripts/hooks/00-start-log-tailing.nu" => [$log_tailing_host]
    _ => [$utils_host]
  })
  for host in $required {
    if not ($host | path exists) {
      error make {msg: $"Staged import host target missing: ($host)"}
    }
  }
}

def staged-parse-check [repo_root: string, rel_path: string] {
  let abs_file = ($repo_root | path join $rel_path)
  if not ($abs_file | path exists) {
    error make {msg: $"Staged script missing: ($rel_path)"}
  }
  assert-staged-hosts-exist $repo_root $rel_path
  let script_dir = ($repo_root | path join ($rel_path | path dirname))
  let check_name = ($rel_path | path basename)
  let inner = (build-staged-inner-cmd $repo_root $rel_path $check_name)
  let result = (
    with-env { STAGED_DIR: $script_dir, INNER_CMD: $inner } {
      ^sh -c 'cd "$STAGED_DIR" && nu --no-config-file --no-history -c "$INNER_CMD"'
      | complete
    }
  )
  if $result.exit_code != 0 {
    let detail = ($result.stderr | str trim)
    error make {msg: $"nu-check failed for staged script ($rel_path): ($detail)"}
  }
  true
}

def parse-check-file [repo_root: string, rel_path: string] {
  let abs_file = ($repo_root | path join $rel_path)
  if $rel_path in $STAGED_IMPORT_FILES {
    staged-parse-check $repo_root $rel_path
  } else {
    ordinary-parse-check $abs_file
  }
}

export def hook-parse-tests [verbose: bool] {
  let repo_root = (get-repo-root)
  let tracked = (list-parse-pass-nu-files $repo_root)
  if ($tracked | is-empty) {
    error make {msg: "No tracked .nu files found for parse checks"}
  }

  mut results = []

  $results = ($results | append (
    run-test "Hook parse regression: known staged import" {
      staged-parse-check $repo_root "services/mitmproxy/scripts/entrypoint-init.nu"
    } $verbose
  ))

  $results = ($results | append (
    run-test "Hook parse regression: unknown missing import fails" {
      let fixture = (
        $repo_root
        | path join "scripts/tests/services/hook-parse-regression/unknown-missing-import.nu"
      )
      let failed = (try {
        ordinary-parse-check $fixture
        false
      } catch {
        true
      })
      if not $failed {
        error make {msg: "Expected missing-module fixture to fail parse check"}
      }
      true
    } $verbose
  ))

  $results = ($results | append (
    run-test "Hook parse regression: exit-zero Error diagnostic fails" {
      let fixture = (
        $repo_root
        | path join "scripts/tests/services/hook-parse-regression/exit-zero-parse-error.nu"
      )
      let failed = (try {
        ordinary-parse-check $fixture
        false
      } catch {
        true
      })
      if not $failed {
        error make {
          msg: "Expected exit-zero diagnostic fixture to fail parse check"
        }
      }
      true
    } $verbose
  ))

  for rel in $tracked {
    $results = ($results | append (
      run-test $"Tracked parse check: ($rel)" {
        parse-check-file $repo_root $rel
      } $verbose
    ))
  }

  $results
}

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  let results = (hook-parse-tests $verbose_flag)
  let failed = ($results | where {|r| $r != true} | length)
  if $failed > 0 {
    exit 1
  }
}
