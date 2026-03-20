"""
Deploy TimePlayed_Plus to the WoW retail AddOns folder.
Copies only functional addon files (same rules as package.py).

Usage: python deploy.py
"""

import os
import re
import shutil

ADDON_NAME = "TimePlayed_Plus"
ADDON_DIR = os.path.dirname(os.path.abspath(__file__))
WOW_ADDONS = r"C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns"
DEPLOY_DIR = os.path.join(WOW_ADDONS, ADDON_NAME)

# Files and dirs to exclude (non-functional per CurseForge guidelines)
EXCLUDE = {
    ".git",
    ".gitignore",
    ".pkgmeta",
    "README.md",
    "LICENSE",
    "package.py",
    "deploy.py",
}

# File extensions to exclude
EXCLUDE_EXT = {
    ".zip",
    ".md",
    ".py",
}


def should_include(rel_path):
    """Check if a file should be included in the deploy."""
    parts = rel_path.replace("\\", "/").split("/")

    for part in parts:
        if part in EXCLUDE:
            return False

    _, ext = os.path.splitext(rel_path)
    if ext.lower() in EXCLUDE_EXT:
        return False

    return True


def deploy():
    # Clean previous deploy
    if os.path.exists(DEPLOY_DIR):
        shutil.rmtree(DEPLOY_DIR)

    count = 0
    for root, dirs, files in os.walk(ADDON_DIR):
        dirs[:] = [d for d in dirs if d not in EXCLUDE]

        for filename in files:
            filepath = os.path.join(root, filename)
            rel_path = os.path.relpath(filepath, ADDON_DIR)

            if should_include(rel_path):
                dest = os.path.join(DEPLOY_DIR, rel_path)
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                shutil.copy2(filepath, dest)
                count += 1

    print(f"Deployed {count} files -> {DEPLOY_DIR}")


if __name__ == "__main__":
    deploy()
