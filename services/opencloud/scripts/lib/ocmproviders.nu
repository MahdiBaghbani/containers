# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images

# OpenCloud service-local OCM provider JSON generator.
# Staged flat into the image at /usr/bin/lib/ocmproviders.nu during Docker build.
#
# Indexed env var schema (i = 0, 1, 2, ... stops when OCM_PROVIDER_{i}_DOMAIN absent):
#   OCM_PROVIDER_{i}_NAME            display name (required; fails if empty)
#   OCM_PROVIDER_{i}_DOMAIN          provider domain (detection key; stops loop if absent)
#   OCM_PROVIDER_{i}_FULL_NAME       optional; default: "{name} provider"
#   OCM_PROVIDER_{i}_ORGANIZATION    optional; default: name
#   OCM_PROVIDER_{i}_HOMEPAGE        optional; default: "https://{domain}"
#   OCM_PROVIDER_{i}_DESCRIPTION     optional; default: "{name} cloud storage"
#   OCM_PROVIDER_{i}_OCM_ENDPOINT    full URL used as endpoint.path for the OCM
#                                    service; takes precedence over OCM_PATH
#   OCM_PROVIDER_{i}_OCM_PATH        path-only fallback for endpoint.path when
#                                    OCM_ENDPOINT is absent
#   OCM_PROVIDER_{i}_OCM_HOST        OCM service hostname; scheme-less values
#                                    are normalized to "http://{host}"
#   OCM_PROVIDER_{i}_WEBDAV_ENDPOINT full URL used as endpoint.path for the
#                                    WebDAV service; takes precedence over
#                                    WEBDAV_PATH
#   OCM_PROVIDER_{i}_WEBDAV_PATH     path-only fallback for endpoint.path when
#                                    WEBDAV_ENDPOINT is absent
#   OCM_PROVIDER_{i}_WEBDAV_HOST     WebDAV service hostname; scheme-less values
#                                    are normalized to "https://{host}/"; values
#                                    with a scheme but no trailing slash get "/"
#                                    appended

# Prepend "http://" when the host string carries no URI scheme.
def normalize-ocm-host [host: string] {
    if ($host | str contains "://") { $host } else { $"http://($host)" }
}

# Prepend "https://" when the host string carries no URI scheme; append "/"
# when the result has no trailing slash.
def normalize-webdav-host [host: string] {
    let with_scheme = (
        if ($host | str contains "://") { $host } else { $"https://($host)" }
    )
    if ($with_scheme | str ends-with "/") { $with_scheme } else { $"($with_scheme)/" }
}

def build-provider-record [i: int] {
    let p         = $"OCM_PROVIDER_($i)_"
    let name      = ($env | get --optional $"($p)NAME"          | default "" | str trim)
    let domain    = ($env | get --optional $"($p)DOMAIN"        | default "" | str trim)
    let full_name = ($env | get --optional $"($p)FULL_NAME"     | default $"($name) provider")
    let org       = ($env | get --optional $"($p)ORGANIZATION"  | default $name)
    let homepage  = ($env | get --optional $"($p)HOMEPAGE"      | default $"https://($domain)")
    let desc      = ($env | get --optional $"($p)DESCRIPTION"   | default $"($name) cloud storage")

    if ($name | is-empty) {
        error make {msg: $"[ocmproviders] OCM_PROVIDER_($i)_NAME is required but empty"}
    }

    let ocm_endpoint  = ($env | get --optional $"($p)OCM_ENDPOINT"    | default "" | str trim)
    let ocm_path_raw  = ($env | get --optional $"($p)OCM_PATH"         | default "" | str trim)
    let wdav_endpoint = ($env | get --optional $"($p)WEBDAV_ENDPOINT"  | default "" | str trim)
    let wdav_path_raw = ($env | get --optional $"($p)WEBDAV_PATH"      | default "" | str trim)
    let ocm_host_raw  = ($env | get --optional $"($p)OCM_HOST"         | default "" | str trim)
    let wdav_host_raw = ($env | get --optional $"($p)WEBDAV_HOST"      | default "" | str trim)

    # endpoint.path: full OCM_ENDPOINT wins; OCM_PATH is path-only fallback.
    let ocm_ep_path  = if not ($ocm_endpoint | is-empty) { $ocm_endpoint } else { $ocm_path_raw }
    let wdav_ep_path = if not ($wdav_endpoint | is-empty) { $wdav_endpoint } else { $wdav_path_raw }

    # Normalize host strings: add scheme if absent; add trailing slash for webdav.
    let ocm_host  = if ($ocm_host_raw | is-empty)  { "" } else { normalize-ocm-host $ocm_host_raw }
    let wdav_host = if ($wdav_host_raw | is-empty) { "" } else { normalize-webdav-host $wdav_host_raw }

    if (($ocm_host | is-empty) and ($ocm_ep_path | is-empty)) {
        error make {msg: $"[ocmproviders] OCM_PROVIDER_($i): OCM service requires at least OCM_HOST or OCM_ENDPOINT/OCM_PATH"}
    }
    if (($wdav_host | is-empty) and ($wdav_ep_path | is-empty)) {
        error make {msg: $"[ocmproviders] OCM_PROVIDER_($i): WebDAV service requires at least WEBDAV_HOST or WEBDAV_ENDPOINT/WEBDAV_PATH"}
    }

    {
        name:         $name,
        full_name:    $full_name,
        organization: $org,
        domain:       $domain,
        homepage:     $homepage,
        description:  $desc,
        services: [
            {
                endpoint: {
                    type: {
                        name: "OCM",
                        description: $"($name) Open Cloud Mesh API"
                    },
                    name: $"($name) - OCM API",
                    path: $ocm_ep_path,
                    is_monitored: true
                },
                api_version: "0.0.1",
                host: $ocm_host
            },
            {
                endpoint: {
                    type: {
                        name: "Webdav",
                        description: $"($name) Webdav API"
                    },
                    name: $"($name) - Webdav API",
                    path: $wdav_ep_path,
                    is_monitored: true
                },
                api_version: "0.0.1",
                host: $wdav_host
            }
        ]
    }
}

# True when at least one indexed provider is configured (OCM_PROVIDER_0_DOMAIN set).
export def has-indexed-providers [] {
    let v = ($env | get --optional "OCM_PROVIDER_0_DOMAIN" | default "" | str trim)
    not ($v | is-empty)
}

# Collect provider records from indexed env vars (0-based, stops at first missing DOMAIN).
export def collect-providers [] {
    mut providers = []
    mut i = 0
    loop {
        let domain_key = $"OCM_PROVIDER_($i)_DOMAIN"
        let domain_val = ($env | get --optional $domain_key | default "" | str trim)
        if ($domain_val | is-empty) { break }
        $providers = ($providers | append (build-provider-record $i))
        $i = $i + 1
    }
    $providers
}

# Generate provider JSON from indexed env vars and write to dst.
export def generate-ocmproviders [dst: string] {
    let providers = (collect-providers)
    if ($providers | is-empty) {
        error make {msg: "[ocmproviders] generate called but no indexed providers found in env"}
    }
    let parent = ($dst | path dirname)
    if not ($parent | path exists) { mkdir $parent }
    $providers | to json --indent 2 | save -f $dst
    print $"[ocmproviders] generated ($providers | length) providers -> ($dst)"
}
