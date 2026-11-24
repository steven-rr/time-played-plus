"""Keep the TOC's Interface line in step with Blizzard's current game versions.

Run every two hours by .github/workflows/versions.yml, which opens an issue twice
for a patch: when it appears on a test realm, to test the addon there and
release a beta, and again when it goes live, to test it on the live game and
release it in full.

Run by hand in the repository, it brings the TOC in line with the live game
versions. A version that is only on a test realm is never added by itself:
test the addon there first, then run this with --tested to add it.
"""
import os
import re
import sys
import time
import urllib.request

TOC = "TimePlayed_Plus.toc"
URL = "https://us.version.battle.net/v2/products/%s/versions"

# The games the addon supports, in the order they are written in the TOC:
# Blizzard's product name, what we call it, and for a test realm the live game
# it usually tests. A test realm counts only while it is ahead of the live games.
PRODUCTS = [
    ("wow", "Retail", None),
    ("wowt", "Retail test realm", "wow"),
    ("wowxptr", "Retail test realm", "wow"),
    ("wow_beta", "Retail beta", "wow"),
    ("wowf", "Forever", None),
    ("wow_classic_era", "Classic Era", None),
    ("wow_classic_era_ptr", "Classic Era test realm", "wow_classic_era"),
    ("wow_anniversary", "Burning Crusade Classic Anniversary", None),
    ("wow_classic", "Mists of Pandaria Classic", None),
    ("wow_classic_ptr", "Classic test realm", "wow_classic"),
    ("wow_classic_beta", "Classic beta", "wow_classic"),
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


def interface(version):
    """The number the TOC's Interface line uses for a (major, minor, patch) version."""
    return version[0] * 10000 + version[1] * 100 + version[2]


def live_game_behind(version, realm_of, live):
    """The live game a test realm's version is ahead of, or None when it is ahead of none.

    A test realm does not always carry the game it is named after, so the game is
    found by version number: the closest live version below it that starts with
    the same number. Only when no live game starts with that number is it taken
    to be the game the realm usually tests.
    """
    if any(v[:2] == version[:2] and v >= version for v in live.values()):
        return None  # this patch, or a later one of the same line, is already live
    same_start = [p for p in live if live[p][0] == version[0]]
    if same_start:
        below = [p for p in same_start if live[p] < version]
        return max(below, key=live.get) if below else None
    return realm_of if version > live[realm_of] else None


def main():
    tested = "--tested" in sys.argv[1:]
    pretend = dict(pair.split("=", 1) for pair in os.environ.get("PRETEND", "").split() if "=" in pair)
    raw = open(TOC, "rb").read()
    line = re.search(rb"^## Interface:[ \t]*([0-9][0-9, \t]*?)[ \t]*\r?$", raw, re.M)
    if not line:
        sys.exit("No '## Interface:' line found in %s. Nothing was changed." % TOC)
    old = [int(n) for n in re.findall(rb"\d+", line.group(1))]
    old_families = {(n // 10000, n // 100 % 100) for n in old}

    # Every live game has to answer. A test realm that does not answer is left out.
    live, ahead = {}, {}
    for product, name, realm_of in PRODUCTS:
        if realm_of is None:
            live[product] = current_version(product, pretend)
            if live[product] is None:
                sys.exit("Could not read Blizzard's current version of %s (%s). Nothing was changed." % (name, product))
    for product, name, realm_of in PRODUCTS:
        version = current_version(product, pretend) if realm_of else None
        game = live_game_behind(version, realm_of, live) if version else None
        if game and version not in ahead.setdefault(game, []):
            ahead[game].append(version)

    # A number the TOC lists that no game uses any more means its game was patched:
    # the game is the one with the closest live version above that number.
    in_use = {interface(v) for v in live.values()} | {interface(v) for versions in ahead.values() for v in versions}
    removed = [n for n in old if n not in in_use]
    patched = set()
    for n in removed:
        was = (n // 10000, n // 100 % 100, n % 100)
        newer = [p for p in live if live[p][0] == was[0] and live[p] > was]
        if newer:
            patched.add(min(newer, key=live.get))

    # new: what the TOC should list now. later: the same, once the test realms are tested.
    new, later, notes, arrived, added, to_test = [], [], [], [], [], []
    for product, name, realm_of in PRODUCTS:
        if realm_of:
            continue
        version = live[product]
        number = interface(version)
        if number not in new:
            new.append(number)
            later.append(number)
            label = "%s %d.%d.%d" % ((name,) + version)
            if number in old and product not in patched:
                notes.append("- %s (%d): already listed" % (label, number))
            else:
                what = ("live now, listed since it was on a test realm" if number in old else
                        "new, a small patch" if version[:2] in old_families else "new, a bigger update")
                notes.append("- **%s (%d): %s. Test it in game before releasing.**" % (label, number, what))
                arrived.append(label)
        for version in sorted(ahead.get(product, [])):
            number = interface(version)
            label = "%s %d.%d.%d" % ((name,) + version)
            size = "a small patch" if version[:2] == live[product][:2] else "a bigger update"
            later.append(number)
            if number in old:
                new.append(number)
                notes.append("- %s (%d): on a test realm, not live yet, already listed" % (label, number))
            elif tested:
                new.append(number)
                notes.append("- **%s (%d): on a test realm, %s, added as tested**" % (label, number, size))
                added.append(label)
            else:
                notes.append("- **%s (%d): on a test realm, %s, not live yet. Test the addon there.**"
                             % (label, number, size))
                to_test.append(label)
    notes += ["- %d: removed, no game version uses it any more" % n for n in removed]

    print("TOC lists:      " + ", ".join(map(str, old)))
    print("Blizzard lists: " + ", ".join(map(str, later)))
    changed = set(new) != set(old)
    parts = []
    if arrived:
        parts.append(", ".join(arrived) + (" is live" if len(arrived) == 1 else " are live"))
    if added:
        parts.append("add " + ", ".join(added))
    if not parts and removed:
        parts.append("remove " + ", ".join(map(str, removed)))
    if to_test:
        parts.append("test " + ", ".join(to_test) + " on the test realm")
    title = "Game versions: " + "; ".join(parts)
    if pretend:
        title += " (test)"
    if changed:
        start, end = line.span(1)
        open(TOC, "wb").write(raw[:start] + ", ".join(map(str, new)).encode() + raw[end:])
    if changed or to_test:
        body = "This is a test with a pretended game version. Nothing needs doing.\n\n" if pretend else ""
        body += ("Blizzard's current game versions differ from the ones the addon lists.\n\n" if changed else
                 "A newer game version is on a test realm. The addon does not list it until it has been tested there.\n\n")
        body += "\n".join(notes)
        if changed:
            body += ("\n\n" + ("Test the addon on the live game. Once it works there, the" if arrived else "The")
                     + " Interface line of the TOC should become:\n\n    ## Interface: " + ", ".join(map(str, new))
                     + "\n\nRunning `python .github/scripts/game_versions.py` in the repository makes that change. "
                       "Players receive it with the next full release.")
        if to_test:
            body += ("\n\nTest the addon on the test realm. Once it works there, the Interface line should become:\n\n"
                     "    ## Interface: " + ", ".join(map(str, later))
                     + "\n\nRunning `python .github/scripts/game_versions.py --tested` makes that change. "
                       "Release it as a beta: a tag with \"beta\" in its name, such as v1.2.3-beta1, is uploaded as a beta. "
                       "The full release follows once the patch is live and tested there.")
        body += "\n\nThis issue closes by itself once nothing is left to change or test.\n"
        if os.environ.get("RUNNER_TEMP"):
            open(os.path.join(os.environ["RUNNER_TEMP"], "game_versions.md"), "w", encoding="utf-8").write(body)
        print(title + "\n" + body)
    else:
        print("Up to date. Nothing to do.")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
            out.write("open=%s\ntitle=%s\n" % ("true" if changed or to_test else "false", title if changed or to_test else ""))


if __name__ == "__main__":
    main()
