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

# SSH configuration validation functions
# SSH configures dev and E2E SSH shell access to running containers.
# Does NOT describe Git transport, Git signing, or OCM share protocol behavior.

export def validate-ssh-config [
    ssh_config: any,
    service_name: string
] {
    mut errors = []
    mut warnings = []

    if $ssh_config == null {
        return {valid: true, errors: [], warnings: []}
    }

    let ssh_type = ($ssh_config | describe)
    if not ($ssh_type | str starts-with "record") {
        $errors = ($errors | append $"Service '($service_name)': ssh must be a record")
        return {valid: false, errors: $errors, warnings: $warnings}
    }

    if not ("enabled" in ($ssh_config | columns)) {
        $errors = ($errors | append $"Service '($service_name)': ssh.enabled is required")
    } else {
        let enabled_type = ($ssh_config.enabled | describe)
        if not ($enabled_type | str starts-with "bool") {
            $errors = ($errors | append $"Service '($service_name)': ssh.enabled must be a boolean")
        }
    }

    let enabled = (try { $ssh_config.enabled | default false } catch { false })
    if $enabled {
        if not ("mode" in ($ssh_config | columns)) {
            $errors = ($errors | append $"Service '($service_name)': ssh.mode is required when ssh.enabled=true")
        } else {
            let mode = $ssh_config.mode
            let valid_modes = ["client" "server" "client-and-server"]
            if not ($mode in $valid_modes) {
                $errors = ($errors | append $"Service '($service_name)': ssh.mode='($mode)' is invalid. Must be one of: ($valid_modes | str join ', ')")
            }
        }

        # Validate port if provided
        if "port" in ($ssh_config | columns) {
            let port = $ssh_config.port
            let port_type = ($port | describe)
            if not ($port_type | str starts-with "int") {
                $errors = ($errors | append $"Service '($service_name)': ssh.port must be an integer")
            } else if $port < 1 or $port > 65535 {
                $errors = ($errors | append $"Service '($service_name)': ssh.port='($port)' is invalid. Must be between 1 and 65535")
            }
        }
    }

    if not ($errors | is-empty) {
        return {valid: false, errors: $errors, warnings: $warnings}
    }

    {valid: true, errors: [], warnings: $warnings}
}

export def validate-version-overrides-ssh [
    overrides: record,
    version_name: string
] {
    mut errors = []
    mut warnings = []

    # SSH is ALLOWED in version overrides (unlike TLS), but rare.
    # Warn so operators know to document the override, then validate the nested config.
    if "ssh" in ($overrides | columns) {
        $warnings = ($warnings | append $"Version '($version_name)': ssh: Version-level SSH overrides are allowed but should be rare and documented.")
        let ssh_config = (try { $overrides.ssh } catch { null })
        if $ssh_config != null {
            let ssh_validation = (validate-ssh-config $ssh_config $version_name)
            if not $ssh_validation.valid {
                $errors = ($errors | append $ssh_validation.errors)
            }
            if "warnings" in ($ssh_validation | columns) {
                $warnings = ($warnings | append $ssh_validation.warnings)
            }
        }
    }

    {
        valid: ($errors | is-empty),
        errors: $errors,
        warnings: $warnings
    }
}

export def validate-platform-ssh [
    platform_config: record,
    platform_name: string
] {
    mut errors = []
    mut warnings = []

    # SSH is ALLOWED in platform configs (unlike TLS)
    if "ssh" in ($platform_config | columns) {
        let ssh_config = (try { $platform_config.ssh } catch { null })
        if $ssh_config != null {
            let ssh_validation = (validate-ssh-config $ssh_config $platform_name)
            if not $ssh_validation.valid {
                $errors = ($errors | append $ssh_validation.errors)
            }
            if "warnings" in ($ssh_validation | columns) {
                $warnings = ($warnings | append $ssh_validation.warnings)
            }
        }
    }

    {
        valid: ($errors | is-empty),
        errors: $errors,
        warnings: $warnings
    }
}

export def validate-ssh-config-merged [
    merged_config: record,
    service_name: string
] {
    mut errors = []
    mut warnings = []

    if "ssh" in ($merged_config | columns) {
        let ssh_config = (try { $merged_config.ssh } catch { null })
        if $ssh_config != null {
            let ssh_validation = (validate-ssh-config $ssh_config $service_name)
            if not $ssh_validation.valid {
                $errors = ($errors | append $ssh_validation.errors)
            }
            if "warnings" in ($ssh_validation | columns) {
                $warnings = ($warnings | append $ssh_validation.warnings)
            }
        }
    }

    {
        valid: ($errors | is-empty),
        errors: $errors,
        warnings: $warnings
    }
}
