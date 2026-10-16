#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Copyright (C) 2025 Mahdi Baghbani <mahdi-baghbani@azadehafzar.io>
#
# Content-Security-Policy for the static CERNBox web routes.

# CERN serves the web UI with form-action 'self', so the SPA can only submit
# forms to its own origin. An empty WEB_CSP drops the header, because nginx
# skips add_header when the value is empty.
export const DEFAULT_WEB_CSP = "form-action 'self'"

# The value lands inside a double-quoted nginx string, so anything that would
# end the string or start an nginx variable is refused.
export def resolve-web-csp [] {
    let csp = ($env.WEB_CSP? | default $DEFAULT_WEB_CSP)
    if ($csp =~ '["\\$\r\n]') {
        error make {msg: "WEB_CSP must not contain double quotes, backslashes, dollar signs or line breaks"}
    }
    $csp
}
