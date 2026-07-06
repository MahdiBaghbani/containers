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

# Clone-source helper staging/setup/cleanup tests (Tests 39, 39b, 39c).

use ../../lib/build/context.nu [detect-clone-source-requirements prepare-clone-source-context cleanup-clone-source-context]
use ../lib.nu [run-test]
use ./_fixtures.nu [make-temp-context rm-temp-context]

export def clone-source-staging-tests [verbose: bool] {
    [
        (run-test "Test 39: clone-source helper skipped when Dockerfile omits it" {
            let dockerfile_text = "FROM debian:bookworm\nRUN echo hello"
            let clone_reqs = (detect-clone-source-requirements $dockerfile_text)
            if $clone_reqs.needs_clone_helper {
              error make {msg: "Expected no clone-source helper requirement for generic Dockerfile"}
            }

            let ctx = (make-temp-context)
            let staged = (prepare-clone-source-context "test-service" $ctx $clone_reqs)
            if $staged.staged {
              rm-temp-context $ctx
              error make {msg: "Expected helper not staged when Dockerfile omits clone-source.nu"}
            }

            let helper_dest = ($ctx | path join "scripts" "lib" "clone-source.nu")
            if ($helper_dest | path exists) {
              rm-temp-context $ctx
              error make {msg: "Expected no clone-source.nu in build context when not required"}
            }

            rm-temp-context $ctx
            true
        } $verbose)

        (run-test "Test 39b: clone-source helper staging fidelity and cleanup" {
            let helper_src = "scripts/lib/build/clone-source.nu"
            let live_content = (open $helper_src)
            let dockerfile_text = "COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu"
            let clone_reqs = (detect-clone-source-requirements $dockerfile_text)
            if not $clone_reqs.needs_clone_helper {
              error make {msg: "Expected clone-source helper requirement when Dockerfile copies it"}
            }

            let ctx = (make-temp-context)
            let staged = (prepare-clone-source-context "test-service" $ctx $clone_reqs)

            let helper_dest = ($ctx | path join "scripts" "lib" "clone-source.nu")
            if not ($helper_dest | path exists) {
              rm-temp-context $ctx
              error make {msg: "Expected clone-source.nu staged into build context"}
            }

            let staged_content = (open $helper_dest)
            if $staged_content != $live_content {
              rm-temp-context $ctx
              error make {msg: "Staged clone-source.nu does not match live helper source"}
            }

            cleanup-clone-source-context $ctx $staged
            if ($helper_dest | path exists) {
              rm-temp-context $ctx
              error make {msg: "Expected clone-source.nu removed after cleanup"}
            }

            rm-temp-context $ctx
            true
        } $verbose)

        (run-test "Test 39c: comment-only clone-source mention does not trigger staging" {
            let dockerfile_text = (
              "FROM debian:bookworm\n" +
              "# The build uses clone-source.nu for git clones\n" +
              "# COPY ./scripts/lib/clone-source.nu would stage the helper\n" +
              "RUN echo hello\n"
            )
            let clone_reqs = (detect-clone-source-requirements $dockerfile_text)
            if $clone_reqs.needs_clone_helper {
              error make {msg: "Expected no clone-source helper requirement for comment-only mentions"}
            }

            let ctx = (make-temp-context)
            let staged = (prepare-clone-source-context "test-service" $ctx $clone_reqs)
            if $staged.staged {
              rm-temp-context $ctx
              error make {msg: "Expected helper not staged for comment-only clone-source mentions"}
            }

            let helper_dest = ($ctx | path join "scripts" "lib" "clone-source.nu")
            if ($helper_dest | path exists) {
              rm-temp-context $ctx
              error make {msg: "Expected no clone-source.nu in build context for comment-only mentions"}
            }

            rm-temp-context $ctx
            true
        } $verbose)
    ]
}
