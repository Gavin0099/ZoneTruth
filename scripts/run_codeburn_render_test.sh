#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RENDER_MD="codeburn/CODEBURN_RENDER_TEST.md"
RENDER_HTML="codeburn/html/CODEBURN_RENDER_TEST.html"

if ! test -f "$RENDER_MD"; then
  echo "codeburn_render_test: missing_markdown_fixture"
  exit 1
fi

python3 codeburn/tools/render_docs.py "$RENDER_MD"

if ! test -f "$RENDER_HTML"; then
  echo "codeburn_render_test: missing_render_output"
  exit 1
fi

if ! grep -q '<span class="class-c">Class C</span>' "$RENDER_HTML"; then
  echo "codeburn_render_test: missing_class_c_badge"
  exit 1
fi

if ! grep -q '<span class="class-d">Class D</span>' "$RENDER_HTML"; then
  echo "codeburn_render_test: missing_class_d_badge"
  exit 1
fi

if ! grep -q 'class="box-warn"' "$RENDER_HTML"; then
  echo "codeburn_render_test: missing_warning_box"
  exit 1
fi

if ! grep -q 'class="box-frozen"' "$RENDER_HTML"; then
  echo "codeburn_render_test: missing_frozen_box"
  exit 1
fi

if ! grep -q 'class="box-advisory"' "$RENDER_HTML"; then
  echo "codeburn_render_test: missing_advisory_box"
  exit 1
fi

if ! grep -q '<table>' "$RENDER_HTML"; then
  echo "codeburn_render_test: missing_table_render"
  exit 1
fi

if ! grep -q '<pre><code' "$RENDER_HTML"; then
  echo "codeburn_render_test: missing_code_block_render"
  exit 1
fi

if ! grep -q 'href="#11-navigation-anchor-test"' "$RENDER_HTML"; then
  echo "codeburn_render_test: missing_nav_anchor_h2"
  exit 1
fi

if ! grep -q 'href="#11a-sub-section-anchor"' "$RENDER_HTML"; then
  echo "codeburn_render_test: missing_nav_anchor_h3"
  exit 1
fi

echo "codeburn_render_test: passed"
