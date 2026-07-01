#!/usr/bin/env bash
set -euo pipefail

# Verifies term-shot (hosts/wsl-desktop/agent-bridge/bin/term-shot): captured terminal text
# on stdin renders to a valid PNG — the 👀 peek relies on this so a wide TUI
# screen lands as a mobile-legible image instead of a scrolling code block.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHOT="$ROOT/hosts/wsl-desktop/agent-bridge/bin/term-shot"

fail() { echo "term-shot smoke test failed: $*" >&2; exit 1; }

if ! python3 -c 'import PIL' 2>/dev/null; then
  echo "term-shot smoke tests skipped (Pillow not installed)"
  exit 0
fi

base="$(mktemp -d)"; trap 'rm -rf "$base"' EXIT
out="$base/shot.png"

# A wide, box-drawing, multi-line capture — the real peek payload shape.
{ printf '╭─────────╮\n'; printf '│ working │\n'; printf '╰─────────╯\n'; printf '❯ %s\n' "$(printf 'x%.0s' {1..180})"; } \
  | "$SHOT" "$out" || fail "render exited non-zero"
[[ -s "$out" ]] || fail "no PNG written"
head -c8 "$out" | grep -q $'\x89PNG' || fail "output is not a PNG"

# Blank input still yields a valid image, not a crash.
printf '\n\n\n' | "$SHOT" "$base/blank.png" || fail "blank render failed"
[[ -s "$base/blank.png" ]] || fail "blank PNG missing"

# Bad usage is a clear non-zero exit.
if printf 'x' | "$SHOT" 2>/dev/null; then fail "missing output path should error"; fi

echo "term-shot smoke tests passed"
