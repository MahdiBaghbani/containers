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

export def login-ghcr [] {
  let user = ((try { $env.GITHUB_ACTOR } catch { "" }) | default "")
  let token = ((try { $env.GITHUB_TOKEN } catch { "" }) | default ((try { $env.GHCR_PAT } catch { "" }) | default ""))
  if ($token == "") {
    return { ok: false, registry: "ghcr.io", reason: "no token" }
  }
  let u = (if $user == "" { "oauth2" } else { $user })
  ^docker login ghcr.io -u $u --password-stdin <<< $token | ignore
  { ok: true, registry: "ghcr.io" }
}

export def login-forgejo [forgejo_registry: string] {
  let user = ((try { $env.FORGEJO_REGISTRY_USER } catch { "" }) | default "")
  let token = ((try { $env.FORGEJO_REGISTRY_TOKEN } catch { "" }) | default "")
  if ($token == "" or $forgejo_registry == "") {
    return { ok: false, registry: $forgejo_registry, reason: "missing creds or registry" }
  }
  let u = (if $user == "" { "oauth2" } else { $user })
  ^docker login $forgejo_registry -u $u --password-stdin <<< $token | ignore
  { ok: true, registry: $forgejo_registry }
}
