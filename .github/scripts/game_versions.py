"""Keep the TOC's Interface line in step with Blizzard's current game versions.

Run once a day by .github/workflows/versions.yml, which opens an issue when a
number is behind. Run by hand in the repository, it makes the change to the TOC.
"""
import os
import re
import sys
import time
import urllib.request

TOC = "TimePlayed_Plus.toc"
URL = "https://us.version.battle.net/v2/products/%s/versions"

# The game versions the addon supports, in the order they are written in the TOC:
# Blizzard's product name, what we call it, and whether it is a test realm.
# A test realm is listed only while it is a small patch ahead of retail.
PRODUCTS = [
    ("wow", "Retail", False),
    ("wowt", "Retail test realm", True),
    ("wowxptr", "Retail test realm", True),
    ("wowf", "Forever", False),
    ("wow_classic_era", "Classic Era", False),
    ("wow_anniversary", "Burning Crusade Classic Anniversary", False),
    ("wow_classic", "Mists of Pandaria Classic", False),
]


def current_version(product, pretend):
    """(major, minor, patch) of a product, or None when Blizzard gives no usable answer."""
    text = pretend.get(product)
    for attempt in range(3):
        if text is not None:
            break
        try:
            with urllib.request.urlopen(URL % product, timeout=30) as reply:
                rows = reply.read().decode("utf-8", "replace").splitlines()
            columns = [c.split("!")[0] for c in rows[0].split("|")]
            us = [r.split("|") for r in rows if r.startswith("us|")]
            text = us[0][columns.index("VersionsName")]
        except (OSError, IndexError, ValueError):
            time.sleep(5 * (attempt + 1))
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)(\.\d+)?$", text or "")
    return tuple(int(part) for part in match.groups()[:3]) if match else None


def main():
    pretend = dict(pair.split("=", 1) for pair in os.environ.get("PRETEND", "").split() if "=" in pair)
    raw = open(TOC, "rb").read()
    line = re.search(rb"^## Interface:[ \t]*([0-9][0-9, \t]*?)[ \t]*\r?$", raw, re.M)
    if not line:
        sys.exit("No '## Interface:' line found in %s. Nothing was changed." % TOC)
    old = [int(n) for n in re.findall(rb"\d+", line.group(1))]
    old_families = {(n // 10000, n // 100 % 100) for n in old}

    new, notes, changes, retail = [], [], [], None
    for product, name, test_realm in PRODUCTS:
        version = current_version(product, pretend)
        if version is None:
            if test_realm:
                continue
            sys.exit("Could not read Blizzard's current version of %s (%s). Nothing was changed." % (name, product))
        if product == "wow":
            retail = version
        if test_realm and not (version[:2] == retail[:2] and version > retail):
            continue
        number = version[0] * 10000 + version[1] * 100 + version[2]
        if number in new:
            continue
        new.append(number)
        label = "%s %d.%d.%d" % ((name,) + version)
        if number in old:
            notes.append("- %s (%d): already listed" % (label, number))
        elif version[:2] in old_families:
            notes.append("- **%s (%d): new, a small patch**" % (label, number))
            changes.append(label)
        else:
            notes.append("- **%s (%d): new, a bigger update. Test it in game before merging.**" % (label, number))
            changes.append(label)
    removed = [n for n in old if n not in new]
    notes += ["- %d: removed, no game version uses it any more" % n for n in removed]

    print("TOC lists:      " + ", ".join(map(str, old)))
    print("Blizzard lists: " + ", ".join(map(str, new)))
    changed = set(new) != set(old)
    title = "Game versions: " + (", ".join(changes) if changes else "remove " + ", ".join(map(str, removed)))
    if pretend:
        title += " (test)"
    if changed:
        start, end = line.span(1)
        open(TOC, "wb").write(raw[:start] + ", ".join(map(str, new)).encode() + raw[end:])
        body = (("This is a test with a pretended game version. Nothing needs doing.\n\n" if pretend else "")
                + "Blizzard's current game versions differ from the ones the addon lists.\n\n" + "\n".join(notes)
                + "\n\nThe Interface line of the TOC should become:\n\n    ## Interface: " + ", ".join(map(str, new))
                + "\n\nRunning `python .github/scripts/game_versions.py` in the repository makes that change. "
                  "Players receive it with the next release. "
                  "This issue closes by itself once the TOC is up to date.\n")
        open(os.path.join(os.environ.get("RUNNER_TEMP", "."), "game_versions.md"), "w", encoding="utf-8").write(body)
        print(title + "\n" + body)
    else:
        print("Up to date. Nothing to do.")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
            out.write("changed=%s\ntitle=%s\n" % ("true" if changed else "false", title if changed else ""))


if __name__ == "__main__":
    main()
