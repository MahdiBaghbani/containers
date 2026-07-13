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

# Dockerfile path validation

use ../platforms/core.nu [check-platforms-manifest-exists load-platforms-manifest]
use ../core/repo.nu [get-repo-root]

export def validate-dockerfile-paths [
  service: string
] {
  mut errors = []
  let repo_root = (get-repo-root)
  let has_platforms = (check-platforms-manifest-exists $service)

  if $has_platforms {
    let platforms_result = (try {
      load-platforms-manifest $service
    } catch { |err|
      return {valid: false, errors: [$"Could not load platforms manifest for '($service)': ($err.msg)"]}
    })
    for platform in $platforms_result.platforms {
      let df = (try { $platform.dockerfile } catch { "" })
      if ($df | str length) > 0 {
        if not (($repo_root | path join $df) | path exists) {
          $errors = ($errors | append $"Service '($service)' platform '($platform.name)': Dockerfile not found: ($df)")
        }
      }
    }
  } else {
    let cfg_path = $"services/($service).nuon"
    let config = (try { open $cfg_path } catch { null })
    if $config != null {
      let df = (try { $config.dockerfile } catch { "" })
      if ($df | str length) > 0 {
        if not (($repo_root | path join $df) | path exists) {
          $errors = ($errors | append $"Service '($service)': Dockerfile not found: ($df)")
        }
      }
    }
  }

  {
    valid: ($errors | is-empty),
    errors: $errors
  }
}