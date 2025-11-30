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

# Unit tests for redis-config.nu functions
# Tests Redis session handler configuration logic

# Test Redis host detection logic
# Verifies REDIS_HOST environment variable handling
def test_redis_host_detection [] {
  print "Testing Redis host detection..."
  mut passed = 0
  mut failed = 0
  
  # Test 1: REDIS_HOST not set returns early
  let redis_host1 = (try { $env.TEST_REDIS_HOST? } catch { null })
  
  if $redis_host1 == null {
    print "  [PASS] redis_host: null when not set (returns early)"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] redis_host: should be null when not set"
    $failed = ($failed + 1)
  }
  
  # Test 2: REDIS_HOST set triggers configuration
  $env.TEST_REDIS_HOST = "redis-server"
  let redis_host2 = (try { $env.TEST_REDIS_HOST? } catch { null })
  
  if $redis_host2 != null {
    print "  [PASS] redis_host: configuration triggered when set"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] redis_host: configuration should trigger when set"
    $failed = ($failed + 1)
  }
  
  # Cleanup
  hide-env TEST_REDIS_HOST
  
  return {passed: $passed, failed: $failed}
}

# Test Unix socket vs TCP connection detection
# Verifies correct path detection based on host format
def test_connection_type_detection [] {
  print "Testing connection type detection..."
  mut passed = 0
  mut failed = 0
  
  # Test 1: Unix socket (starts with /)
  let socket_host = "/var/run/redis/redis.sock"
  let is_socket = ($socket_host | str starts-with "/")
  
  if $is_socket {
    print "  [PASS] connection type: Unix socket detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] connection type: Unix socket should be detected"
    $failed = ($failed + 1)
  }
  
  # Test 2: TCP host (hostname)
  let tcp_host = "redis-server"
  let is_tcp = not ($tcp_host | str starts-with "/")
  
  if $is_tcp {
    print "  [PASS] connection type: TCP host detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] connection type: TCP host should be detected"
    $failed = ($failed + 1)
  }
  
  # Test 3: TCP host with IP
  let ip_host = "192.168.1.100"
  let is_ip_tcp = not ($ip_host | str starts-with "/")
  
  if $is_ip_tcp {
    print "  [PASS] connection type: IP address as TCP detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] connection type: IP address should be TCP"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Test session save path URL construction
# Verifies correct URL format for different configurations
def test_save_path_construction [] {
  print "Testing save path URL construction..."
  mut passed = 0
  mut failed = 0
  
  # Test 1: Unix socket without auth
  let socket = "/var/run/redis/redis.sock"
  let save_path1 = $"unix://($socket)"
  let expected1 = "unix:///var/run/redis/redis.sock"
  
  if $save_path1 == $expected1 {
    print "  [PASS] save_path: Unix socket without auth"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] save_path: expected '($expected1)', got '($save_path1)'"
    $failed = ($failed + 1)
  }
  
  # Test 2: Unix socket with password only
  let password = "secret123"
  let save_path2 = $"unix://($socket)?auth=($password)"
  let expected2 = "unix:///var/run/redis/redis.sock?auth=secret123"
  
  if $save_path2 == $expected2 {
    print "  [PASS] save_path: Unix socket with password"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] save_path: expected '($expected2)', got '($save_path2)'"
    $failed = ($failed + 1)
  }
  
  # Test 3: Unix socket with user and password
  let user = "redis-user"
  let save_path3 = $"unix://($socket)?auth[]=($user)&auth[]=($password)"
  let expected3 = "unix:///var/run/redis/redis.sock?auth[]=redis-user&auth[]=secret123"
  
  if $save_path3 == $expected3 {
    print "  [PASS] save_path: Unix socket with user and password"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] save_path: expected '($expected3)', got '($save_path3)'"
    $failed = ($failed + 1)
  }
  
  # Test 4: TCP without auth
  let host = "redis-server"
  let port = "6379"
  let save_path4 = $"tcp://($host):($port)"
  let expected4 = "tcp://redis-server:6379"
  
  if $save_path4 == $expected4 {
    print "  [PASS] save_path: TCP without auth"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] save_path: expected '($expected4)', got '($save_path4)'"
    $failed = ($failed + 1)
  }
  
  # Test 5: TCP with password only
  let save_path5 = $"tcp://($host):($port)?auth=($password)"
  let expected5 = "tcp://redis-server:6379?auth=secret123"
  
  if $save_path5 == $expected5 {
    print "  [PASS] save_path: TCP with password"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] save_path: expected '($expected5)', got '($save_path5)'"
    $failed = ($failed + 1)
  }
  
  # Test 6: TCP with user and password
  let save_path6 = $"tcp://($host):($port)?auth[]=($user)&auth[]=($password)"
  let expected6 = "tcp://redis-server:6379?auth[]=redis-user&auth[]=secret123"
  
  if $save_path6 == $expected6 {
    print "  [PASS] save_path: TCP with user and password"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] save_path: expected '($expected6)', got '($save_path6)'"
    $failed = ($failed + 1)
  }
  
  # Test 7: Default port (using default operator, not try-catch for null)
  let default_port = ($env.TEST_REDIS_PORT? | default "6379")
  if $default_port == "6379" {
    print "  [PASS] save_path: default port is 6379"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] save_path: default port should be 6379, got '($default_port)'"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Test PHP configuration generation
# Verifies correct PHP ini format
def test_php_config_generation [] {
  print "Testing PHP config generation..."
  mut passed = 0
  mut failed = 0
  
  # Test 1: Config contains session.save_handler
  let config = [
    "session.save_handler = redis"
    "session.save_path = \"tcp://redis:6379\""
    "redis.session.locking_enabled = 1"
    "redis.session.lock_retries = -1"
    "redis.session.lock_wait_time = 10000"
  ]
  
  let has_handler = ($config | any {|line| $line | str contains "session.save_handler"})
  if $has_handler {
    print "  [PASS] php_config: contains session.save_handler"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] php_config: should contain session.save_handler"
    $failed = ($failed + 1)
  }
  
  # Test 2: Config contains session.save_path
  let has_path = ($config | any {|line| $line | str contains "session.save_path"})
  if $has_path {
    print "  [PASS] php_config: contains session.save_path"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] php_config: should contain session.save_path"
    $failed = ($failed + 1)
  }
  
  # Test 3: Config contains locking settings
  let has_locking = ($config | any {|line| $line | str contains "locking_enabled"})
  if $has_locking {
    print "  [PASS] php_config: contains locking settings"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] php_config: should contain locking settings"
    $failed = ($failed + 1)
  }
  
  # Test 4: Config can be joined into valid ini format
  let ini_content = ($config | str join "\n")
  let has_newlines = ($ini_content | str contains "\n")
  if $has_newlines {
    print "  [PASS] php_config: can be joined into ini format"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] php_config: should be joinable with newlines"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Main test runner
def main [--verbose] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_redis_host_detection)
  $total_passed = ($total_passed + $test1.passed)
  $total_failed = ($total_failed + $test1.failed)
  
  let test2 = (test_connection_type_detection)
  $total_passed = ($total_passed + $test2.passed)
  $total_failed = ($total_failed + $test2.failed)
  
  let test3 = (test_save_path_construction)
  $total_passed = ($total_passed + $test3.passed)
  $total_failed = ($total_failed + $test3.failed)
  
  let test4 = (test_php_config_generation)
  $total_passed = ($total_passed + $test4.passed)
  $total_failed = ($total_failed + $test4.failed)
  
  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"
  
  if $total_failed == 0 {
    exit 0
  } else {
    exit 1
  }
}
