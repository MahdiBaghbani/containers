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

.PHONY: help build build-push list-services validate-service
.PHONY: tls ca certs all clean tls.help tls.ca tls.certs tls.all tls.clean
.PHONY: lint-docs lint-docs-fix

# Auto discover services in services/*.nuon files (using lib directly)
SERVICES := $(shell nu -c "use scripts/lib/services.nu list-service-names; list-service-names | str join ' '")

# Default build flags
PUSH ?= 0
LATEST ?= 1
PROVENANCE ?= 0
TAG ?=
EXTRA_TAG ?=

# Build script path
BUILD_SCRIPT := scripts/build.nu

# TLS script paths (Nushell)
TLS_CA_SCRIPT := scripts/tls/generate-ca.nu
TLS_ALL_CERTS_SCRIPT := scripts/tls/generate-all-certs.nu
TLS_CLEAN_SCRIPT := scripts/tls/clean.nu

## Show this help message
help:
	@echo "Open Cloud Mesh Container Build System"
	@echo ""
	@echo "Available targets:"
	@echo "  build              Build all services (local, no push)"
	@echo "  build-push         Build and push all services to registries"
	@echo "  list-services      List all available services"
	@echo ""
	@echo "TLS certificate management:"
	@echo "  tls ca             Generate shared Certificate Authority (CA)"
	@echo "  tls certs          Generate certificates for all services"
	@echo "  tls all            Generate CA and all certificates"
	@echo "  tls clean          Clean up generated certificates"
	@echo "  (Run 'make tls.help' for detailed TLS options)"
	@echo ""
	@echo "Build a specific service:"
	@echo "  make build SERVICE=revad-base"
	@echo "  make build-push SERVICE=revad-base"
	@echo ""
	@echo "Build flags (can be combined):"
	@echo "  SERVICE=<name>     Service to build (default: build all)"
	@echo "  PUSH=1             Push to registries (default: 0)"
	@echo "  LATEST=1           Tag as latest (default: 1)"
	@echo "  PROVENANCE=1       Generate SBOM/provenance (default: 0)"
	@echo "  TAG=<tag>          Override version tag"
	@echo "  EXTRA_TAG=<tag>    Add extra tag"
	@echo ""
	@echo "Examples:"
	@echo "  make build                                    # Build all services locally"
	@echo "  make build SERVICE=revad-base                  # Build revad-base locally"
	@echo "  make build-push SERVICE=revad-base             # Build and push revad-base"
	@echo "  make build PUSH=1 PROVENANCE=1                # Build all with push and provenance"
	@echo "  make tls ca                                   # Generate shared CA"
	@echo "  make tls certs DOMAIN_SUFFIX=docker          # Generate certs for all services"
	@echo "  make tls all                                  # Generate CA and all certs"
	@echo "  make tls clean                                # Remove generated TLS artifacts"
	@echo ""
	@echo "Documentation linting:"
	@echo "  lint-docs                                     # Check documentation for writing rule violations"
	@echo "  lint-docs-fix                                 # Fix writing rule violations automatically"
	@echo ""

## List all available services
list-services:
	@echo "Available services:"
	@nu -c 'use scripts/lib/services.nu list-service-names; list-service-names | each { |s| print (["  - ", $$s] | str join "") }'
	@echo ""
	@nu -c 'use scripts/lib/services.nu list-service-names; print (["Total: ", (list-service-names | length | into string), " service(s)"] | str join "")'

## Validate SERVICE variable if provided
validate-service:
ifneq ($(SERVICE),)
	@nu -c 'use scripts/lib/services.nu [service-exists list-service-names]; if not (service-exists "$(SERVICE)") { print "Error: Service $(SERVICE) not found."; print ""; print "Available services:"; list-service-names | each { |s| print (["  - ", $$s] | str join "") }; exit 1 }'
endif

## Build service(s) locally or all if SERVICE not specified
build: validate-service
	@nu scripts/build.nu \
		$(if $(SERVICE),--service "$(SERVICE)",) \
		$(if $(filter 1,$(PUSH)),--push=true,) \
		$(if $(filter 1,$(LATEST)),--latest=true,) \
		$(if $(filter 1,$(PROVENANCE)),--provenance=true,) \
		$(if $(TAG),--version "$(TAG)",) \
		$(if $(EXTRA_TAG),--extra-tag "$(EXTRA_TAG)",)

## Build and push service(s) to registries
build-push: PUSH=1
build-push: build

## TLS namespace - silent no-op when used as prefix
tls:
	@:

## Show TLS help  
tls.help: tls
	@echo "TLS Certificate Management"
	@echo ""
	@echo "Available commands:"
	@echo "  make tls ca        Generate shared Certificate Authority (CA)"
	@echo "  make tls certs     Generate certificates for all services"
	@echo "  make tls all       Generate CA and all certificates"
	@echo "  make tls clean     Clean up generated certificates"
	@echo ""
	@echo "Options for 'make tls certs':"
	@echo "  DOMAIN_SUFFIX=<suffix>      Domain suffix for certificates (default: docker)"
	@echo "  INSTANCE_COUNT=<count>      Number of instances per service (default: 1)"
	@echo "  FILTER=<service1,service2>  Only generate certs for specified services"
	@echo ""
	@echo "Examples:"
	@echo "  make tls all"
	@echo "  make tls certs DOMAIN_SUFFIX=prod.example.com INSTANCE_COUNT=3"
	@echo "  make tls certs FILTER=revad-base,reva-gateway"
	@echo ""

## Generate shared Certificate Authority
ca: tls
	@echo "Generating Certificate Authority..."
	@nu $(TLS_CA_SCRIPT)

## Generate certificates for all services
## Usage: make tls certs DOMAIN_SUFFIX=docker INSTANCE_COUNT=1 FILTER="service1,service2"
certs: tls
	@echo "Generating certificates for all services..."
	@nu $(TLS_ALL_CERTS_SCRIPT) \
		$(if $(DOMAIN_SUFFIX),--domain-suffix "$(DOMAIN_SUFFIX)",) \
		$(if $(INSTANCE_COUNT),--instance-count "$(INSTANCE_COUNT)",) \
		$(if $(FILTER),--filter [$(FILTER)],)

## Generate CA and all certificates
all: tls ca certs

## Clean up generated certificates
clean: tls
	@nu $(TLS_CLEAN_SCRIPT)

## Lint documentation files for writing rule violations
lint-docs:
	@nu scripts/lint-docs.nu

## Lint and fix documentation files
lint-docs-fix:
	@nu scripts/lint-docs.nu --fix
