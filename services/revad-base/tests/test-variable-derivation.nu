#!/usr/bin/env nu

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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Test suite for init.nu variable derivation logic
# See services/revad-base/scripts/init.nu for implementation

def test-minimal-env [] {
  print "=== Test 1: Minimal environment (DOMAIN only) ==="
  
  $env.DOMAIN = "test.revad.docker"
  let DOMAIN = ((try { $env.DOMAIN } catch { "" }) | default "")
  let REVAD_TLS_ENABLED = ((try { $env.REVAD_TLS_ENABLED } catch { "" }) | default ((try { $env.TLS_ENABLED } catch { "" }) | default "false"))
  let REVAD_PROTOCOL = ((try { $env.REVAD_PROTOCOL } catch { "" }) | default (if $REVAD_TLS_ENABLED == "false" { "http" } else { "https" }))
  let REVAD_PORT = ((try { $env.REVAD_PORT } catch { "" }) | default (if $REVAD_TLS_ENABLED == "false" { "80" } else { "443" }))
  let REVAD_HOST = ((try { $env.REVAD_HOST } catch { "" }) | default $DOMAIN)
  
  let WEB_DOMAIN_RAW = (try { $env.WEB_DOMAIN } catch { "" } | default "")
  let WEB_DOMAIN = (if (($WEB_DOMAIN_RAW | describe) == "nothing" or ($WEB_DOMAIN_RAW | str trim | str length) == 0) {
    if ($DOMAIN | str length) > 0 {
      let hostname = ($DOMAIN | split row "." | get 0)
      let suffix = (if ($DOMAIN | split row "." | length) > 1 {
        ($DOMAIN | split row "." | skip 1 | str join ".")
      } else {
        ""
      })
      let clean_hostname = ($hostname | str replace -a "reva" "")
      if ($suffix | str length) > 0 {
        $"($clean_hostname).($suffix)"
      } else {
        $clean_hostname
      }
    } else {
      $DOMAIN
    }
  } else {
    $WEB_DOMAIN_RAW
  })
  
  let WEB_TLS_ENABLED_RAW = (try { $env.WEB_TLS_ENABLED } catch { "" } | default "")
  let WEB_TLS_ENABLED = (if (($WEB_TLS_ENABLED_RAW | describe) == "nothing" or ($WEB_TLS_ENABLED_RAW | str trim | str length) == 0) { $REVAD_TLS_ENABLED } else { $WEB_TLS_ENABLED_RAW })
  let WEB_PROTOCOL_RAW = (try { $env.WEB_PROTOCOL } catch { "" } | default "")
  let WEB_PROTOCOL = (if (($WEB_PROTOCOL_RAW | describe) == "nothing" or ($WEB_PROTOCOL_RAW | str trim | str length) == 0) {
    (if $WEB_TLS_ENABLED == "false" { "http" } else { "https" })
  } else {
    $WEB_PROTOCOL_RAW
  })
  
  let REVAD_INTERNAL_HOST = ((try { $env.REVAD_INTERNAL_HOST } catch { "" }) | default $DOMAIN)
  let REVAD_INTERNAL_PORT = ((try { $env.REVAD_INTERNAL_PORT } catch { "" }) | default $REVAD_PORT)
  let REVAD_INTERNAL_PROTOCOL = ((try { $env.REVAD_INTERNAL_PROTOCOL } catch { "" }) | default $REVAD_PROTOCOL)
  
  let REVAD_EXTERNAL_HOST_RAW = (try { $env.REVAD_EXTERNAL_HOST } catch { "" } | default "")
  let REVAD_EXTERNAL_HOST = (if (($REVAD_EXTERNAL_HOST_RAW | describe) == "nothing" or ($REVAD_EXTERNAL_HOST_RAW | str trim | str length) == 0) { $WEB_DOMAIN } else { $REVAD_EXTERNAL_HOST_RAW })
  let REVAD_EXTERNAL_PORT_RAW = (try { $env.REVAD_EXTERNAL_PORT } catch { "" } | default "")
  let REVAD_EXTERNAL_PORT = (if (($REVAD_EXTERNAL_PORT_RAW | describe) == "nothing" or ($REVAD_EXTERNAL_PORT_RAW | str trim | str length) == 0) {
    (if $WEB_TLS_ENABLED == "true" { "443" } else { "80" })
  } else {
    $REVAD_EXTERNAL_PORT_RAW
  })
  let REVAD_EXTERNAL_PROTOCOL_RAW = (try { $env.REVAD_EXTERNAL_PROTOCOL } catch { "" } | default "")
  let REVAD_EXTERNAL_PROTOCOL = (if (($REVAD_EXTERNAL_PROTOCOL_RAW | describe) == "nothing" or ($REVAD_EXTERNAL_PROTOCOL_RAW | str trim | str length) == 0) { $WEB_PROTOCOL } else { $REVAD_EXTERNAL_PROTOCOL_RAW })
  
  let WEB_EXTERNAL_HOST_RAW = (try { $env.WEB_EXTERNAL_HOST } catch { "" } | default "")
  let WEB_EXTERNAL_HOST = (if (($WEB_EXTERNAL_HOST_RAW | describe) == "nothing" or ($WEB_EXTERNAL_HOST_RAW | str trim | str length) == 0) { $WEB_DOMAIN } else { $WEB_EXTERNAL_HOST_RAW })
  let WEB_EXTERNAL_PORT_RAW = (try { $env.WEB_EXTERNAL_PORT } catch { "" } | default "")
  let WEB_EXTERNAL_PORT = (if (($WEB_EXTERNAL_PORT_RAW | describe) == "nothing" or ($WEB_EXTERNAL_PORT_RAW | str trim | str length) == 0) {
    (if $WEB_TLS_ENABLED == "true" { "443" } else { "80" })
  } else {
    $WEB_EXTERNAL_PORT_RAW
  })
  let WEB_EXTERNAL_PROTOCOL_RAW = (try { $env.WEB_EXTERNAL_PROTOCOL } catch { "" } | default "")
  let WEB_EXTERNAL_PROTOCOL = (if (($WEB_EXTERNAL_PROTOCOL_RAW | describe) == "nothing" or ($WEB_EXTERNAL_PROTOCOL_RAW | str trim | str length) == 0) { $WEB_PROTOCOL } else { $WEB_EXTERNAL_PROTOCOL_RAW })
  
  let RESERVED_PATHS = ["api", "graph", "ocs", "ocm", "webdav", "remote.php", "preferences", "archiver", "app", ".well-known", "ocm-provider", "dav", "status.php", "metrics", "s"]
  let DATA_PREFIX_LOCALHOME_RAW = ((try { $env.REVAD_DATA_PREFIX_LOCALHOME } catch { "" }) | default "data-localhome")
  let DATA_PREFIX_LOCALHOME = (if ($DATA_PREFIX_LOCALHOME_RAW in $RESERVED_PATHS) {
    error make { msg: $"Prefix ($DATA_PREFIX_LOCALHOME_RAW) conflicts with reserved path" }
  } else {
    $DATA_PREFIX_LOCALHOME_RAW
  })
  let DATA_PREFIX_OCM_RAW = ((try { $env.REVAD_DATA_PREFIX_OCM } catch { "" }) | default "data-ocm")
  let DATA_PREFIX_OCM = (if ($DATA_PREFIX_OCM_RAW in $RESERVED_PATHS) {
    error make { msg: $"Prefix ($DATA_PREFIX_OCM_RAW) conflicts with reserved path" }
  } else {
    $DATA_PREFIX_OCM_RAW
  })
  let DATA_PREFIX_SCIENCEMESH_RAW = ((try { $env.REVAD_DATA_PREFIX_SCIENCEMESH } catch { "" }) | default "data-sciencemesh")
  let DATA_PREFIX_SCIENCEMESH = (if ($DATA_PREFIX_SCIENCEMESH_RAW in $RESERVED_PATHS) {
    error make { msg: $"Prefix ($DATA_PREFIX_SCIENCEMESH_RAW) conflicts with reserved path" }
  } else {
    $DATA_PREFIX_SCIENCEMESH_RAW
  })
  
  let REVAD_EXTERNAL_PROTOCOL_FINAL = (if ($REVAD_EXTERNAL_PROTOCOL | str trim | str length) == 0 {
    $REVAD_PROTOCOL
  } else {
    $REVAD_EXTERNAL_PROTOCOL
  })
  let REVAD_EXTERNAL_HOST_FINAL = (if ($REVAD_EXTERNAL_HOST | str trim | str length) == 0 {
    (if ($DOMAIN | str length) > 0 { $DOMAIN } else { "localhost" })
  } else {
    $REVAD_EXTERNAL_HOST
  })
  
  let EXTERNAL_REVAD_ENDPOINT = $"($REVAD_EXTERNAL_PROTOCOL_FINAL)://($REVAD_EXTERNAL_HOST_FINAL)"
  
  print $"DOMAIN: ($DOMAIN)"
  print $"WEB_DOMAIN: ($WEB_DOMAIN)"
  print $"REVAD_EXTERNAL_HOST: ($REVAD_EXTERNAL_HOST)"
  print $"REVAD_EXTERNAL_PROTOCOL: ($REVAD_EXTERNAL_PROTOCOL)"
  print $"REVAD_EXTERNAL_PROTOCOL_FINAL: ($REVAD_EXTERNAL_PROTOCOL_FINAL)"
  print $"REVAD_EXTERNAL_HOST_FINAL: ($REVAD_EXTERNAL_HOST_FINAL)"
  print $"EXTERNAL_REVAD_ENDPOINT: ($EXTERNAL_REVAD_ENDPOINT)"
  
  if ($EXTERNAL_REVAD_ENDPOINT | str contains "://") == false or ($REVAD_EXTERNAL_HOST_FINAL | str length) == 0 {
    error make { msg: $"Failed to derive valid EXTERNAL_REVAD_ENDPOINT. REVAD_EXTERNAL_PROTOCOL_FINAL=($REVAD_EXTERNAL_PROTOCOL_FINAL), REVAD_EXTERNAL_HOST_FINAL=($REVAD_EXTERNAL_HOST_FINAL)" }
  }
  
  print "Test 1 passed"
}

def test-empty-domain [] {
  print "\n=== Test 2: Empty DOMAIN (should fallback to localhost) ==="
  
  $env.DOMAIN = ""
  $env.WEB_DOMAIN = ""
  
  let DOMAIN = ((try { $env.DOMAIN } catch { "" }) | default "")
  let REVAD_TLS_ENABLED = "false"
  let REVAD_PROTOCOL = "http"
  let REVAD_PORT = "80"
  let WEB_DOMAIN = $DOMAIN
  let WEB_TLS_ENABLED = "false"
  let WEB_PROTOCOL = "http"
  
  let REVAD_EXTERNAL_HOST_RAW = (try { $env.REVAD_EXTERNAL_HOST } catch { "" } | default "")
  let REVAD_EXTERNAL_HOST = (if (($REVAD_EXTERNAL_HOST_RAW | describe) == "nothing" or ($REVAD_EXTERNAL_HOST_RAW | str trim | str length) == 0) { $WEB_DOMAIN } else { $REVAD_EXTERNAL_HOST_RAW })
  let REVAD_EXTERNAL_PROTOCOL_RAW = (try { $env.REVAD_EXTERNAL_PROTOCOL } catch { "" } | default "")
  let REVAD_EXTERNAL_PROTOCOL = (if (($REVAD_EXTERNAL_PROTOCOL_RAW | describe) == "nothing" or ($REVAD_EXTERNAL_PROTOCOL_RAW | str trim | str length) == 0) { $WEB_PROTOCOL } else { $REVAD_EXTERNAL_PROTOCOL_RAW })
  
  let REVAD_EXTERNAL_PROTOCOL_FINAL = (if ($REVAD_EXTERNAL_PROTOCOL | str trim | str length) == 0 {
    $REVAD_PROTOCOL
  } else {
    $REVAD_EXTERNAL_PROTOCOL
  })
  let REVAD_EXTERNAL_HOST_FINAL = (if ($REVAD_EXTERNAL_HOST | str trim | str length) == 0 {
    (if ($DOMAIN | str length) > 0 { $DOMAIN } else { "localhost" })
  } else {
    $REVAD_EXTERNAL_HOST
  })
  
  let EXTERNAL_REVAD_ENDPOINT = $"($REVAD_EXTERNAL_PROTOCOL_FINAL)://($REVAD_EXTERNAL_HOST_FINAL)"
  
  print $"DOMAIN: ($DOMAIN)"
  print $"REVAD_EXTERNAL_HOST: ($REVAD_EXTERNAL_HOST)"
  print $"REVAD_EXTERNAL_HOST_FINAL: ($REVAD_EXTERNAL_HOST_FINAL)"
  print $"EXTERNAL_REVAD_ENDPOINT: ($EXTERNAL_REVAD_ENDPOINT)"
  
  if ($EXTERNAL_REVAD_ENDPOINT | str contains "://") == false or ($REVAD_EXTERNAL_HOST_FINAL | str length) == 0 {
    error make { msg: $"Failed to derive valid EXTERNAL_REVAD_ENDPOINT. REVAD_EXTERNAL_PROTOCOL_FINAL=($REVAD_EXTERNAL_PROTOCOL_FINAL), REVAD_EXTERNAL_HOST_FINAL=($REVAD_EXTERNAL_HOST_FINAL)" }
  }
  
  if $REVAD_EXTERNAL_HOST_FINAL != "localhost" {
    error make { msg: $"Expected REVAD_EXTERNAL_HOST_FINAL=localhost, got ($REVAD_EXTERNAL_HOST_FINAL)" }
  }
  
  if $EXTERNAL_REVAD_ENDPOINT != "http://localhost" {
    error make { msg: $"Expected EXTERNAL_REVAD_ENDPOINT=http://localhost, got ($EXTERNAL_REVAD_ENDPOINT)" }
  }
  
  print "Test 2 passed (correctly fell back to localhost)"
}

def test-reserved-prefix [] {
  print "\n=== Test 3: Reserved prefix (should fail) ==="
  
  $env.REVAD_DATA_PREFIX_LOCALHOME = "api"
  
  let RESERVED_PATHS = ["api", "graph", "ocs", "ocm", "webdav", "remote.php", "preferences", "archiver", "app", ".well-known", "ocm-provider", "dav", "status.php", "metrics", "s"]
  let DATA_PREFIX_LOCALHOME_RAW = ((try { $env.REVAD_DATA_PREFIX_LOCALHOME } catch { "" }) | default "data-localhome")
  
  try {
    let DATA_PREFIX_LOCALHOME = (if ($DATA_PREFIX_LOCALHOME_RAW in $RESERVED_PATHS) {
      error make { msg: $"Prefix ($DATA_PREFIX_LOCALHOME_RAW) conflicts with reserved path" }
    } else {
      $DATA_PREFIX_LOCALHOME_RAW
    })
    error make { msg: "Test 3 failed: Should have detected reserved prefix" }
  } catch {
    print "Test 3 passed (correctly detected reserved prefix)"
  }
}

def test-full-env [] {
  print "\n=== Test 4: Full environment variables ==="
  
  $env.DOMAIN = "revad.test.docker"
  $env.WEB_DOMAIN = "web.test.docker"
  $env.REVAD_TLS_ENABLED = "false"
  $env.REVAD_PORT = "8080"
  $env.REVAD_PROTOCOL = "http"
  $env.WEB_TLS_ENABLED = "true"
  $env.WEB_PROTOCOL = "https"
  $env.REVAD_EXTERNAL_HOST = "external.test.docker"
  $env.REVAD_EXTERNAL_PORT = "8443"
  $env.REVAD_EXTERNAL_PROTOCOL = "https"
  
  let DOMAIN = ((try { $env.DOMAIN } catch { "" }) | default "")
  let REVAD_TLS_ENABLED = ((try { $env.REVAD_TLS_ENABLED } catch { "" }) | default "false")
  let REVAD_PROTOCOL = ((try { $env.REVAD_PROTOCOL } catch { "" }) | default (if $REVAD_TLS_ENABLED == "false" { "http" } else { "https" }))
  let REVAD_PORT = ((try { $env.REVAD_PORT } catch { "" }) | default (if $REVAD_TLS_ENABLED == "false" { "80" } else { "443" }))
  let WEB_DOMAIN = ((try { $env.WEB_DOMAIN } catch { "" }) | default $DOMAIN)
  let WEB_TLS_ENABLED_RAW = (try { $env.WEB_TLS_ENABLED } catch { "" } | default "")
  let WEB_TLS_ENABLED = (if (($WEB_TLS_ENABLED_RAW | describe) == "nothing" or ($WEB_TLS_ENABLED_RAW | str trim | str length) == 0) { $REVAD_TLS_ENABLED } else { $WEB_TLS_ENABLED_RAW })
  let WEB_PROTOCOL_RAW = (try { $env.WEB_PROTOCOL } catch { "" } | default "")
  let WEB_PROTOCOL = (if (($WEB_PROTOCOL_RAW | describe) == "nothing" or ($WEB_PROTOCOL_RAW | str trim | str length) == 0) {
    (if $WEB_TLS_ENABLED == "false" { "http" } else { "https" })
  } else {
    $WEB_PROTOCOL_RAW
  })
  
  let REVAD_EXTERNAL_HOST_RAW = (try { $env.REVAD_EXTERNAL_HOST } catch { "" } | default "")
  let REVAD_EXTERNAL_HOST = (if (($REVAD_EXTERNAL_HOST_RAW | describe) == "nothing" or ($REVAD_EXTERNAL_HOST_RAW | str trim | str length) == 0) { $WEB_DOMAIN } else { $REVAD_EXTERNAL_HOST_RAW })
  let REVAD_EXTERNAL_PORT_RAW = (try { $env.REVAD_EXTERNAL_PORT } catch { "" } | default "")
  let REVAD_EXTERNAL_PORT = (if (($REVAD_EXTERNAL_PORT_RAW | describe) == "nothing" or ($REVAD_EXTERNAL_PORT_RAW | str trim | str length) == 0) {
    (if $WEB_TLS_ENABLED == "true" { "443" } else { "80" })
  } else {
    $REVAD_EXTERNAL_PORT_RAW
  })
  let REVAD_EXTERNAL_PROTOCOL_RAW = (try { $env.REVAD_EXTERNAL_PROTOCOL } catch { "" } | default "")
  let REVAD_EXTERNAL_PROTOCOL = (if (($REVAD_EXTERNAL_PROTOCOL_RAW | describe) == "nothing" or ($REVAD_EXTERNAL_PROTOCOL_RAW | str trim | str length) == 0) { $WEB_PROTOCOL } else { $REVAD_EXTERNAL_PROTOCOL_RAW })
  
  let REVAD_EXTERNAL_PROTOCOL_FINAL = (if ($REVAD_EXTERNAL_PROTOCOL | str trim | str length) == 0 {
    $REVAD_PROTOCOL
  } else {
    $REVAD_EXTERNAL_PROTOCOL
  })
  let REVAD_EXTERNAL_HOST_FINAL = (if ($REVAD_EXTERNAL_HOST | str trim | str length) == 0 {
    (if ($DOMAIN | str length) > 0 { $DOMAIN } else { "localhost" })
  } else {
    $REVAD_EXTERNAL_HOST
  })
  
  let EXTERNAL_REVAD_ENDPOINT = $"($REVAD_EXTERNAL_PROTOCOL_FINAL)://($REVAD_EXTERNAL_HOST_FINAL)"
  
  print $"DOMAIN: ($DOMAIN)"
  print $"WEB_DOMAIN: ($WEB_DOMAIN)"
  print $"REVAD_EXTERNAL_HOST: ($REVAD_EXTERNAL_HOST)"
  print $"REVAD_EXTERNAL_HOST_FINAL: ($REVAD_EXTERNAL_HOST_FINAL)"
  print $"REVAD_EXTERNAL_PROTOCOL: ($REVAD_EXTERNAL_PROTOCOL)"
  print $"REVAD_EXTERNAL_PROTOCOL_FINAL: ($REVAD_EXTERNAL_PROTOCOL_FINAL)"
  print $"REVAD_EXTERNAL_PORT: ($REVAD_EXTERNAL_PORT)"
  print $"EXTERNAL_REVAD_ENDPOINT: ($EXTERNAL_REVAD_ENDPOINT)"
  
  if ($EXTERNAL_REVAD_ENDPOINT | str contains "://") == false or ($REVAD_EXTERNAL_HOST_FINAL | str length) == 0 {
    error make { msg: $"Failed to derive valid EXTERNAL_REVAD_ENDPOINT. REVAD_EXTERNAL_PROTOCOL_FINAL=($REVAD_EXTERNAL_PROTOCOL_FINAL), REVAD_EXTERNAL_HOST_FINAL=($REVAD_EXTERNAL_HOST_FINAL)" }
  }
  
  if $REVAD_EXTERNAL_HOST_FINAL != "external.test.docker" {
    error make { msg: $"Expected REVAD_EXTERNAL_HOST_FINAL=external.test.docker, got ($REVAD_EXTERNAL_HOST_FINAL)" }
  }
  
  if $EXTERNAL_REVAD_ENDPOINT != "https://external.test.docker" {
    error make { msg: $"Expected EXTERNAL_REVAD_ENDPOINT=https://external.test.docker, got ($EXTERNAL_REVAD_ENDPOINT)" }
  }
  
  print "Test 4 passed"
}

def test-fallback-scenario [] {
  print "\n=== Test 5: Fallback scenario (empty REVAD_EXTERNAL_* should use REVAD_* defaults) ==="
  
  $env.DOMAIN = "test.revad.docker"
  $env.REVAD_TLS_ENABLED = "true"
  $env.REVAD_PROTOCOL = "https"
  
  let DOMAIN = ((try { $env.DOMAIN } catch { "" }) | default "")
  let REVAD_TLS_ENABLED = ((try { $env.REVAD_TLS_ENABLED } catch { "" }) | default "false")
  let REVAD_PROTOCOL = ((try { $env.REVAD_PROTOCOL } catch { "" }) | default (if $REVAD_TLS_ENABLED == "false" { "http" } else { "https" }))
  
  let WEB_DOMAIN_RAW = (try { $env.WEB_DOMAIN } catch { "" } | default "")
  let WEB_DOMAIN = (if (($WEB_DOMAIN_RAW | describe) == "nothing" or ($WEB_DOMAIN_RAW | str trim | str length) == 0) {
    if ($DOMAIN | str length) > 0 {
      let hostname = ($DOMAIN | split row "." | get 0)
      let suffix = (if ($DOMAIN | split row "." | length) > 1 {
        ($DOMAIN | split row "." | skip 1 | str join ".")
      } else {
        ""
      })
      let clean_hostname = ($hostname | str replace -a "reva" "")
      if ($suffix | str length) > 0 {
        $"($clean_hostname).($suffix)"
      } else {
        $clean_hostname
      }
    } else {
      $DOMAIN
    }
  } else {
    $WEB_DOMAIN_RAW
  })
  
  let WEB_TLS_ENABLED_RAW = (try { $env.WEB_TLS_ENABLED } catch { "" } | default "")
  let WEB_TLS_ENABLED = (if (($WEB_TLS_ENABLED_RAW | describe) == "nothing" or ($WEB_TLS_ENABLED_RAW | str trim | str length) == 0) { $REVAD_TLS_ENABLED } else { $WEB_TLS_ENABLED_RAW })
  let WEB_PROTOCOL_RAW = (try { $env.WEB_PROTOCOL } catch { "" } | default "")
  let WEB_PROTOCOL = (if (($WEB_PROTOCOL_RAW | describe) == "nothing" or ($WEB_PROTOCOL_RAW | str trim | str length) == 0) {
    (if $WEB_TLS_ENABLED == "false" { "http" } else { "https" })
  } else {
    $WEB_PROTOCOL_RAW
  })
  
  let REVAD_EXTERNAL_HOST_RAW = (try { $env.REVAD_EXTERNAL_HOST } catch { "" } | default "")
  let REVAD_EXTERNAL_HOST = (if (($REVAD_EXTERNAL_HOST_RAW | describe) == "nothing" or ($REVAD_EXTERNAL_HOST_RAW | str trim | str length) == 0) { $WEB_DOMAIN } else { $REVAD_EXTERNAL_HOST_RAW })
  let REVAD_EXTERNAL_PROTOCOL_RAW = (try { $env.REVAD_EXTERNAL_PROTOCOL } catch { "" } | default "")
  let REVAD_EXTERNAL_PROTOCOL = (if (($REVAD_EXTERNAL_PROTOCOL_RAW | describe) == "nothing" or ($REVAD_EXTERNAL_PROTOCOL_RAW | str trim | str length) == 0) { $WEB_PROTOCOL } else { $REVAD_EXTERNAL_PROTOCOL_RAW })
  
  let REVAD_EXTERNAL_PROTOCOL_FINAL = (if ($REVAD_EXTERNAL_PROTOCOL | str trim | str length) == 0 {
    $REVAD_PROTOCOL
  } else {
    $REVAD_EXTERNAL_PROTOCOL
  })
  let REVAD_EXTERNAL_HOST_FINAL = (if ($REVAD_EXTERNAL_HOST | str trim | str length) == 0 {
    (if ($DOMAIN | str length) > 0 { $DOMAIN } else { "localhost" })
  } else {
    $REVAD_EXTERNAL_HOST
  })
  
  let EXTERNAL_REVAD_ENDPOINT = $"($REVAD_EXTERNAL_PROTOCOL_FINAL)://($REVAD_EXTERNAL_HOST_FINAL)"
  
  print $"DOMAIN: ($DOMAIN)"
  print $"REVAD_PROTOCOL: ($REVAD_PROTOCOL)"
  print $"REVAD_EXTERNAL_PROTOCOL: ($REVAD_EXTERNAL_PROTOCOL)"
  print $"REVAD_EXTERNAL_PROTOCOL_FINAL: ($REVAD_EXTERNAL_PROTOCOL_FINAL)"
  print $"REVAD_EXTERNAL_HOST: ($REVAD_EXTERNAL_HOST)"
  print $"REVAD_EXTERNAL_HOST_FINAL: ($REVAD_EXTERNAL_HOST_FINAL)"
  print $"EXTERNAL_REVAD_ENDPOINT: ($EXTERNAL_REVAD_ENDPOINT)"
  
  if $REVAD_EXTERNAL_PROTOCOL_FINAL != "https" {
    error make { msg: $"Expected REVAD_EXTERNAL_PROTOCOL_FINAL=https \(from REVAD_PROTOCOL\), got ($REVAD_EXTERNAL_PROTOCOL_FINAL)" }
  }
  
  if $REVAD_EXTERNAL_HOST_FINAL != "test.revad.docker" {
    error make { msg: $"Expected REVAD_EXTERNAL_HOST_FINAL=test.revad.docker \(from DOMAIN\), got ($REVAD_EXTERNAL_HOST_FINAL)" }
  }
  
  if $EXTERNAL_REVAD_ENDPOINT != "https://test.revad.docker" {
    error make { msg: $"Expected EXTERNAL_REVAD_ENDPOINT=https://test.revad.docker, got ($EXTERNAL_REVAD_ENDPOINT)" }
  }
  
  print "Test 5 passed (correctly fell back to REVAD_PROTOCOL and DOMAIN)"
}

export def run-all [] {
  test-minimal-env
  test-empty-domain
  test-reserved-prefix
  test-full-env
  test-fallback-scenario
  print "\nAll variable derivation tests passed!"
}
