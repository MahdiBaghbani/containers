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

# Registry login operations
# See docs/concepts/build-system.md for registry configuration

use ../registries/info.nu [get-registry-info]

# Get first non-empty environment variable from a list of keys
def get-env-first-non-empty [keys: list<string>] {
  for $key in $keys {
    let value = (try { $env | get $key } catch { "" })
    if ($value | str length) > 0 {
      return $value
    }
  }
  ""
}

# Internal registry login helper
def login-registry-internal [
  registry: string,
  token_env_keys: list<string>,
  user_env_keys: list<string>
] {
  if ($registry | str length) == 0 {
    return { ok: false, registry: $registry, reason: "registry not set" }
  }
  
  let token = (get-env-first-non-empty $token_env_keys)
  if ($token | str length) == 0 {
    return { ok: false, registry: $registry, reason: "no token" }
  }
  
  let user = (get-env-first-non-empty $user_env_keys)
  let u = (if ($user | str length) == 0 { "oauth2" } else { $user })
  
  let login_result = (^docker login $registry -u $u --password-stdin <<< $token | complete)
  
  if $login_result.exit_code != 0 {
    let stderr_summary = (try {
      ($login_result.stderr | lines | where {|l| ($l | str length) > 0 } | first 1 | str join " ")
    } catch {
      "docker login failed"
    })
    return { ok: false, registry: $registry, reason: $stderr_summary }
  }
  
  { ok: true, registry: $registry }
}

export def login-ghcr [] {
  login-registry-internal "ghcr.io" ["GITHUB_TOKEN"] ["GITHUB_ACTOR"]
}

export def login-forgejo [forgejo_registry: string] {
  login-registry-internal $forgejo_registry ["FORGEJO_REGISTRY_TOKEN"] ["FORGEJO_REGISTRY_USER"]
}

export def login-default-registry [] {
  let registry_info = (get-registry-info)
  let is_github_ci = ($registry_info.ci_platform == "github") and ((try { $env.GITHUB_ACTIONS } catch { "" }) == "true")
  
  if $is_github_ci {
    login-ghcr
  } else {
    { ok: true, registry: "", reason: "no-op for local or non-GitHub CI" }
  }
}
