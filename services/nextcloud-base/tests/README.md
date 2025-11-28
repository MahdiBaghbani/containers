# Nextcloud Base Scripts Test Suite

Unit tests for `nextcloud-base` service scripts. Tests validate script logic in isolation using controlled test environments with fixtures.

## Running Tests

From project root:

```bash
# Run all tests
nu services/nextcloud-base/tests/test-runner.nu

# Run specific suite
nu services/nextcloud-base/tests/test-runner.nu --suite utils

# Run with verbose output
nu services/nextcloud-base/tests/test-runner.nu --verbose
```

From tests directory:

```bash
cd services/nextcloud-base/tests

# Run all tests
nu test-runner.nu

# Run specific suite
nu test-runner.nu --suite redis-config
```

## Test Suites

| Suite           | Module                | Tests | Coverage                                      |
| --------------- | --------------------- | ----- | --------------------------------------------- |
| utils           | utils.nu              | 16    | detect_user_group, directory_empty, file_env, get_env_or_default |
| nextcloud-init  | nextcloud-init.nu     | 10    | version_greater, version comparison logic     |
| entrypoint      | entrypoint-init.nu    | 14    | Command parsing, init skip logic, version decisions, major version validation |
| source-prep     | source-prep.nu        | 10    | Source mount detection, rsync options, directory preparation |
| apache-config   | apache-config.nu      | 8     | Apache command detection, APACHE_DISABLE_REWRITE_IP handling |
| redis-config    | redis-config.nu       | 16    | Redis host detection, connection types, save path construction, PHP config |
| hooks           | hooks.nu              | 12    | Hook folder detection, script discovery, executable checks, hook naming |
| post-install    | post-install.nu       | 13    | OCC command construction, config modification, log setup |

Total: **99 tests**

## Test Structure

Each test file follows this pattern:

```nu
#!/usr/bin/env nu
# SPDX-License-Identifier: AGPL-3.0-or-later
# ... copyright header ...

use ../scripts/lib/{module}.nu [function1, function2]

def test_function_name [] {
  print "Testing function_name..."
  mut passed = 0
  mut failed = 0
  
  # Test cases
  if $condition {
    print "  [PASS] description"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] description"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

def main [--verbose] {
  mut total_passed = 0
  mut total_failed = 0
  
  let test1 = (test_function_name)
  $total_passed = ($total_passed + $test1.passed)
  $total_failed = ($total_failed + $test1.failed)
  
  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"
  
  if $total_failed == 0 { exit 0 } else { exit 1 }
}
```

## Test Patterns

### Return Values

Tests can return either:

- Boolean (`true`/`false`) for simple single-test functions
- Record (`{passed: X, failed: Y}`) for multi-test functions

### Temporary Files

Tests use `/tmp/nextcloud-test-{uuid}` for temporary directories:

```nu
let test_base = $"/tmp/nextcloud-test-(random uuid)"
mkdir $test_base
# ... run tests ...
rm -rf $test_base  # cleanup
```

### Environment Variables

Tests set and clean up environment variables:

```nu
$env.TEST_VAR = "value"
# ... run test ...
hide-env TEST_VAR  # cleanup
```

### Testing Non-Exported Functions

For non-exported functions (like `check_config_differences` in entrypoint-init.nu):

1. Copy the function locally in the test file
2. Test the logic in isolation
3. Or test indirectly via exported functions that call them

## Fixtures

Located in `fixtures/`:

| File                | Purpose                                      |
| ------------------- | -------------------------------------------- |
| version.php         | Sample Nextcloud version (30.0.11.0)         |
| version-old.php     | Older version for comparison (29.0.0.0)      |
| version-invalid.php | Invalid version file for error case testing  |

## Testing Philosophy

1. **Logic testing only**: Tests validate conditional branches and data transformations, not actual external command execution (rsync, php, su, chown)

2. **Controlled environment**: All file operations use `/tmp` with proper cleanup

3. **No Docker required**: Tests run without Docker containers or Nextcloud installations

4. **Isolation**: Each test cleans up after itself to prevent pollution

## Adding New Tests

1. Create `test-{module}.nu` following the structure pattern above
2. Add module name to `test_suites` list in `test-runner.nu`
3. Run full suite to verify integration

## Requirements

- Nushell 0.80 or later
- No external dependencies required for test execution
