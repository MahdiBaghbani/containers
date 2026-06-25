<!-- markdownlint-disable MD024 -->
# How I want cernbox-web to build its extensions

This is my running write-up on how we build the CERNBox web frontend
(`cernbox/web`) together with the extensions (`cernbox/web-extensions`). The
main thing I want to capture here is the per-extension pinning idea, which I am
deliberately keeping for later. I wrote down the toolchain-bundle model first
because the pinning idea only makes sense on top of it.

Quick status note so future me does not get confused:

- Tier 1 is landed for the 11.x lanes, and I already built it successfully once
  after wiring the manifest, Dockerfile, and allowlist-first builder together.
- Tier 2 is still blocked on one real upstream fact: `cernbox/web` does not ship
  a 12.x ref yet, so I am not adding a tracked 12.x lane until that exists.
- Per-extension pinning (Tier 3) is designed here but parked on purpose.
- A couple of things I am explicitly not doing are called out near the end.

## The problem, as I see it

We build `cernbox-web` from two upstreams that version themselves separately
and never agree on a combined manifest:

- `cernbox/web` ships as whole-repo tags (`v1.0.25` is package version 11.3.0)
  plus a default `cernbox` branch that is also 11.3.0.
- `cernbox/web-extensions` is really a bag of independent extensions. Each one
  is released on its own per-extension git tag (`<ext>/v<semver>`), and CI only
  builds the single extension that got tagged. There is no whole-repo build
  upstream at all.

Two things fall out of that, and they drive everything below:

1. There is a hard split between a web 11.x toolchain and a web 12.x toolchain,
   and the node version is the load-bearing axis. More on that next.
2. The extensions repo carries packages that are not really members of any
   coherent set. `image-editor` is the obvious one: duplicate `const`
   declarations, no `vite.config.ts`, no `index.html`, and zero tags. Upstream
   already excludes it (and `backups`) from their own `pnpm-workspace.yaml` on
   `main`, so I am not inventing that judgement, I am just following it.

## Why the node version is the thing that matters

Giuseppe told me what matters is the node version, and once I lined up the
numbers I think he is exactly right. The 11.x and 12.x worlds are not just
different `@ownclouders/*` versions, they are two self-consistent toolchains.
Build an extension from one line against a web base from the other and the
bundle fails to load. Here is what I measured:

| Axis                                | web 11.x line          | web 12.x line          |
| ----------------------------------- | ---------------------- | ---------------------- |
| cernbox/web version                 | 11.3.0                 | none shipped yet       |
| web engines.node / volta            | >=18 / 20.18.0         | n/a                    |
| web packageManager                  | pnpm@9.12.3            | n/a                    |
| web-extensions baseline ref         | dffaad6 (last pre-12)  | main                   |
| @ownclouders/extension-sdk, web-pkg | 11.0.4                 | ^12.1.2 (catalog)      |
| web Vite / extensions Vite baseline | 5.4.8 / 5.4.11         | n/a / ^7.2.4           |
| @types/node                         | 11.x era               | ^22.19.1               |
| extensions root packageManager      | none (no root pkg)     | pnpm@10.4.1            |

The chain is simple once you see it: Vite 7 wants Node 20.19+/22.12+ and pnpm
10, while Vite 5 is happy on Node 20 and pnpm 9. So "build the 12.x extensions"
quietly means "move to Node 22 / pnpm 10 / Vite 7", and "stay on web 11.3.0"
means "stay on Node 20 / pnpm 9 / Vite 5". My read is that the build lane has to
treat the node version, the pnpm version, and the extension set as one bound
unit. That was the whole problem: they used to be Dockerfile constants. Tier 1
fixes exactly that for the 11.x lanes.

## The foundation: a lane is one coherent toolchain bundle

Everything else assumes this is in place first. For the 11.x lanes this is now
how `cernbox-web` works: each version lane declares a self-consistent tuple,
all version-scoped in `services/cernbox-web/versions.nuon`:

- `sources.web.ref` for the web frontend version.
- `sources.web_extensions.ref` for the coherent extensions baseline.
- `external_images.build.tag` for the node toolchain (for example
  `20-trixie-slim`). This is already overridable per lane, and
  `services/nextcloud-contacts/versions.nuon` already does it with
  `24-trixie-slim`, so there is precedent I can lean on.
- `build_args.PNPM_VERSION` for the pnpm toolchain, consumed by
  `corepack prepare pnpm@${PNPM_VERSION}` instead of the old hardcoded
  `pnpm@9`.
- `build_args.WEB_EXT_ALLOW` for the curated extension set, starting from the
  upstream `pnpm-workspace.yaml` `packages:` list and then appending the
  Makefile-only theme packages that still have to ship in the final image.

On the builder side `scripts/build-extensions.nu` is now allowlist-first. When
`--only` is set it builds exactly that curated set in order and fails closed if
a named member is missing. Anything else in the tree (work-in-progress,
12.x-only, whatever upstream adds next) is simply not in the contract, so it
cannot break the image. When `--only` is empty it still falls back to the old
discovery plus `--skip` behavior, so the path stays backward-compatible.

For the current 11.x lanes, the exact curated set I want is:
`cernbox-integration, ifc-js, jupyter, lightweight-accounts,
ndmspc-reader, old-web-redirector, open-in-swan, otg, rootjs,
search-in-folder, tours, theme-cernbox, tours-cernbox`.

That is intentionally tighter than the current discovery path:

- `codimd`, `data-repositories`, `draw-io`, and `ms-tracing` stay out because
  they are already on the 12.x dependency line.
- `backups` stays out because upstream already excludes it from the curated
  workspace set.
- `image-editor` stays out because it is both upstream-excluded and structurally
  broken.

The nice side effect: once `cernbox/web` actually publishes a 12.x ref, the
future 12.x lane becomes pure data (node 22, pnpm 10.4.1, extensions ref
`main`, the full `main` allowlist plus the two theme packages) with no
Dockerfile edits.

## Per-extension pinning (parked for later)

### The part that made me stop

I wanted clean per-extension tag pinning, but I do not think it is possible the
way I first imagined, and that is the whole reason this tier is parked. A bunch
of the extensions I actually care about have never been tagged:

- No tags at all, so SHA or branch only: `cernbox-integration`, `ifc-js`,
  `backups`, `codimd`, `data-repositories`, `draw-io`, `image-editor`.
- Tagged ones, for reference: `jupyter` (`jupyter/v3.1.0` is 11.0.4 and
  `jupyter/v3.1.1` is 12.x, tagged the same day), `rootjs` (up to
  `rootjs/v4.0.1`), `open-in-swan` (up to `v3.0.0`), `otg` (up to `v1.0.2`),
  `old-web-redirector` (up to `v2.0.0`), `lightweight-accounts` (up to
  `v1.0.3`), `ndmspc-reader` (`v2.0.1`), `search-in-folder` (`v1.0.0`),
  `tours` (up to `v2.0.2`). `theme-cernbox` and `tours-cernbox` are
  Makefile-only theme packages, separate from the Vite extensions.

`cernbox-integration` and `ifc-js` matter for M8 and they have no tags, so a
tag-only model would silently drop exactly the glue I need. So the model has to
be a hybrid:

- Baseline: the whole monorepo at one coherent SHA is the default ref for every
  extension. This keeps the "one coherent cut" guarantee and adds zero extra
  git work in the normal case.
- Overlay: an optional per-extension ref override (tag, SHA, or branch) and an
  optional per-extension URL override for forks. Only the overridden ones cost
  an extra fetch.
- Coherence guard: once the set is resolved, check each built extension against
  the lane web line and fail the build on a mismatch. More on that below.

### How I would carry the pins

Two ways, and I am in favor of the simpler one for now.

Path B, which I would do first, reuses the generic `build_args` passthrough we
already have. No build-system change. I encode the pins as one string build arg
in a small grammar and drop it in `build_args.WEB_EXT_PINS`:

```text
WEB_EXT_PINS = "name=ref[;url],name=ref[;url],..."
# examples:
#   jupyter=jupyter/v3.1.0
#   myext=feature/x;https://github.com/MahdiBaghbani/web-extensions
```

This is the same shape as how `WEB_EXT_ALLOW` gets wired in Tier 1: a Dockerfile
`ARG` default plus an optional `versions.nuon` override. Only the new resolver
script has to understand the grammar.

Path A would promote pins to a first-class manifest field, something like:

```text
"web_extension_pins": {
  "jupyter": { "ref": "jupyter/v3.1.0" },
  "myext":   { "url": "https://github.com/MahdiBaghbani/web-extensions",
               "ref": "feature/x" }
}
```

Then the build library serializes that record into the same `WEB_EXT_PINS`
grammar at one place and could validate the pin shape before building. My
preference would be to only reach for Path A once pins are common enough to earn
real schema and validation. Until then Path B does the same job with less
moving machinery.

### Fetch and overlay

I want to mirror the resolve-then-build split we already use for the reva
configs (`services/revad-base/scripts/lib/resolve-configs.nu` resolves, then the
build runs). So a new resolver, maybe
`services/cernbox-web/scripts/resolve-extension-pins.nu`, that:

1. Takes the extensions root already cloned at the baseline ref, the
   `WEB_EXT_PINS` string, and a git cache dir.
2. For each pin, shallow-fetches that one extension path at its ref from its url
   (defaulting to the cernbox web-extensions url), then replaces the baseline
   directory for that extension. I can reuse the SHA-versus-branch logic that is
   already in the Dockerfile (init plus fetch plus checkout FETCH_HEAD for a
   40-hex SHA, clone or fetch by name for a tag or branch).
3. Stays idempotent and fails closed if a pin ref or url is unreachable.

On the Dockerfile side I would insert this step after the baseline clone and
before `build-extensions.nu`, guarded by a non-empty `WEB_EXT_PINS`, keeping the
existing git cache mounts. When `WEB_EXT_PINS` is empty the step does nothing, so
the normal build path is untouched.

### The coherence guard, which I think is the real point

This whole mess started from a silent 11.x/12.x mismatch, so I do not want pins
to reopen that door quietly. Before building, the resolver (or a check inside
`build-extensions.nu`) should enforce the toolchain invariant:

- Add a lane build arg `WEB_LINE_MAJOR`, for example `"11"`.
- For each extension about to be built, read its `package.json`, take the major
  of `@ownclouders/web-pkg` (fall back to `@ownclouders/extension-sdk`), and
  compare it to `WEB_LINE_MAJOR`.
- On a mismatch, fail closed with something specific, like: "extension jupyter
  resolves to web-pkg 12.x but lane web line is 11; pin it to an 11.x ref or
  drop it from the allowlist".

That turns the original runtime breakage into a build-time error, which is
exactly Giuseppe's node-version point made into a check the build can enforce.

### How I would actually pick an 11.x ref

There is no auto-resolver on purpose (see below). When I need a pin I would:

1. List the extension tags (`<ext>/v*`).
2. Newest first, open `<ext>/package.json` at that tag and look at
   `@ownclouders/web-pkg` (or `@ownclouders/extension-sdk`).
3. The first tag whose major is 11 is the last 11.x release, so I pin that.
4. If the extension has no tags, pin by SHA or branch, or just leave it on the
   baseline SHA.

I want the pins explicit and chosen by hand so the coherence decision stays
visible in the manifest instead of hiding in a script.

## What I am leaving out on purpose

- No automatic "find the last 11.x tag" resolver. It is fragile and it hides the
  decision I actually want to see. Pins stay explicit.
- Per-extension pinning is not on by default. The baseline SHA stays the
  default, and pinning is opt-in per lane.
- No building of work-in-progress or 12.x-only packages on the 11.x line. The
  allowlist keeps them out, and if a pin tries to sneak one in, the coherence
  guard rejects it.

## Order I would build this in

1. Tier 1 (landed): Dockerfile `PNPM_VERSION` and `WEB_EXT_ALLOW` args,
   allowlist-first `build-extensions.nu`, and the per-lane toolchain plus
   curated set in `versions.nuon`.
2. Tier 2 (blocked for now): add a 12.x data lane only after CERNBox tags or
   branches a real web 12.x ref. Until that upstream ref exists, I do not want
   a fake local lane pretending the bundle is coherent.
3. Tier 3 (parked): per-extension pinning via `WEB_EXT_PINS` (Path B),
   `resolve-extension-pins.nu`, and the `WEB_LINE_MAJOR` guard, as above.

## Notes to self for when I build Tier 3

- `scripts/build-extensions.nu` and any new `scripts/*.nu` are Nushell source,
  so those edits have to go through the Nushell specialist subagent per the
  workspace delegation rules. `versions.nuon` (data) and the `Dockerfile` are
  not gated by that rule.
- Keep the resolve step a strict no-op when `WEB_EXT_PINS` is empty, so the
  default path gains no latency and no extra git calls.
- Add tests next to the resolver: empty-pins no-op, a tag pin, a SHA pin, a
  fork-url pin, and a coherence-guard rejection for a 12.x pin on an 11.x lane.

If any of this stops matching what we actually see when I build it, I would
rather update this file than let it drift, so say so and I will narrow it down.
