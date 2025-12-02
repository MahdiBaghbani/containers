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

def parse-origin [origin: string] {
  let o = $origin
  if ($o | str starts-with "ssh://") {
    let without_scheme = ($o | str replace -a "ssh://" "")
    let host_and_path = ($without_scheme | str replace -a "git@" "")
    let host = ($host_and_path | split row "/" | get 0)
    let path = ($host_and_path | split row "/" | skip 1 | str join "/")
    let path_no_git = (if ($path | str ends-with ".git") { ($path | split row ".git" | get 0) } else { $path })
    { host: $host, path: $path_no_git }
  } else if ($o | str starts-with "git@") or ($o | str contains ":") {
    let without_user = ($o | str replace -a "git@" "")
    let parts = ($without_user | split row ":")
    let host = ($parts | get 0)
    let path = ($parts | get 1)
    let path_no_git = (if ($path | str ends-with ".git") { ($path | split row ".git" | get 0) } else { $path })
    { host: $host, path: $path_no_git }
  } else if ($o | str starts-with "http") {
    let url = ($o | url parse)
    let host = $url.host
    let path = ($url.path | str trim -l -c "/")
    let path_no_git = (if ($path | str ends-with ".git") { ($path | split row ".git" | get 0) } else { $path })
    { host: $host, path: $path_no_git }
  } else {
    error make { msg: ($"Unsupported origin format: ($o)") }
  }
}

# Detect which CI platform we're running on
def detect-ci-platform [] {
  let in_github = (((try { $env.GITHUB_ACTIONS } catch { "" }) | default "") | str length) > 0
  let has_forgejo_env = (((try { $env.FORGEJO } catch { "" }) | default "") | str length) > 0
  let has_gitea_env = (((try { $env.GITEA_ACTIONS } catch { "" }) | default "") | str length) > 0
  let in_forgejo = $has_forgejo_env or $has_gitea_env
  
  if $in_github {
    "github"
  } else if $in_forgejo {
    "forgejo"
  } else {
    "local"
  }
}

export def get-registry-info [] {
  let ci_platform = (detect-ci-platform)
  
  let origin = (try {
    git remote get-url origin | str trim
  } catch {
    ""
  })
  if ($origin | str length) == 0 {
    return {
      ci_platform: $ci_platform,
      forgejo_registry: "",
      forgejo_path: "",
      github_registry: "ghcr.io",
      github_path: "",
      owner: "local",
      repo: "local"
    }
  }
  let parsed = (parse-origin $origin)
  let path_parts = ($parsed.path | split row "/")
  let owner = ($path_parts | get 0)
  let repo = ($path_parts | get 1)

  # For GitHub CI, use GITHUB_REPOSITORY for the path
  let github_repo = ((try { $env.GITHUB_REPOSITORY } catch { "" }) | default ($"($owner)/($repo)"))
  
  # For Forgejo, use the parsed host as registry (only valid when running on Forgejo)
  # When running on GitHub, forgejo_registry will be github.com which is wrong, but we won't use it
  let forgejo_registry = (if $ci_platform == "forgejo" { $parsed.host } else { "" })
  let forgejo_path = ($"($owner)/($repo)")

  {
    ci_platform: $ci_platform,
    forgejo_registry: $forgejo_registry,
    forgejo_path: $forgejo_path,
    github_registry: "ghcr.io",
    github_path: $github_repo,
    owner: $owner,
    repo: $repo
  }
}
