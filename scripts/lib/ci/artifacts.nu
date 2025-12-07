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

# GitHub Actions artifacts helper for downloading dependency shards
# Used by prepare-node-deps to load dependency images from earlier jobs in the same run

use ./cache-shards.nu [make-shard-name]

# Detect GitHub Actions CI context from environment variables
# Returns {ok: true, owner, repo, run_id, token, api_url} or {ok: false, reason: "..."}
export def get-github-run-context [] {
  let is_github = (try { $env.GITHUB_ACTIONS } catch { "" })
  if $is_github != "true" {
    return {ok: false, reason: "Not running in GitHub Actions"}
  }

  let repo = (try { $env.GITHUB_REPOSITORY } catch { "" })
  let run_id = (try { $env.GITHUB_RUN_ID } catch { "" })
  let token = (try { $env.GITHUB_TOKEN } catch { "" })
  let api_url = (try { $env.GITHUB_API_URL } catch { "https://api.github.com" })

  if ($repo | str length) == 0 {
    return {ok: false, reason: "GITHUB_REPOSITORY not set"}
  }
  if ($run_id | str length) == 0 {
    return {ok: false, reason: "GITHUB_RUN_ID not set"}
  }
  if ($token | str length) == 0 {
    return {ok: false, reason: "GITHUB_TOKEN not set"}
  }

  let parts = ($repo | split row "/")
  if ($parts | length) != 2 {
    return {ok: false, reason: $"GITHUB_REPOSITORY has unexpected format: ($repo)"}
  }

  {
    ok: true,
    owner: ($parts | get 0),
    repo: ($parts | get 1),
    run_id: $run_id,
    token: $token,
    api_url: $api_url
  }
}

# List artifacts for the current workflow run via GitHub REST API
# Returns list of {id, name, archive_download_url} or empty list on failure
export def list-run-artifacts-github [ctx: record] {
  if not $ctx.ok {
    return []
  }

  let url = $"($ctx.api_url)/repos/($ctx.owner)/($ctx.repo)/actions/runs/($ctx.run_id)/artifacts"
  
  mut all_artifacts = []
  mut page = 1
  let per_page = 100

  # Paginate through all artifacts
  loop {
    let page_url = $"($url)?per_page=($per_page)&page=($page)"
    
    let result = (try {
      let response = (^curl -sS -H $"Authorization: Bearer ($ctx.token)" -H "Accept: application/vnd.github+json" $page_url | complete)
      if $response.exit_code != 0 {
        {ok: false, error: "curl failed", body: null}
      } else {
        let body = (try { $response.stdout | from json } catch { null })
        if $body == null {
          {ok: false, error: "Invalid JSON response", body: null}
        } else {
          {ok: true, error: "", body: $body}
        }
      }
    } catch {|err|
      {ok: false, error: (try { $err.msg } catch { "HTTP request failed" }), body: null}
    })

    if not $result.ok {
      print --stderr $"WARNING: Failed to list artifacts: ($result.error)"
      break
    }

    let artifacts = (try { $result.body.artifacts } catch { [] })
    if ($artifacts | is-empty) {
      break
    }

    # Extract relevant fields
    let page_items = ($artifacts | each {|a|
      {
        id: (try { $a.id } catch { 0 }),
        name: (try { $a.name } catch { "" }),
        archive_download_url: (try { $a.archive_download_url } catch { "" })
      }
    })

    $all_artifacts = ($all_artifacts | append $page_items)

    # Check if there are more pages
    let total_count = (try { $result.body.total_count } catch { 0 })
    if ($all_artifacts | length) >= $total_count {
      break
    }

    $page = $page + 1
  }

  $all_artifacts
}

# Download and load a specific shard artifact by name
# Returns {ok: true, loaded: <count>} or {ok: false, reason: "..."}
export def download-and-load-shard [
  ctx: record,
  artifact_list: list,
  service: string,
  version: string,
  platform: string = ""
] {
  let shard_name = (make-shard-name $service $version $platform)
  
  # Find matching artifact
  let matching = ($artifact_list | where {|a| $a.name == $shard_name})
  if ($matching | is-empty) {
    return {ok: false, reason: $"Shard artifact not found: ($shard_name)"}
  }

  let artifact = ($matching | first)
  let download_url = $artifact.archive_download_url

  if ($download_url | str length) == 0 {
    return {ok: false, reason: $"No download URL for artifact: ($shard_name)"}
  }

  # Create temp directory for download
  let temp_dir = $"/tmp/shard-download-($shard_name)-($artifact.id)"
  let zip_path = $"($temp_dir)/artifact.zip"

  if ($temp_dir | path exists) {
    rm -rf $temp_dir
  }
  mkdir $temp_dir

  # Download the artifact ZIP
  let dl_result = (try {
    let response = (^curl -sS -L -H $"Authorization: Bearer ($ctx.token)" -H "Accept: application/vnd.github+json" -o $zip_path $download_url | complete)
    if $response.exit_code != 0 {
      {ok: false, error: "Download failed"}
    } else if not ($zip_path | path exists) {
      {ok: false, error: "Downloaded file not found"}
    } else {
      {ok: true, error: ""}
    }
  } catch {|err|
    {ok: false, error: (try { $err.msg } catch { "Download failed" })}
  })

  if not $dl_result.ok {
    rm -rf $temp_dir
    return {ok: false, reason: $"Failed to download ($shard_name): ($dl_result.error)"}
  }

  # Extract the ZIP
  let extract_dir = $"($temp_dir)/extracted"
  mkdir $extract_dir

  let unzip_result = (try {
    let response = (^unzip -q $zip_path -d $extract_dir | complete)
    if $response.exit_code != 0 {
      {ok: false, error: "Unzip failed"}
    } else {
      {ok: true, error: ""}
    }
  } catch {|err|
    {ok: false, error: (try { $err.msg } catch { "Unzip failed" })}
  })

  if not $unzip_result.ok {
    rm -rf $temp_dir
    return {ok: false, reason: $"Failed to extract ($shard_name): ($unzip_result.error)"}
  }

  # Find and load all .tar.zst files
  let tarballs = (try {
    glob $"($extract_dir)/**/*.tar.zst"
  } catch {
    []
  })

  if ($tarballs | is-empty) {
    rm -rf $temp_dir
    return {ok: false, reason: $"No .tar.zst files in artifact ($shard_name)"}
  }

  mut loaded = 0
  for tarball in $tarballs {
    let load_result = (try {
      let response = (^zstd -d -c $tarball | ^docker load | complete)
      if $response.exit_code == 0 {
        {ok: true}
      } else {
        {ok: false}
      }
    } catch {
      {ok: false}
    })

    if $load_result.ok {
      $loaded = $loaded + 1
    } else {
      print --stderr $"WARNING: Failed to docker load: ($tarball | path basename)"
    }
  }

  # Cleanup
  rm -rf $temp_dir

  if $loaded == 0 {
    {ok: false, reason: $"Failed to load any images from ($shard_name)"}
  } else {
    {ok: true, loaded: $loaded}
  }
}
