"""
0-extract-dictionary.py
=======================
Title  : CCHS Data Dictionary PDF Extractor
Author : Andriy Koval
Date   : 2026-02-19

Purpose
-------
Convert the 14 CCHS data dictionary PDF files into plain-text (.txt) files so
their verbatim content is searchable and can inform Ellis lane transformations
(variable name verification, code lookups, derived-variable documentation).

Input
-----
  data-private/raw/2026-02-19/  (14 PDF files listed explicitly below)

Output
------
  data-private/derived/2026-02-19/
    CCHS_2010_Alpha_Index.txt
    CCHS_2010_CV_Tables.txt
    CCHS_2010_DataDictionary_Freqs-ver2.txt      ← primary verification target
    CCHS_2010_Derived_Variables.txt
    CCHS_2010_Record_Layout.txt
    CCHS_2010_Topical_Index.txt
    CCHS_2014_Alpha_Index.txt
    CCHS_2014_CV_Tables.txt
    CCHS_2014_DataDictionary_Freqs.txt           ← primary verification target
    CCHS_2014_Derived_Variables.txt
    CCHS_2014_Record_Layout.txt
    CCHS_2014_Topical_Index.txt
    FILES_2010_E.txt
    FILES_2014_E.txt
    dictionary-manifest.md                        ← extraction summary table

Dependencies
------------
  pdfplumber>=0.11.0    (pure Python; install via pip — no admin, no system DLLs)

  Install into the project virtual environment:
    python utility/init-venv.py          # bootstraps .venv from python-requirements.txt
  OR directly:
    .venv\\Scripts\\pip install pdfplumber

Usage (from repo root)
----------------------
  .venv\\Scripts\\python.exe manipulation\\0-extract-dictionary\\0-extract-dictionary.py

  Alternatively, from this script's directory:
    ..\\..\\venv\\Scripts\\python.exe 0-extract-dictionary.py

Notes
-----
- File list is hard-coded (not a glob) to ensure reproducibility and intentional
  inclusion — stats_instructions_v3.pdf is deliberately excluded.
- Page-break markers ("--- PAGE N ---") are preserved in the .txt output so
  analysts can cross-reference specific pages in the original PDFs.
- CCHS PUMF documentation PDFs are text-layer (not scanned images), so OCR is
  not required.  If a file yields very little text, it may indicate a scanned
  page — flag will appear in the manifest.
- Run time: typically 2-10 minutes for large dictionary files (400-1000+ pages).
"""

from __future__ import annotations

import sys
import datetime
from pathlib import Path

# ---------------------------------------------------------------------------
# Dependency check — surface a clear message before the ImportError fires
# ---------------------------------------------------------------------------
try:
    import pdfplumber
except ImportError:
    print(
        "\n[ERROR] pdfplumber is not installed in the active Python environment.\n"
        "Install it with:\n"
        "    .venv\\\\Scripts\\\\pip install pdfplumber>=0.11.0\n"
        "Or run:  python utility/init-venv.py  from the repo root to bootstrap the full .venv.\n",
        file=sys.stderr,
    )
    sys.exit(1)

# ---------------------------------------------------------------------------
# Path resolution — works whether script is run from repo root OR from this dir
# ---------------------------------------------------------------------------
SCRIPT_DIR   = Path(__file__).resolve().parent
REPO_ROOT    = SCRIPT_DIR.parent.parent   # manipulation/0-extract-dictionary/ → repo root

INPUT_DIR    = REPO_ROOT / "data-private" / "raw"     / "2026-02-19"
OUTPUT_DIR   = REPO_ROOT / "data-private" / "derived" / "2026-02-19"

# ---------------------------------------------------------------------------
# Explicit file list — hard-coded for reproducibility
# stats_instructions_v3.pdf is intentionally excluded.
# ---------------------------------------------------------------------------
PDF_FILES = [
    # 2010-2011 cycle (6 reference documents)
    ("CCHS_2010_Alpha Index.pdf",              "2010-11 alphabetical variable index"),
    ("CCHS_2010_CV_Tables.pdf",                "2010-11 coefficient of variation tables"),
    ("CCHS_2010_DataDictionary_Freqs-ver2.pdf","2010-11 data dictionary with frequencies (primary verification target)"),
    ("CCHS_2010_Derived_Variables.pdf",        "2010-11 derived variable documentation"),
    ("CCHS_2010_Record Layout.pdf",            "2010-11 record layout"),
    ("CCHS_2010_Topical Index.pdf",            "2010-11 topical variable index"),
    # 2013-2014 cycle (6 reference documents)
    ("CCHS_2014_Alpha_Index.pdf",              "2013-14 alphabetical variable index"),
    ("CCHS_2014_CV_Tables.pdf",                "2013-14 coefficient of variation tables"),
    ("CCHS_2014_DataDictionary_Freqs.pdf",     "2013-14 data dictionary with frequencies (primary verification target)"),
    ("CCHS_2014_Derived_Variables.pdf",        "2013-14 derived variable documentation"),
    ("CCHS_2014_Record_Layout.pdf",            "2013-14 record layout"),
    ("CCHS_2014_Topical_Index.pdf",            "2013-14 topical variable index"),
    # Companion file guides
    ("FILES_2010_E.pdf",                       "2010-11 companion file description guide"),
    ("FILES_2014_E.pdf",                       "2013-14 companion file description guide"),
]

PAGE_SEP = "\n\n--- PAGE {n} ---\n\n"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def safe_stem(filename: str) -> str:
    """Return a filesystem-safe output stem, replacing spaces with underscores."""
    return Path(filename).stem.replace(" ", "_")


def extract_pdf(pdf_path: Path) -> tuple[str, int, str]:
    """
    Extract all text from a PDF file using pdfplumber.

    Returns
    -------
    text        : concatenated text with page-break markers
    page_count  : number of pages processed
    status      : 'ok' | 'warning_low_text' | 'error:<message>'
    """
    pages_text: list[str] = []

    try:
        with pdfplumber.open(pdf_path) as pdf:
            page_count = len(pdf.pages)
            for i, page in enumerate(pdf.pages, start=1):
                raw = page.extract_text() or ""
                pages_text.append(PAGE_SEP.format(n=i) + raw)
    except Exception as exc:
        return "", 0, f"error:{exc}"

    full_text  = "".join(pages_text)
    char_count = len(full_text.strip())

    # Heuristic: if we extracted almost no text the PDF may be image-only
    status = "warning_low_text" if (page_count > 0 and char_count < page_count * 20) else "ok"
    return full_text, page_count, status


def write_manifest(records: list[dict], output_dir: Path) -> None:
    """Write a Markdown summary table to dictionary-manifest.md."""
    manifest_path = output_dir / "dictionary-manifest.md"
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")

    lines = [
        "# CCHS Dictionary Extraction Manifest",
        "",
        f"Generated: {now}  ",
        f"Source PDFs: `data-private/raw/2026-02-19/`  ",
        f"Output TXTs: `data-private/derived/2026-02-19/`",
        "",
        "## Extraction Summary",
        "",
        "| # | PDF filename | Output .txt | Pages | Chars | Status | Description |",
        "|---|-------------|-------------|------:|------:|--------|-------------|",
    ]

    for rec in records:
        row = (
            f"| {rec['idx']} "
            f"| `{rec['pdf_name']}` "
            f"| `{rec['txt_name']}` "
            f"| {rec['pages']:,} "
            f"| {rec['chars']:,} "
            f"| {rec['status']} "
            f"| {rec['description']} |"
        )
        lines.append(row)

    ok_count      = sum(1 for r in records if r["status"] == "ok")
    warn_count    = sum(1 for r in records if "warning" in r["status"])
    error_count   = sum(1 for r in records if "error" in r["status"])
    total_pages   = sum(r["pages"] for r in records)
    total_chars   = sum(r["chars"] for r in records)

    lines += [
        "",
        "## Totals",
        "",
        f"- **Files processed**: {len(records)}",
        f"- **OK**: {ok_count}  |  **Warnings** (low text / possible scan): {warn_count}  |  **Errors**: {error_count}",
        f"- **Total pages**: {total_pages:,}",
        f"- **Total characters extracted**: {total_chars:,}",
        "",
        "## Spot-Check Suggestions",
        "",
        "Run these searches in the extracted .txt files to verify key variables:  ",
        "",
        "- `CCHS_2010_DataDictionary_Freqs-ver2.txt` → search `CCC_300`, `CCC_185`, `DHHDGLVG`, `NOC_31`",
        "- `CCHS_2014_DataDictionary_Freqs.txt`      → search `LOPG040`, `DHHGAGE`, `ALCDGTYP`, `HWTDGBMI`",
        "- `CCHS_2010_Derived_Variables.txt`          → search `EDUDH04`, `HWTDGBMI`",
        "- `CCHS_2014_Derived_Variables.txt`          → search `PACDPAI`, `SMKDSTY`",
        "",
        "## Usage",
        "",
        "```bash",
        "# Re-run extraction from repo root:",
        '.venv\\Scripts\\python.exe manipulation\\0-extract-dictionary\\0-extract-dictionary.py',
        "```",
    ]

    manifest_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"  Manifest written → {manifest_path.relative_to(REPO_ROOT)}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    print("\n" + "=" * 65)
    print("  CCHS Dictionary PDF → Text Extraction")
    print("=" * 65)
    print(f"  Input  : {INPUT_DIR.relative_to(REPO_ROOT)}")
    print(f"  Output : {OUTPUT_DIR.relative_to(REPO_ROOT)}")
    print(f"  Files  : {len(PDF_FILES)} PDFs\n")

    # Validate input directory
    if not INPUT_DIR.exists():
        print(f"[ERROR] Input directory not found: {INPUT_DIR}", file=sys.stderr)
        sys.exit(1)

    # Create output directory
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    records: list[dict] = []
    n_ok = n_warn = n_err = 0

    for idx, (pdf_name, description) in enumerate(PDF_FILES, start=1):
        pdf_path = INPUT_DIR / pdf_name
        txt_name = safe_stem(pdf_name) + ".txt"
        txt_path = OUTPUT_DIR / txt_name

        prefix = f"  [{idx:02d}/{len(PDF_FILES)}] {pdf_name}"

        if not pdf_path.exists():
            print(f"{prefix}")
            print(f"         ✗ NOT FOUND — skipping")
            records.append({
                "idx": idx, "pdf_name": pdf_name, "txt_name": txt_name,
                "pages": 0, "chars": 0,
                "status": "error:file_not_found", "description": description,
            })
            n_err += 1
            continue

        print(f"{prefix}")
        print(f"         → extracting ...", end="", flush=True)

        text, page_count, status = extract_pdf(pdf_path)
        char_count = len(text.strip())

        # Write text output (even partial, for diagnosis)
        header = (
            f"# {pdf_name}\n"
            f"# Extracted: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')}\n"
            f"# Pages: {page_count}  |  Status: {status}\n"
            f"# Description: {description}\n"
            + "=" * 70 + "\n"
        )
        txt_path.write_text(header + text, encoding="utf-8")

        status_icon = "✓" if status == "ok" else ("⚠" if "warning" in status else "✗")
        print(f" {status_icon}  {page_count:,} pages, {char_count:,} chars  [{status}]")

        records.append({
            "idx": idx, "pdf_name": pdf_name, "txt_name": txt_name,
            "pages": page_count, "chars": char_count,
            "status": status, "description": description,
        })

        if status == "ok":
            n_ok += 1
        elif "warning" in status:
            n_warn += 1
        else:
            n_err += 1

    # Write manifest
    print()
    write_manifest(records, OUTPUT_DIR)

    # Summary
    print()
    print("=" * 65)
    print(f"  Done.  OK: {n_ok}  |  Warnings: {n_warn}  |  Errors: {n_err}")
    if n_warn > 0:
        print("  ⚠  Low-text files may be image-only scans — check manifest.")
    if n_err > 0:
        print("  ✗  Some files were not found or failed — check manifest.")
    print("=" * 65 + "\n")

    if n_err > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
