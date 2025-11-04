# Documentation

Guides and architecture docs for the OCM Containers project.

## Available Docs

**[nushell.md](nushell.md)** - Nushell development guide. Read this before editing any `.nu` files in `scripts/`.

Covers:
- Differences from Bash/POSIX shells
- Functions, data types, pipelines
- Error handling
- Common pitfalls and debugging

**[architecture.md](architecture.md)** - System architecture and design.

Covers:
- Container orchestration
- Service config structure
- TLS workflow
- Build system

**[version-manifests.md](version-manifests.md)** - Multi-version build guide.

## Quick Start

New to the project? Start with [architecture.md](architecture.md), then [nushell.md](nushell.md) if working on scripts.

Working on scripts? Check [nushell.md](nushell.md) for development guidelines.

Need commands? Run `make help` or `make tls.help`.

## Documentation Layout

- `docs/` - Detailed guides
- `Makefile` - Self-documenting commands
- Code comments - Inline explanations

## Contributing

Document solutions as you find them. Keep debugging scenarios updated.
