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

# Merged clone-source compatibility: SHA/tag clone wiring checks.

use ../../lib/validate/core.nu [validate-service-complete]
use ../lib.nu [run-test]
use ./_temp.nu [make-temp rm-temp]

export def clone-compat-tests [verbose: bool] {
  [
    (run-test "validate-service-complete: SHA source with legacy git clone --branch fails" {
      let tmp = (make-temp)
      let sha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      let result = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "clonfail")
        $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
RUN git clone --branch \"\${APP_REF}\" --depth 1 \${APP_URL} /src/app
" | save -f ($tmp | path join "services" "clonfail" "Dockerfile")
        {
          name: "clonfail",
          context: "services/clonfail",
          dockerfile: "services/clonfail/Dockerfile"
        } | save -f ($tmp | path join "services" "clonfail.nuon")
        {
          default: "v1",
          defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
          versions: [{name: "v1"}]
        } | save -f ($tmp | path join "services" "clonfail" "versions.nuon")
        validate-service-complete "clonfail"
      })
      rm-temp $tmp
      if $result.valid {
        error make {msg: "Expected SHA + legacy git clone --branch to fail clone compat validation"}
      }
      let legacy_err = ($result.errors | where {|e| $e | str contains "clone --branch"} | length)
      if $legacy_err == 0 {
        error make {msg: $"Expected legacy clone --branch error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-complete: legacy git clone --branch with line continuation fails" {
      let tmp = (make-temp)
      let sha = "aeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeae"
      let result = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "clonlegacycont")
        $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
RUN git clone \\
  --branch \"\${APP_REF}\" \\
  --depth 1 \${APP_URL} /src/app
" | save -f ($tmp | path join "services" "clonlegacycont" "Dockerfile")
        {
          name: "clonlegacycont",
          context: "services/clonlegacycont",
          dockerfile: "services/clonlegacycont/Dockerfile"
        } | save -f ($tmp | path join "services" "clonlegacycont.nuon")
        {
          default: "v1",
          defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
          versions: [{name: "v1"}]
        } | save -f ($tmp | path join "services" "clonlegacycont" "versions.nuon")
        validate-service-complete "clonlegacycont"
      })
      rm-temp $tmp
      if $result.valid {
        error make {msg: "Expected multiline legacy git clone --branch to fail clone compat validation"}
      }
      let legacy_err = ($result.errors | where {|e| $e | str contains "clone --branch"} | length)
      if $legacy_err == 0 {
        error make {msg: $"Expected legacy clone --branch error for continuation Dockerfile, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-complete: SHA source with clone-source helper passes" {
      let tmp = (make-temp)
      let sha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      let result = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "clonok")
        $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_REF_KIND=\"\"
COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu
RUN nu /tmp/clone-source.nu --mode git --url \"\${APP_URL}\" --ref \"\${APP_REF}\" --ref-kind \"\${APP_REF_KIND}\" --cache-dir /cache --dest /src/app
" | save -f ($tmp | path join "services" "clonok" "Dockerfile")
        {
          name: "clonok",
          context: "services/clonok",
          dockerfile: "services/clonok/Dockerfile"
        } | save -f ($tmp | path join "services" "clonok.nuon")
        {
          default: "v1",
          defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
          versions: [{name: "v1"}]
        } | save -f ($tmp | path join "services" "clonok" "versions.nuon")
        validate-service-complete "clonok"
      })
      rm-temp $tmp
      if not $result.valid {
        error make {msg: $"Expected SHA + clone-source helper to pass, got: ($result.errors | str join ', ')"}
      }
      let lacks_wiring = ($result.errors | any {|e| $e | str contains "lacks"})
      if $lacks_wiring {
        error make {msg: $"Expected clone-source helper wiring to satisfy compat, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-complete: SHA source with inline fetch/checkout passes" {
      let tmp = (make-temp)
      let sha = "cccccccccccccccccccccccccccccccccccccccc"
      let result = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "cloninline")
        $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_SHA=\"\"
RUN git clone --depth 1 \${APP_URL} /src/app && if ! git -C /src/app checkout \"\${APP_SHA}\"; then git -C /src/app fetch --depth 1 origin \"\${APP_SHA}\" && git -C /src/app checkout \"\${APP_SHA}\"; fi
" | save -f ($tmp | path join "services" "cloninline" "Dockerfile")
        {
          name: "cloninline",
          context: "services/cloninline",
          dockerfile: "services/cloninline/Dockerfile"
        } | save -f ($tmp | path join "services" "cloninline.nuon")
        {
          default: "v1",
          defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
          versions: [{name: "v1"}]
        } | save -f ($tmp | path join "services" "cloninline" "versions.nuon")
        validate-service-complete "cloninline"
      })
      rm-temp $tmp
      if not $result.valid {
        error make {msg: $"Expected inline SHA fetch/checkout to pass, got: ($result.errors | str join ', ')"}
      }
      let lacks_err = ($result.errors | any {|e| $e | str contains "lacks"})
      if $lacks_err {
        error make {msg: $"Expected inline SHA path to satisfy compat, got: ($result.errors | str join ', ')"}
      }
      let legacy_err = ($result.errors | any {|e| $e | str contains "clone --branch"})
      if $legacy_err {
        error make {msg: $"Expected inline SHA path to avoid legacy clone error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-complete: decoupled inline fetch and checkout fails" {
      let tmp = (make-temp)
      let sha = "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd"
      let result = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "clondecouple")
        $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_SHA=\"\"
RUN git -C /src/other fetch --depth 1 origin main
RUN git -C /src/app checkout \"\${APP_SHA}\"
" | save -f ($tmp | path join "services" "clondecouple" "Dockerfile")
        {
          name: "clondecouple",
          context: "services/clondecouple",
          dockerfile: "services/clondecouple/Dockerfile"
        } | save -f ($tmp | path join "services" "clondecouple.nuon")
        {
          default: "v1",
          defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
          versions: [{name: "v1"}]
        } | save -f ($tmp | path join "services" "clondecouple" "versions.nuon")
        validate-service-complete "clondecouple"
      })
      rm-temp $tmp
      if $result.valid {
        error make {msg: "Expected decoupled inline fetch/checkout to fail clone compat validation"}
      }
      let lacks_err = ($result.errors | any {|e| $e | str contains "lacks"})
      if not $lacks_err {
        error make {msg: $"Expected lacks-wiring error for decoupled inline path, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-complete: inline SHA comment does not satisfy compat" {
      let tmp = (make-temp)
      let sha = "abababababababababababababababababababab"
      let result = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "cloncomment")
        $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
RUN echo building # git fetch APP_SHA and git checkout APP_SHA here
" | save -f ($tmp | path join "services" "cloncomment" "Dockerfile")
        {
          name: "cloncomment",
          context: "services/cloncomment",
          dockerfile: "services/cloncomment/Dockerfile"
        } | save -f ($tmp | path join "services" "cloncomment.nuon")
        {
          default: "v1",
          defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
          versions: [{name: "v1"}]
        } | save -f ($tmp | path join "services" "cloncomment" "versions.nuon")
        validate-service-complete "cloncomment"
      })
      rm-temp $tmp
      if $result.valid {
        error make {msg: "Expected inline SHA comment decoy to fail clone compat validation"}
      }
      let lacks_err = ($result.errors | any {|e| (($e | str contains "lacks") and ($e | str contains "app"))})
      if not $lacks_err {
        error make {msg: $"Expected final lacks-wiring rejection for app, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-complete: SHA source without clone wiring fails" {
      let tmp = (make-temp)
      let sha = "dddddddddddddddddddddddddddddddddddddddd"
      let result = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "clonnowire")
        $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_REF_KIND=\"\"
# git fetch APP_SHA and checkout would go here
RUN echo building
" | save -f ($tmp | path join "services" "clonnowire" "Dockerfile")
        {
          name: "clonnowire",
          context: "services/clonnowire",
          dockerfile: "services/clonnowire/Dockerfile"
        } | save -f ($tmp | path join "services" "clonnowire.nuon")
        {
          default: "v1",
          defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
          versions: [{name: "v1"}]
        } | save -f ($tmp | path join "services" "clonnowire" "versions.nuon")
        validate-service-complete "clonnowire"
      })
      rm-temp $tmp
      if $result.valid {
        error make {msg: "Expected SHA source without wiring to fail clone compat validation"}
      }
      let lacks_err = ($result.errors | any {|e| $e | str contains "lacks"})
      if not $lacks_err {
        error make {msg: $"Expected final lacks-wiring error, got: ($result.errors | str join ', ')"}
      }
      let legacy_err = ($result.errors | any {|e| $e | str contains "clone --branch"})
      if $legacy_err {
        error make {msg: $"Expected lacks-wiring branch, not legacy clone error, got: ($result.errors | str join ', ')"}
      }
      let app_err = ($result.errors | any {|e| ($e | str contains "sources.app") and ($e | str contains "lacks")})
      if not $app_err {
        error make {msg: $"Expected sources.app lacks-wiring error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-complete: scattered REF_KIND without clone wiring fails" {
      let tmp = (make-temp)
      let sha = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
      let result = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "clonscatter" "scripts" "build")
        $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_REF_KIND=\"\"
ARG PLUGIN_REF=\"\"
ARG PLUGIN_REF_KIND=\"\"
COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu
RUN nu /tmp/clone-source.nu --mode git --url \"\${APP_URL}\" --ref \"\${APP_REF}\" --ref-kind \"\${APP_REF_KIND}\" --cache-dir /cache --dest /src/app
" | save -f ($tmp | path join "services" "clonscatter" "Dockerfile")
        $"
# PLUGIN_REF_KIND mentioned but not wired to clone-source.nu
let ref_kind = $env.PLUGIN_REF_KIND? | default \"\"
" | save -f ($tmp | path join "services" "clonscatter" "scripts" "build" "unused.nu")
        {
          name: "clonscatter",
          context: "services/clonscatter",
          dockerfile: "services/clonscatter/Dockerfile"
        } | save -f ($tmp | path join "services" "clonscatter.nuon")
        {
          default: "v1",
          defaults: {
            sources: {
              app: {url: "https://example.com/app.git", ref: $sha},
              plugin: {url: "https://example.com/plugin.git", ref: "ffffffffffffffffffffffffffffffffffffffff"}
            }
          },
          versions: [{name: "v1"}]
        } | save -f ($tmp | path join "services" "clonscatter" "versions.nuon")
        validate-service-complete "clonscatter"
      })
      rm-temp $tmp
      if $result.valid {
        error make {msg: "Expected plugin SHA without clone wiring to fail"}
      }
      let plugin_err = ($result.errors | any {|e|
        ($e | str contains "plugin") and ($e | str contains "lacks")
      })
      if not $plugin_err {
        error make {msg: $"Expected plugin lacks-wiring error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-complete: co-block PLUGIN tokens without clone wiring fails" {
      let tmp = (make-temp)
      let sha = "fdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfd"
      let result = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "cloncoblock")
        $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_REF_KIND=\"\"
ARG PLUGIN_REF=\"\"
ARG PLUGIN_REF_KIND=\"\"
COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu
RUN nu /tmp/clone-source.nu --mode git --url \"\${APP_URL}\" --ref \"\${APP_REF}\" --ref-kind \"\${APP_REF_KIND}\" --cache-dir /cache --dest /src/app && echo PLUGIN_REF_KIND \${PLUGIN_REF}
" | save -f ($tmp | path join "services" "cloncoblock" "Dockerfile")
        {
          name: "cloncoblock",
          context: "services/cloncoblock",
          dockerfile: "services/cloncoblock/Dockerfile"
        } | save -f ($tmp | path join "services" "cloncoblock.nuon")
        {
          default: "v1",
          defaults: {
            sources: {
              app: {url: "https://example.com/app.git", ref: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
              plugin: {url: "https://example.com/plugin.git", ref: $sha}
            }
          },
          versions: [{name: "v1"}]
        } | save -f ($tmp | path join "services" "cloncoblock" "versions.nuon")
        validate-service-complete "cloncoblock"
      })
      rm-temp $tmp
      if $result.valid {
        error make {msg: "Expected PLUGIN SHA with co-block token echo to fail clone compat validation"}
      }
      let plugin_err = ($result.errors | any {|e|
        ($e | str contains "sources.plugin") and ($e | str contains "lacks")
      })
      if not $plugin_err {
        error make {msg: $"Expected sources.plugin lacks-wiring error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-complete: REF_KIND alone does not satisfy REF participation" {
      let tmp = (make-temp)
      let sha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      let result = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "clonrefkind" "scripts" "build")
        $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_REF_KIND=\"\"
ARG PLUGIN_REF_KIND=\"\"
COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu
RUN nu /tmp/clone-source.nu --mode git --url \"\${APP_URL}\" --ref \"\${APP_REF}\" --ref-kind \"\${APP_REF_KIND}\" --cache-dir /cache --dest /src/app
" | save -f ($tmp | path join "services" "clonrefkind" "Dockerfile")
        $"
# ref_kind binding only; plugin REF arg not used in clone wiring
let ref_kind = $env.PLUGIN_REF_KIND? | default \"\"
" | save -f ($tmp | path join "services" "clonrefkind" "scripts" "build" "unused.nu")
        {
          name: "clonrefkind",
          context: "services/clonrefkind",
          dockerfile: "services/clonrefkind/Dockerfile"
        } | save -f ($tmp | path join "services" "clonrefkind.nuon")
        {
          default: "v1",
          defaults: {
            sources: {
              app: {url: "https://example.com/app.git", ref: $sha},
              plugin: {url: "https://example.com/plugin.git", ref: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
            }
          },
          versions: [{name: "v1"}]
        } | save -f ($tmp | path join "services" "clonrefkind" "versions.nuon")
        validate-service-complete "clonrefkind"
      })
      rm-temp $tmp
      if not $result.valid {
        error make {msg: $"REF_KIND without REF should not enforce plugin wiring, got: ($result.errors | str join ', ')"}
      }
      let plugin_err = ($result.errors | any {|e| $e | str contains "plugin"})
      if $plugin_err {
        error make {msg: $"PLUGIN_REF_KIND alone must not count as PLUGIN_REF participation, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-complete: clone block with REF_KIND but not REF fails" {
      let tmp = (make-temp)
      let sha = "cccccccccccccccccccccccccccccccccccccccc"
      let result = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "clonblockhole")
        $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
ARG APP_REF_KIND=\"\"
RUN nu /tmp/clone-source.nu --mode git --url \"\${APP_URL}\" --ref-kind \"\${APP_REF_KIND}\" --cache-dir /cache --dest /src/app
" | save -f ($tmp | path join "services" "clonblockhole" "Dockerfile")
        {
          name: "clonblockhole",
          context: "services/clonblockhole",
          dockerfile: "services/clonblockhole/Dockerfile"
        } | save -f ($tmp | path join "services" "clonblockhole.nuon")
        {
          default: "v1",
          defaults: {sources: {app: {url: "https://example.com/app.git", ref: $sha}}},
          versions: [{name: "v1"}]
        } | save -f ($tmp | path join "services" "clonblockhole" "versions.nuon")
        validate-service-complete "clonblockhole"
      })
      rm-temp $tmp
      if $result.valid {
        error make {msg: "Expected clone block with REF_KIND but no REF to fail clone compat validation"}
      }
      let lacks_err = ($result.errors | any {|e| $e | str contains "lacks"})
      if not $lacks_err {
        error make {msg: $"Expected lacks-wiring error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-complete: override script under scripts/build passes" {
      let tmp = (make-temp)
      let sha = "1111111111111111111111111111111111111111"
      let outcome = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "clonoverride" "scripts" "build")
        let dockerfile_path = ($tmp | path join "services" "clonoverride" "Dockerfile")
        $"
FROM scratch
ARG OCIS_REVA_REF=\"\"
ARG OCIS_REVA_URL=\"\"
RUN nu /usr/local/bin/reva-override.nu
" | save -f $dockerfile_path
        $"
def checkout-sha [work_dir: string, sha: string]: nothing -> nothing {
    ^git -C $work_dir fetch --depth 1 origin $sha
    ^git -C $work_dir checkout $sha
}

def main [] {
    let url = $env.OCIS_REVA_URL? | default \"\"
    let ref_ = $env.OCIS_REVA_REF? | default \"\"
    let sha = $env.OCIS_REVA_SHA? | default \"\"
    let ref_kind = $env.OCIS_REVA_REF_KIND? | default \"\"
    ^nu /usr/local/bin/clone-source.nu --mode git --url $url --ref $ref_ --ref-kind $ref_kind --cache-dir /cache --dest /src/reva
    if not ($sha | is-empty) {
        checkout-sha /src/reva $sha
    }
}
" | save -f ($tmp | path join "services" "clonoverride" "scripts" "build" "reva-override.nu")
        {
          name: "clonoverride",
          context: "services/clonoverride",
          dockerfile: "services/clonoverride/Dockerfile"
        } | save -f ($tmp | path join "services" "clonoverride.nuon")
        {
          default: "v1",
          defaults: {
            sources: {
              ocis_reva: {url: "https://example.com/reva.git", ref: $sha}
            }
          },
          versions: [{name: "v1"}]
        } | save -f ($tmp | path join "services" "clonoverride" "versions.nuon")
        {
          result: (validate-service-complete "clonoverride"),
          dockerfile_text: (open -r $dockerfile_path)
        }
      })
      rm-temp $tmp
      let result = ($outcome.result)
      if not $result.valid {
        error make {msg: $"Expected override-script clone wiring to pass, got: ($result.errors | str join ', ')"}
      }
      let lacks_err = ($result.errors | any {|e| $e | str contains "lacks"})
      if $lacks_err {
        error make {msg: $"Expected scripts/build override to satisfy compat, got: ($result.errors | str join ', ')"}
      }
      let dockerfile_text = ($outcome.dockerfile_text)
      if ($dockerfile_text | str contains "clone-source.nu") {
        error make {msg: "Expected clone wiring to live only under scripts/build, not Dockerfile"}
      }
      true
    } $verbose)
    (run-test "validate-service-complete: tag ref with legacy git clone --branch passes" {
      let tmp = (make-temp)
      let result = (do {
        cd $tmp
        (^git init | complete | ignore)
        mkdir ($tmp | path join "services" "clontag")
        $"
FROM scratch
ARG APP_REF=\"\"
ARG APP_URL=\"\"
RUN git clone --branch \"\${APP_REF}\" --depth 1 \${APP_URL} /src/app
" | save -f ($tmp | path join "services" "clontag" "Dockerfile")
        {
          name: "clontag",
          context: "services/clontag",
          dockerfile: "services/clontag/Dockerfile"
        } | save -f ($tmp | path join "services" "clontag.nuon")
        {
          default: "v1",
          defaults: {sources: {app: {url: "https://example.com/app.git", ref: "v1.0.0"}}},
          versions: [{name: "v1"}]
        } | save -f ($tmp | path join "services" "clontag" "versions.nuon")
        validate-service-complete "clontag"
      })
      rm-temp $tmp
      if not $result.valid {
        error make {msg: $"Expected tag ref + legacy clone to pass, got: ($result.errors | str join ', ')"}
      }
      let clone_compat_err = ($result.errors | any {|e|
        ($e | str contains "clone --branch") or ($e | str contains "lacks")
      })
      if $clone_compat_err {
        error make {msg: $"Tag ref should skip SHA clone compat enforcement, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-complete: cernbox-revad passes with pinned SHA revad_plugins" {
      let result = (validate-service-complete "cernbox-revad")
      if not $result.valid {
        error make {msg: $"Expected cernbox-revad complete validation to pass, got: ($result.errors | str join ', ')"}
      }
      let clone_compat_err = ($result.errors | any {|e|
        ($e | str contains "lacks") or ($e | str contains "clone --branch")
      })
      if $clone_compat_err {
        error make {msg: $"Expected cernbox-revad clone compat to pass, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
  ]
}
