#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# Regression fixture: missing module must fail tracked parse checks.

use ./hook-parse-regression-missing-module.nu [never-imported]

def main [] {
  never-imported
}
