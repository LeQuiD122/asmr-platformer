"""What to paste into Studio since you last did, worked out rather than remembered.

    python tools/paste_list.py              what is new or changed since the last --mark
    python tools/paste_list.py --zip out.zip   the same, and every file of it in one zip
    python tools/paste_list.py --mark       you have pasted everything: remember this as the baseline

Nothing is synced into Studio: every Luau file is pasted by hand and every mesh imported by hand. The
list of what changed used to be written out at the end of each round, from memory. This keeps a
fingerprint of every file under src/ and meshes/ (tools/.pasted.json) as it was when you last said you
had pasted, and lists what is different now, with where each file goes in Studio (line 2 of every
Luau file names it) and whether it is new.

With no baseline yet, it lists what git says has changed since the last commit.
"""
import hashlib
import json
import pathlib
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "tools" / ".pasted.json"
WATCHED = [("src", "*.lua"), ("meshes", "*.fbx"), ("meshes", "*.obj")]


def fingerprint():
    found = {}
    for folder, pattern in WATCHED:
        for path in (ROOT / folder).rglob(pattern):
            found[path.relative_to(ROOT).as_posix()] = hashlib.sha1(path.read_bytes()).hexdigest()
    return found


def studio_place(rel):
    """Where a file goes: the first comment in its first three lines that names a .lua path."""
    path = ROOT / rel
    if not rel.endswith(".lua"):
        return "import into Studio (Asset Manager) and put where HANDOFF says"
    for line in path.read_text(encoding="utf-8").splitlines()[:3]:
        text = line.strip()
        if text.startswith("--") and ".lua" in text and "/" in text:
            place = text.lstrip("- ").strip()
            kind = "Script" if ".server.lua" in place else "LocalScript" if ".client.lua" in place else "ModuleScript"
            return "%s  (%s)" % (place.rsplit(".lua", 1)[0].replace(".server", "").replace(".client", ""), kind)
    return "(line 2 names no Studio path: check the file)"


def from_git():
    out = subprocess.run(["git", "status", "--porcelain", "--", "src", "meshes"], capture_output=True, text=True,
                         cwd=str(ROOT)).stdout
    changed = {}
    for line in out.splitlines():
        state, rel = line[:2], line[3:].strip().strip('"')
        if rel.endswith("/"):
            for path in (ROOT / rel).rglob("*"):
                if path.is_file():
                    changed[path.relative_to(ROOT).as_posix()] = "NEW"
        elif rel.endswith((".lua", ".fbx", ".obj")):
            changed[rel] = "NEW" if "?" in state or "A" in state else "GONE" if "D" in state else "CHANGED"
    return changed


def main(argv):
    now = fingerprint()
    if "--mark" in argv:
        MANIFEST.write_text(json.dumps(now, indent=1, sort_keys=True), encoding="utf-8")
        print("baseline marked: %d files as they are now. The next list starts from here." % len(now))
        return 0
    if MANIFEST.exists():
        before = json.loads(MANIFEST.read_text(encoding="utf-8"))
        changes = {rel: "NEW" for rel in now if rel not in before}
        changes.update({rel: "CHANGED" for rel in now if rel in before and before[rel] != now[rel]})
        changes.update({rel: "GONE" for rel in before if rel not in now})
        since = "since the last --mark"
    else:
        changes = from_git()
        since = "since the last git commit (no baseline yet: run with --mark once you have pasted everything)"
    if not changes:
        print("nothing to paste %s." % since)
        return 0
    print("%d file(s) to paste %s:\n" % (len(changes), since))
    for state in ("NEW", "CHANGED", "GONE"):
        for rel in sorted(r for r, s in changes.items() if s == state):
            if state == "GONE":
                print("  %-7s %-52s delete it in Studio too" % (state, rel))
            else:
                print("  %-7s %-52s -> %s" % (state, rel, studio_place(rel)))
    if "--zip" in argv:
        index = argv.index("--zip")
        target = pathlib.Path(argv[index + 1] if index + 1 < len(argv) else "paste.zip")
        with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as bundle:
            for rel, state in sorted(changes.items()):
                if state != "GONE":
                    bundle.write(ROOT / rel, rel)
        print("\nzipped to %s" % target.resolve())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
