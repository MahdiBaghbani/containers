# opencloudmesh-go example

This service is development-only for now. Do not treat this example as a
production deployment until a production platform and hardening contract
exist for `opencloudmesh-go`.

## Local source build (off-git local plane)

Use the sibling checkout path `../opencloudmesh-go` for local source builds
from `repos/containers`. Do not commit a tracked `local` version; define a
local source path override in the off-git local plane instead.

1. Create the local plane root (once):

```bash
mkdir -p .dockypody.local/services/opencloudmesh-go
```

2. Add a versions fragment (git-ignored; sample only):

Write it in the same JSONC-style form as tracked manifests. Do not save compact
Nushell `to nuon` output or NUON table syntax for this file.

```nuon
{
  "versions": [
    {
      "name": "master",
      "latest": false,
      "overrides": {
        "sources": {
          "ocm_go": {
            "path": "../opencloudmesh-go"
          }
        }
      }
    }
  ]
}
```

Save as `.dockypody.local/services/opencloudmesh-go/versions.nuon`.

3. Build:

```bash
nu scripts/dockypody.nu build --plane local --service opencloudmesh-go --version master
```

## Mode and path env notes

- Leave `OCM_GO_MODE` unset for upstream strict mode.
- `OCM_GO_MODE=compat` is the canonical compatibility mode.
- `OCM_GO_MODE=dev` still loads the upstream dev preset, but the container
  keeps its baked TLS and SSRF overrides. It is not a pure upstream
  `DevConfig`.
- `OCM_GO_PATH` and `OCM_GO_MODE` are consumed by `Dockerfile.development`
  when materializing the `ocm_go` source. Env-only `{ID}_PATH` overrides
  still work without a local-plane fragment.

If you need a private-route SSRF policy, set both
`OCM_GO_ROUTE_PRIVATE_CIDRS` and `OCM_GO_ROUTE_SUFFIXES`. Leave both unset
when the default baked strict SSRF posture is enough.
