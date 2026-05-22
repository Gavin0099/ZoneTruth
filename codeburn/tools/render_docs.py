#!/usr/bin/env python3
"""
CodeBurn Documentation Renderer — .md → .html

Converts codeburn/*.md governance documents to styled, readable HTML.
Source .md files remain authoritative; HTML is the presentation layer.

Usage:
  python codeburn/tools/render_docs.py              # render all codeburn/*.md
  python codeburn/tools/render_docs.py FILE.md      # render one file
  python codeburn/tools/render_docs.py --list       # list what would be rendered

Output: codeburn/html/<FILENAME>.html

Design constraints:
  - Zero external dependencies (stdlib only)
  - Markdown parsing: regex-based, covers common patterns
  - Styles: inline CSS (self-contained HTML, no external files)
  - Epistemic class labels: color-coded (Class C = amber, Class D = orange-red)
  - Forbidden patterns (FCP-*): red warning boxes
  - Frozen invariants: blue info boxes
  - Tables: styled with borders
"""
from __future__ import annotations

import re
import sys
import html as html_lib
from pathlib import Path
from datetime import datetime

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

CODEBURN_DIR = Path(__file__).parent.parent
HTML_OUT_DIR = CODEBURN_DIR / "html"

# Which .md files to render (in codeburn/ root only, not subdirs)
MD_GLOB = "CODEBURN_*.md"

# ---------------------------------------------------------------------------
# CSS
# ---------------------------------------------------------------------------

CSS = """
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  font-size: 15px;
  line-height: 1.7;
  color: #1a1a2e;
  background: #f8f9fa;
  max-width: 900px;
  margin: 0 auto;
  padding: 2rem 1.5rem 4rem;
}
h1 { font-size: 1.9rem; color: #0d1b2a; border-bottom: 3px solid #0066cc; padding-bottom: .5rem; margin: 2rem 0 1rem; }
h2 { font-size: 1.4rem; color: #0d1b2a; border-left: 4px solid #0066cc; padding-left: .75rem; margin: 2.5rem 0 .75rem; }
h3 { font-size: 1.15rem; color: #1a3a5c; margin: 1.5rem 0 .5rem; }
h4 { font-size: 1rem; color: #1a3a5c; margin: 1rem 0 .4rem; }
p  { margin: .6rem 0; }
ul, ol { margin: .6rem 0 .6rem 1.5rem; }
li { margin: .25rem 0; }
a  { color: #0066cc; }
code {
  background: #e8edf2;
  border-radius: 3px;
  padding: .1em .35em;
  font-family: 'SF Mono', 'Fira Code', Consolas, monospace;
  font-size: .88em;
  color: #b5290a;
}
pre {
  background: #1e2836;
  color: #d4e5f7;
  border-radius: 6px;
  padding: 1rem 1.25rem;
  overflow-x: auto;
  margin: 1rem 0;
  font-family: 'SF Mono', 'Fira Code', Consolas, monospace;
  font-size: .87em;
  line-height: 1.6;
}
pre code { background: none; color: inherit; padding: 0; font-size: inherit; }
blockquote {
  border-left: 4px solid #aac4e0;
  background: #eef4fb;
  padding: .75rem 1rem;
  margin: 1rem 0;
  border-radius: 0 6px 6px 0;
  color: #2c4a6e;
  font-style: italic;
}
hr { border: none; border-top: 2px solid #dde4ec; margin: 2rem 0; }

/* Tables */
table { border-collapse: collapse; width: 100%; margin: 1rem 0; font-size: .93em; }
th { background: #0d1b2a; color: #fff; padding: .5rem .75rem; text-align: left; }
td { padding: .45rem .75rem; border-bottom: 1px solid #d8e2ec; }
tr:nth-child(even) td { background: #f0f5fa; }

/* Epistemic class badges */
.class-c  { display:inline-block; background:#e6a817; color:#fff; font-size:.78em; font-weight:700; padding:.15em .55em; border-radius:12px; vertical-align:middle; }
.class-d  { display:inline-block; background:#c0392b; color:#fff; font-size:.78em; font-weight:700; padding:.15em .55em; border-radius:12px; vertical-align:middle; }
.class-frozen { display:inline-block; background:#1565c0; color:#fff; font-size:.78em; font-weight:700; padding:.15em .55em; border-radius:12px; vertical-align:middle; }

/* Warning boxes (FCP, FORBIDDEN) */
.box-warn {
  background: #fdf0ed;
  border: 1.5px solid #c0392b;
  border-left: 5px solid #c0392b;
  border-radius: 6px;
  padding: .85rem 1rem;
  margin: 1rem 0;
  color: #7b1a10;
}
.box-warn::before { content: "⛔ "; font-size: 1.1em; }

/* Frozen / invariant boxes */
.box-frozen {
  background: #eef4fb;
  border: 1.5px solid #1565c0;
  border-left: 5px solid #1565c0;
  border-radius: 6px;
  padding: .85rem 1rem;
  margin: 1rem 0;
  color: #0d2d5e;
}
.box-frozen::before { content: "🔒 "; font-size: 1.1em; }

/* Advisory / note boxes */
.box-advisory {
  background: #fffbea;
  border: 1.5px solid #e6a817;
  border-left: 5px solid #e6a817;
  border-radius: 6px;
  padding: .85rem 1rem;
  margin: 1rem 0;
  color: #5a3a00;
}
.box-advisory::before { content: "⚠️ "; font-size: 1.1em; }

/* Status pills */
.status-complete { display:inline-block; background:#1b7340; color:#fff; font-size:.78em; padding:.1em .5em; border-radius:10px; }
.status-active   { display:inline-block; background:#1565c0; color:#fff; font-size:.78em; padding:.1em .5em; border-radius:10px; }
.status-frozen   { display:inline-block; background:#5a1e8a; color:#fff; font-size:.78em; padding:.1em .5em; border-radius:10px; }

/* Nav */
.doc-nav { background:#fff; border:1px solid #d8e2ec; border-radius:8px; padding:1rem 1.25rem; margin-bottom:2rem; }
.doc-nav h4 { color:#555; font-size:.85em; text-transform:uppercase; letter-spacing:.05em; margin-bottom:.5rem; }
.doc-nav a  { display:block; color:#0066cc; text-decoration:none; padding:.15rem 0; font-size:.92em; }
.doc-nav a:hover { text-decoration:underline; }

/* Header strip */
.doc-header {
  background: #0d1b2a;
  color: #fff;
  padding: 1.5rem 1.75rem;
  border-radius: 10px;
  margin-bottom: 2rem;
}
.doc-header .title { font-size: 1.5rem; font-weight: 700; margin-bottom: .4rem; }
.doc-header .meta  { font-size: .85em; color: #8ab4d0; }

/* Footer */
.doc-footer { margin-top:3rem; padding-top:1rem; border-top:1px solid #d8e2ec; color:#888; font-size:.82em; }
"""

# ---------------------------------------------------------------------------
# Markdown → HTML converter (regex-based, no external deps)
# ---------------------------------------------------------------------------

def _escape(text: str) -> str:
    return html_lib.escape(text)


def _inline(text: str) -> str:
    """Convert inline markdown (bold, italic, code, links) to HTML."""
    # Code spans (process first to avoid interference)
    text = re.sub(r'`([^`]+)`', lambda m: f'<code>{_escape(m.group(1))}</code>', text)
    # Bold
    text = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', text)
    text = re.sub(r'__([^_]+)__', r'<strong>\1</strong>', text)
    # Italic
    text = re.sub(r'\*([^*]+)\*', r'<em>\1</em>', text)
    text = re.sub(r'_([^_]+)_', r'<em>\1</em>', text)
    # Links
    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', text)
    # Epistemic class badges
    text = re.sub(r'\bClass C\b', '<span class="class-c">Class C</span>', text)
    text = re.sub(r'\bClass D\b', '<span class="class-d">Class D</span>', text)
    # FORBIDDEN / BLOCKED highlight
    text = re.sub(r'\b(FORBIDDEN|BLOCKED|CATEGORICALLY FORBIDDEN)\b',
                  r'<strong style="color:#c0392b">\1</strong>', text)
    # Status in tables
    text = re.sub(r'\bCOMPLETE\b', '<span class="status-complete">COMPLETE</span>', text)
    text = re.sub(r'\bACTIVE\b', '<span class="status-active">ACTIVE</span>', text)
    text = re.sub(r'\bFROZEN\b', '<span class="status-frozen">FROZEN</span>', text)
    return text


def _parse_table(lines: list[str]) -> str:
    """Parse a markdown table block into HTML."""
    rows = []
    for line in lines:
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        rows.append(cells)
    if not rows:
        return ''
    html = '<table>\n'
    # First row = header
    html += '<tr>' + ''.join(f'<th>{_inline(_escape(c))}</th>' for c in rows[0]) + '</tr>\n'
    # Skip separator row (---), rest = body
    for row in rows[2:]:
        html += '<tr>' + ''.join(f'<td>{_inline(_escape(c))}</td>' for c in row) + '</tr>\n'
    html += '</table>\n'
    return html


def _is_table_row(line: str) -> bool:
    return line.strip().startswith('|') and '|' in line.strip()[1:]


def _is_separator(line: str) -> bool:
    return bool(re.match(r'^\s*\|[\s\-:|]+\|\s*$', line))


def md_to_html(md: str) -> tuple[str, str, list[tuple[str, str]]]:
    """
    Convert markdown to HTML body.
    Returns: (html_body, title, headings_for_nav)
    """
    lines = md.split('\n')
    out: list[str] = []
    title = ''
    headings: list[tuple[str, str]] = []  # (id, text)
    i = 0
    in_code_block = False
    code_lang = ''
    code_lines: list[str] = []
    in_list: list[str] = []  # stack of 'ul' or 'ol'
    in_blockquote = False
    table_lines: list[str] = []

    def flush_list():
        while in_list:
            tag = in_list.pop()
            out.append(f'</{tag}>')

    def flush_blockquote():
        nonlocal in_blockquote
        if in_blockquote:
            out.append('</blockquote>')
            in_blockquote = False

    def flush_table():
        nonlocal table_lines
        if table_lines:
            out.append(_parse_table(table_lines))
            table_lines = []

    while i < len(lines):
        line = lines[i]

        # Code block fence
        if line.startswith('```'):
            if in_code_block:
                # End of code block
                code_text = _escape('\n'.join(code_lines))
                lang_cls = f' class="language-{code_lang}"' if code_lang else ''
                out.append(f'<pre><code{lang_cls}>{code_text}</code></pre>')
                code_lines = []
                in_code_block = False
                code_lang = ''
            else:
                flush_list()
                flush_blockquote()
                flush_table()
                in_code_block = True
                code_lang = line[3:].strip()
            i += 1
            continue

        if in_code_block:
            code_lines.append(line)
            i += 1
            continue

        # Table detection
        if _is_table_row(line):
            flush_list()
            flush_blockquote()
            table_lines.append(line)
            i += 1
            continue
        else:
            flush_table()

        # Blank line
        if not line.strip():
            flush_list()
            flush_blockquote()
            i += 1
            continue

        # HR
        if re.match(r'^---+\s*$', line) or re.match(r'^===+\s*$', line):
            flush_list()
            flush_blockquote()
            out.append('<hr>')
            i += 1
            continue

        # Headings
        m = re.match(r'^(#{1,4})\s+(.+)$', line)
        if m:
            flush_list()
            flush_blockquote()
            level = len(m.group(1))
            text = m.group(2).strip()
            # Strip trailing #
            text = re.sub(r'\s+#+\s*$', '', text)
            slug = re.sub(r'[^a-z0-9-]', '-', text.lower())
            slug = re.sub(r'-+', '-', slug).strip('-')
            h_html = _inline(_escape(text))
            if level == 1 and not title:
                title = text
            if level <= 3:
                headings.append((slug, text))
            out.append(f'<h{level} id="{slug}">{h_html}</h{level}>')
            i += 1
            continue

        # Blockquote
        if line.startswith('>'):
            flush_list()
            if not in_blockquote:
                out.append('<blockquote>')
                in_blockquote = True
            content = line.lstrip('> ').strip()
            # Detect advisory/warn patterns in blockquotes
            if re.search(r'\bFORBIDDEN\b|\bBLOCKED\b|\bMUST NOT\b', content, re.I):
                out.append(f'<p class="box-warn" style="margin:0;background:none;border:none;padding:0">{_inline(_escape(content))}</p>')
            else:
                out.append(f'<p>{_inline(_escape(content))}</p>')
            i += 1
            continue
        else:
            flush_blockquote()

        # Ordered list
        m = re.match(r'^(\s*)\d+\.\s+(.+)$', line)
        if m:
            indent = len(m.group(1))
            text = m.group(2)
            depth = indent // 2
            while len(in_list) > depth + 1:
                out.append(f'</{in_list.pop()}>')
            if len(in_list) == depth:
                in_list.append('ol')
                out.append('<ol>')
            elif in_list and in_list[-1] == 'ul':
                out.append('</ul>')
                in_list[-1] = 'ol'
                out.append('<ol>')
            out.append(f'<li>{_inline(_escape(text))}</li>')
            i += 1
            continue

        # Unordered list
        m = re.match(r'^(\s*)[-*+]\s+(.+)$', line)
        if m:
            indent = len(m.group(1))
            text = m.group(2)
            depth = indent // 2
            while len(in_list) > depth + 1:
                out.append(f'</{in_list.pop()}>')
            if len(in_list) == depth:
                in_list.append('ul')
                out.append('<ul>')
            elif in_list and in_list[-1] == 'ol':
                out.append('</ol>')
                in_list[-1] = 'ul'
                out.append('<ul>')
            out.append(f'<li>{_inline(_escape(text))}</li>')
            i += 1
            continue

        # Paragraph
        flush_list()
        text = _inline(_escape(line.strip()))

        # Detect warning/frozen box triggers in paragraphs
        raw_upper = line.upper()
        if any(kw in raw_upper for kw in ['FORBIDDEN', 'MUST NOT', 'CATEGORICALLY FORBIDDEN',
                                           'FCP-', 'BLOCKED BY', 'VIOLATION']):
            out.append(f'<p class="box-warn">{text}</p>')
        elif any(kw in raw_upper for kw in ['FROZEN', 'ANTI-COLLAPSE', 'INVARIANT',
                                             'LOCKED RULE', 'PERMANENTLY']):
            out.append(f'<p class="box-frozen">{text}</p>')
        elif any(kw in raw_upper for kw in ['ADVISORY', 'HEURISTIC', 'UNVERIFIED',
                                             'NOT VERIFIED', 'OBSERVABILITY ONLY']):
            out.append(f'<p class="box-advisory">{text}</p>')
        else:
            out.append(f'<p>{text}</p>')
        i += 1

    flush_list()
    flush_blockquote()
    flush_table()

    return '\n'.join(out), title, headings


# ---------------------------------------------------------------------------
# HTML page template
# ---------------------------------------------------------------------------

def render_page(md_path: Path) -> str:
    md_text = md_path.read_text(encoding='utf-8')
    body, title, headings = md_to_html(md_text)

    if not title:
        title = md_path.stem.replace('_', ' ').replace('CODEBURN ', '')

    # Navigation
    nav_html = ''
    if len(headings) > 2:
        links = ''.join(f'<a href="#{slug}">{text}</a>' for slug, text in headings)
        nav_html = f'<div class="doc-nav"><h4>Contents</h4>{links}</div>'

    # Doc header strip
    source_name = md_path.name
    generated = datetime.now().strftime('%Y-%m-%d %H:%M')
    header_html = f'''<div class="doc-header">
  <div class="title">{html_lib.escape(title)}</div>
  <div class="meta">Source: {source_name} &nbsp;·&nbsp; Generated: {generated} &nbsp;·&nbsp; CodeBurn v1.1</div>
</div>'''

    footer_html = f'''<div class="doc-footer">
  Source: <code>{source_name}</code> — HTML is the presentation layer. The .md source is authoritative.
  <br>CodeBurn v1.1 governed architecture baseline.
</div>'''

    return f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{html_lib.escape(title)}</title>
<style>{CSS}</style>
</head>
<body>
{header_html}
{nav_html}
{body}
{footer_html}
</body>
</html>'''


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    args = sys.argv[1:]

    if '--list' in args:
        files = sorted(CODEBURN_DIR.glob(MD_GLOB))
        for f in files:
            print(f.name)
        return 0

    if args:
        targets = [Path(a) for a in args if not a.startswith('--')]
    else:
        targets = sorted(CODEBURN_DIR.glob(MD_GLOB))

    if not targets:
        print('No .md files found.')
        return 1

    HTML_OUT_DIR.mkdir(exist_ok=True)

    for md_path in targets:
        if not md_path.exists():
            print(f'  NOT FOUND: {md_path}', file=sys.stderr)
            continue
        try:
            html = render_page(md_path)
            out_path = HTML_OUT_DIR / (md_path.stem + '.html')
            out_path.write_text(html, encoding='utf-8')
            print(f'  {md_path.name}  →  {out_path.relative_to(CODEBURN_DIR.parent)}')
        except Exception as e:
            print(f'  ERROR {md_path.name}: {e}', file=sys.stderr)

    return 0


if __name__ == '__main__':
    sys.exit(main())
