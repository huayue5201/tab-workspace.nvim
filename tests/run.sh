#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
for f in tests/*.lua; do
  printf '\n== %s\n' "$f"
  nvim --headless -u NONE -l "$f" || fail=1
done
exit $fail
