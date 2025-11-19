# Revad Base Init Script Test Suite

Test suite for `init.nu` variable derivation logic.

## Running Tests

From the project root:

```bash
nu services/revad-base/tests/run-tests.nu
```

Or from the tests directory:

```bash
cd services/revad-base/tests
nu run-tests.nu
```

## Test Coverage

### Test 1: Minimal Environment (DOMAIN only)

Tests that all variables can be derived correctly with only `DOMAIN` set. Verifies:

- Default values for TLS, protocol, and port settings
- WEB_DOMAIN derivation from DOMAIN (removing "reva" from hostname)
- External endpoint construction
- Data prefix defaults

### Test 2: Empty DOMAIN Fallback

Tests that the script correctly falls back to `localhost` when `DOMAIN` is empty or not set.

### Test 3: Reserved Prefix Validation

Tests that reserved path prefixes (like "api", "graph", etc.) are correctly rejected for data provider prefixes.

### Test 4: Full Environment Variables

Tests that explicitly set environment variables override defaults correctly.

### Test 5: Fallback Scenario

Tests that when `REVAD_EXTERNAL_HOST` and `REVAD_EXTERNAL_PROTOCOL` are not set, the script correctly falls back to `REVAD_PROTOCOL` and `DOMAIN`.

## Test Structure

- `test-variable-derivation.nu` - Individual test functions for variable derivation logic
- `run-tests.nu` - Test runner that executes all tests

## Notes

These tests validate the variable derivation logic in isolation without requiring:

- Actual directory structures (`/revad`, `/configs`, etc.)
- Docker containers
- Reva binaries
- Configuration files

The tests focus on ensuring the environment variable parsing and default value logic works correctly.
