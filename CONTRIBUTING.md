<!--
# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Copyright (C) 2025 Mahdi Baghbani <mahdi-baghbani@azadehafzar.io>
#-->

# Contributing

Thanks for thinking about pitching in. Bug fixes, new services, and small
documentation clean-ups are all welcome, and none of them are too small to
send.

## Before you start

- Read the [Getting Started guide](docs/guides/getting-started.md)
- Read the [Build System](docs/concepts/build-system.md) overview
- If you are changing build scripts, read the
  [Nushell Development guide](docs/guides/nushell-development.md) first
- The public entry point is `nu scripts/dockypody.nu`

## Making changes

- Keep service, version, and platform manifests in sync when a change spans
  multiple layers
- Follow [Dockerfile Development](docs/guides/dockerfile-development.md) for
  Dockerfile changes
- Keep `docs/` in sync with behavior changes
- Prefer focused pull requests with one coherent intent

## Validate before opening a pull request

```bash
# Validate one service, or all of them
nu scripts/dockypody.nu validate --service <name>
nu scripts/dockypody.nu validate --all-services

# Run the non-image test suite
nu scripts/dockypody.nu test --suite all

# Lint documentation
nu scripts/dockypody.nu docs lint
```

If your change is narrower, run the smallest relevant validation command and
report what you ran in the pull request.

## Pull requests

When you open a pull request, say what problem you are solving and why, list
the validation commands you ran, and mention anything you left for later if the
change is deliberately partial.

By contributing, you agree that your contributions are licensed under
AGPL-3.0-or-later, consistent with this repository.
