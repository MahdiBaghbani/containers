#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Copyright (C) 2025 Mahdi Baghbani <mahdi-baghbani@azadehafzar.io>

# Registry and OCM network settings applied after a mode config is rendered.

const VALID_RUNTIME_MODES = [
    "gateway"
    "dataprovider-localhome"
    "dataprovider-ocm"
    "dataprovider-sciencemesh"
    "authprovider-oidc"
    "authprovider-machine"
    "authprovider-ocmshares"
    "authprovider-ocmsharecode"
    "authprovider-ocmexchangedtoken"
    "authprovider-publicshares"
    "shareproviders"
    "groupuserproviders"
]

def env-trim [name: string] {
    let raw = (try { $env | get $name } catch { null })
    if $raw == null {
        return ""
    }
    $raw | into string | str trim
}

def is-record [value: any] {
    if $value == null {
        return false
    }
    ($value | describe) | str starts-with "record"
}

def is-list-like [value: any] {
    if $value == null {
        return false
    }
    let kind = ($value | describe)
    (($kind | str starts-with "list") or ($kind | str starts-with "table"))
}

# Go duration units only. Callers keep the original text for TOML.
def scaled-nanos [num_text: string, unit_ns: int] {
    let magnitude = (try { $num_text | into float } catch { null })
    if $magnitude == null or $magnitude < 0 {
        return null
    }
    let nanos = $magnitude * ($unit_ns | into float)
    if $nanos > 9223372036854775000.0 {
        return null
    }
    try { $nanos | math round | into int } catch { null }
}

def duration-nanos [text: string] {
    let trimmed = ($text | str trim)
    if ($trimmed | str length) == 0 {
        return null
    }
    mut rest = $trimmed
    if ($rest | str starts-with "+") {
        $rest = ($rest | str substring 1..)
    }
    if ($rest | str starts-with "-") or ($rest | str length) == 0 {
        return null
    }
    mut total = 0
    mut saw = false
    while ($rest | str length) > 0 {
        let matched = ($rest | parse --regex '^(?P<num>[0-9]+(\\.[0-9]*)?|\\.[0-9]+)(?P<unit>ns|us|ms|s|m|h)(?P<rest>.*)$')
        if ($matched | is-empty) {
            return null
        }
        let row = ($matched | first)
        let unit_ns = (match $row.unit {
            "ns" => 1
            "us" => 1000
            "ms" => 1000000
            "s" => 1000000000
            "m" => 60000000000
            "h" => 3600000000000
            _ => 0
        })
        if $unit_ns == 0 {
            return null
        }
        let piece = (scaled-nanos $row.num $unit_ns)
        if $piece == null {
            return null
        }
        let next = $row.rest
        if ($next | str length) >= ($rest | str length) {
            return null
        }
        $total = $total + $piece
        $rest = $next
        $saw = true
    }
    if not $saw or $total <= 0 {
        return null
    }
    $total
}

def env-duration [name: string, default_text: string, msg: string] {
    let raw = (env-trim $name)
    let text = (if ($raw | str length) == 0 { $default_text } else { $raw })
    let nanos = (duration-nanos $text)
    if $nanos == null {
        error make {msg: $msg}
    }
    {text: $text, nanos: $nanos}
}

def parse-strict-bool [raw: string, msg: string] {
    if ($raw | str length) == 0 {
        return false
    }
    let lowered = ($raw | str lowercase)
    if $lowered == "true" {
        return true
    }
    if $lowered == "false" {
        return false
    }
    error make {msg: $msg}
}

# Only "true" enables. OC_INSECURE fills in when OCM_CLIENT_INSECURE is unset.
def resolve-insecure [] {
    let specific = (env-trim "OCM_CLIENT_INSECURE")
    let chosen = (if ($specific | str length) > 0 {
        $specific
    } else {
        (env-trim "OC_INSECURE")
    })
    if ($chosen | str length) == 0 {
        return false
    }
    ($chosen | str lowercase) == "true"
}

def parse-timeout [raw: string] {
    if ($raw | str length) == 0 {
        return 10
    }
    if ($raw | parse --regex '^[1-9][0-9]*$' | is-empty) {
        error make {msg: "OCM_TIMEOUT must be a positive integer"}
    }
    let n = (try { $raw | into int } catch { null })
    if $n == null or $n <= 0 {
        error make {msg: "OCM_TIMEOUT must be a positive integer"}
    }
    $n
}

def parse-cidrs [raw: string] {
    if ($raw | str length) == 0 {
        return []
    }
    let parsed = (try { $raw | from json } catch { null })
    if $parsed == null or not (is-list-like $parsed) {
        error make {msg: "OCM_ALLOWED_FEDERATION_CIDRS must be a JSON array of strings"}
    }
    for item in $parsed {
        if $item == null or ($item | describe) != "string" {
            error make {msg: "OCM_ALLOWED_FEDERATION_CIDRS must be a JSON array of strings"}
        }
    }
    $parsed
}

def parse-bucket [raw: string] {
    let text = (if ($raw | str length) == 0 { "reva_registry" } else { $raw })
    if ($text | parse --regex '^[A-Za-z0-9_-]+$' | is-empty) {
        error make {msg: "REVAD_NATS_BUCKET must contain only letters, digits, underscore, or hyphen"}
    }
    $text
}

def parse-nats-address [raw: string] {
    if ($raw | str length) == 0 {
        error make {msg: "REVAD_NATS_ADDRESS is required when registry driver is nats"}
    }
    let matched = ($raw | parse --regex '^nats://(?P<host>[A-Za-z0-9][A-Za-z0-9._-]*):(?P<port>[0-9]{1,5})$')
    if ($matched | is-empty) {
        error make {msg: "REVAD_NATS_ADDRESS must be a nats:// host:port URL"}
    }
    let row = ($matched | first)
    let host = $row.host
    if (($host | str contains "..") or ($host | str ends-with ".")) {
        error make {msg: "REVAD_NATS_ADDRESS must be a nats:// host:port URL"}
    }
    let port = (try { $row.port | into int } catch { -1 })
    if $port < 1 or $port > 65535 {
        error make {msg: "REVAD_NATS_ADDRESS must be a nats:// host:port URL"}
    }
    $raw
}

def registry-table [settings: record] {
    let reg = $settings.registry
    mut table = {
        driver: $reg.driver
        heartbeat_interval: $reg.heartbeat_interval
        degraded_after: $reg.degraded_after
        offline_after: $reg.offline_after
        reap_after: $reg.reap_after
    }
    if $reg.driver == "nats" {
        let nats = $reg.nats
        mut driver = {
            address: $nats.address
            bucket: $nats.bucket
            ttl: $nats.ttl
        }
        let token = ($nats.token? | default "")
        if (($token | describe) == "string") and (($token | str length) > 0) {
            $driver = ($driver | upsert token $token)
        }
        $table = ($table | upsert drivers {nats: $driver})
    }
    $table
}

def provider-view [value: any] {
    if $value == null {
        return {shape: "missing", items: []}
    }
    if (is-record $value) {
        return {shape: "record", items: [$value]}
    }
    if (is-list-like $value) {
        return {shape: "list", items: $value}
    }
    error make {msg: "runtime config provider shape is invalid"}
}

def assert-one-received [value: any, msg: string] {
    let view = (provider-view $value)
    if $view.shape == "missing" {
        error make {msg: $msg}
    }
    let count = ($view.items | where {|item|
        (is-record $item) and (($item.driver? | default "") == "ocmreceived")
    } | length)
    if $count != 1 {
        error make {msg: $msg}
    }
}

def received-provider [item: record, settings: record] {
    let network = $settings.network
    let drivers = ($item.drivers? | default {})
    if not (is-record $drivers) {
        error make {msg: "runtime config provider shape is invalid"}
    }
    let existing = ($drivers.ocmreceived? | default {})
    if not (is-record $existing) {
        error make {msg: "runtime config provider shape is invalid"}
    }
    let updated = ($existing | merge {
        provider_domain: $settings.provider_domain
        ocm_timeout: $network.timeout
        ocm_insecure: $network.insecure
        allowed_federation_cidrs: $network.allowed_federation_cidrs
        ocm_use_env_proxy: $network.use_env_proxy
        allow_loopback_federation: $network.allow_loopback_federation
    })
    $item | upsert drivers ($drivers | upsert ocmreceived $updated)
}

def map-received [value: any, settings: record] {
    let view = (provider-view $value)
    if $view.shape == "missing" {
        return null
    }
    let items = ($view.items | each {|item|
        if not (is-record $item) {
            error make {msg: "runtime config provider shape is invalid"}
        }
        if ($item.driver? | default "") == "ocmreceived" {
            received-provider $item $settings
        } else {
            $item
        }
    })
    if $view.shape == "record" {
        $items | first
    } else {
        $items
    }
}

def with-http-ocm [svc: record, settings: record] {
    let network = $settings.network
    $svc
    | upsert ocm_client_timeout $network.timeout
    | upsert ocm_client_insecure $network.insecure
    | upsert allowed_federation_cidrs $network.allowed_federation_cidrs
    | upsert ocm_client_use_env_proxy $network.use_env_proxy
    | upsert allow_loopback_federation $network.allow_loopback_federation
}

def with-http-sciencemesh [svc: record, settings: record] {
    let network = $settings.network
    $svc
    | upsert ocm_client_timeout $network.timeout
    | upsert ocm_client_insecure $network.insecure
    | upsert allowed_federation_cidrs $network.allowed_federation_cidrs
    | upsert ocm_client_use_env_proxy $network.use_env_proxy
}

def with-open-driver [svc: record, settings: record] {
    if ($svc.driver? | default "") != "open" {
        return $svc
    }
    let network = $settings.network
    let drivers = ($svc.drivers? | default {})
    if not (is-record $drivers) {
        error make {msg: "runtime config provider shape is invalid"}
    }
    let existing = ($drivers.open? | default {})
    if not (is-record $existing) {
        error make {msg: "runtime config provider shape is invalid"}
    }
    let open = ($existing | merge {
        insecure: $network.insecure
        allowed_federation_cidrs: $network.allowed_federation_cidrs
        ocm_client_use_env_proxy: $network.use_env_proxy
    })
    $svc | upsert drivers ($drivers | upsert open $open)
}

def map-authorizer [value: any, settings: record] {
    let view = (provider-view $value)
    if $view.shape == "missing" {
        return null
    }
    let items = ($view.items | each {|item|
        if not (is-record $item) {
            error make {msg: "runtime config provider shape is invalid"}
        }
        with-open-driver $item $settings
    })
    if $view.shape == "record" {
        $items | first
    } else {
        $items
    }
}

def put-received [config: record, parent: string, value: any, settings: record] {
    if $value == null {
        return $config
    }
    let mapped = (map-received $value $settings)
    if $parent == "grpc" {
        $config | upsert grpc.services.storageprovider $mapped
    } else {
        $config | upsert http.services.dataprovider $mapped
    }
}

export def runtime-settings-from-env [] {
    let driver_raw = (env-trim "REVAD_REGISTRY_DRIVER")
    let driver = (if ($driver_raw | str length) == 0 { "memory" } else { $driver_raw })
    if not ($driver in ["memory", "nats"]) {
        error make {msg: "REVAD_REGISTRY_DRIVER must be memory or nats"}
    }

    let heartbeat = (env-duration "REVAD_REGISTRY_HEARTBEAT_INTERVAL" "5s" "REVAD_REGISTRY_HEARTBEAT_INTERVAL must be a positive duration")
    let degraded = (env-duration "REVAD_REGISTRY_DEGRADED_AFTER" "15s" "REVAD_REGISTRY_DEGRADED_AFTER must be a positive duration")
    let offline = (env-duration "REVAD_REGISTRY_OFFLINE_AFTER" "30s" "REVAD_REGISTRY_OFFLINE_AFTER must be a positive duration")
    let reap = (env-duration "REVAD_REGISTRY_REAP_AFTER" "5m" "REVAD_REGISTRY_REAP_AFTER must be a positive duration")
    if not (
        ($heartbeat.nanos < $degraded.nanos)
        and ($degraded.nanos < $offline.nanos)
        and ($offline.nanos < $reap.nanos)
    ) {
        error make {msg: "registry liveness order must be heartbeat < degraded < offline < reap"}
    }

    # TTL is checked even for the memory driver so a short override cannot
    # outlive the offline threshold once the suite selects nats.
    let ttl = (env-duration "REVAD_NATS_TTL" "30s" "REVAD_NATS_TTL must be a positive duration")
    if $ttl.nanos < $offline.nanos {
        error make {msg: "REVAD_NATS_TTL must be at least offline_after"}
    }
    let bucket = (parse-bucket (env-trim "REVAD_NATS_BUCKET"))

    let domain = (env-trim "DOMAIN")
    if ($domain | str length) == 0 {
        error make {msg: "Environment variable DOMAIN is required"}
    }

    mut registry = {
        driver: $driver
        heartbeat_interval: $heartbeat.text
        degraded_after: $degraded.text
        offline_after: $offline.text
        reap_after: $reap.text
    }
    if $driver == "nats" {
        let address = (parse-nats-address (env-trim "REVAD_NATS_ADDRESS"))
        let token = (env-trim "REVAD_NATS_TOKEN")
        mut nats = {
            address: $address
            bucket: $bucket
            ttl: $ttl.text
        }
        if ($token | str length) > 0 {
            $nats = ($nats | upsert token $token)
        }
        $registry = ($registry | upsert nats $nats)
    }

    {
        registry: $registry
        network: {
            allowed_federation_cidrs: (parse-cidrs (env-trim "OCM_ALLOWED_FEDERATION_CIDRS"))
            timeout: (parse-timeout (env-trim "OCM_TIMEOUT"))
            insecure: (resolve-insecure)
            use_env_proxy: (parse-strict-bool (env-trim "OCM_USE_ENV_PROXY") "OCM_USE_ENV_PROXY must be true or false")
            allow_loopback_federation: (parse-strict-bool (env-trim "OCM_ALLOW_LOOPBACK_FEDERATION") "OCM_ALLOW_LOOPBACK_FEDERATION must be true or false")
        }
        provider_domain: $domain
    }
}

export def apply-runtime-settings [config: record, mode: string, settings: record] {
    if not ($mode in $VALID_RUNTIME_MODES) {
        error make {msg: "unknown runtime config mode"}
    }
    if $mode == "dataprovider-sciencemesh" {
        assert-one-received ($config.grpc?.services?.storageprovider?) "dataprovider-sciencemesh requires exactly one ocmreceived storage provider"
        assert-one-received ($config.http?.services?.dataprovider?) "dataprovider-sciencemesh requires exactly one ocmreceived data provider"
    }

    let shared = ($config.shared? | default {})
    if not (is-record $shared) {
        error make {msg: "runtime config provider shape is invalid"}
    }
    mut out = ($config | upsert shared ($shared | upsert registry (registry-table $settings)))

    let ocm = $out.http?.services?.ocm?
    if $ocm != null {
        if not (is-record $ocm) {
            error make {msg: "runtime config service shape is invalid"}
        }
        $out = ($out | upsert http.services.ocm (with-http-ocm $ocm $settings))
    }

    let mesh = $out.http?.services?.sciencemesh?
    if $mesh != null {
        if not (is-record $mesh) {
            error make {msg: "runtime config service shape is invalid"}
        }
        $out = ($out | upsert http.services.sciencemesh (with-http-sciencemesh $mesh $settings))
    }

    let authorizer = $out.grpc?.services?.ocmproviderauthorizer?
    if $authorizer != null {
        $out = ($out | upsert grpc.services.ocmproviderauthorizer (map-authorizer $authorizer $settings))
    }

    $out = (put-received $out "grpc" ($out.grpc?.services?.storageprovider?) $settings)
    $out = (put-received $out "http" ($out.http?.services?.dataprovider?) $settings)
    $out
}

export def write-runtime-settings [config_path: string, mode: string] {
    if not ($config_path | path exists) {
        error make {msg: "runtime config file is missing"}
    }
    let settings = (runtime-settings-from-env)
    let config = (try { open $config_path } catch { null })
    if $config == null or not (is-record $config) {
        error make {msg: "runtime config file is not valid TOML"}
    }
    let updated = (apply-runtime-settings $config $mode $settings)
    $updated | to toml | save -f $config_path
}
