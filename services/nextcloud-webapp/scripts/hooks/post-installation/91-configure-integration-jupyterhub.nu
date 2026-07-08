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

# Configure integration_jupyterhub from environment variables.
# Runs after the app is enabled (hook order: 90 -> 91).

use /usr/bin/lib/utils.nu [run_as, get_env_or_default]

const OAUTH_ENV_FILE = "/var/www/html/data/integration_jupyterhub_oauth.env"
const OAUTH_CLIENT_NAME = "jupyterhub"

def sh_quote [s: string] {
  $"'($s | str replace "'" "''")'"
}

def occ_user [] {
  let uid = (^id -u | into int)
  if $uid == 0 {
    ($env.APACHE_RUN_USER? | default "www-data") | str replace --regex "^#" ""
  } else {
    ($uid | into string)
  }
}

def run_occ [user: string, args: string] {
  run_as $user $"php /var/www/html/occ ($args)" | complete
}

def warn_occ_failure [label: string, result: record] {
  print $"Warning: ($label) failed with exit code ($result.exit_code)"
  if ($result.stdout | str length) > 0 {
    print $result.stdout
  }
  if ($result.stderr | str length) > 0 {
    print $result.stderr
  }
}

def parse_ttl [] {
  let raw = (get_env_or_default "INTEGRATION_JUPYTERHUB_OCM_ACCESS_TOKEN_TTL" "3600" | str trim)
  let parsed = (try { $raw | into int } catch { null })
  if $parsed == null or $parsed <= 0 {
    print $"Warning: invalid INTEGRATION_JUPYTERHUB_OCM_ACCESS_TOKEN_TTL '($raw)', using 3600"
    3600
  } else {
    $parsed
  }
}

def hub_base_url [jupyter_host: string] {
  if ($jupyter_host | str starts-with "http://") or ($jupyter_host | str starts-with "https://") {
    $jupyter_host | str trim | str trim --right '/'
  } else {
    $"https://($jupyter_host)" | str trim | str trim --right '/'
  }
}

def oauth_credentials_exist [] {
  if not ($OAUTH_ENV_FILE | path exists) {
    return false
  }
  let content = (open --raw $OAUTH_ENV_FILE)
  ($content | str contains "INTEGRATION_JUPYTERHUB_OAUTH_CLIENT_ID=")
    and ($content | str contains "INTEGRATION_JUPYTERHUB_OAUTH_CLIENT_SECRET=")
}

def write_oauth_credentials [client_id: string, client_secret: string] {
  let content = [
    $"INTEGRATION_JUPYTERHUB_OAUTH_CLIENT_ID=($client_id)"
    $"INTEGRATION_JUPYTERHUB_OAUTH_CLIENT_SECRET=($client_secret)"
  ] | str join (char nl)

  $content | save -f $OAUTH_ENV_FILE
  ^chown "www-data:root" $OAUTH_ENV_FILE | ignore
  ^chmod "0644" $OAUTH_ENV_FILE | ignore
  print $"Wrote OAuth credentials to ($OAUTH_ENV_FILE)"
}

def provision_oauth_client [user: string, callback_url: string] {
  if (oauth_credentials_exist) {
    print "OAuth credentials already present, skipping client creation"
    return
  }

  let cmd = $"oauth2:add-client (sh_quote $OAUTH_CLIENT_NAME) (sh_quote $callback_url) --output=json"
  let result = (run_occ $user $cmd)

  if $result.exit_code != 0 {
    warn_occ_failure "oauth2:add-client" $result
    return
  }

  let client = (try {
    $result.stdout | from json
  } catch {|e|
    print $"Warning: failed to parse oauth2:add-client JSON: ($e.msg)"
    return
  })

  if ($client.clientId? | default "") == "" or ($client.clientSecret? | default "") == "" {
    print "Warning: oauth2:add-client JSON missing clientId or clientSecret"
    return
  }

  write_oauth_credentials $client.clientId $client.clientSecret
}

def main [] {
  let app_dir = "/var/www/html/apps/integration_jupyterhub"
  if not ($app_dir | path exists) {
    print "Warning: integration_jupyterhub app directory not found, skipping configuration"
    return
  }

  let user = (occ_user)
  let ttl = (parse_ttl)

  let ttl_result = (run_occ $user $"config:app:set integration_jupyterhub ocm_access_token_ttl --value=($ttl)")
  if $ttl_result.exit_code == 0 {
    print $"Set ocm_access_token_ttl = ($ttl)"
  } else {
    warn_occ_failure "config:app:set ocm_access_token_ttl" $ttl_result
  }

  let sharing_result = (run_occ $user "integration_jupyterhub:set-webapp-sharing enable")
  if $sharing_result.exit_code == 0 {
    print "Enabled webapp sharing"
  } else {
    warn_occ_failure "integration_jupyterhub:set-webapp-sharing" $sharing_result
  }

  let targets_result = (run_occ $user "integration_jupyterhub:set-webapp-targets blank")
  if $targets_result.exit_code == 0 {
    print "Set webapp targets to blank"
  } else {
    warn_occ_failure "integration_jupyterhub:set-webapp-targets" $targets_result
  }

  let jupyter_host = (get_env_or_default "JUPYTER_HOST" "" | str trim)
  if ($jupyter_host | str length) == 0 {
    print "Warning: JUPYTER_HOST is not set, skipping hub URL and OAuth provisioning"
    return
  }

  let hub_url = (hub_base_url $jupyter_host)
  let url_result = (run_occ $user $"integration_jupyterhub:set-url (sh_quote $hub_url)")
  if $url_result.exit_code != 0 {
    warn_occ_failure "integration_jupyterhub:set-url" $url_result
    return
  }

  print $"Set hub URL to ($hub_url)"

  let callback_url = $"($hub_url)/hub/oauth_callback"
  provision_oauth_client $user $callback_url
}
