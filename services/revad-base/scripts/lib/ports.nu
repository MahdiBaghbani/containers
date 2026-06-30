#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Copyright (C) 2025 Mahdi Baghbani <mahdi-baghbani@azadehafzar.io>
#
# Single source of truth for Reva gRPC port derivation by REVAD_CONTAINER_MODE.

use ./utils.nu [get_env_or_default]

# Optional env override: blank values fall back to default.
def optional-env-or-default [var_name: string, default_value: string] {
    let raw = (get_env_or_default $var_name "")
    if ($raw | str trim | str length) == 0 {
        $default_value
    } else {
        $raw | str trim
    }
}

# Validate a resolved TCP port (1-65535) before probes or wiring use it.
export def validate-grpc-port [port: string] {
    let trimmed = ($port | str trim)
    if ($trimmed | str length) == 0 {
        error make {msg: "gRPC port must not be empty"}
    }
    if ($trimmed | parse --regex '^\d+$' | is-empty) {
        error make {msg: $"invalid gRPC port: ($port)"}
    }
    let n = ($trimmed | into int)
    if $n < 1 or $n > 65535 {
        error make {msg: $"invalid gRPC port: ($port)"}
    }
    $trimmed
}

# Default gRPC ports for modes that ship a fixed listen port in the image.
const FIXED_MODE_GRPC_PORTS = {
    gateway: "9142"
    shareproviders: "9144"
    groupuserproviders: "9145"
    "authprovider-oidc": "9158"
    "authprovider-machine": "9166"
    "authprovider-publicshares": "9160"
    "authprovider-ocmshares": "9278"
    "authprovider-ocmsharecode": "9280"
    "authprovider-ocmexchangedtoken": "9282"
}

# Registry defaults used when gateway.toml references dataprovider addresses.
# Dataprovider containers themselves must set REVAD_DATAPROVIDER_*_GRPC_PORT.
const DATAPROVIDER_REGISTRY_GRPC_PORTS = {
    localhome: "9143"
    ocm: "9146"
    sciencemesh: "9147"
}

# Return the baked default gRPC port for a fixed REVAD_CONTAINER_MODE value.
# Dataprovider modes have no container default; callers must use env resolution.
export def default-grpc-port-for-mode [mode: string] {
    if ($mode in ($FIXED_MODE_GRPC_PORTS | columns)) {
        return ($FIXED_MODE_GRPC_PORTS | get $mode)
    }
    if ($mode | str starts-with "dataprovider-") {
        error make {
            msg: $"dataprovider mode ($mode) has no default gRPC port; set REVAD_DATAPROVIDER_*_GRPC_PORT"
        }
    }
    error make { msg: $"unknown REVAD_CONTAINER_MODE for gRPC port: ($mode)" }
}

# Registry default for gateway.toml dataprovider address placeholders only.
export def default-dataprovider-registry-grpc-port [dataprovider_type: string] {
    if not ($dataprovider_type in ($DATAPROVIDER_REGISTRY_GRPC_PORTS | columns)) {
        let valid = ($DATAPROVIDER_REGISTRY_GRPC_PORTS | columns | str join ", ")
        error make {
            msg: $"unknown dataprovider type for registry port: ($dataprovider_type). Valid: ($valid)"
        }
    }
    $DATAPROVIDER_REGISTRY_GRPC_PORTS | get $dataprovider_type
}

# Resolve the gRPC port for the active container mode (healthcheck and strict probes).
export def resolve-grpc-port-for-mode [mode: string] {
    let port = if ($mode | str starts-with "dataprovider-") {
        let dp_type = ($mode | str substring 13..)
        require-dataprovider-grpc-port $dp_type
    } else if $mode == "gateway" {
        optional-env-or-default "REVAD_GATEWAY_GRPC_PORT" (default-grpc-port-for-mode $mode)
    } else if $mode == "shareproviders" {
        optional-env-or-default "REVAD_SHAREPROVIDERS_GRPC_PORT" (default-grpc-port-for-mode $mode)
    } else if $mode == "groupuserproviders" {
        optional-env-or-default "REVAD_GROUPUSERPROVIDERS_GRPC_PORT" (default-grpc-port-for-mode $mode)
    } else if ($mode | str starts-with "authprovider-") {
        let ap_type = ($mode | str substring 13..)
        let type_upper = ($ap_type | str upcase)
        optional-env-or-default $"REVAD_AUTHPROVIDER_($type_upper)_GRPC_PORT" (default-grpc-port-for-mode $mode)
    } else {
        default-grpc-port-for-mode $mode
    }
    validate-grpc-port $port
}

# Dataprovider init: explicit env required (no invented default on the container).
export def require-dataprovider-grpc-port [dataprovider_type: string] {
    let type_upper = ($dataprovider_type | str upcase)
    let port = (get_env_or_default $"REVAD_DATAPROVIDER_($type_upper)_GRPC_PORT" "" | str trim)
    if ($port | str length) == 0 {
        error make {
            msg: $"REVAD_DATAPROVIDER_($type_upper)_GRPC_PORT is required for dataprovider ($dataprovider_type)"
        }
    }
    validate-grpc-port $port
}

# Gateway registry wiring: env override with cookbook-friendly defaults.
export def resolve-dataprovider-registry-grpc-port [dataprovider_type: string] {
    let type_upper = ($dataprovider_type | str upcase)
    let port = (optional-env-or-default $"REVAD_DATAPROVIDER_($type_upper)_GRPC_PORT" (default-dataprovider-registry-grpc-port $dataprovider_type))
    validate-grpc-port $port
}

export def resolve-gateway-grpc-port [] {
    validate-grpc-port (optional-env-or-default "REVAD_GATEWAY_GRPC_PORT" (default-grpc-port-for-mode "gateway"))
}

export def resolve-authprovider-grpc-port [authprovider_type: string] {
    let mode = $"authprovider-($authprovider_type)"
    let type_upper = ($authprovider_type | str upcase)
    let port = (optional-env-or-default $"REVAD_AUTHPROVIDER_($type_upper)_GRPC_PORT" (default-grpc-port-for-mode $mode))
    validate-grpc-port $port
}

export def resolve-shareproviders-grpc-port [] {
    validate-grpc-port (optional-env-or-default "REVAD_SHAREPROVIDERS_GRPC_PORT" (default-grpc-port-for-mode "shareproviders"))
}

export def resolve-groupuserproviders-grpc-port [] {
    validate-grpc-port (optional-env-or-default "REVAD_GROUPUSERPROVIDERS_GRPC_PORT" (default-grpc-port-for-mode "groupuserproviders"))
}
