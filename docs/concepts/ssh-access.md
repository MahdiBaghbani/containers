<!--
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
-->
# SSH Access Management

## Overview

The DockyPody SSH access feature provides seamless dev and E2E SSH shell access to running containers. It enables developers to connect from Kasm-based workspaces (firefox, cypress) directly to peer containers using their normal test hostnames:

```bash
ssh nextcloud1.docker
```

This feature is **dev and E2E only**. It is not a production SSH hardening policy.

## What This Is NOT

The `ssh` manifest key does **NOT** describe:

- Git transport URLs (`ssh://`, `git@...`)
- Git SSH signing
- OCM product-level protocols named `ssh`
- Merely installing the OpenSSH package without enabling DockyPody access

## SSH Modes

The system supports three SSH modes:

- **`client`**: Container acts as SSH client (generates `~/.ssh/config`, copies keypair)
- **`server`**: Container runs sshd daemon (generates host keys, configures sshd, starts daemon)
- **`client-and-server`**: Both client and server capabilities
- **`disabled`** (default): No SSH access functionality

## Key Structure

```text
ssh/
├── ssh.json                    # Metadata (key_name, comment, default_user fallback)
├── dockypody                   # Default private key (dev-only)
├── dockypody.pub               # Default public key
└── known_hosts                 # Default known hosts (optional)
```

## Service Configuration

Services declare SSH requirements in their `.nuon` config:

```nuon
{
  "name": "nextcloud-base",
  "ssh": {
    "enabled": true,
    "mode": "server",
    "default_user": "root",
    "port": 22,
    "listen": "0.0.0.0"
  }
}
```

### Field Reference

| Field | Type | Required | Default | Description |
| ----- | ---- | -------- | ------- | ----------- |
| `enabled` | bool | yes | `false` | Enable SSH access |
| `mode` | string | yes (if enabled) | `"disabled"` | `"client"`, `"server"`, `"client-and-server"` |
| `default_user` | string | no | `"root"` | Default SSH user |
| `port` | int | no | `22` | SSH daemon port |
| `listen` | string | no | `"0.0.0.0"` | Bind address |

## Platform Overrides

Unlike TLS, SSH configuration **IS allowed** in `platforms.nuon`. This enables dev/prod splits:

```nuon
{
  "platforms": [
    {
      "name": "production",
      "ssh": { "enabled": false, "mode": "disabled" }
    },
    {
      "name": "development",
      "ssh": { "enabled": true, "mode": "server" }
    }
  ]
}
```

## Build-Time Processing

### Build Arguments

The build system projects these arguments from merged config:

| Argument | Source | Override Protected |
| -------- | ------ | ------------------ |
| `SSH_ENABLED` | `ssh.enabled` | Yes (system-managed) |
| `SSH_MODE` | `ssh.mode` | Yes (system-managed) |
| `SSH_DEFAULT_USER` | `ssh.default_user` | Yes (system-managed) |
| `SSH_PORT` | `ssh.port` | Yes (system-managed) |
| `SSH_LISTEN` | `ssh.listen` | Yes (system-managed) |

### Context Staging

The build system stages SSH material into the build context:

1. Copies `ssh/ssh.json` if present
2. Copies `ssh/dockypody` and `.pub` to build context
3. Copies `ssh/known_hosts` if present
4. Cleans up after build (success or failure)

## Dockerfile Patterns

### Client Mode (Kasm workspaces)

```dockerfile
ARG SSH_ENABLED="false"
ARG SSH_MODE="disabled"
ARG SSH_DEFAULT_USER="root"
ARG SSH_PORT="22"
ARG SSH_LISTEN="0.0.0.0"

# ... later in Dockerfile ...

RUN apt-get install --no-install-recommends --assume-yes \
    openssh-client;

COPY --chmod=755 ./scripts/startup/ocm-ssh-client-env.nu /dockerstartup/ocm-ssh-client-env.nu

ENV OCM_SSH_ENABLED="${SSH_ENABLED}" \
    OCM_SSH_MODE="${SSH_MODE}" \
    OCM_SSH_DEFAULT_USER="${SSH_DEFAULT_USER}" \
    OCM_SSH_PORT="${SSH_PORT}" \
    OCM_SSH_LISTEN="${SSH_LISTEN}"
```

### Server Mode (target services)

```dockerfile
ARG SSH_ENABLED="false"
ARG SSH_MODE="disabled"
ARG SSH_DEFAULT_USER="root"
ARG SSH_PORT="22"
ARG SSH_LISTEN="0.0.0.0"

# ... later in Dockerfile ...

RUN apt-get install --no-install-recommends --assume-yes \
    openssh-server;

# The build system stages the shared sshd module into the build context as:
#   scripts/lib/sshd.nu
# so the service can copy it alongside its other entrypoint libs.
COPY --chmod=755 ./scripts/lib/sshd.nu /usr/bin/lib/sshd.nu

ENV OCM_SSH_ENABLED="${SSH_ENABLED}" \
    OCM_SSH_MODE="${SSH_MODE}" \
    OCM_SSH_DEFAULT_USER="${SSH_DEFAULT_USER}" \
    OCM_SSH_PORT="${SSH_PORT}" \
    OCM_SSH_LISTEN="${SSH_LISTEN}"
```

## Runtime Scripts

### Client Script: `ocm-ssh-client-env.nu`

Sets up SSH client environment in Kasm workspaces:

- Creates `~/.ssh/` directory with correct permissions
- Copies default keypair to `~/.ssh/id_ed25519`
- Generates `~/.ssh/config` with Host patterns for `*.docker`
- Configures `StrictHostKeyChecking accept-new` for dev use

### Server Module: `sshd.nu`

Starts and configures sshd in target containers (shared implementation):

- Generates host keys at runtime (`ssh-keygen -A`)
- Writes hardened `sshd_config`
- Sets up `authorized_keys` for configured user
- Starts sshd in background

This module exports `start-sshd-if-enabled` and must be invoked by the
service entrypoint path (for example from `entrypoint-init.nu`) so sshd is
started before the main process when SSH server mode is enabled.

## Security Framing

This feature is explicitly **dev and E2E only**:

- Root access is enabled by default for fast debugging
- Password authentication is disabled (key-only)
- Host keys are generated at runtime, never baked into images
- The default keypair (`dockypody`) is development-only
- Production deployments should mount custom keys via secrets

## Network Boundary

The SSH contract assumes the runtime harness provides resolvable `*.docker` names on the shared test network. DockyPody does not derive or manage those network aliases.

## Disablement

SSH can be completely disabled by:

1. Setting `ssh.enabled: false` in service manifest
2. Setting `OCM_SSH_ENABLED=false` at runtime (runtime override)
3. Not mounting the SSH keypair into the container

## Key Generation

Generate a new default keypair:

```bash
nu scripts/dockypody.nu ssh key
```

Regenerate (delete and re-create) the default keypair:

```bash
nu scripts/dockypody.nu ssh key --force
```

Or generate directly with ssh-keygen:

```bash
ssh-keygen -t ed25519 -f ssh/dockypody -N "" -C "docky@pody"
```

## Error Handling

| Error | Cause | Resolution |
| ----- | ----- | ---------- |
| `ssh: mode is required when enabled=true` | Missing `ssh.mode` field | Add `mode: "server"` or `"client"` |
| `SSH keypair not found` | Missing `ssh/dockypody` | Generate keypair |
| `sshd: no hostkeys available` | Host keys not generated | Ensure `start-sshd-if-enabled` runs before the main process |
| `Permission denied (publickey)` | authorized_keys missing | Check keypair copy in entrypoint |

## See Also

- [Service Configuration](service-configuration.md) - SSH config in manifests
- [Build System](build-system.md) - Build arg injection and context staging
- [Dockerfile Development Rules](../guides/dockerfile-development.md) - SSH ARG patterns
