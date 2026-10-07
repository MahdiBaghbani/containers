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

# Runtime registry and OCM network settings applied after a mode config is rendered.

use ../scripts/lib/resolve-configs.nu [resolve_configs]
use ../scripts/lib/runtime-config.nu [
  runtime-settings-from-env
  apply-runtime-settings
  write-runtime-settings
]

const SERVICE_ROOT = (path self | path dirname | path join ".." | path expand)
const CONFIG_DIR = ($SERVICE_ROOT | path join "configs")
const OVERLAY_DIR = ($SERVICE_ROOT | path join "configs-overlays")
const SCRATCH = "/tmp/test_runtime_config"

const MODES = [
  "gateway"
  "dataprovider-localhome"
  "dataprovider-ocm"
  "dataprovider-sciencemesh"
  "authprovider-oidc"
  "authprovider-machine"
  "authprovider-ocmshares"
  "authprovider-ocmsharecode"
  "authprovider-ocmexchangedtoken"
  "authprovider-publicshares"
  "shareproviders"
  "groupuserproviders"
]

const JWT = "{{placeholder:jwt-secret:reva-secret}}"
const RECEIVER_NATS = "nats://receiver-revad-registry:4222"
const SENDER_NATS = "nats://sender-revad-registry:4222"
const STOCK_DOMAIN = "cernbox.example"

# Quote and backslash so the TOML writer must escape it. Never print this value.
def nats-token [] {
  "p@ss\"w\\ord"
}

def mark [ok: bool, label: string] {
  if $ok {
    0
  } else {
    print $"  [FAIL] ($label)"
    1
  }
}

def add-mark [passed: int, failed: int, miss: int] {
  {passed: ($passed + (1 - $miss)), failed: ($failed + $miss)}
}

def runtime-env [overrides: record] {
  let base = {
    DOMAIN: ""
    REVAD_REGISTRY_DRIVER: ""
    REVAD_NATS_ADDRESS: ""
    REVAD_NATS_TOKEN: ""
    REVAD_NATS_BUCKET: ""
    REVAD_NATS_TTL: ""
    REVAD_REGISTRY_HEARTBEAT_INTERVAL: ""
    REVAD_REGISTRY_DEGRADED_AFTER: ""
    REVAD_REGISTRY_OFFLINE_AFTER: ""
    REVAD_REGISTRY_REAP_AFTER: ""
    OCM_ALLOWED_FEDERATION_CIDRS: ""
    OCM_TIMEOUT: ""
    OCM_CLIENT_INSECURE: ""
    OC_INSECURE: ""
    OCM_USE_ENV_PROXY: ""
    OCM_ALLOW_LOOPBACK_FEDERATION: ""
  }
  $base | merge $overrides
}

# Env overlays stay inside this call. The closure sees them; the caller does not.
def with-runtime-env [overrides: record, action: closure] {
  load-env (runtime-env $overrides)
  do $action
}

def stock-nats [address: string, domain: string] {
  {
    DOMAIN: $domain
    REVAD_REGISTRY_DRIVER: "nats"
    REVAD_NATS_ADDRESS: $address
    REVAD_NATS_BUCKET: "reva_registry"
    REVAD_NATS_TTL: "30s"
    REVAD_REGISTRY_HEARTBEAT_INTERVAL: "5s"
    REVAD_REGISTRY_DEGRADED_AFTER: "15s"
    REVAD_REGISTRY_OFFLINE_AFTER: "30s"
    REVAD_REGISTRY_REAP_AFTER: "5m"
  }
}

def section-count [text: string, header: string] {
  $text | lines | where {|line| ($line | str trim) == $header} | length
}

def stock-registry [cfg: record, address: string] {
  let reg = $cfg.shared.registry
  let nats = $reg.drivers.nats
  (
    ($reg.driver == "nats")
    and ($reg.heartbeat_interval == "5s")
    and ($reg.degraded_after == "15s")
    and ($reg.offline_after == "30s")
    and ($reg.reap_after == "5m")
    and ($nats.address == $address)
    and ($nats.bucket == "reva_registry")
    and ($nats.ttl == "30s")
    and (not ("token" in ($nats | columns)))
  )
}

def memory-registry [cfg: record] {
  let reg = $cfg.shared.registry
  (
    ($reg.driver == "memory")
    and ($reg.heartbeat_interval == "5s")
    and ($reg.degraded_after == "15s")
    and ($reg.offline_after == "30s")
    and ($reg.reap_after == "5m")
    and (not ("drivers" in ($reg | columns)))
  )
}

def sorted-cols [rec: record] {
  $rec | columns | sort
}

def received-fields [] {
  [
    "allow_loopback_federation"
    "allowed_federation_cidrs"
    "ocm_insecure"
    "ocm_timeout"
    "ocm_use_env_proxy"
    "provider_domain"
  ]
}

def received-ok [item: record, domain: string, net: record] {
  let driver = $item.drivers.ocmreceived
  (
    ($item.driver == "ocmreceived")
    and ((sorted-cols $driver) == (received-fields))
    and ($driver.provider_domain == $domain)
    and ($driver.ocm_timeout == $net.timeout)
    and ($driver.ocm_insecure == $net.insecure)
    and ($driver.allowed_federation_cidrs == $net.cidrs)
    and ($driver.ocm_use_env_proxy == $net.proxy)
    and ($driver.allow_loopback_federation == $net.loop)
  )
}

def both-received [cfg: record, domain: string, net: record] {
  let storage = ($cfg.grpc.services.storageprovider | first)
  let data = ($cfg.http.services.dataprovider | first)
  (
    (received-ok $storage $domain $net)
    and (received-ok $data $domain $net)
    and ($storage.data_server_url == "{{placeholder:data-server-url-internal.sciencemesh}}")
  )
}

def localhome-unchanged [cfg: record] {
  let storage = ($cfg.grpc.services.storageprovider | first)
  let data = ($cfg.http.services.dataprovider | first)
  let storage_driver = $storage.drivers.localhome
  let data_driver = $data.drivers.localhome
  (
    ($storage.driver == "localhome")
    and ($storage.mount_id == "localhome")
    and ($storage_driver.root == "/revalocalstorage")
    and ($storage_driver.user_layout == "{{.Username}}")
    and ($storage_driver.share_folder == "MyShares")
    and (not ("provider_domain" in (sorted-cols $storage_driver)))
    and (not ("ocm_timeout" in (sorted-cols $storage_driver)))
    and ($data.driver == "localhome")
    and ($data_driver.root == "/revalocalstorage")
    and (not ("allow_loopback_federation" in (sorted-cols $data_driver)))
  )
}

def outgoing-unchanged [cfg: record] {
  let storage = ($cfg.grpc.services.storageprovider | first)
  let data = ($cfg.http.services.dataprovider | first)
  (
    ($storage.driver == "ocmoutcoming")
    and ($storage.drivers.ocmoutcoming.machine_secret == "{{ vars.machine_api_key }}")
    and (not ("provider_domain" in (sorted-cols $storage.drivers.ocmoutcoming)))
    and ($data.driver == "ocmoutcoming")
    and ($data.drivers.ocmoutcoming.machine_secret == "{{ vars.machine_api_key }}")
    and (not ("ocm_use_env_proxy" in (sorted-cols $data.drivers.ocmoutcoming)))
  )
}

def gateway-network [cfg: record, net: record] {
  let ocm = $cfg.http.services.ocm
  let mesh = $cfg.http.services.sciencemesh
  let mesh_cols = (sorted-cols $mesh)
  let open = $cfg.grpc.services.ocmproviderauthorizer.drivers.open
  (
    ($ocm.prefix == "ocm")
    and ($ocm.token_manager == "jwt")
    and ($ocm.token_managers.jwt.expire == 86400)
    and ($ocm.ocm_client_timeout == $net.timeout)
    and ($ocm.ocm_client_insecure == $net.insecure)
    and ($ocm.allowed_federation_cidrs == $net.cidrs)
    and ($ocm.ocm_client_use_env_proxy == $net.proxy)
    and ($ocm.allow_loopback_federation == $net.loop)
    and ($mesh.ocm_client_timeout == $net.timeout)
    and ($mesh.ocm_client_insecure == $net.insecure)
    and ($mesh.allowed_federation_cidrs == $net.cidrs)
    and ($mesh.ocm_client_use_env_proxy == $net.proxy)
    and ($mesh.ocm_mount_point == "/sciencemesh")
    and (not ("allow_loopback_federation" in $mesh_cols))
    and ($cfg.grpc.services.ocmproviderauthorizer.driver == "open")
    and ((sorted-cols $open) == ["allowed_federation_cidrs" "insecure" "ocm_client_use_env_proxy"])
    and ($open.insecure == $net.insecure)
    and ($open.allowed_federation_cidrs == $net.cidrs)
    and ($open.ocm_client_use_env_proxy == $net.proxy)
    and ($cfg.grpc.services.ocmproviderauthorizer.drivers.json.providers == "{{placeholder:config-dir}}/providers.testnet.json")
  )
}

def semantics-ok [mode: string, cfg: record, domain: string, net: record] {
  let jwt_ok = ($cfg.shared.jwt_secret == $JWT)
  match $mode {
    "gateway" => (
      $jwt_ok
      and ($cfg.shared.skip_user_groups_in_token == true)
      and ($cfg.http.services.wellknown.ocmprovider.enable_code_flow == true)
      and ($cfg.grpc.services.authregistry.driver == "static")
      and ($cfg.grpc.services.authregistry.drivers.static.rules.basic == "{{placeholder:authprovider.oidc.address}}")
      and ($cfg.grpc.services.storageregistry.driver == "static")
      and ($cfg.grpc.services.storageregistry.drivers.static.home_provider == "/")
      and (($cfg.grpc.services.storageregistry.drivers.static.rules | get "/").address == "{{placeholder:storageprovider.localhome}}")
      and (gateway-network $cfg $net)
    )
    "shareproviders" => (
      $jwt_ok
      and ($cfg.shared.skip_user_groups_in_token == true)
      and ($cfg.grpc.services.ocmshareprovider.webapp_endpoint == "{{placeholder:external-reva-endpoint}}/external/sciencemesh")
      and (not ("webapp_template" in (sorted-cols $cfg.grpc.services.ocmshareprovider)))
      and ($cfg.grpc.services.ocmshareprovider.drivers.json.file == "{{placeholder:ocmshares-json-file}}")
      and ($cfg.grpc.services.ocmincoming.drivers.json.file == "{{placeholder:ocmshares-json-file}}")
    )
    "groupuserproviders" => (
      $jwt_ok
      and ($cfg.shared.skip_user_groups_in_token == true)
      and ($cfg.grpc.services.userprovider.driver == "json")
      and ($cfg.grpc.services.userprovider.drivers.json.users == "{{placeholder:config-dir}}/users.demo.json")
      and ($cfg.grpc.services.groupprovider.driver == "json")
      and ($cfg.grpc.services.groupprovider.drivers.json.groups == "{{placeholder:config-dir}}/groups.demo.json")
    )
    "dataprovider-localhome" => {
      $jwt_ok and (localhome-unchanged $cfg)
    }
    "dataprovider-ocm" => {
      $jwt_ok and (outgoing-unchanged $cfg)
    }
    "dataprovider-sciencemesh" => {
      $jwt_ok and (both-received $cfg $domain $net)
    }
    "authprovider-ocmexchangedtoken" => (
      $jwt_ok
      and ($cfg.grpc.services.authprovider.auth_manager == "ocmexchangedtoken")
      and ($cfg.grpc.services.authprovider.auth_managers.ocmexchangedtoken.token_manager == "jwt")
      and ($cfg.grpc.services.authprovider.auth_managers.ocmexchangedtoken.token_managers.jwt.expire == 86400)
    )
    "authprovider-publicshares" => (
      $jwt_ok
      and ($cfg.grpc.services.authprovider.auth_manager == "publicshares")
      and ($cfg.grpc.services.publicstorageprovider.mount_path == "/public")
      and ($cfg.grpc.services.publicstorageprovider.gateway_addr == "{{placeholder:gateway-svc}}")
    )
    _ => {
      let manager = ($mode | str replace "authprovider-" "")
      $jwt_ok and ($cfg.grpc.services.authprovider.auth_manager == $manager)
    }
  }
}

def defaults-net [] {
  {timeout: 10, insecure: false, cidrs: [], proxy: false, loop: false}
}

def neutralize-tree [dir: string] {
  let files = (
    ls $dir
    | where type == file
    | where {|row| $row.name | str ends-with ".toml"}
    | get name
  )
  for file in $files {
    let text = (open --raw $file)
    let fixed = (
      $text
      | str replace -a 'expire = {{placeholder:jwt-expire:86400}}' 'expire = 86400'
      | str replace -a 'ocm_timeout = {{placeholder:ocm-timeout:10}}' 'ocm_timeout = 10'
      | str replace -a 'ocm_insecure = {{placeholder:ocm-insecure:false}}' 'ocm_insecure = false'
    )
    $fixed | save -f $file
  }
}

def fresh-master [] {
  rm -rf $SCRATCH
  let dest = ($SCRATCH | path join "master")
  ^mkdir -p $dest
  resolve_configs $CONFIG_DIR $OVERLAY_DIR "master" $dest
  neutralize-tree $dest
  $dest
}

def stage-mode [master: string, mode: string] {
  let dest_dir = ($SCRATCH | path join "work")
  ^mkdir -p $dest_dir
  let dest = ($dest_dir | path join $"($mode).toml")
  ^cp $"($master)/($mode).toml" $dest
  $dest
}

def minimal-body [] {
  "[shared]\njwt_secret = \"kept-secret\"\n"
}

def write-text [path: string, text: string] {
  ^mkdir -p ($path | path dirname)
  $text | save -f $path
}

def expect-fixed [expected: string, forbidden: string, action: closure] {
  try {
    do $action
    {ok: false, echoed: false, detail: "call did not fail"}
  } catch {|err|
    let msg = (try { $err.msg } catch { "missing error message" })
    let echoed = (($forbidden | str length) > 0) and ($msg | str contains $forbidden)
    if $echoed {
      {ok: false, echoed: true, detail: "input echoed"}
    } else if $msg != $expected {
      {ok: false, echoed: false, detail: $msg}
    } else {
      {ok: true, echoed: false, detail: ""}
    }
  }
}

def check-expect [label: string, expected: string, forbidden: string, action: closure] {
  let got = (expect-fixed $expected $forbidden $action)
  if $got.ok {
    0
  } else if $got.echoed {
    print $"  [FAIL] ($label): input echoed"
    1
  } else {
    print $"  [FAIL] ($label): ($got.detail)"
    1
  }
}

def run-mode [master: string, mode: string] {
  let path = (stage-mode $master $mode)
  let net = (defaults-net)
  mut passed = 0
  mut failed = 0

  let mem = (with-runtime-env {DOMAIN: $STOCK_DOMAIN} {||
    write-runtime-settings $path $mode
    {cfg: (open $path), text: (open --raw $path)}
  })
  let mem_ok = (
    (memory-registry $mem.cfg)
    and ((section-count $mem.text "[shared.registry]") == 1)
    and ((section-count $mem.text "[shared.registry.drivers.nats]") == 0)
    and (semantics-ok $mode $mem.cfg $STOCK_DOMAIN $net)
  )
  let mem_miss = (mark $mem_ok $"($mode) memory registry and semantic tables")
  $passed = ($passed + (1 - $mem_miss))
  $failed = ($failed + $mem_miss)

  let nats = (with-runtime-env (stock-nats $RECEIVER_NATS $STOCK_DOMAIN) {||
    write-runtime-settings $path $mode
    let once = (open --raw $path)
    write-runtime-settings $path $mode
    let twice = (open --raw $path)
    {cfg: (open $path), once: $once, twice: $twice}
  })
  let nats_ok = (
    (stock-registry $nats.cfg $RECEIVER_NATS)
    and ($nats.once == $nats.twice)
    and ((section-count $nats.twice "[shared.registry]") == 1)
    and ((section-count $nats.twice "[shared.registry.drivers.nats]") == 1)
    and (semantics-ok $mode $nats.cfg $STOCK_DOMAIN $net)
  )
  let nats_miss = (mark $nats_ok $"($mode) stock nats schema, idempotence, semantic tables")
  $passed = ($passed + (1 - $nats_miss))
  $failed = ($failed + $nats_miss)

  {passed: $passed, failed: $failed}
}

# All 12 effective master configs, including a file that already exists on disk.
def test-all-modes [] {
  print "Testing all 12 modes, master overlays, and idempotence..."
  rm -rf $SCRATCH
  let result = (try {
    let master = (fresh-master)
    mut passed = 0
    mut failed = 0
    for mode in $MODES {
      let step = (try {
        run-mode $master $mode
      } catch {|err|
        print $"  [FAIL] ($mode) unexpected: ($err.msg)"
        {passed: 0, failed: 1}
      })
      $passed = ($passed + $step.passed)
      $failed = ($failed + $step.failed)
    }
    {passed: $passed, failed: $failed}
  } catch {|err|
    print $"  [FAIL] mode setup: ($err.msg)"
    {passed: 0, failed: 1}
  })
  rm -rf $SCRATCH
  if $result.failed == 0 {
    print "  [PASS] All 12 modes: PASSED"
  }
  $result
}

def test-stock-schema [] {
  print "Testing exact stock NATS schema and memory omission..."
  rm -rf $SCRATCH
  let path = ($SCRATCH | path join "schema.toml")
  let result = (try {
    mut passed = 0
    mut failed = 0
    write-text $path (minimal-body)

    let receiver = (with-runtime-env (stock-nats $RECEIVER_NATS $STOCK_DOMAIN) {||
      write-runtime-settings $path "groupuserproviders"
      open --raw $path
    })
    let receiver_expected = '[shared]
jwt_secret = "kept-secret"

[shared.registry]
driver = "nats"
heartbeat_interval = "5s"
degraded_after = "15s"
offline_after = "30s"
reap_after = "5m"

[shared.registry.drivers.nats]
address = "nats://receiver-revad-registry:4222"
bucket = "reva_registry"
ttl = "30s"'
    let receiver_miss = (mark (($receiver | str trim) == ($receiver_expected | str trim)) "receiver stock schema text")
    $passed = ($passed + (1 - $receiver_miss))
    $failed = ($failed + $receiver_miss)

    let sender = (with-runtime-env (stock-nats $SENDER_NATS $STOCK_DOMAIN) {||
      write-runtime-settings $path "groupuserproviders"
      open --raw $path
    })
    let sender_expected = ($receiver_expected | str replace $RECEIVER_NATS $SENDER_NATS)
    let sender_miss = (mark (($sender | str trim) == ($sender_expected | str trim)) "sender stock schema text")
    $passed = ($passed + (1 - $sender_miss))
    $failed = ($failed + $sender_miss)

    let blank_token = (with-runtime-env (stock-nats $RECEIVER_NATS $STOCK_DOMAIN | merge {REVAD_NATS_TOKEN: "   "}) {||
      write-runtime-settings $path "groupuserproviders"
      open $path
    })
    let blank_miss = (mark (stock-registry $blank_token $RECEIVER_NATS) "whitespace token stays omitted")
    $passed = ($passed + (1 - $blank_miss))
    $failed = ($failed + $blank_miss)

    write-text $path (minimal-body)
    let memory = (with-runtime-env {DOMAIN: $STOCK_DOMAIN} {||
      write-runtime-settings $path "shareproviders"
      open --raw $path
    })
    let memory_expected = '[shared]
jwt_secret = "kept-secret"

[shared.registry]
driver = "memory"
heartbeat_interval = "5s"
degraded_after = "15s"
offline_after = "30s"
reap_after = "5m"'
    let memory_miss = (mark (
      (($memory | str trim) == ($memory_expected | str trim))
      and (not ($memory | str contains "drivers.nats"))
      and (not ($memory | str contains "nats://"))
    ) "memory driver has no NATS block")
    $passed = ($passed + (1 - $memory_miss))
    $failed = ($failed + $memory_miss)

    {passed: $passed, failed: $failed}
  } catch {|err|
    print $"  [FAIL] stock schema unexpected: ($err.msg)"
    {passed: 0, failed: 1}
  })
  rm -rf $SCRATCH
  if $result.failed == 0 {
    print "  [PASS] Stock schema: PASSED"
  }
  $result
}

def test-token-roundtrip [] {
  print "Testing escaped NATS token round-trip..."
  rm -rf $SCRATCH
  let path = ($SCRATCH | path join "token.toml")
  let secret = (nats-token)
  let result = (try {
    mut passed = 0
    mut failed = 0
    write-text $path (minimal-body)

    let length_miss = (mark (($secret | str length) == 10) "token fixture length")
    $passed = ($passed + (1 - $length_miss))
    $failed = ($failed + $length_miss)

    let rendered = (with-runtime-env (stock-nats $RECEIVER_NATS $STOCK_DOMAIN | merge {REVAD_NATS_TOKEN: $secret}) {||
      write-runtime-settings $path "gateway"
      {cfg: (open $path), text: (open --raw $path)}
    })
    let token_line = $"token = '($secret)'"
    let round_ok = (
      ($rendered.cfg.shared.registry.drivers.nats.token? | default "") == $secret
      and ($rendered.text | str contains $token_line)
      and ((section-count $rendered.text "[shared.registry]") == 1)
    )
    let round_miss = (mark $round_ok "token round-trip and escape")
    $passed = ($passed + (1 - $round_miss))
    $failed = ($failed + $round_miss)

    let cleared = (with-runtime-env (stock-nats $SENDER_NATS $STOCK_DOMAIN) {||
      write-runtime-settings $path "gateway"
      {cfg: (open $path), text: (open --raw $path)}
    })
    let cleared_ok = (
      (stock-registry $cleared.cfg $SENDER_NATS)
      and (not ($cleared.text | str contains $secret))
      and (not ($cleared.text | str contains "token ="))
    )
    let cleared_miss = (mark $cleared_ok "clearing the token removes it")
    $passed = ($passed + (1 - $cleared_miss))
    $failed = ($failed + $cleared_miss)

    {passed: $passed, failed: $failed}
  } catch {|err|
    let safe = ($err.msg | str replace -a (nats-token) "[redacted]")
    print $"  [FAIL] token unexpected: ($safe)"
    {passed: 0, failed: 1}
  })
  rm -rf $SCRATCH
  if $result.failed == 0 {
    print "  [PASS] Token round-trip: PASSED"
  }
  $result
}

def test-durations [] {
  print "Testing duration units, order, and original strings..."
  rm -rf $SCRATCH
  let path = ($SCRATCH | path join "duration.toml")
  let result = (try {
    mut passed = 0
    mut failed = 0
    write-text $path (minimal-body)

    # Whole-number units. A fractional magnitude such as 2.5m is rejected
    # by the current parser, so these strings stay on integer Go units.
    let units = (with-runtime-env {
      DOMAIN: $STOCK_DOMAIN
      REVAD_REGISTRY_DRIVER: "memory"
      REVAD_REGISTRY_HEARTBEAT_INTERVAL: "1ns"
      REVAD_REGISTRY_DEGRADED_AFTER: "1us"
      REVAD_REGISTRY_OFFLINE_AFTER: "1ms"
      REVAD_REGISTRY_REAP_AFTER: "1h"
      REVAD_NATS_TTL: "2m"
    } {||
      write-runtime-settings $path "authprovider-machine"
      open $path
    })
    let reg = $units.shared.registry
    let units_ok = (
      ($reg.driver == "memory")
      and ($reg.heartbeat_interval == "1ns")
      and ($reg.degraded_after == "1us")
      and ($reg.offline_after == "1ms")
      and ($reg.reap_after == "1h")
      and (not ("drivers" in (sorted-cols $reg)))
    )
    let units_miss = (mark $units_ok "original Go duration strings")
    $passed = ($passed + (1 - $units_miss))
    $failed = ($failed + $units_miss)

    let ttl_text = (with-runtime-env {
      DOMAIN: $STOCK_DOMAIN
      REVAD_REGISTRY_DRIVER: "nats"
      REVAD_NATS_ADDRESS: $RECEIVER_NATS
      REVAD_NATS_TTL: "2m"
      REVAD_REGISTRY_HEARTBEAT_INTERVAL: "1ns"
      REVAD_REGISTRY_DEGRADED_AFTER: "1us"
      REVAD_REGISTRY_OFFLINE_AFTER: "1ms"
      REVAD_REGISTRY_REAP_AFTER: "1h"
    } {||
      write-runtime-settings $path "authprovider-machine"
      (open $path).shared.registry.drivers.nats.ttl
    })
    let ttl_miss = (mark ($ttl_text == "2m") "ttl keeps the original duration text")
    $passed = ($passed + (1 - $ttl_miss))
    $failed = ($failed + $ttl_miss)

    let zero_cases = [
      {name: "REVAD_REGISTRY_HEARTBEAT_INTERVAL", value: "0s"}
      {name: "REVAD_REGISTRY_DEGRADED_AFTER", value: "0s"}
      {name: "REVAD_REGISTRY_OFFLINE_AFTER", value: "0m"}
      {name: "REVAD_REGISTRY_REAP_AFTER", value: "0s"}
      {name: "REVAD_NATS_TTL", value: "0s"}
    ]
    for case in $zero_cases {
      let overrides = {DOMAIN: $STOCK_DOMAIN} | upsert $case.name $case.value
      let expected = $"($case.name) must be a positive duration"
      let miss = (check-expect $"zero ($case.name)" $expected $case.value {||
        with-runtime-env $overrides {|| runtime-settings-from-env }
      })
      $passed = ($passed + (1 - $miss))
      $failed = ($failed + $miss)
    }

    let negative_cases = [
      {name: "REVAD_REGISTRY_HEARTBEAT_INTERVAL", value: "-1s"}
      {name: "REVAD_NATS_TTL", value: "-5ms"}
    ]
    for case in $negative_cases {
      let overrides = {DOMAIN: $STOCK_DOMAIN} | upsert $case.name $case.value
      let expected = $"($case.name) must be a positive duration"
      let miss = (check-expect $"negative ($case.name)" $expected $case.value {||
        with-runtime-env $overrides {|| runtime-settings-from-env }
      })
      $passed = ($passed + (1 - $miss))
      $failed = ($failed + $miss)
    }

    let bad_cases = [
      {name: "REVAD_REGISTRY_HEARTBEAT_INTERVAL", value: "10"}
      {name: "REVAD_REGISTRY_OFFLINE_AFTER", value: "5d"}
    ]
    for case in $bad_cases {
      let overrides = {DOMAIN: $STOCK_DOMAIN} | upsert $case.name $case.value
      let expected = $"($case.name) must be a positive duration"
      let miss = (check-expect $"bad ($case.name)" $expected $case.value {||
        with-runtime-env $overrides {|| runtime-settings-from-env }
      })
      $passed = ($passed + (1 - $miss))
      $failed = ($failed + $miss)
    }

    let order_msg = "registry liveness order must be heartbeat < degraded < offline < reap"
    let order_cases = [
      {label: "heartbeat equal degraded", heartbeat: "15s", degraded: "15s", offline: "30s", reap: "5m", forbidden: "15s"}
      {label: "heartbeat greater degraded", heartbeat: "20s", degraded: "15s", offline: "30s", reap: "5m", forbidden: "20s"}
      {label: "degraded equal offline", heartbeat: "5s", degraded: "30s", offline: "30s", reap: "5m", forbidden: "30s"}
      {label: "offline equal reap", heartbeat: "5s", degraded: "15s", offline: "5m", reap: "5m", forbidden: "5m"}
    ]
    for case in $order_cases {
      let overrides = {
        DOMAIN: $STOCK_DOMAIN
        REVAD_REGISTRY_HEARTBEAT_INTERVAL: $case.heartbeat
        REVAD_REGISTRY_DEGRADED_AFTER: $case.degraded
        REVAD_REGISTRY_OFFLINE_AFTER: $case.offline
        REVAD_REGISTRY_REAP_AFTER: $case.reap
      }
      let miss = (check-expect $case.label $order_msg $case.forbidden {||
        with-runtime-env $overrides {|| runtime-settings-from-env }
      })
      $passed = ($passed + (1 - $miss))
      $failed = ($failed + $miss)
    }

    let short_ttl = (check-expect "ttl shorter than offline" "REVAD_NATS_TTL must be at least offline_after" "29s" {||
      with-runtime-env {DOMAIN: $STOCK_DOMAIN, REVAD_NATS_TTL: "29s"} {|| runtime-settings-from-env }
    })
    $passed = ($passed + (1 - $short_ttl))
    $failed = ($failed + $short_ttl)

    let equal_ttl = (with-runtime-env {
      DOMAIN: $STOCK_DOMAIN
      REVAD_REGISTRY_DRIVER: "nats"
      REVAD_NATS_ADDRESS: $RECEIVER_NATS
      REVAD_NATS_TTL: "30s"
      REVAD_REGISTRY_OFFLINE_AFTER: "30s"
    } {||
      write-runtime-settings $path "authprovider-oidc"
      (open $path).shared.registry.drivers.nats.ttl
    })
    let equal_miss = (mark ($equal_ttl == "30s") "ttl equal to offline is accepted")
    $passed = ($passed + (1 - $equal_miss))
    $failed = ($failed + $equal_miss)

    {passed: $passed, failed: $failed}
  } catch {|err|
    print $"  [FAIL] duration unexpected: ($err.msg)"
    {passed: 0, failed: 1}
  })
  rm -rf $SCRATCH
  if $result.failed == 0 {
    print "  [PASS] Durations: PASSED"
  }
  $result
}

def test-fixed-failures [] {
  print "Testing fixed errors with no fallback and no input echo..."
  rm -rf $SCRATCH
  let path = ($SCRATCH | path join "fail.toml")
  let result = (try {
    mut passed = 0
    mut failed = 0
    let body = (minimal-body)
    let cases = [
      {label: "unknown driver", expected: "REVAD_REGISTRY_DRIVER must be memory or nats", forbidden: "redis", overrides: {DOMAIN: $STOCK_DOMAIN, REVAD_REGISTRY_DRIVER: "redis"}}
      {label: "driver case", expected: "REVAD_REGISTRY_DRIVER must be memory or nats", forbidden: "NATS", overrides: {DOMAIN: $STOCK_DOMAIN, REVAD_REGISTRY_DRIVER: "NATS"}}
      {label: "blank nats address", expected: "REVAD_NATS_ADDRESS is required when registry driver is nats", forbidden: "", overrides: {DOMAIN: $STOCK_DOMAIN, REVAD_REGISTRY_DRIVER: "nats", REVAD_NATS_ADDRESS: ""}}
      {label: "whitespace nats address", expected: "REVAD_NATS_ADDRESS is required when registry driver is nats", forbidden: "   ", overrides: {DOMAIN: $STOCK_DOMAIN, REVAD_REGISTRY_DRIVER: "nats", REVAD_NATS_ADDRESS: "   "}}
      {label: "non nats address", expected: "REVAD_NATS_ADDRESS must be a nats:// host:port URL", forbidden: "http://receiver-revad-registry:4222", overrides: {DOMAIN: $STOCK_DOMAIN, REVAD_REGISTRY_DRIVER: "nats", REVAD_NATS_ADDRESS: "http://receiver-revad-registry:4222"}}
      {label: "missing nats port", expected: "REVAD_NATS_ADDRESS must be a nats:// host:port URL", forbidden: "nats://receiver-revad-registry", overrides: {DOMAIN: $STOCK_DOMAIN, REVAD_REGISTRY_DRIVER: "nats", REVAD_NATS_ADDRESS: "nats://receiver-revad-registry"}}
      {label: "nats port out of range", expected: "REVAD_NATS_ADDRESS must be a nats:// host:port URL", forbidden: "nats://registry.example:99999", overrides: {DOMAIN: $STOCK_DOMAIN, REVAD_REGISTRY_DRIVER: "nats", REVAD_NATS_ADDRESS: "nats://registry.example:99999"}}
      {label: "invalid bucket", expected: "REVAD_NATS_BUCKET must contain only letters, digits, underscore, or hyphen", forbidden: "bad bucket", overrides: {DOMAIN: $STOCK_DOMAIN, REVAD_NATS_BUCKET: "bad bucket"}}
      {label: "proxy bool", expected: "OCM_USE_ENV_PROXY must be true or false", forbidden: "yes", overrides: {DOMAIN: $STOCK_DOMAIN, OCM_USE_ENV_PROXY: "yes"}}
      {label: "loopback bool", expected: "OCM_ALLOW_LOOPBACK_FEDERATION must be true or false", forbidden: "1", overrides: {DOMAIN: $STOCK_DOMAIN, OCM_ALLOW_LOOPBACK_FEDERATION: "1"}}
      {label: "timeout zero", expected: "OCM_TIMEOUT must be a positive integer", forbidden: "0", overrides: {DOMAIN: $STOCK_DOMAIN, OCM_TIMEOUT: "0"}}
      {label: "timeout fraction", expected: "OCM_TIMEOUT must be a positive integer", forbidden: "10.5", overrides: {DOMAIN: $STOCK_DOMAIN, OCM_TIMEOUT: "10.5"}}
      {label: "timeout word", expected: "OCM_TIMEOUT must be a positive integer", forbidden: "abc", overrides: {DOMAIN: $STOCK_DOMAIN, OCM_TIMEOUT: "abc"}}
      {label: "cidr bad json", expected: "OCM_ALLOWED_FEDERATION_CIDRS must be a JSON array of strings", forbidden: "not-json", overrides: {DOMAIN: $STOCK_DOMAIN, OCM_ALLOWED_FEDERATION_CIDRS: "not-json"}}
      {label: "cidr number", expected: "OCM_ALLOWED_FEDERATION_CIDRS must be a JSON array of strings", forbidden: "[1]", overrides: {DOMAIN: $STOCK_DOMAIN, OCM_ALLOWED_FEDERATION_CIDRS: "[1]"}}
      {label: "cidr mixed", expected: "OCM_ALLOWED_FEDERATION_CIDRS must be a JSON array of strings", forbidden: "[\"ok\", 2]", overrides: {DOMAIN: $STOCK_DOMAIN, OCM_ALLOWED_FEDERATION_CIDRS: "[\"ok\", 2]"}}
      {label: "unknown mode", expected: "unknown runtime config mode", forbidden: "not-a-mode", overrides: {DOMAIN: $STOCK_DOMAIN}, mode: "not-a-mode"}
    ]

    for case in $cases {
      write-text $path $body
      let before = (open --raw $path)
      let mode = ($case.mode? | default "gateway")
      let overrides = $case.overrides
      let miss = (check-expect $case.label $case.expected $case.forbidden {||
        with-runtime-env $overrides {||
          if $mode == "not-a-mode" {
            apply-runtime-settings {shared: {jwt_secret: "kept-secret"}} "not-a-mode" {
              registry: {driver: "memory"}
              network: {}
              provider_domain: "d"
            }
          }
          write-runtime-settings $path $mode
        }
      })
      $passed = ($passed + (1 - $miss))
      $failed = ($failed + $miss)
      let same = ((open --raw $path) == $before)
      let same_miss = (mark $same $"($case.label) leaves the file unchanged")
      $passed = ($passed + (1 - $same_miss))
      $failed = ($failed + $same_miss)
    }

    {passed: $passed, failed: $failed}
  } catch {|err|
    print $"  [FAIL] fixed errors unexpected: ($err.msg)"
    {passed: 0, failed: 1}
  })
  rm -rf $SCRATCH
  if $result.failed == 0 {
    print "  [PASS] Fixed errors: PASSED"
  }
  $result
}

def render-mode [master: string, mode: string, overrides: record] {
  let path = (stage-mode $master $mode)
  with-runtime-env $overrides {||
    write-runtime-settings $path $mode
    open $path
  }
}

def test-network [] {
  print "Testing OCM network transforms and production defaults..."
  rm -rf $SCRATCH
  let result = (try {
    let master = (fresh-master)
    mut passed = 0
    mut failed = 0
    let first_net = {timeout: 21, insecure: true, cidrs: ["10.8.0.0/24"], proxy: true, loop: true}
    let first_env = {
      DOMAIN: "sender.example"
      OCM_TIMEOUT: "21"
      OCM_CLIENT_INSECURE: "true"
      OCM_USE_ENV_PROXY: "true"
      OCM_ALLOW_LOOPBACK_FEDERATION: "true"
      OCM_ALLOWED_FEDERATION_CIDRS: '["10.8.0.0/24"]'
    }
    let second_net = {timeout: 33, insecure: false, cidrs: ["172.16.5.0/24" "10.9.0.0/16"], proxy: false, loop: false}
    let second_env = {
      DOMAIN: "receiver.example"
      OCM_TIMEOUT: "33"
      OCM_CLIENT_INSECURE: "false"
      OCM_USE_ENV_PROXY: "false"
      OCM_ALLOW_LOOPBACK_FEDERATION: "false"
      OCM_ALLOWED_FEDERATION_CIDRS: '["172.16.5.0/24","10.9.0.0/16"]'
    }

    let gateway = (render-mode $master "gateway" $first_env)
    let gateway_miss = (mark (gateway-network $gateway $first_net) "gateway exact keys and open authorizer")
    $passed = ($passed + (1 - $gateway_miss))
    $failed = ($failed + $gateway_miss)

    let mesh_path = (stage-mode $master "dataprovider-sciencemesh")
    let first_mesh = (with-runtime-env $first_env {||
      write-runtime-settings $mesh_path "dataprovider-sciencemesh"
      open $mesh_path
    })
    let first_mesh_miss = (mark (both-received $first_mesh "sender.example" $first_net) "both received drivers take the first domain and subnet")
    $passed = ($passed + (1 - $first_mesh_miss))
    $failed = ($failed + $first_mesh_miss)

    let second_mesh = (with-runtime-env $second_env {||
      write-runtime-settings $mesh_path "dataprovider-sciencemesh"
      open $mesh_path
    })
    let second_mesh_miss = (mark (both-received $second_mesh "receiver.example" $second_net) "alternate domain and subnet replace both received drivers")
    $passed = ($passed + (1 - $second_mesh_miss))
    $failed = ($failed + $second_mesh_miss)

    let localhome = (render-mode $master "dataprovider-localhome" $first_env)
    let local_miss = (mark (localhome-unchanged $localhome) "localhome drivers stay unchanged")
    $passed = ($passed + (1 - $local_miss))
    $failed = ($failed + $local_miss)

    let outgoing = (render-mode $master "dataprovider-ocm" $first_env)
    let outgoing_miss = (mark (outgoing-unchanged $outgoing) "outgoing drivers stay unchanged")
    $passed = ($passed + (1 - $outgoing_miss))
    $failed = ($failed + $outgoing_miss)

    let defaults = (defaults-net)
    let default_gateway = (render-mode $master "gateway" {DOMAIN: $STOCK_DOMAIN})
    let default_mesh = (render-mode $master "dataprovider-sciencemesh" {DOMAIN: $STOCK_DOMAIN})
    let default_miss = (mark (
      (gateway-network $default_gateway $defaults)
      and (both-received $default_mesh $STOCK_DOMAIN $defaults)
    ) "production defaults are false and empty")
    $passed = ($passed + (1 - $default_miss))
    $failed = ($failed + $default_miss)

    let oc_true = (render-mode $master "gateway" {DOMAIN: $STOCK_DOMAIN, OC_INSECURE: "TRUE"})
    let oc_miss = (mark ($oc_true.http.services.ocm.ocm_client_insecure == true) "OC_INSECURE fills in when OCM_CLIENT_INSECURE is unset")
    $passed = ($passed + (1 - $oc_miss))
    $failed = ($failed + $oc_miss)

    let specific = (render-mode $master "gateway" {
      DOMAIN: $STOCK_DOMAIN
      OC_INSECURE: "true"
      OCM_CLIENT_INSECURE: "false"
    })
    let specific_mesh = (render-mode $master "dataprovider-sciencemesh" {
      DOMAIN: $STOCK_DOMAIN
      OC_INSECURE: "true"
      OCM_CLIENT_INSECURE: "false"
    })
    let specific_miss = (mark (
      ($specific.http.services.ocm.ocm_client_insecure == false)
      and ($specific.http.services.sciencemesh.ocm_client_insecure == false)
      and ($specific.grpc.services.ocmproviderauthorizer.drivers.open.insecure == false)
      and (($specific_mesh.grpc.services.storageprovider | first).drivers.ocmreceived.ocm_insecure == false)
    ) "OCM_CLIENT_INSECURE overrides OC_INSECURE")
    $passed = ($passed + (1 - $specific_miss))
    $failed = ($failed + $specific_miss)

    let loose = (render-mode $master "gateway" {DOMAIN: $STOCK_DOMAIN, OCM_CLIENT_INSECURE: "yes"})
    let loose_miss = (mark ($loose.http.services.ocm.ocm_client_insecure == false) "OCM_CLIENT_INSECURE accepts only true")
    $passed = ($passed + (1 - $loose_miss))
    $failed = ($failed + $loose_miss)

    {passed: $passed, failed: $failed}
  } catch {|err|
    print $"  [FAIL] network unexpected: ($err.msg)"
    {passed: 0, failed: 1}
  })
  rm -rf $SCRATCH
  if $result.failed == 0 {
    print "  [PASS] Network transform: PASSED"
  }
  $result
}

def save-cfg [path: string, cfg: record] {
  $cfg | to toml | save -f $path
}

def test-sciencemesh-cardinality [] {
  print "Testing sciencemesh received-driver cardinality..."
  rm -rf $SCRATCH
  let result = (try {
    let master = (fresh-master)
    mut passed = 0
    mut failed = 0
    let storage_msg = "dataprovider-sciencemesh requires exactly one ocmreceived storage provider"
    let data_msg = "dataprovider-sciencemesh requires exactly one ocmreceived data provider"
    let mode_env = {DOMAIN: $STOCK_DOMAIN}

    let missing_path = (stage-mode $master "dataprovider-localhome")
    let missing_before = (open --raw $missing_path)
    let missing_miss = (check-expect "missing received storage" $storage_msg "" {||
      with-runtime-env $mode_env {|| write-runtime-settings $missing_path "dataprovider-sciencemesh" }
    })
    $passed = ($passed + (1 - $missing_miss))
    $failed = ($failed + $missing_miss)
    let missing_same = (mark ((open --raw $missing_path) == $missing_before) "missing storage does not rewrite the file")
    $passed = ($passed + (1 - $missing_same))
    $failed = ($failed + $missing_same)

    let absent_path = (stage-mode $master "dataprovider-sciencemesh")
    let absent_cfg = (open $absent_path)
    let absent_services = ($absent_cfg.grpc.services | reject storageprovider)
    save-cfg $absent_path ($absent_cfg | upsert grpc.services $absent_services)
    let absent_before = (open --raw $absent_path)
    let absent_miss = (check-expect "absent storage provider" $storage_msg "" {||
      with-runtime-env $mode_env {|| write-runtime-settings $absent_path "dataprovider-sciencemesh" }
    })
    $passed = ($passed + (1 - $absent_miss))
    $failed = ($failed + $absent_miss)
    let absent_same = (mark ((open --raw $absent_path) == $absent_before) "absent storage does not rewrite the file")
    $passed = ($passed + (1 - $absent_same))
    $failed = ($failed + $absent_same)

    let data_path = (stage-mode $master "dataprovider-sciencemesh")
    let data_cfg = (open $data_path)
    let data_items = ($data_cfg.http.services.dataprovider | each {|item| $item | upsert driver "localhome"})
    save-cfg $data_path ($data_cfg | upsert http.services.dataprovider $data_items)
    let data_before = (open --raw $data_path)
    let data_miss = (check-expect "missing received data" $data_msg "" {||
      with-runtime-env $mode_env {|| write-runtime-settings $data_path "dataprovider-sciencemesh" }
    })
    $passed = ($passed + (1 - $data_miss))
    $failed = ($failed + $data_miss)
    let data_same = (mark ((open --raw $data_path) == $data_before) "missing data does not rewrite the file")
    $passed = ($passed + (1 - $data_same))
    $failed = ($failed + $data_same)

    let dup_storage_path = (stage-mode $master "dataprovider-sciencemesh")
    let dup_storage_cfg = (open $dup_storage_path)
    let storage_items = $dup_storage_cfg.grpc.services.storageprovider
    let doubled_storage = ($storage_items | append ($storage_items | first))
    save-cfg $dup_storage_path ($dup_storage_cfg | upsert grpc.services.storageprovider $doubled_storage)
    let dup_storage_before = (open --raw $dup_storage_path)
    let dup_storage_miss = (check-expect "duplicate received storage" $storage_msg "" {||
      with-runtime-env $mode_env {|| write-runtime-settings $dup_storage_path "dataprovider-sciencemesh" }
    })
    $passed = ($passed + (1 - $dup_storage_miss))
    $failed = ($failed + $dup_storage_miss)
    let dup_storage_same = (mark ((open --raw $dup_storage_path) == $dup_storage_before) "duplicate storage does not rewrite the file")
    $passed = ($passed + (1 - $dup_storage_same))
    $failed = ($failed + $dup_storage_same)

    let dup_data_path = (stage-mode $master "dataprovider-sciencemesh")
    let dup_data_cfg = (open $dup_data_path)
    let http_items = $dup_data_cfg.http.services.dataprovider
    let doubled_data = ($http_items | append ($http_items | first))
    save-cfg $dup_data_path ($dup_data_cfg | upsert http.services.dataprovider $doubled_data)
    let dup_data_before = (open --raw $dup_data_path)
    let dup_data_miss = (check-expect "duplicate received data" $data_msg "" {||
      with-runtime-env $mode_env {|| write-runtime-settings $dup_data_path "dataprovider-sciencemesh" }
    })
    $passed = ($passed + (1 - $dup_data_miss))
    $failed = ($failed + $dup_data_miss)
    let dup_data_same = (mark ((open --raw $dup_data_path) == $dup_data_before) "duplicate data does not rewrite the file")
    $passed = ($passed + (1 - $dup_data_same))
    $failed = ($failed + $dup_data_same)

    {passed: $passed, failed: $failed}
  } catch {|err|
    print $"  [FAIL] cardinality unexpected: ($err.msg)"
    {passed: 0, failed: 1}
  })
  rm -rf $SCRATCH
  if $result.failed == 0 {
    print "  [PASS] ScienceMesh cardinality: PASSED"
  }
  $result
}

def test-existing-handwritten [] {
  print "Testing an existing runtime file with a prior registry..."
  rm -rf $SCRATCH
  let path = ($SCRATCH | path join "existing.toml")
  let result = (try {
    mut passed = 0
    mut failed = 0
    let seeded = '[shared]
jwt_secret = "kept-secret"
gatewaysvc = "gw:9142"

[shared.registry]
driver = "memory"
heartbeat_interval = "1s"
degraded_after = "2s"
offline_after = "3s"
reap_after = "4s"

# certfile disabled - HTTP mode
'
    write-text $path $seeded
    let rendered = (with-runtime-env (stock-nats $RECEIVER_NATS $STOCK_DOMAIN) {||
      write-runtime-settings $path "gateway"
      let once = (open --raw $path)
      write-runtime-settings $path "gateway"
      {cfg: (open $path), once: $once, twice: (open --raw $path)}
    })
    let ok = (
      ($rendered.cfg.shared.jwt_secret == "kept-secret")
      and ($rendered.cfg.shared.gatewaysvc == "gw:9142")
      and (stock-registry $rendered.cfg $RECEIVER_NATS)
      and ($rendered.once == $rendered.twice)
      and ((section-count $rendered.twice "[shared.registry]") == 1)
      and (not ($rendered.twice | str contains "certfile"))
      and (not ($rendered.twice | str contains "heartbeat_interval = \"1s\""))
    )
    let miss = (mark $ok "existing file keeps jwt, drops comments, one registry")
    $passed = ($passed + (1 - $miss))
    $failed = ($failed + $miss)
    {passed: $passed, failed: $failed}
  } catch {|err|
    print $"  [FAIL] existing file unexpected: ($err.msg)"
    {passed: 0, failed: 1}
  })
  rm -rf $SCRATCH
  if $result.failed == 0 {
    print "  [PASS] Existing runtime file: PASSED"
  }
  $result
}

def main [--verbose] {
  mut total_passed = 0
  mut total_failed = 0

  for step in [
    (test-all-modes)
    (test-stock-schema)
    (test-token-roundtrip)
    (test-durations)
    (test-fixed-failures)
    (test-network)
    (test-sciencemesh-cardinality)
    (test-existing-handwritten)
  ] {
    $total_passed = ($total_passed + $step.passed)
    $total_failed = ($total_failed + $step.failed)
  }

  if $verbose {
    print "runtime-config verbose summary recorded above"
  }

  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"

  if $total_failed == 0 {
    exit 0
  } else {
    exit 1
  }
}
