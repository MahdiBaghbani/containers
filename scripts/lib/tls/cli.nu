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

# TLS CLI facade - see docs/concepts/tls-management.md

use ./ca.nu [generate-ca]
use ./cert.nu [generate-cert]
use ./certs.nu [generate-all-certs]
use ./clean.nu [clean-certs]
use ./copy.nu [copy-tls]

# Re-export all TLS functions for direct module usage
export use ./ca.nu [generate-ca]
export use ./cert.nu [generate-cert]
export use ./certs.nu [generate-all-certs]
export use ./clean.nu [clean-certs]
export use ./copy.nu [copy-tls]

# Show TLS CLI help
export def tls-help [] {
  print "Usage: nu scripts/dockypody.nu tls <subcommand> [options]"
  print ""
  print "Subcommands:"
  print "  ca      Generate the shared CA certificate"
  print "  certs   Generate service certificates"
  print "  clean   Remove TLS artifacts"
  print ""
  print "Options:"
  print "  --filter <list>        (certs) Comma-separated allow-list of service names"
  print "  --force                (ca) Regenerate the CA even if it already exists;"
  print "                         existing service certs must then be regenerated"
  print "  --verbose              (ca/certs) Show detailed output"
  print "  --service <name>       (clean) Target specific service(s), comma-separated"
  print "  --dry-run              (clean) Show what would be removed without removing"
  print "  --skip-shared-ca       (clean) Keep the shared CA; clean only service artifacts"
  print "  --keep-empty-dirs      (clean) Do not remove directories left empty after cleanup"
  print "  --service-ca-only      (clean) Remove only service-local CA mirrors"
}

# TLS CLI entrypoint - called from dockypody.nu
export def tls-cli [
  subcommand: string,  # Subcommand: ca, certs, clean, help
  flags: record        # Flags: { service_list, filter_list, skip_shared_ca, keep_empty_dirs, service_ca_only, force, dry_run, verbose }
] {
  let service_list = (try { $flags.service_list } catch { [] })
  let filter_list = (try { $flags.filter_list } catch { [] })
  let skip_shared_ca = (try { $flags.skip_shared_ca } catch { false })
  let keep_empty_dirs = (try { $flags.keep_empty_dirs } catch { false })
  let service_ca_only = (try { $flags.service_ca_only } catch { false })
  let force = (try { $flags.force } catch { false })
  let dry_run = (try { $flags.dry_run } catch { false })
  let verbose = (try { $flags.verbose } catch { false })

  match $subcommand {
    "help" => {
      tls-help
    }
    "ca" => {
      if $force {
        if $verbose {
          generate-ca --force --verbose
        } else {
          generate-ca --force
        }
      } else {
        if $verbose {
          generate-ca --verbose
        } else {
          generate-ca
        }
      }
    }
    "certs" => {
      if $verbose {
        generate-all-certs --filter $filter_list --verbose
      } else {
        generate-all-certs --filter $filter_list
      }
    }
    "clean" => {
      clean-certs --service $service_list --dry-run=$dry_run --skip-shared-ca=$skip_shared_ca --keep-empty-dirs=$keep_empty_dirs --service-ca-only=$service_ca_only
    }
    _ => {
      print $"Unknown tls subcommand: ($subcommand)"
      print ""
      tls-help
      exit 1
    }
  }
}
