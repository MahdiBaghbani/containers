#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# Regression fixture: ide-check may exit 0 while emitting Error diagnostics.

def main [] {
  print $"  [FAIL] Example: FAILED (" + "x" + " errors)"
}
