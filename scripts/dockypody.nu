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

# Unified CLI for DockyPody build system
# Supports both direct invocation and module import
# See docs/reference/cli-reference.md for usage

# Import only help functions for non-subcommand CLIs (build, test, validate)
# Subcommand-based CLIs (tls, ssh, ci, docs) handle help internally via the
# positional "help" subcommand
use ./lib/build/cli.nu [build-help]
use ./lib/validate/cli.nu [validate-help]
use ./lib/test/cli.nu [test-help]
use ./lib/inspect/cli.nu [inspect-help]

def show-help [] {
  print "dockypody - DockyPody unified CLI"
  print ""
  print "Usage: nu scripts/dockypody.nu <command> [subcommand] [options]"
  print ""
  print "Commands:"
  print "  build              Build container images"
  print "  test               Run test suites"
  print "  validate           Validate configurations"
  print "  inspect <subcommand> Inspect guard-owned effective config"
  print "  tls <subcommand>   Manage TLS certificates (ca, certs, clean)"
  print "  ssh <subcommand>   Manage SSH keypair (key)"
  print "  ci <subcommand>    CI helper operations (list-deps, load-deps, images, ghcr-purge, etc.)"
  print "  docs <subcommand>  Documentation tools (lint)"
  print ""
  print "Examples:"
  print "  nu scripts/dockypody.nu build --service gaia"
  print "  nu scripts/dockypody.nu build --service gaia --all-versions"
  print "  nu scripts/dockypody.nu test --suite defaults"
  print "  nu scripts/dockypody.nu tls ca"
  print "  nu scripts/dockypody.nu ssh key"
  print "  nu scripts/dockypody.nu ssh key --force"
  print "  nu scripts/dockypody.nu ci list-deps --service nextcloud"
  print "  nu scripts/dockypody.nu docs lint"
  print ""
  print "Run with <command> help for command-specific options."
}

# Main entrypoint - supports direct invocation: nu scripts/dockypody.nu build --service foo
# Help contract is the positional "help" subcommand, e.g. `dockypody.nu help`,
# `dockypody.nu build help`, `dockypody.nu tls help`. Nushell's auto-help
# intercepts `--help`/`-h` before this body runs, so those are not DockyPody-owned.
def main [
  command?: string,           # Command: build, test, validate, inspect, tls, ssh, ci, docs, help
  subcommand?: string,        # Subcommand or "help" for command-specific help
  # Build flags
  --service: string = "",
  --all-services,
  --push,
  --latest,
  --extra-tag: string = "",
  --provenance,
  --version: string = "",
  --all-versions,
  --versions: string = "",
  --latest-only,
  --platform: string = "",
  --matrix-json,
  --progress: string = "auto",
  --cache-bust: string = "",
  --no-cache,
  --show-build-order,
  --dep-cache: string = "",
  --push-deps,
  --tag-deps,
  --fail-fast,
  --pull: string = "",
  --cache-match: string = "",
  --disk-monitor: string = "off",
  --prune-cache-mounts,
  # Test flags
  --suite: string = "all",
  # Validate flags
  --manifests-only,
  # Plane (build, validate, inspect)
  --plane: string = "tracked",
  # TLS/CI flags
  --filter: string = "",
  --service-ca-only,
  --skip-shared-ca,
  --keep-empty-dirs,
  --force,
  --target: string = "",
  --ref: string = "",
  --sha: string = "",
  --dependencies: string = "",
  --transitive,
  --debug,
  --partial-success,
  # Docs flags
  --fix,
  # Common flags
  --dry-run,
  --max-deletes: int = 0,
  --verbose
] {
  # Top-level help: positional "help" or no command. `--help`/`-h` never reach
  # here because Nushell's auto-help intercepts them before main runs.
  if $command == null or $command == "help" {
    show-help
    return
  }
  
  match $command {
    "ssh" => {
      let subcmd = if $subcommand == null { "help" } else { $subcommand }
      run-ssh-command $subcmd $force
    }
    "build" => {
      if $subcommand == "help" {
        build-help
        return
      }
      run-build-command {
        service: $service
        all_services: $all_services
        push: $push
        latest: $latest
        extra_tag: $extra_tag
        provenance: $provenance
        version: $version
        all_versions: $all_versions
        versions: $versions
        latest_only: $latest_only
        platform: $platform
        matrix_json: $matrix_json
        progress: $progress
        cache_bust: $cache_bust
        no_cache: $no_cache
        show_build_order: $show_build_order
        dep_cache: $dep_cache
        push_deps: $push_deps
        tag_deps: $tag_deps
        fail_fast: $fail_fast
        pull: $pull
        cache_match: $cache_match
        disk_monitor: $disk_monitor
        prune_cache_mounts: $prune_cache_mounts,
        plane: $plane
      }
    }
    "test" => {
      if $subcommand == "help" {
        test-help
        return
      }
      run-test-command $suite $verbose
    }
    "validate" => {
      if $subcommand == "help" {
        validate-help
        return
      }
      run-validate-command $service $all_services $manifests_only $plane
    }
    "inspect" => {
      let subcmd = if $subcommand == null { "help" } else { $subcommand }
      if $subcmd == "help" {
        inspect-help
        return
      }
      run-inspect-command $subcmd $service $version $platform $plane
    }
    "tls" => {
      # Default missing subcommand to "help"; tls-cli handles it internally.
      let subcmd = if $subcommand == null { "help" } else { $subcommand }
      let filter_list = if ($filter | str length) > 0 { $filter | split row "," } else { [] }
      let service_list = if ($service | str length) > 0 { $service | split row "," } else { [] }
      run-tls-command $subcmd $service_list $filter_list $service_ca_only $skip_shared_ca $keep_empty_dirs $force $dry_run $verbose
    }
    "ci" => {
      # Default missing subcommand to "help"; ci-cli handles it internally.
      let subcmd = if $subcommand == null { "help" } else { $subcommand }
      run-ci-command $subcmd $service $version $platform $dependencies $target $ref $sha $transitive $debug $dry_run $max_deletes $force $partial_success $plane
    }
    "docs" => {
      # Default missing subcommand to "help"; docs-cli handles it internally.
      let subcmd = if $subcommand == null { "help" } else { $subcommand }
      run-docs-command $subcmd $fix
    }
    _ => {
      print $"Unknown command: ($command)"
      print ""
      show-help
      exit 1
    }
  }
}

# Internal command handlers

def run-build-command [flags: record] {
  use ./lib/build/cli.nu [build-cli]
  
  build-cli --service $flags.service --all-services=$flags.all_services --push=$flags.push --latest=$flags.latest --extra-tag $flags.extra_tag --provenance=$flags.provenance --version $flags.version --all-versions=$flags.all_versions --versions $flags.versions --latest-only=$flags.latest_only --platform $flags.platform --matrix-json=$flags.matrix_json --progress $flags.progress --cache-bust $flags.cache_bust --no-cache=$flags.no_cache --show-build-order=$flags.show_build_order --dep-cache $flags.dep_cache --push-deps=$flags.push_deps --tag-deps=$flags.tag_deps --fail-fast=$flags.fail_fast --pull $flags.pull --cache-match $flags.cache_match --disk-monitor $flags.disk_monitor --prune-cache-mounts=$flags.prune_cache_mounts --plane $flags.plane
}

def run-test-command [suite: string, verbose: bool] {
  use ./lib/test/cli.nu [test-cli]
  test-cli $suite $verbose
}

def run-validate-command [service: string, all_services: bool, manifests_only: bool, plane: string] {
  use ./lib/validate/cli.nu [validate-cli]
  validate-cli {
    service: $service,
    all_services: $all_services,
    manifests_only: $manifests_only,
    plane: $plane
  }
}

def run-inspect-command [
  subcommand: string,
  service: string,
  version: string,
  platform: string,
  plane: string
] {
  use ./lib/inspect/cli.nu [inspect-cli]
  inspect-cli $subcommand {
    service: $service,
    version: $version,
    platform: $platform,
    plane: $plane
  }
}

def run-ssh-command [
  subcommand: string,
  force: bool
] {
  use ./lib/ssh/cli.nu [ssh-cli]
  ssh-cli $subcommand {
    force: $force
  }
}

def run-tls-command [
  subcommand: string,
  service_list: list<string>,
  filter_list: list<string>,
  service_ca_only: bool,
  skip_shared_ca: bool,
  keep_empty_dirs: bool,
  force: bool,
  dry_run: bool,
  verbose: bool
] {
  use ./lib/tls/cli.nu [tls-cli]
  tls-cli $subcommand {
    service_list: $service_list,
    filter_list: $filter_list,
    service_ca_only: $service_ca_only,
    skip_shared_ca: $skip_shared_ca,
    keep_empty_dirs: $keep_empty_dirs,
    force: $force,
    dry_run: $dry_run,
    verbose: $verbose
  }
}

def run-ci-command [
  subcommand: string,
  service: string,
  version: string,
  platform: string,
  dependencies: string,
  target: string,
  ref: string,
  sha: string,
  transitive: bool,
  debug: bool,
  dry_run: bool,
  max_deletes: int,
  force: bool,
  partial_success: bool,
  plane: string
] {
  use ./lib/ci/cli.nu [ci-cli]
  ci-cli $subcommand {
    service: $service,
    version: $version,
    platform: $platform,
    dependencies: $dependencies,
    target: $target,
    ref: $ref,
    sha: $sha,
    transitive: $transitive,
    debug: $debug,
    dry_run: $dry_run,
    max_deletes: $max_deletes,
    force: $force,
    partial_success: $partial_success,
    plane: $plane
  }
}

def run-docs-command [subcommand: string, fix: bool] {
  use ./lib/docs/cli.nu [docs-cli]
  docs-cli $subcommand {
    files: [],
    fix: $fix
  }
}
