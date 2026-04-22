#!/bin/bash
set -euo pipefail

# Trust Desktop .desktop launchers once per user profile.
# This avoids depending on gvfs metadata timing and avoids trusting newly added
# .desktop files on every session.
sentinel="$HOME/.local/share/ocm/.desktop-icons-trusted"

if [ -f "$sentinel" ]; then
  exit 0
fi

mkdir -p "$(dirname "$sentinel")"

shopt -s nullglob
for f in "$HOME/Desktop/"*.desktop; do
  gio set -t string "$f" metadata::xfce-exe-checksum "$(sha256sum "$f" | awk '{print $1}')" || true
done

touch "$sentinel"
