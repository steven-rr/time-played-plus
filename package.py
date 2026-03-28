"""
CurseForge-compliant packager for TimePlayed_Plus.
Zips only functional addon files into ~/Dev/TimePlayed_Plus-<version>.zip
with the addon folder as the root entry.

Usage: python package.py
"""

import os
import re
import zipfile

ADDON_NAME = "TimePlayed_Plus"
ADDON_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.expanduser("~/Dev")

# Files and dirs to exclude from the zip (non-functional per CurseForge guidelines)
EXCLUDE = {
    ".git",
    ".gitignore",
    ".pkgmeta",
    ".github",
    ".claude",
    ".DS_Store",
    "README.md",
    "LICENSE",
    "package.py",
    "deploy.py",
    "docs",
    "textures",
}

# File extensions to exclude
EXCLUDE_EXT = {
    ".zip",
    ".md",
    ".py",
    ".txt",
}


def get_version():
    """Read version from the main TOC file."""
    toc_path = os.path.join(ADDON_DIR, f"{ADDON_NAME}.toc")
    with open(toc_path, "r", encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^## Version:\s*(.+)", line)
            if m:
                return m.group(1).strip()
    return "0.0.0"


def should_include(rel_path):
    """Check if a file should be included in the zip."""
    parts = rel_path.replace("\\", "/").split("/")

    # Skip if any path component is in the exclude set
    for part in parts:
        if part in EXCLUDE:
            return False

    # Skip excluded extensions
    _, ext = os.path.splitext(rel_path)
    if ext.lower() in EXCLUDE_EXT:
        return False

    return True


def package():
    version = get_version()
    zip_name = f"{ADDON_NAME}-{version}.zip"
    zip_path = os.path.join(OUTPUT_DIR, zip_name)

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    count = 0
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(ADDON_DIR):
            # Skip .git directory entirely
            dirs[:] = [d for d in dirs if d not in EXCLUDE]

            for filename in files:
                filepath = os.path.join(root, filename)
                rel_path = os.path.relpath(filepath, ADDON_DIR)

                if should_include(rel_path):
                    # Archive path: AddonName/relative/path
                    arc_path = os.path.join(ADDON_NAME, rel_path)
                    zf.write(filepath, arc_path)
                    count += 1

    print(f"Packaged {count} files -> {zip_path}")


if __name__ == "__main__":
    package()
