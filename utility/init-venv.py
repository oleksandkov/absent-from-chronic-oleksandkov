"""
venv Initialization for Python Reproducibility
===============================================
Run this script when you need a project-local Python environment with all
visualization and analysis packages pre-installed.

Mirrors the role of utility/init-renv.R for the Python side of the project.

Usage (from repo root):
    python utility/init-venv.py          # interactive
    python utility/init-venv.py --yes    # non-interactive (CI / headless)
    python utility/init-venv.py --check  # status only, no changes
"""

import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

# ── Configuration ──────────────────────────────────────────────────────────────
VENV_DIR        = Path(".venv")           # project-local virtual environment
REQUIREMENTS    = Path("utility/python-requirements.txt")
LOCKFILE        = Path("venv.lock")       # frozen pinned versions (like renv.lock)


# ── Helpers ────────────────────────────────────────────────────────────────────

def banner(title: str) -> None:
    line = "=" * 57
    print(f"\n{line}")
    print(f"  {title}")
    print(f"{line}\n")


def venv_python() -> Path:
    """Return path to the Python executable inside the venv."""
    if platform.system() == "Windows":
        return VENV_DIR / "Scripts" / "python.exe"
    return VENV_DIR / "bin" / "python"


def venv_pip() -> Path:
    """Return path to pip inside the venv."""
    if platform.system() == "Windows":
        return VENV_DIR / "Scripts" / "pip.exe"
    return VENV_DIR / "bin" / "pip"


def venv_activate_hint() -> str:
    if platform.system() == "Windows":
        return f"  .venv\\Scripts\\activate        (Command Prompt / PowerShell)"
    return f"  source .venv/bin/activate     (bash / zsh)"


def run(cmd: list, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    """Run a subprocess command, printing it first for transparency."""
    print(f"  $ {' '.join(str(c) for c in cmd)}")
    return subprocess.run(
        cmd,
        check=check,
        capture_output=capture,
        text=True,
    )


def venv_exists() -> bool:
    return (VENV_DIR / "pyvenv.cfg").exists()


def lockfile_exists() -> bool:
    return LOCKFILE.exists()


# ── Windows Long Path guard ────────────────────────────────────────────────────

def check_windows_long_paths() -> bool:
    """Return True if Windows LongPathsEnabled registry key is set to 1."""
    if platform.system() != "Windows":
        return True  # not applicable on non-Windows
    try:
        import winreg
        key = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"SYSTEM\CurrentControlSet\Control\FileSystem",
        )
        value, _ = winreg.QueryValueEx(key, "LongPathsEnabled")
        winreg.CloseKey(key)
        return bool(value)
    except Exception:
        return False  # key missing → long paths not enabled


def warn_long_paths_disabled() -> None:
    print("")
    print("⚠️   Windows Long Path support is NOT enabled.")
    print("    Some packages (e.g. jupyterlab extensions) install files with")
    print("    paths longer than 260 characters, which will fail on your system.")
    print("")
    print("    To enable Long Paths (requires Administrator):")
    print("      Option A – PowerShell (run as Admin):")
    print("        New-ItemProperty -Path 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\FileSystem'")
    print("                         -Name LongPathsEnabled -Value 1 -PropertyType DWORD -Force")
    print("")
    print("      Option B – Group Policy Editor:")
    print("        gpedit.msc → Computer Configuration → Administrative Templates")
    print("                   → System → Filesystem → Enable Win32 long paths")
    print("")
    print("    After enabling, restart your terminal and re-run this script.")
    print("    Continuing anyway – packages that need long paths are already")
    print("    excluded from utility/python-requirements.txt.")
    print("")


# ── Status check ───────────────────────────────────────────────────────────────

def show_status() -> None:
    banner("PYTHON VENV STATUS")

    py_version = platform.python_version()
    print(f"  Host Python     : {sys.executable}  (v{py_version})")
    print(f"  venv directory  : {VENV_DIR.resolve()}")
    print(f"  venv exists     : {'✅ Yes' if venv_exists() else '❌ No'}")
    print(f"  requirements    : {'✅ Found' if REQUIREMENTS.exists() else '❌ Missing'}")
    print(f"  lockfile        : {'✅ Found  →  ' + str(LOCKFILE) if lockfile_exists() else '❌ Not yet created'}")

    if venv_exists():
        result = run([venv_python(), "--version"], capture=True, check=False)
        venv_ver = result.stdout.strip() or result.stderr.strip()
        print(f"  venv Python     : {venv_ver}")

        result = run([venv_pip(), "list", "--format=columns"], capture=True, check=False)
        lines = result.stdout.strip().splitlines()
        pkg_count = max(0, len(lines) - 2)   # subtract header lines
        print(f"  packages        : {pkg_count} installed")

    print()


# ── User consent ───────────────────────────────────────────────────────────────

def check_user_consent() -> bool:
    print("This will:")
    print("  • Create a project-local virtual environment in  .venv/")
    print("  • Install packages from  utility/python-requirements.txt")
    print("  • Write  venv.lock  with exact pinned versions")
    print()
    print("⚠️  When to use this venv setup:")
    print("  ✅  Reproducible research that ships Python visualizations")
    print("  ✅  Mixed R + Python workflows inside this project")
    print("  ✅  Collaborating where everyone needs identical package versions")
    print("  ❌  System-wide Python workflows (use your system Python instead)")
    print("  ❌  Conda-managed environments (see environment.yml)")
    print()

    answer = input("Proceed with venv initialization? (y/N): ").strip().lower()
    return answer in ("y", "yes")


# ── Core init logic ────────────────────────────────────────────────────────────

def init_venv(force: bool = False) -> bool:
    """Create the venv, install packages, and write the lockfile."""

    # ── Guard: Windows Long Paths ─────────────────────────────────────────────
    if platform.system() == "Windows" and not check_windows_long_paths():
        warn_long_paths_disabled()

    # ── Guard: already exists? ─────────────────────────────────────────────────
    if venv_exists() and not force:
        print("⚠️   A virtual environment already exists at  .venv/")
        answer = input("Reinitialize? This will overwrite the existing venv (y/N): ").strip().lower()
        if answer not in ("y", "yes"):
            print("Cancelled.")
            return False

    # ── Guard: requirements file ───────────────────────────────────────────────
    if not REQUIREMENTS.exists():
        print(f"❌  Requirements file not found: {REQUIREMENTS}")
        print("    Expected path (from repo root): utility/python-requirements.txt")
        return False

    # ── Step 1: create venv (remove stale/partial one first) ────────────────────
    print("\n🔧  Creating virtual environment …")
    if VENV_DIR.exists():
        print(f"  Removing existing  {VENV_DIR}  …")
        shutil.rmtree(VENV_DIR)
    run([sys.executable, "-m", "venv", str(VENV_DIR)])

    # ── Step 2: upgrade pip inside venv ───────────────────────────────────────
    print("\n📦  Upgrading pip …")
    run([venv_python(), "-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel"])

    # ── Step 3: install packages ────────────────────────────────────────────────
    print(f"\n📦  Installing packages from {REQUIREMENTS} …")
    try:
        run([venv_pip(), "install", "-r", str(REQUIREMENTS)])
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr or ""
        if "No such file or directory" in stderr or "long path" in stderr.lower():
            print("\n❌  Installation failed – likely a Windows Long Path issue.")
            warn_long_paths_disabled()
        else:
            print(f"\n❌  pip install failed (exit {exc.returncode}).")
        return False

    # ── Step 3a: upgrade all packages to latest available versions ──────────────
    print(f"\n🔄  Upgrading all packages to latest versions …")
    try:
        run([venv_pip(), "install", "--upgrade", "-r", str(REQUIREMENTS)])
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr or ""
        if "No such file or directory" in stderr or "long path" in stderr.lower():
            print("\n❌  Upgrade failed – likely a Windows Long Path issue.")
            warn_long_paths_disabled()
        else:
            print(f"\n❌  pip upgrade failed (exit {exc.returncode}).")
        return False

    # ── Step 4: write lockfile ─────────────────────────────────────────────────
    print(f"\n📸  Writing lockfile  {LOCKFILE}  …")
    result = run([venv_pip(), "freeze"], capture=True)
    LOCKFILE.write_text(
        "# venv.lock – auto-generated by utility/init-venv.py\n"
        "# Do not edit manually.  Commit this file for reproducibility.\n"
        "# Restore with: pip install -r venv.lock\n\n"
        + result.stdout,
        encoding="utf-8",
    )

    # ── Success ────────────────────────────────────────────────────────────────
    banner("VENV INITIALIZATION COMPLETE!")
    print("  ✅  Virtual environment created in  .venv/")
    print(f"  ✅  {REQUIREMENTS}  packages installed")
    print(f"  ✅  Exact versions frozen in  {LOCKFILE}")
    print()
    print("  📋  Next steps:")
    print(f"    1. Commit  {LOCKFILE}  to version control")
    print( "    2. Share with collaborators – they restore with:")
    print( "         pip install -r venv.lock")
    print( "    3. Activate the environment before running Python code:")
    print(f"{venv_activate_hint()}")
    print()
    print("  🔧  Useful venv commands:")
    print(f"    • Activate    : {venv_activate_hint().strip()}")
    print( "    • Deactivate  : deactivate")
    print(f"    • Freeze      : pip freeze > {LOCKFILE}")
    print( "    • Install new : pip install <package>")
    print( "    • Status      : python utility/init-venv.py --check")
    print()

    return True


def init_venv_noninteractive() -> bool:
    """Non-interactive path used by CI or --yes flag."""
    if not REQUIREMENTS.exists():
        print(f"❌  Requirements file not found: {REQUIREMENTS}")
        return False
    return init_venv(force=True)


# ── Entry point ────────────────────────────────────────────────────────────────

def main() -> None:
    # ── Ensure we run from repo root ───────────────────────────────────────────
    if not Path("utility/init-venv.py").exists():
        sys.exit(
            "❌  Please run this script from the repository root:\n"
            "       python utility/init-venv.py"
        )

    banner("VENV INITIALIZATION FOR PYTHON REPRODUCIBILITY")

    parser = argparse.ArgumentParser(
        description="Initialize a project-local Python virtual environment.",
        epilog="Similar to utility/init-renv.R for the R side of this project.",
    )
    parser.add_argument(
        "--yes", "-y",
        action="store_true",
        help="Non-interactive mode: skip confirmation prompts and initialize.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Only show environment status – make no changes.",
    )
    args = parser.parse_args()

    # ── Windows Long Path info (always show on Windows) ──────────────────────
    if platform.system() == "Windows" and not args.check:
        if not check_windows_long_paths():
            warn_long_paths_disabled()
            # Don't abort – requirements are already safe without ipywidgets

    # ── Status-only mode ───────────────────────────────────────────────────────
    if args.check:
        show_status()
        return

    # ── Non-interactive mode ───────────────────────────────────────────────────
    if args.yes or not sys.stdin.isatty():
        print("Non-interactive mode: initializing venv …\n")
        success = init_venv_noninteractive()
    else:
        # ── Interactive mode ───────────────────────────────────────────────────
        if check_user_consent():
            success = init_venv()
        else:
            print("\nvenv initialization cancelled.")
            print("💡  Your host Python and conda environment (environment.yml) still work normally!")
            return

    if not success:
        sys.exit("❌  venv initialization failed. See messages above.")


if __name__ == "__main__":
    main()
