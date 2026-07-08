#!/usr/bin/env nu

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

# Runtime contract tests for JupyterHub JUPYTER_HOST normalization, Python TLS
# helpers, jupyterhub_config.py local-helper imports, Nushell TLS preflight, and
# entrypoint-init.nu. Run from repo root or service dir:
#   nu services/jupyterhub/tests/runtime-contract-test.nu

use ../scripts/lib/tls.nu [
    resolve-jupyterhub-tls-paths
    validate-jupyterhub-tls-contract
]

def service_root [] {
    $env.CURRENT_FILE | path dirname | path join ".."
}

def helpers_config_dir [] {
    service_root | path join "config"
}

def jupyterhub_config_path [] {
    helpers_config_dir | path join "jupyterhub_config.py"
}

def entrypoint_init_path [] {
    service_root | path join "scripts" "entrypoint-init.nu"
}

def assert_eq [label: string, got: any, want: any] {
    if $got != $want {
        error make {
            msg: $"FAIL [$label]: got ($got | to nuon), want ($want | to nuon)"
        }
    }
}

def assert_contains [label: string, haystack: string, needle: string] {
    if not ($haystack | str contains $needle) {
        error make {
            msg: $"FAIL [$label]: expected to find ($needle | to nuon) in:\n($haystack)"
        }
    }
}

def assert_throws_contains [label: string, thunk: closure, needle: string] {
    let err = (try {
        do $thunk
        null
    } catch {|caught|
        $caught
    })

    if $err == null {
        error make {
            msg: $"FAIL [$label]: expected error containing ($needle | to nuon), got none"
        }
    }

    let msg = (try { $err.msg } catch { $err | into string })
    if not ($msg | str contains $needle) {
        error make {
            msg: $"FAIL [$label]: expected error containing ($needle | to nuon), got ($msg | to nuon)"
        }
    }
}

def py_run [code: string, args: list<string>] {
    let pyfile = (^mktemp --suffix=.py)
    $code | save -f $pyfile
    let result = (try {
        (^python3 $pyfile ...$args | complete)
    } finally {
        ^rm -f $pyfile
    })
    $result
}

def py_helper_stdout [helper: string, args: list<string>] {
    let config_dir = (helpers_config_dir)
    let argv = ([$config_dir] | append $args)
    let code = ([
        "import sys"
        "sys.path.insert(0, sys.argv[1])"
        "from jupyterhub_helpers import __HELPER__"
        "print(__HELPER__(*sys.argv[2:]))"
    ] | str join (char newline) | str replace -a "__HELPER__" $helper)
    let result = (py_run $code $argv)
    if $result.exit_code != 0 {
        error make {
            msg: $"python ($helper) failed: ($result.stderr | str trim)"
        }
    }
    $result.stdout | str trim
}

def py_helper_raises [label: string, helper: string, needle: string, args: list<string>] {
    let config_dir = (helpers_config_dir)
    let argv = ([$config_dir] | append $args)
    let code = ([
        "import sys"
        "sys.path.insert(0, sys.argv[1])"
        "from jupyterhub_helpers import __HELPER__"
        "try:"
        "    __HELPER__(*sys.argv[2:])"
        "except Exception as exc:"
        "    print(str(exc), file=sys.stderr)"
        "    sys.exit(1)"
        "print(\"unexpected success\")"
    ] | str join (char newline) | str replace -a "__HELPER__" $helper)
    let result = (py_run $code $argv)
    if $result.exit_code == 0 {
        error make {
            msg: $"FAIL [$label]: expected ($helper) to fail, got success"
        }
    }
    assert_contains $label ($result.stderr | str trim) $needle
}

def make_tls_fixture [
    cert_name: string,
    with_cert: bool = true,
    with_key: bool = true,
] {
    let tmp = (^mktemp -d)
    let cert = $"($tmp)/($cert_name).crt"
    let key = $"($tmp)/($cert_name).key"
    if $with_cert {
        "fixture-cert" | save -f $cert
    }
    if $with_key {
        "fixture-key" | save -f $key
    }
    {tmp: $tmp, cert: $cert, key: $key}
}

def run_entrypoint_init [env_vars: record] {
    let script = (entrypoint_init_path)
    (with-env $env_vars {
        (^nu $script | complete)
    })
}

# --- jupyterhub_helpers: JUPYTER_HOST normalization ---

def test_host_bare_and_https_public_urls [] {
    let cases = [
        {
            label: "bare hostname (proxy / standard HTTPS)"
            host: "jupyterhub1.docker"
            bare: "jupyterhub1.docker"
            public: "https://jupyterhub1.docker"
            oauth: "https://jupyterhub1.docker/hub/oauth_callback"
        }
        {
            label: "https hostname without port"
            host: "https://jupyterhub1.docker"
            bare: "jupyterhub1.docker"
            public: "https://jupyterhub1.docker"
            oauth: "https://jupyterhub1.docker/hub/oauth_callback"
        }
        {
            label: "bare host with explicit 443"
            host: "jupyterhub1.docker:443"
            bare: "jupyterhub1.docker"
            public: "https://jupyterhub1.docker"
            oauth: "https://jupyterhub1.docker/hub/oauth_callback"
        }
        {
            label: "https host with explicit 443"
            host: "https://jupyterhub1.docker:443"
            bare: "jupyterhub1.docker"
            public: "https://jupyterhub1.docker"
            oauth: "https://jupyterhub1.docker/hub/oauth_callback"
        }
        {
            label: "https trailing slash"
            host: "https://jupyterhub1.docker/"
            bare: "jupyterhub1.docker"
            public: "https://jupyterhub1.docker"
            oauth: "https://jupyterhub1.docker/hub/oauth_callback"
        }
    ]

    for case in $cases {
        let bare = (py_helper_stdout "normalize_jupyter_host_bare" [$case.host])
        assert_eq $"host bare ($case.label)" $bare $case.bare

        let public = (py_helper_stdout "public_url_from_jupyter_host" [$case.host])
        assert_eq $"public_url ($case.label)" $public $case.public

        let oauth = (py_helper_stdout "oauth_callback_url_from_jupyter_host" [$case.host])
        assert_eq $"oauth_callback ($case.label)" $oauth $case.oauth
    }
}

def test_host_http_rejected [] {
    (py_helper_raises
        "http scheme rejected"
        "normalize_jupyter_host_bare"
        "http:// is not allowed"
        ["http://jupyterhub1.docker"])
}

def test_host_non_443_port_rejected [] {
    (py_helper_raises
        "non-443 port rejected"
        "normalize_jupyter_host_bare"
        "non-443 port"
        ["jupyterhub1.docker:8443"])
}

# --- jupyterhub_config.py: traitlets-like exec imports local helpers ---

def py_exec_jupyterhub_config [cert_path: string, key_path: string] {
    let config_path = (jupyterhub_config_path)
    let argv = [$config_path $cert_path $key_path]
    let code = ([
        "import os"
        "import sys"
        "import types"
        ""
        "config_path = sys.argv[1]"
        "cert_path = sys.argv[2]"
        "key_path = sys.argv[3]"
        ""
        "def apply_defaults(c):"
        "    return None"
        ""
        "stub_config = types.ModuleType(\"nextcloud_ocm_jupyterhub.config\")"
        "stub_config.apply_defaults = apply_defaults"
        "stub_pkg = types.ModuleType(\"nextcloud_ocm_jupyterhub\")"
        "stub_pkg.config = stub_config"
        "sys.modules[\"nextcloud_ocm_jupyterhub\"] = stub_pkg"
        "sys.modules[\"nextcloud_ocm_jupyterhub.config\"] = stub_config"
        ""
        "os.environ.update({"
        "    \"NEXTCLOUD_HOST\": \"nextcloud.docker\","
        "    \"NEXTCLOUD_CLIENT_ID\": \"test-client-id\","
        "    \"NEXTCLOUD_CLIENT_SECRET\": \"test-client-secret\","
        "    \"JUPYTERHUB_API_KEY\": \"test-api-key\","
        "    \"JUPYTERHUB_OCM_API_KEY\": \"test-ocm-api-key\","
        "    \"JUPYTERHUB_CRYPT_KEY\": \"test-crypt-key\","
        "    \"OCM_TRUSTED_BACK_CHANNEL_DOMAINS\": \"nextcloud.docker\","
        "    \"OCM_TRUSTED_ISSUER_DOMAINS\": \"nextcloud.docker\","
        "    \"JUPYTER_HOST\": \"jupyterhub1.docker\","
        "    \"JUPYTERHUB_SSL_CERT\": cert_path,"
        "    \"JUPYTERHUB_SSL_KEY\": key_path,"
        "    \"DOCKYPODY_TLS_CERT_NAME\": \"\","
        "})"
        ""
        "class _NS:"
        "    pass"
        ""
        "c = _NS()"
        "c.JupyterHub = _NS()"
        "c.Spawner = _NS()"
        "c.Authenticator = _NS()"
        "c.NextcloudOAuthenticator = _NS()"
        "c.CryptKeeper = _NS()"
        ""
        "globals_dict = {"
        "    \"c\": c,"
        "    \"__name__\": \"__main__\","
        "    \"__file__\": config_path,"
        "    \"__builtins__\": __builtins__,"
        "}"
        ""
        "with open(config_path, encoding=\"utf-8\") as fh:"
        "    source = fh.read()"
        ""
        "exec(compile(source, config_path, \"exec\"), globals_dict)"
        ""
        "assert c.JupyterHub.spawner_class == \"simple\""
        "assert c.JupyterHub.bind_url == \"https://:443\""
        "assert c.JupyterHub.ssl_cert == cert_path"
        "assert c.JupyterHub.ssl_key == key_path"
        "assert c.JupyterHub.public_url == \"https://jupyterhub1.docker\""
        "assert c.NextcloudOAuthenticator.oauth_callback_url == \"https://jupyterhub1.docker/hub/oauth_callback\""
        "import json"
        "print(json.dumps({"
        "    \"bind_url\": c.JupyterHub.bind_url,"
        "    \"ssl_cert\": c.JupyterHub.ssl_cert,"
        "    \"ssl_key\": c.JupyterHub.ssl_key,"
        "    \"public_url\": c.JupyterHub.public_url,"
        "    \"oauth_callback_url\": c.NextcloudOAuthenticator.oauth_callback_url,"
        "}))"
    ] | str join (char newline))
    (py_run $code $argv)
}

def test_jupyterhub_config_imports_local_helpers [] {
    let fixture = (make_tls_fixture "jupyterhub")
    let result = try {
        let out = (py_exec_jupyterhub_config $fixture.cert $fixture.key)
        if $out.exit_code != 0 {
            error make {
                msg: $"jupyterhub_config exec failed: ($out.stderr | str trim)"
            }
        }
        let cfg = ($out.stdout | str trim | from json)
        assert_eq "config bind_url" $cfg.bind_url "https://:443"
        assert_eq "config ssl_cert" $cfg.ssl_cert $fixture.cert
        assert_eq "config ssl_key" $cfg.ssl_key $fixture.key
        assert_eq "config public_url" $cfg.public_url "https://jupyterhub1.docker"
        assert_eq "config oauth_callback_url" $cfg.oauth_callback_url "https://jupyterhub1.docker/hub/oauth_callback"
        null
    } catch {|e| $e}

    ^rm -rf $fixture.tmp

    if $result != null {
        error make {msg: $result.msg}
    }
}

# --- jupyterhub_helpers: require_tls_file ---

def test_require_tls_file_existing [] {
    let tmp = (^mktemp -d)
    let cert = $"($tmp)/test.crt"
    "ok" | save -f $cert

    let result = try {
        py_helper_stdout "require_tls_file" [$cert "JUPYTERHUB_SSL_CERT"]
        null
    } catch {|e| $e}

    ^rm -rf $tmp

    if $result != null {
        error make {msg: $result.msg}
    }
}

def test_require_tls_file_unset [] {
    (py_helper_raises
        "tls file unset"
        "require_tls_file"
        "JUPYTERHUB_SSL_CERT is unset"
        ["" "JUPYTERHUB_SSL_CERT"])
}

def test_require_tls_file_missing [] {
    (py_helper_raises
        "tls file missing"
        "require_tls_file"
        "not found at /no/such/tls.crt"
        ["/no/such/tls.crt" "JUPYTERHUB_SSL_CERT"])
}

# --- jupyterhub_helpers: resolve_tls_paths default discovery ---

def parse_py_tuple_pair [out: string] {
    let trimmed = ($out | str trim)
    if not ($trimmed | str starts-with "(") {
        error make {msg: $"expected Python tuple, got ($trimmed)"}
    }
    let inner = ($trimmed | str substring 1..-2)
    let parts = ($inner | split row ", ")
    if ($parts | length) != 2 {
        error make {msg: $"expected 2-element tuple, got ($parts | length)"}
    }
    {
        cert: ($parts.0 | str trim | str replace -a "'" "")
        key: ($parts.1 | str trim | str replace -a "'" "")
    }
}

def test_resolve_tls_paths_discovers_defaults [] {
    let fixture = (make_tls_fixture "jupyterhub")
    let result = try {
        let out = (py_helper_stdout "resolve_tls_paths" [
            "jupyterhub"
            ""
            ""
            $fixture.tmp
        ])
        let got = (parse_py_tuple_pair $out)
        assert_eq "resolve_tls_paths cert" $got.cert $fixture.cert
        assert_eq "resolve_tls_paths key" $got.key $fixture.key
        null
    } catch {|e| $e}

    ^rm -rf $fixture.tmp

    if $result != null {
        error make {msg: $result.msg}
    }
}

def test_resolve_tls_paths_missing_default_cert [] {
    let fixture = (make_tls_fixture "jupyterhub" false true)
    (py_helper_raises
        "missing default cert"
        "resolve_tls_paths"
        "not found at"
        ["jupyterhub" "" "" $fixture.tmp])
    ^rm -rf $fixture.tmp
}

def test_resolve_tls_paths_missing_default_key [] {
    let fixture = (make_tls_fixture "jupyterhub" true false)
    (py_helper_raises
        "missing default key"
        "resolve_tls_paths"
        "not found at"
        ["jupyterhub" "" "" $fixture.tmp])
    ^rm -rf $fixture.tmp
}

def test_resolve_tls_paths_unset_cert_name [] {
    (py_helper_raises
        "unset cert name"
        "resolve_tls_paths"
        "DOCKYPODY_TLS_CERT_NAME is unset"
        ["" "" ""])
}

# --- scripts/lib/tls.nu: resolve and validate ---

def test_tls_resolve_discovers_defaults [] {
    let fixture = (make_tls_fixture "jupyterhub")
    let result = try {
        let got = (with-env {
            DOCKYPODY_TLS_CERT_NAME: "jupyterhub"
            JUPYTERHUB_SSL_CERT: ""
            JUPYTERHUB_SSL_KEY: ""
        } {
            resolve-jupyterhub-tls-paths $fixture.tmp
        })
        assert_eq "resolve cert" $got.cert $fixture.cert
        assert_eq "resolve key" $got.key $fixture.key
        null
    } catch {|e| $e}

    ^rm -rf $fixture.tmp

    if $result != null {
        error make {msg: $result.msg}
    }
}

def test_tls_validate_missing_cert_fails_fast [] {
    let fixture = (make_tls_fixture "jupyterhub" false true)
    (assert_throws_contains "missing cert validate" {||
        with-env {
            DOCKYPODY_TLS_CERT_NAME: "jupyterhub"
            JUPYTERHUB_SSL_CERT: ""
            JUPYTERHUB_SSL_KEY: ""
        } {
            validate-jupyterhub-tls-contract $fixture.tmp
        }
    } "certificate not found")
    ^rm -rf $fixture.tmp
}

def test_tls_validate_missing_key_fails_fast [] {
    let fixture = (make_tls_fixture "jupyterhub" true false)
    (assert_throws_contains "missing key validate" {||
        with-env {
            DOCKYPODY_TLS_CERT_NAME: "jupyterhub"
            JUPYTERHUB_SSL_CERT: ""
            JUPYTERHUB_SSL_KEY: ""
        } {
            validate-jupyterhub-tls-contract $fixture.tmp
        }
    } "key not found")
    ^rm -rf $fixture.tmp
}

def test_tls_validate_honors_cert_override [] {
    let fixture = (make_tls_fixture "jupyterhub")
    let override = $"($fixture.tmp)/override.crt"
    "override-cert" | save -f $override

    let result = try {
        let got = (with-env {
            DOCKYPODY_TLS_CERT_NAME: "jupyterhub"
            JUPYTERHUB_SSL_CERT: $override
            JUPYTERHUB_SSL_KEY: ""
        } {
            validate-jupyterhub-tls-contract $fixture.tmp
        })
        assert_eq "override cert kept" $got.cert $override
        assert_eq "discovered key" $got.key $fixture.key
        null
    } catch {|e| $e}

    ^rm -rf $fixture.tmp

    if $result != null {
        error make {msg: $result.msg}
    }
}

def test_tls_validate_override_missing_fails_fast [] {
    let fixture = (make_tls_fixture "jupyterhub")
    (assert_throws_contains "override cert missing" {||
        with-env {
            DOCKYPODY_TLS_CERT_NAME: "jupyterhub"
            JUPYTERHUB_SSL_CERT: "/no/such/override.crt"
            JUPYTERHUB_SSL_KEY: ""
        } {
            validate-jupyterhub-tls-contract $fixture.tmp
        }
    } "JUPYTERHUB_SSL_CERT override not found")
    ^rm -rf $fixture.tmp
}

# --- entrypoint-init.nu: subprocess preflight ---

def test_entrypoint_init_success [] {
    let fixture = (make_tls_fixture "jupyterhub")
    let result = try {
        let out = (run_entrypoint_init {
            DOCKYPODY_TLS_CERT_NAME: ""
            JUPYTERHUB_SSL_CERT: $fixture.cert
            JUPYTERHUB_SSL_KEY: $fixture.key
        })
        if $out.exit_code != 0 {
            error make {msg: $"entrypoint-init failed: ($out.stderr)"}
        }
        assert_contains "preflight stdout" $out.stdout "TLS preflight OK"
        assert_contains "cert path in stdout" $out.stdout $fixture.cert
        assert_contains "key path in stdout" $out.stdout $fixture.key
        null
    } catch {|e| $e}

    ^rm -rf $fixture.tmp

    if $result != null {
        error make {msg: $result.msg}
    }
}

def test_entrypoint_init_missing_cert_fails [] {
    let fixture = (make_tls_fixture "jupyterhub")
    let result = try {
        let out = (run_entrypoint_init {
            DOCKYPODY_TLS_CERT_NAME: ""
            JUPYTERHUB_SSL_CERT: "/no/such/override.crt"
            JUPYTERHUB_SSL_KEY: $fixture.key
        })
        if $out.exit_code == 0 {
            error make {msg: "expected entrypoint-init to fail on missing cert"}
        }
        assert_contains "missing cert stderr" $out.stderr "JUPYTERHUB_SSL_CERT override not found"
        null
    } catch {|e| $e}

    ^rm -rf $fixture.tmp

    if $result != null {
        error make {msg: $result.msg}
    }
}

def main [] {
    test_host_bare_and_https_public_urls
    test_host_http_rejected
    test_host_non_443_port_rejected
    test_jupyterhub_config_imports_local_helpers
    test_require_tls_file_existing
    test_require_tls_file_unset
    test_require_tls_file_missing
    test_resolve_tls_paths_discovers_defaults
    test_resolve_tls_paths_missing_default_cert
    test_resolve_tls_paths_missing_default_key
    test_resolve_tls_paths_unset_cert_name
    test_tls_resolve_discovers_defaults
    test_tls_validate_missing_cert_fails_fast
    test_tls_validate_missing_key_fails_fast
    test_tls_validate_honors_cert_override
    test_tls_validate_override_missing_fails_fast
    test_entrypoint_init_success
    test_entrypoint_init_missing_cert_fails

    print "PASS: all jupyterhub runtime contract tests"
}
