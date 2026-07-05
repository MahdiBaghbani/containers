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

export def assert-cache-bust-format [
  cache_bust: string,
  expected_length: int,
  expected_format: string = "hash"
] {
  let actual_length = ($cache_bust | str length)
  if $actual_length != $expected_length {
    error make { msg: $"Cache bust length mismatch: expected ($expected_length), got ($actual_length): ($cache_bust)" }
  }

  if $expected_format == "uuid" {
    if not ($cache_bust | str contains "-") {
      error make { msg: $"Cache bust format mismatch: expected UUID format with dashes, got: ($cache_bust)" }
    }
  } else if $expected_format == "hash" {
    if ($cache_bust | str contains "-") {
      error make { msg: $"Cache bust format mismatch: expected hash format \(no dashes\), got: ($cache_bust)" }
    }
  } else if $expected_format == "sha" {
    if ($cache_bust | str contains "-") {
      error make { msg: $"Cache bust format mismatch: expected SHA format \(no dashes\), got: ($cache_bust)" }
    }
  }
  true
}

export def assert-cache-bust-value [
  cache_bust: string,
  expected_value: string
] {
  if $cache_bust != $expected_value {
    error make { msg: $"Cache bust value mismatch: expected '($expected_value)', got '($cache_bust)'" }
  }
  true
}

export def assert-build-args-contain [
  build_args: record,
  expected_fields: list
] {
  for field in $expected_fields {
    if not ($field in ($build_args | columns)) {
      error make { msg: $"Build args missing required field: ($field)" }
    }
  }
  true
}

export def assert-build-order [
  build_order: list,
  expected_order: list
] {
  if ($build_order | length) != ($expected_order | length) {
    error make { msg: $"Build order length mismatch: expected ($expected_order | length), got ($build_order | length)" }
  }

  for $i in 0..<($expected_order | length) {
    let expected = ($expected_order | get $i)
    let actual = ($build_order | get $i)
    if $actual != $expected {
      error make { msg: $"Build order mismatch at index ($i): expected '($expected)', got '($actual)'" }
    }
  }
  true
}

export def assert-graph-structure [
  graph: record,
  expected_nodes: list,
  expected_edges: list
] {
  let actual_nodes = $graph.nodes
  if ($actual_nodes | length) != ($expected_nodes | length) {
    error make { msg: $"Graph nodes count mismatch: expected ($expected_nodes | length), got ($actual_nodes | length)" }
  }

  for expected_node in $expected_nodes {
    if not ($expected_node in $actual_nodes) {
      error make { msg: $"Graph missing expected node: ($expected_node)" }
    }
  }

  let actual_edges = $graph.edges
  if ($actual_edges | length) != ($expected_edges | length) {
    error make { msg: $"Graph edges count mismatch: expected ($expected_edges | length), got ($actual_edges | length)" }
  }

  for expected_edge in $expected_edges {
    let found = ($actual_edges | any {|edge| ($edge.from == $expected_edge.from) and ($edge.to == $expected_edge.to)})
    if not $found {
      error make { msg: $"Graph missing expected edge: from '($expected_edge.from)' to '($expected_edge.to)'" }
    }
  }
  true
}
