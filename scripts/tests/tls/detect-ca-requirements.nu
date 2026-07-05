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

# Dockerfile parsing and detect-ca-requirements coverage.

use ../../lib/build/context.nu [detect-ca-requirements]
use ../lib.nu [run-test]

export def detect-ca-requirements-tests [verbose: bool] {
    [
        (run-test "detect-ca-requirements: cert-only mode always false/false" {
            let reqs = (detect-ca-requirements "COPY ./tls /tmp/tls-source/" "myca" "cert-only")
            if $reqs.needs_ca_crt or $reqs.needs_ca_key {
                error make {msg: "cert-only mode should never need CA files in context"}
            }
            true
        } $verbose)
        (run-test "detect-ca-requirements: disabled TLS always false/false" {
            let reqs = (detect-ca-requirements "COPY ./tls /tmp/tls-source/" "myca" "disabled")
            if $reqs.needs_ca_crt or $reqs.needs_ca_key {
                error make {msg: "disabled mode should never need CA files"}
            }
            true
        } $verbose)
        (run-test "detect-ca-requirements: COPY ./tls -> needs_ca_crt=true" {
            let dockerfile = "FROM ubuntu\nCOPY ./tls /tmp/tls-source/\nRUN echo ok"
            let reqs = (detect-ca-requirements $dockerfile "dockypody-ca" "ca-and-cert")
            if not $reqs.needs_ca_crt {
                error make {msg: $"Expected needs_ca_crt=true for COPY ./tls, got: ($reqs)"}
            }
            if $reqs.needs_ca_key {
                error make {msg: $"Expected needs_ca_key=false when no .key reference, got: ($reqs)"}
            }
            true
        } $verbose)
        (run-test "detect-ca-requirements: COPY ./tls/certificate-authority -> needs_ca_crt=true" {
            let dockerfile = "FROM ubuntu\nCOPY ./tls/certificate-authority/ /tmp/ca-source/\nRUN echo ok"
            let reqs = (detect-ca-requirements $dockerfile "dockypody-ca" "ca-only")
            if not $reqs.needs_ca_crt {
                error make {msg: $"Expected needs_ca_crt=true, got: ($reqs)"}
            }
            true
        } $verbose)
        (run-test "detect-ca-requirements: explicit .key ref -> needs_ca_key=true" {
            let ca = "dockypody-ca"
            let dockerfile = $"FROM ubuntu\nCOPY ./tls /tmp/tls-source/\nRUN cp \"/tmp/tls-source/certificate-authority/($ca).key\" /opt/ca.key"
            let reqs = (detect-ca-requirements $dockerfile $ca "ca-and-cert")
            if not $reqs.needs_ca_crt {
                error make {msg: "Expected needs_ca_crt=true"}
            }
            if not $reqs.needs_ca_key {
                error make {msg: "Expected needs_ca_key=true for explicit .key reference"}
            }
            true
        } $verbose)
        (run-test "detect-ca-requirements: no tls copy -> false/false" {
            let dockerfile = "FROM ubuntu\nRUN apt-get install -y curl\nEXPOSE 8080"
            let reqs = (detect-ca-requirements $dockerfile "dockypody-ca" "ca-and-cert")
            if $reqs.needs_ca_crt or $reqs.needs_ca_key {
                error make {msg: $"Expected false/false for Dockerfile with no TLS copies, got: ($reqs)"}
            }
            true
        } $verbose)
        (run-test "detect-ca-requirements: COPY ./tls/ (trailing slash) -> needs_ca_crt=true" {
            let dockerfile = "FROM ubuntu\nCOPY ./tls/ /tmp/tls-source/\nRUN echo ok"
            let reqs = (detect-ca-requirements $dockerfile "dockypody-ca" "ca-and-cert")
            if not $reqs.needs_ca_crt {
                error make {msg: $"Expected needs_ca_crt=true for COPY ./tls/, got: ($reqs)"}
            }
            if $reqs.needs_ca_key {
                error make {msg: $"Expected needs_ca_key=false when no .key reference, got: ($reqs)"}
            }
            true
        } $verbose)
        (run-test "detect-ca-requirements: \${TLS_CA_NAME}.key var ref -> needs_ca_key=true" {
            let dockerfile = (
                "FROM mitmproxy/mitmproxy\n" +
                "COPY ./tls/certificate-authority/${TLS_CA_NAME}.crt /etc/ssl/certs/ca.crt\n" +
                "COPY ./tls/certificate-authority/${TLS_CA_NAME}.key /opt/mitm/ca.key"
            )
            let reqs = (detect-ca-requirements $dockerfile "dockypody-ca" "ca-and-cert")
            if not $reqs.needs_ca_crt {
                error make {msg: $"Expected needs_ca_crt=true for TLS_CA_NAME var .crt ref, got: ($reqs)"}
            }
            if not $reqs.needs_ca_key {
                error make {msg: $"Expected needs_ca_key=true for TLS_CA_NAME var .key ref, got: ($reqs)"}
            }
            true
        } $verbose)
        (run-test "detect-ca-requirements: \${TLS_CA_NAME}.crt only -> needs_ca_crt=true, needs_ca_key=false" {
            let dockerfile = (
                "FROM ubuntu\n" +
                "COPY ./tls/certificate-authority/${TLS_CA_NAME}.crt /usr/local/share/ca-certificates/custom.crt\n" +
                "RUN update-ca-certificates"
            )
            let reqs = (detect-ca-requirements $dockerfile "dockypody-ca" "ca-and-cert")
            if not $reqs.needs_ca_crt {
                error make {msg: $"Expected needs_ca_crt=true for TLS_CA_NAME var .crt ref, got: ($reqs)"}
            }
            if $reqs.needs_ca_key {
                error make {msg: $"Expected needs_ca_key=false when no .key reference, got: ($reqs)"}
            }
            true
        } $verbose)
        (run-test "detect-ca-requirements: TLS_CA_NAME without .crt/.key extension -> error" {
            let dockerfile = (
                "FROM ubuntu\n" +
                "COPY ./tls/certificate-authority/${TLS_CA_NAME} /etc/ca/"
            )
            let errored = (try {
                let _ = (detect-ca-requirements $dockerfile "dockypody-ca" "ca-and-cert")
                false
            } catch {
                true
            })
            if not $errored {
                error make {msg: "Expected error for TLS_CA_NAME reference without .crt/.key extension"}
            }
            true
        } $verbose)
    ]
}
