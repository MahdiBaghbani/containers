# opencloudmesh-go example

This service is development-only for now. Do not treat this example as a
production deployment until a production platform and hardening contract
exist for `opencloudmesh-go`.

Use the sibling checkout path `../opencloudmesh-go` for local source builds
from `repos/containers`.

Mode notes:

- Leave `OCM_GO_MODE` unset for upstream strict mode.
- `OCM_GO_MODE=compat` is the canonical compatibility mode.
- `OCM_GO_MODE=dev` still loads the upstream dev preset, but the container
  keeps its baked TLS and SSRF overrides. It is not a pure upstream
  `DevConfig`.

If you need a private-route SSRF policy, set both
`OCM_GO_ROUTE_PRIVATE_CIDRS` and `OCM_GO_ROUTE_SUFFIXES`. Leave both unset
when the default baked strict SSRF posture is enough.
