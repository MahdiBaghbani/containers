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

# TLS configuration validation functions

export def validate-tls-config [
    tls_config: any,
    service_name: string
] {
    mut errors = []
    mut warnings = []
    
    if $tls_config == null {
        return {valid: true, errors: [], warnings: []}
    }
    
    let tls_type = ($tls_config | describe)
    if not ($tls_type | str starts-with "record") {
        $errors = ($errors | append $"Service '($service_name)': tls must be a record")
        return {valid: false, errors: $errors, warnings: $warnings}
    }
    
    if not ("enabled" in ($tls_config | columns)) {
        $errors = ($errors | append $"Service '($service_name)': tls.enabled is required")
    } else {
        let enabled_type = ($tls_config.enabled | describe)
        if not ($enabled_type | str starts-with "bool") {
            $errors = ($errors | append $"Service '($service_name)': tls.enabled must be a boolean")
        }
    }
    
    let enabled = (try { $tls_config.enabled | default false } catch { false })
    if $enabled {
        if not ("mode" in ($tls_config | columns)) {
            $errors = ($errors | append $"Service '($service_name)': tls.mode is required when tls.enabled=true")
        } else {
            let mode = $tls_config.mode
            let valid_modes = ["ca-only", "ca-and-cert", "cert-only"]
            if not ($mode in $valid_modes) {
                $errors = ($errors | append $"Service '($service_name)': tls.mode='($mode)' is invalid. Must be one of: ($valid_modes | str join ', ')")
            }
            
            let cert_name = (try { $tls_config.cert_name } catch { "" })
            
            if $mode == "ca-only" and ($cert_name | str trim | is-not-empty) {
                $warnings = ($warnings | append $"Service '($service_name)': tls.mode='ca-only' but tls.cert_name='($cert_name)' is provided. cert_name will be ignored in ca-only mode.")
            }
            
            if $mode != "ca-only" {
                if ($cert_name | is-empty) {
                    $errors = ($errors | append $"Service '($service_name)': tls.cert_name is required when tls.enabled=true and tls.mode is not 'ca-only'")
                }
            }
        }
    }
    
    if not ($errors | is-empty) {
        return {valid: false, errors: $errors, warnings: $warnings}
    }
    
    {valid: true, errors: [], warnings: $warnings}
}

export def validate-version-overrides-tls [
    overrides: record,
    version_name: string
] {
    mut errors = []
    
    if "tls" in ($overrides | columns) {
        $errors = ($errors | append $"Version '($version_name)': tls: Section forbidden. Configure TLS in base service config only.")
    }
    
    {
        valid: ($errors | is-empty),
        errors: $errors
    }
}

export def validate-tls-config-merged [
    merged_config: record,
    service_name: string
] {
    mut errors = []
    mut warnings = []
    
    if "tls" in ($merged_config | columns) {
        let tls_config = (try { $merged_config.tls } catch { null })
        if $tls_config != null {
            let tls_validation = (validate-tls-config $tls_config $service_name)
            if not $tls_validation.valid {
                $errors = ($errors | append $tls_validation.errors)
            }
            if "warnings" in ($tls_validation | columns) {
                $warnings = ($warnings | append $tls_validation.warnings)
            }
            
            let tls_enabled = (try { $tls_config.enabled | default false } catch { false })
            if $tls_enabled {
                # common-tools is the exception - it provides the CA bundle, so it doesn't need to depend on itself
                if $service_name != "common-tools" {
                    let deps = (try { $merged_config.dependencies } catch { {} })
                    let has_common_tools = ($deps | columns | any {|dep_key|
                        let dep = ($deps | get $dep_key)
                        let dep_service = (try { $dep.service } catch { $dep_key })
                        $dep_service == "common-tools"
                    })
                    
                    if not $has_common_tools {
                        $errors = ($errors | append $"Service '($service_name)': TLS is enabled but 'common-tools' dependency is missing. Services with TLS enabled MUST have a 'common-tools' dependency. This can be specified in base config, platform config, or version overrides.")
                    }
                }
            }
        }
    }
    
    {
        valid: ($errors | is-empty),
        errors: $errors,
        warnings: $warnings
    }
}
