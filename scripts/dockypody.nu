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
# Subcommand-based CLIs (tls, ci, docs) handle help internally via "help" subcommand
use ./lib/build/cli.nu [build-help]
use ./lib/validate/cli.nu [validate-help]
use ./lib/test/cli.nu [test-help]

def show-help [] {
  print "dockypody - DockyPody unified CLI"
  print ""
  print "Usage: nu scripts/dockypody.nu <command> [subcommand] [options]"
  print ""
  print "Commands:"
  print "  build              Build container images"
  print "  test               Run test suites"
  print "  validate           Validate configurations"
  print "  tls <subcommand>   Manage TLS certificates (ca, certs, clean, sync)"
  print "  ci <subcommand>    CI helper operations (list-deps, load-deps, images, etc.)"
  print "  docs <subcommand>  Documentation tools (lint)"
  print ""
  print "Examples:"
  print "  nu scripts/dockypody.nu build --service gaia"
  print "  nu scripts/dockypody.nu build --service gaia --all-versions"
  print "  nu scripts/dockypody.nu test --suite defaults"
  print "  nu scripts/dockypody.nu tls ca"
  print "  nu scripts/dockypody.nu ci list-deps --service nextcloud"
  print "  nu scripts/dockypody.nu docs lint"
  print ""
  print "Run with <command> help for command-specific options."
}

# Main entrypoint - supports direct invocation: nu scripts/dockypody.nu build --service foo
# Note: --help is handled via positional args to avoid Nushell's auto-help interception
def main [
  command?: string,           # Command: build, test, validate, tls, ci, help
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
  # TLS/CI flags
  --filter: string = "",
  --force-copy-ca,
  --skip-shared-ca,
  --keep-empty-dirs,
  --force,
  --target: string = "",
  --ref: string = "",
  --sha: string = "",
  --transitive,
  --debug,
  # Docs flags
  --fix,
  # Common flags
  --dry-run,
  --verbose
] {
  # Handle top-level help (command is null, "help", "--help", or "-h")
  if $command == null or $command == "help" or $command == "--help" or $command == "-h" {
    show-help
    return
  }
  
  match $command {
    "build" => {
      if $subcommand == "help" or $subcommand == "--help" or $subcommand == "-h" {
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
        prune_cache_mounts: $prune_cache_mounts
      }
    }
    "test" => {
      if $subcommand == "help" or $subcommand == "--help" or $subcommand == "-h" {
        test-help
        return
      }
      run-test-command $suite $verbose
    }
    "validate" => {
      if $subcommand == "help" or $subcommand == "--help" or $subcommand == "-h" {
        validate-help
        return
      }
      run-validate-command $service $all_services $manifests_only
    }
    "tls" => {
      # Normalize help flags to "help" subcommand - tls-cli handles it internally
      let subcmd = if $subcommand == null or $subcommand == "--help" or $subcommand == "-h" { "help" } else { $subcommand }
      let filter_list = if ($filter | str length) > 0 { $filter | split row "," } else { [] }
      let service_list = if ($service | str length) > 0 { $service | split row "," } else { [] }
      run-tls-command $subcmd $service_list $filter_list $force_copy_ca $skip_shared_ca $keep_empty_dirs $force $dry_run $verbose
    }
    "ci" => {
      # Normalize help flags to "help" subcommand - ci-cli handles it internally
      let subcmd = if $subcommand == null or $subcommand == "--help" or $subcommand == "-h" { "help" } else { $subcommand }
      run-ci-command $subcmd $service $target $ref $sha $transitive $debug $dry_run
    }
    "docs" => {
      # Normalize help flags to "help" subcommand - docs-cli handles it internally
      let subcmd = if $subcommand == null or $subcommand == "--help" or $subcommand == "-h" { "help" } else { $subcommand }
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
  
  build-cli --service $flags.service --all-services=$flags.all_services --push=$flags.push --latest=$flags.latest --extra-tag $flags.extra_tag --provenance=$flags.provenance --version $flags.version --all-versions=$flags.all_versions --versions $flags.versions --latest-only=$flags.latest_only --platform $flags.platform --matrix-json=$flags.matrix_json --progress $flags.progress --cache-bust $flags.cache_bust --no-cache=$flags.no_cache --show-build-order=$flags.show_build_order --dep-cache $flags.dep_cache --push-deps=$flags.push_deps --tag-deps=$flags.tag_deps --fail-fast=$flags.fail_fast --pull $flags.pull --cache-match $flags.cache_match --disk-monitor $flags.disk_monitor --prune-cache-mounts=$flags.prune_cache_mounts
}

def run-test-command [suite: string, verbose: bool] {
  use ./lib/test/cli.nu [test-cli]
  test-cli $suite $verbose
}

def run-validate-command [service: string, all_services: bool, manifests_only: bool] {
  use ./lib/validate/cli.nu [validate-cli]
  validate-cli {
    service: $service,
    all_services: $all_services,
    manifests_only: $manifests_only
  }
}

def run-tls-command [
  subcommand: string,
  service_list: list<string>,
  filter_list: list<string>,
  force_copy_ca: bool,
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
    force_copy_ca: $force_copy_ca,
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
  target: string,
  ref: string,
  sha: string,
  transitive: bool,
  debug: bool,
  dry_run: bool
] {
  use ./lib/ci/cli.nu [ci-cli]
  ci-cli $subcommand {
    service: $service,
    target: $target,
    ref: $ref,
    sha: $sha,
    transitive: $transitive,
    debug: $debug,
    dry_run: $dry_run
  }
}

def run-docs-command [subcommand: string, fix: bool] {
  use ./lib/docs/cli.nu [docs-cli]
  docs-cli $subcommand {
    files: [],
    fix: $fix
  }
}
