# Revad Base Scripts Test Suite

Test suite for `revad-base` initialization scripts and utility functions.

## Running Tests

From the project root:

```bash
nu services/revad-base/tests/test-runner.nu
```

Or run a specific test suite:

```bash
nu services/revad-base/tests/test-runner.nu --suite gateway
```

Or from the tests directory:

```bash
cd services/revad-base/tests
nu test-runner.nu
```

## Test Structure

All test files follow a consistent structure:

- Each test file has a `def main [--verbose]` function
- Test functions return `{passed: X, failed: Y}` format
- Tests output summary line: `Tests: X passed, Y failed`
- Exit code 0 for success, 1 for failure

## Test Files

### Core Tests

- `test-entrypoint.nu` - Tests `entrypoint-init.nu` functions (mode validation, type extraction)
- `test-gateway.nu` - Tests `init-gateway.nu` (config copy, placeholder processing, TLS)
- `test-dataprovider.nu` - Tests `init-dataprovider.nu` (type validation, config copy, placeholder processing)
- `test-authprovider.nu` - Tests `init-authprovider.nu` (type validation, config copy, placeholder processing)
- `test-shareproviders.nu` - Tests `init-shareproviders.nu` (config copy, placeholder processing, TLS)
- `test-groupuserproviders.nu` - Tests `init-groupuserproviders.nu` (config copy, placeholder processing, TLS)

### Utility Tests

- `test-shared.nu` - Tests `shared.nu` functions (DNS, hosts, directories, JSON copy, TLS)
- `test-utils.nu` - Tests `utils.nu` functions (file replacement, placeholder validation, env vars, placeholder processing)
- `test-merge-partials.nu` - Tests `merge-partials.nu` functions (partial config parsing, merging, ordering, marker system)

## Test Coverage

### Entrypoint Tests

- Mode validation (valid/invalid modes)
- Dataprovider type extraction
- Authprovider type extraction

### Gateway Tests

- Config file copying
- Placeholder processing (all gateway placeholders)
- TLS certificate disabling

### Dataprovider Tests

- Type validation (localhome, ocm, sciencemesh)
- Config file copying for each type
- Placeholder processing (nested placeholders)
- Data server URL construction

### Authprovider Tests

- Type validation (oidc, machine, ocmshares, publicshares)
- Config file copying for each type
- Placeholder processing (type-specific placeholders)
- Gateway address construction
- TLS certificate disabling

### Share Providers Tests

- Config file copying
- Placeholder processing
- Gateway address construction
- External endpoint construction
- TLS certificate disabling

### User/Group Providers Tests

- Config file copying
- Placeholder processing
- Gateway address construction
- TLS certificate disabling

### Shared Functions Tests

- NSSwitch configuration
- Hosts file management
- Log file creation
- Directory creation
- JSON file copying
- Config file disabling

### Utility Functions Tests

- File string replacement
- Placeholder validation
- Environment variable retrieval
- Placeholder processing

### Partial Config Merge Tests

- Partial file parsing (valid and invalid formats)
- Target file filtering (finding partials for specific config files)
- Ordering algorithm (explicit order numbers, alphabetical fallback, auto-assignment)
- Marker removal (preventing duplicate appends on container restart)
- Runtime merge with markers (for restart prevention)
- Build-time merge without markers (baked into image)
- Directory scanning (multiple partial directories with priority)

## Test Runner

The `test-runner.nu` script:

- Runs all test suites or a specific suite
- Parses test output for summary lines
- Aggregates passed/failed counts
- Provides overall test summary
- Handles missing test files gracefully
- Supports verbose output mode

Available test suites: `utils`, `shared`, `gateway`, `dataprovider`, `authprovider`, `shareproviders`, `groupuserproviders`, `entrypoint`, `merge-partials`

## Notes

These tests validate script logic in isolation without requiring:

- Actual directory structures (`/revad`, `/configs`, etc.)
- Docker containers
- Reva binaries
- Configuration files

The tests focus on ensuring:

- Environment variable parsing works correctly
- Placeholder processing functions correctly
- Config file operations work as expected
- Type validation and extraction logic is correct

## Test Output Format

All tests output a summary line in this format:

```text
Tests: X passed, Y failed
```

The test runner parses this line to aggregate results across all test suites.
