#!/usr/bin/env bash
# Rebuilds FILE_MAP.md from the `link` calls in bootstrap.sh.
# Run by pushdot so the file map can never drift from bootstrap.sh.
# Must run from the repo root.
set -euo pipefail

mkdir -p docs
{
  echo "# File map"
  echo
  echo "This file is generated from \`bootstrap.sh\` by \`tools/gen-file-map.sh\`."
  echo "Do not edit it by hand. Run the script again after you change \`bootstrap.sh\`."
  echo
  echo "| Repository file | Linked to |"
  echo "| --- | --- |"
  grep '^link "' bootstrap.sh | sed -E 's/^link "([^"]+)"[[:space:]]+"([^"]+)".*/| `\1` | `\2` |/'
} > docs/FILE_MAP.md

echo "Wrote FILE_MAP.md"
