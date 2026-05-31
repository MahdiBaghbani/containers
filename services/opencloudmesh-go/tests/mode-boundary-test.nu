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

# Upstream config.Load boundary tests for the baked container config.
# Run: nu tests/mode-boundary-test.nu
#
# Skipped when /home/ubuntu/projects/ocm/repos/opencloudmesh-go is absent.
#
# The Go boundary verifies:
#   - strict, compat, and dev all load cleanly against the baked container
#     config; only these three are valid surface modes
#   - dev mode loads with tls.mode=static and ssrf.mode=strict because the
#     baked container config overrides those values; OCM_GO_MODE=dev means
#     upstream dev preset plus baked container TLS/SSRF overrides, not the
#     pure upstream DevConfig defaults (which set tls.mode and ssrf.mode
#     to "off")

use ../scripts/entrypoint-init.nu [setup_ssrf_runtime_route]
use ../scripts/lib/merge-partials-ocmgo.nu [merge_partial_configs]

def assert_eq [label: string, got: any, want: any] {
    if $got != $want {
        error make {
            msg: $"FAIL [$label]: got ($got | to nuon), want ($want | to nuon)"
        }
    }
}

# Returns the absolute path to the upstream opencloudmesh-go repo.
# The path is deterministic for this workspace layout.
def upstream_repo_path []: nothing -> string {
    "/home/ubuntu/projects/ocm/repos/opencloudmesh-go"
}

# Content of the transient Go test file placed in the upstream config package.
# Tests strict, compat, and dev only.
# DevOverrides verifies that OCM_GO_MODE=dev delivers upstream dev preset
# overlaid with baked container TLS/SSRF overrides, not pure upstream
# DevConfig defaults.
def go_boundary_test_content []: nothing -> string {
    [
        "package config_test"
        ""
        "import ("
        "    \"os\""
        "    \"testing\""
        "    \"github.com/MahdiBaghbani/opencloudmesh-go/internal/platform/config\""
        ")"
        ""
        "func TestContainerConfigBoundaryLoad(t *testing.T) {"
        "    configPath := os.Getenv(\"OCM_CONTAINER_CONFIG_PATH\")"
        "    if configPath == \"\" {"
        "        t.Skip(\"OCM_CONTAINER_CONFIG_PATH not set\")"
        "    }"
        "    tests := []struct {"
        "        mode string"
        "    }{"
        "        {\"strict\"},"
        "        {\"compat\"},"
        "        {\"dev\"},"
        "    }"
        "    for _, tt := range tests {"
        "        t.Run(tt.mode, func(t *testing.T) {"
        "            cfg, err := config.Load(config.LoaderOptions{"
        "                ConfigPath: configPath,"
        "                ModeFlag:   tt.mode,"
        "            })"
        "            if err != nil {"
        "                t.Fatalf(\"Load(mode=%q) error: %v\", tt.mode, err)"
        "            }"
        "            if cfg.Mode != tt.mode {"
        "                t.Errorf(\"mode %q: cfg.Mode=%q, want %q\", tt.mode, cfg.Mode, tt.mode)"
        "            }"
        "        })"
        "    }"
        "}"
        ""
        "// TestContainerConfigBoundaryDevOverrides checks that OCM_GO_MODE=dev"
        "// resolves to upstream dev preset PLUS baked container TLS/SSRF"
        "// overrides. The baked config.toml sets [tls] mode=\"static\" and"
        "// [outbound_http.ssrf] mode=\"strict\"; those must survive the dev"
        "// preset merge and not revert to the upstream DevConfig defaults."
        "func TestContainerConfigBoundaryDevOverrides(t *testing.T) {"
        "    configPath := os.Getenv(\"OCM_CONTAINER_CONFIG_PATH\")"
        "    if configPath == \"\" {"
        "        t.Skip(\"OCM_CONTAINER_CONFIG_PATH not set\")"
        "    }"
        "    cfg, err := config.Load(config.LoaderOptions{"
        "        ConfigPath: configPath,"
        "        ModeFlag:   \"dev\","
        "    })"
        "    if err != nil {"
        "        t.Fatalf(\"Load(mode=dev) error: %v\", err)"
        "    }"
        "    if cfg.TLS.Mode != \"static\" {"
        "        t.Errorf(\"dev: tls.mode=%q, want static (baked container override)\", cfg.TLS.Mode)"
        "    }"
        "    if cfg.OutboundHTTP.SSRF.Mode != \"strict\" {"
        "        t.Errorf(\"dev: ssrf.mode=%q, want strict (baked container override)\", cfg.OutboundHTTP.SSRF.Mode)"
        "    }"
        "}"
    ] | str join "\n"
}

def run_go_boundary_tests [upstream: string, config_path: string] {
    let config_pkg = $"($upstream)/internal/platform/config"
    let tmp_test_file = $"($config_pkg)/zz_ocm_container_boundary_test.go"

    # Write transient test file; removed in all paths via cleanup at end.
    go_boundary_test_content | save -f $tmp_test_file

    let result = (try {
        let output = (with-env {OCM_CONTAINER_CONFIG_PATH: $config_path} {
            ^go test -C $upstream -run "TestContainerConfig" ./internal/platform/config/ -v | complete
        })
        $output
    } catch {|err|
        rm -f $tmp_test_file
        error make {msg: $"go test dispatch failed: (try { $err.msg } catch { $err | into string })"}
    })

    rm -f $tmp_test_file

    if $result.exit_code != 0 {
        error make {
            msg: $"FAIL [go boundary]: go test exited ($result.exit_code)\n($result.stdout)\n($result.stderr)"
        }
    }

    let out = $result.stdout
    if not ($out | str contains "PASS") {
        error make {
            msg: $"FAIL [go boundary]: expected PASS in output:\n($out)"
        }
    }
}

def main [] {
    let upstream = (upstream_repo_path)
    if not ($upstream | path exists) {
        print $"SKIP: upstream repo absent at ($upstream), skipping Go boundary tests"
        return
    }

    # Resolve baked container config relative to this test file's location.
    let baked_config = ($env.FILE_PWD | path join "../configs/config.toml")
    if not ($baked_config | path exists) {
        error make {msg: $"baked container config not found at ($baked_config)"}
    }

    # Materialize the merged config artifact through the same flow the
    # entrypoint uses: copy baked config, run route setup (no-op with no
    # route envs), then merge any partials.  The resulting config.toml
    # is what upstream config.Load actually receives at container boot.
    let tmp = (^mktemp -d)
    let cfg_dir = $"($tmp)/configs"
    let partial_dir = $"($cfg_dir)/partial"

    let result = try {
        mkdir $cfg_dir
        mkdir $partial_dir
        ^cp $baked_config $"($cfg_dir)/config.toml"

        with-env {OCM_GO_ROUTE_PRIVATE_CIDRS: "", OCM_GO_ROUTE_SUFFIXES: ""} {
            setup_ssrf_runtime_route $cfg_dir $partial_dir
        }
        merge_partial_configs $cfg_dir $partial_dir

        let merged_config = $"($cfg_dir)/config.toml"
        run_go_boundary_tests $upstream $merged_config
        null
    } catch {|e| $e}

    ^rm -rf $tmp

    if $result != null {
        error make {msg: $result.msg}
    }

    print "PASS: Go config.Load boundary"
}
