<!--
# SPDX-License-Identifier: AGPL-3.0-or-later
# Open Cloud Mesh Containers: container build scripts and images
# Copyright (C) 2025 Open Cloud Mesh Contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
-->

# System Administration Guide

Quick reference for system administration tasks relevant to container builds and Docker operations.

## ZFS Filesystem Management

On ZFS filesystems, use these commands to check disk usage:

### Check ZFS Pool Space

```bash
# List all ZFS datasets with used/available space
zfs list

# Show specific properties (used, available, referenced, compression ratio)
zfs get used,available,referenced,compressratio

# Check specific dataset
zfs list rpool/ROOT/ubuntu_id2v5s/var/lib/docker

# Human-readable output with sizes
zfs list -o name,used,avail,refer,mountpoint -H | awk '{printf "%-50s %10s %10s %10s %s\n", $1, $2, $3, $4, $5}'
```

### ZFS Space Fields

- **USED**: Total space used by dataset and all children
- **AVAIL**: Available space for this dataset
- **REFER**: Space referenced by this dataset (not including children)
- **compressratio**: Compression ratio (e.g., 1.75x means 1.75:1 compression)

### Find Large Directories (Docker-related)

```bash
# Check Docker data directory size
du -sh /var/lib/docker

# Check Buildx cache location (if on ZFS)
zfs list | grep docker

# Find largest directories in Docker
du -h /var/lib/docker | sort -rh | head -20
```

## Disk Space Management

### Check Overall Disk Usage

```bash
# Standard disk usage
df -h

# Show inodes usage
df -i

# Check specific mount point
df -h /var/lib/docker
```

### Find Large Files and Directories

```bash
# Find largest directories in current location
du -h | sort -rh | head -20

# Find largest files
find /var/lib/docker -type f -exec du -h {} + | sort -rh | head -20

# Check Docker directory sizes
du -sh /var/lib/docker/* | sort -rh
```

## Docker System Cleanup

### Remove Unused Docker Resources

```bash
# Remove unused containers, networks, images, and build cache
docker system prune

# Remove all unused images (not just dangling)
docker system prune -a

# Remove volumes as well
docker system prune -a --volumes

# Dry run to see what would be removed
docker system prune --dry-run
```

### Check Docker Disk Usage

```bash
# Show Docker disk usage breakdown
docker system df

# Detailed view
docker system df -v
```

## See Also

- [Docker Buildx Guide](docker-buildx.md) - Docker Buildx cache management
- [Build System Concepts](../concepts/build-system.md) - Build system architecture
