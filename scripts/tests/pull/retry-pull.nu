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

# retry-pull tests. Hermetic mocks. No docker, no PATH stub.

use ../../lib/build/pull.nu [retry-pull]
use ../lib.nu [run-test]

def assert [cond: bool, msg: string] {
    if not $cond {
        error make {msg: $msg}
    }
}

const HTTP_502 = "received unexpected HTTP status: 502 Bad Gateway"
const MANIFEST = "manifest for quay.io/keycloak/keycloak:26.4.2 not found: manifest unknown: manifest unknown"
const UNAUTH = "unauthorized: authentication required"
const TAG_MISS = "Error response from daemon: failed to resolve reference \"docker.io/library/alpine:no-such-tag-xyzzy123\": docker.io/library/alpine:no-such-tag-xyzzy123: not found"
const QUOTA = "toomanyrequests: You have reached your pull rate limit"
const ABUSE = "toomanyrequests: Too Many Requests. Please see https://docs.docker.com/docker-hub/download-rate-limit/"
const TAG_REF = "php:8.3-apache-trixie"
const DIGEST_REF = "php@sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

export def retry-pull-tests [verbose: bool] {
    [
        (run-test "retry-pull: 502 then success on attempt 2" {
            let result = (
                retry-pull $TAG_REF {|ref, n|
                    if $n == 1 {
                        {success: false, error: $HTTP_502}
                    } else if $n == 2 {
                        {success: true, error: ""}
                    } else {
                        error make {msg: $"extra call n=($n)"}
                    }
                } --max-attempts 4 --backoff-ms 0
            )
            assert $result.success "expected success after one 502"
            assert ($result.error == "") "expected empty error"
            true
        } $verbose),

        (run-test "retry-pull: all 502 fail keeps last error and exact count" {
            let result = (
                retry-pull $TAG_REF {|ref, n|
                    {success: false, error: $"($HTTP_502) call-($n)"}
                } --max-attempts 4 --backoff-ms 0
            )
            assert (not $result.success) "expected failure after budget"
            assert ($result.error == $"($HTTP_502) call-4") "last error must be call-4"
            true
        } $verbose),

        (run-test "retry-pull: manifest unknown and unauthorized are one-shot" {
            let man = (
                retry-pull $TAG_REF {|ref, n|
                    {success: false, error: $"($MANIFEST) call-($n)"}
                } --max-attempts 4 --backoff-ms 0
            )
            assert (not $man.success) "manifest should fail"
            assert ($man.error == $"($MANIFEST) call-1") "manifest must not retry"
            let auth = (
                retry-pull $TAG_REF {|ref, n|
                    {success: false, error: $"($UNAUTH) call-($n)"}
                } --max-attempts 4 --backoff-ms 0
            )
            assert (not $auth.success) "unauthorized should fail"
            assert ($auth.error == $"($UNAUTH) call-1") "unauthorized must not retry"
            true
        } $verbose),

        (run-test "retry-pull: tag-ref : not found gets one retry" {
            let result = (
                retry-pull $TAG_REF {|ref, n|
                    {success: false, error: $"($TAG_MISS) call-($n)"}
                } --max-attempts 4 --backoff-ms 0
            )
            assert (not $result.success) "missing tag should fail"
            assert ($result.error == $"($TAG_MISS) call-2") "tag : not found retries once"
            true
        } $verbose),

        (run-test "retry-pull: digest-ref : not found is permanent" {
            let result = (
                retry-pull $DIGEST_REF {|ref, n|
                    {success: false, error: $"($ref): not found call-($n)"}
                } --max-attempts 4 --backoff-ms 0
            )
            assert (not $result.success) "digest miss should fail"
            assert ($result.error == $"($DIGEST_REF): not found call-1") "digest must not retry"
            true
        } $verbose),

        (run-test "retry-pull: quota 429 skip on pull rate limit" {
            let result = (
                retry-pull $TAG_REF {|ref, n|
                    {success: false, error: $"($QUOTA) call-($n)"}
                } --max-attempts 4 --backoff-ms 0
            )
            assert (not $result.success) "quota should fail"
            assert ($result.error == $"($QUOTA) call-1") "quota skip is one call"
            true
        } $verbose),

        (run-test "retry-pull: abuse 429 uses default backoff budget" {
            let result = (
                retry-pull $TAG_REF {|ref, n|
                    {success: false, error: $"($ABUSE) call-($n)"}
                } --max-attempts 4 --backoff-ms 0
            )
            assert (not $result.success) "abuse should exhaust"
            assert ($result.error == $"($ABUSE) call-4") "abuse keeps full budget"
            true
        } $verbose),

        (run-test "retry-pull: timeout string is retryable" {
            let result = (
                retry-pull $TAG_REF {|ref, n|
                    {success: false, error: $"timed out after 300s pulling ($ref) call-($n)"}
                } --max-attempts 4 --backoff-ms 0
            )
            assert (not $result.success) "timeout should exhaust"
            assert ($result.error == $"timed out after 300s pulling ($TAG_REF) call-4") "timeout must retry"
            true
        } $verbose),

        (run-test "retry-pull: max-attempts 1 disables retry" {
            let result = (
                retry-pull $TAG_REF {|ref, n|
                    {success: false, error: $"($HTTP_502) call-($n)"}
                } --max-attempts 1 --backoff-ms 0
            )
            assert (not $result.success) "single try should fail"
            assert ($result.error == $"($HTTP_502) call-1") "max-attempts 1 is one call"
            true
        } $verbose),
    ]
}
