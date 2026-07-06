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

export def create-test-version-spec [
  version_name: string = "v1.0.0",
  latest: bool = true,
  tags: list = [],
  overrides: record = {}
] {
  {
    name: $version_name,
    latest: $latest,
    tags: $tags,
    overrides: $overrides
  }
}

export def create-test-dependency [
  service: string,
  version: string = "",
  build_arg: string = ""
] {
  mut dep = {service: $service}
  if ($version | str length) > 0 {
    $dep = ($dep | upsert version $version)
  }
  if ($build_arg | str length) > 0 {
    $dep = ($dep | upsert build_arg $build_arg)
  }
  $dep
}

export def create-test-deps-resolved [dependencies: record = {}] {
  $dependencies
}

export def create-test-tls-meta [
  enabled: bool = false,
  mode: string = "disabled",
  cert_name: string = "",
  ca_name: string = ""
] {
  {
    enabled: $enabled,
    mode: $mode,
    cert_name: $cert_name,
    ca_name: $ca_name
  }
}

export def create-test-registry-info [
  registry: string = "",
  namespace: string = "",
  is_local: bool = true
] {
  {
    registry: $registry,
    namespace: $namespace,
    is_local: $is_local
  }
}
