"""What to paste and import into Studio since you last did, worked out rather than remembered.

    python tools/paste_list.py                 what is new, changed or gone since the last --mark
    python tools/paste_list.py --since a8c356a what is new, changed or gone since that git commit
    python tools/paste_list.py --zip out.zip   the same, and every file of it in one zip
    python tools/paste_list.py --mark          you have pasted everything: remember this as the baseline

Nothing is synced into Studio: every Luau file is pasted by hand, every mesh and sound imported by hand.
The list of what changed used to be written out at the end of each round, from memory. This keeps a
fingerprint of every file under src/, meshes/ and audio/ (tools/.pasted.json) as it was when you last said
you had pasted, and lists what is different now, grouped by where it goes, in the order to do it: the
shared modules first (everything else requires them), then the server, then the client, then the meshes,
then the sounds, then what to delete. Each Luau file's place is read from its own line 2; each sound's
folder from the folder it was generated into.

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
WATCHED = [("src", "*.lua"), ("meshes", "*.fbx"), ("meshes", "*.obj"), ("audio", "*.wav")]
EXTENSIONS = (".lua", ".fbx", ".obj", ".wav")

# Where each folder of generated sounds goes (AudioService, Cinema and AmbienceService look there by name).
SOUND_FOLDERS = {
    "materials": "SoundService.MaterialSounds",
    "buttons": "SoundService.MaterialSounds",
    "sheets": "SoundService.MaterialSounds",  # four takes in one upload; keep the _x4 in the name
    "story": "SoundService.StorySounds",
    "endings": "SoundService.StorySounds",
    "ambience": "SoundService.AmbienceSounds",
    "lobby": "SoundService.LobbySounds",
    "water": "SoundService.WaterSounds",
    "shop": "SoundService.ShopSounds",
}

# The order to do it in, and the heading for each group.
GROUPS = [
    ("ReplicatedStorage/Shared", "Shared modules (ReplicatedStorage.Shared): paste these first"),
    ("ServerScriptService", "Server (ServerScriptService)"),
    ("StarterPlayerScripts", "Client (StarterPlayerScripts)"),
    ("mesh", "Meshes (Asset Manager; where HANDOFF says)"),
    ("sound", "Sounds (Asset Manager, then into the SoundService folder named)"),
    ("other", "Other"),
]


def fingerprint():
    found = {}
    for folder, pattern in WATCHED:
        base = ROOT / folder
        if base.exists():
            for path in base.rglob(pattern):
                found[path.relative_to(ROOT).as_posix()] = hashlib.sha1(path.read_bytes()).hexdigest()
    return found


def studio_place(rel):
    """Where a file goes, and which group it is listed in."""
    path = ROOT / rel
    if rel.endswith(".wav"):
        parts = rel.split("/")
        folder = SOUND_FOLDERS.get(parts[1] if len(parts) > 2 else "", "SoundService (see SOUND_BRIEF.md)")
        return "sound", "%s, named %s" % (folder, path.stem)
    if not rel.endswith(".lua"):
        return "mesh", "import, then put where HANDOFF says (named %s)" % path.stem
    for line in path.read_text(encoding="utf-8").splitlines()[:3]:
        text = line.strip()
        if text.startswith("--") and ".lua" in text and "/" in text:
            place = text.lstrip("- ").strip()
            kind = "Script" if ".server.lua" in place else "LocalScript" if ".client.lua" in place else "ModuleScript"
            where = place.rsplit(".lua", 1)[0].replace(".server", "").replace(".client", "")
            group = next((g for g, _ in GROUPS if where.startswith(g)), "other")
            return group, "%s  (%s)" % (where, kind)
    return "other", "(line 2 names no Studio path: check the file)"


def git_changes(argv_since):
    """NEW / CHANGED / GONE since a git commit (`--since REF`) or since the last commit."""
    changed = {}
    if argv_since:
        out = subprocess.run(["git", "diff", "--name-status", argv_since, "--", "src", "meshes", "audio"],
                             capture_output=True, text=True, cwd=str(ROOT)).stdout
        for line in out.splitlines():
            state, _, rel = line.partition("\t")
            rel = rel.strip()
            if rel.endswith(EXTENSIONS):
                changed[rel] = "NEW" if state.startswith("A") else "GONE" if state.startswith("D") else "CHANGED"
    out = subprocess.run(["git", "status", "--porcelain", "--", "src", "meshes", "audio"], capture_output=True,
                         text=True, cwd=str(ROOT)).stdout
    for line in out.splitlines():
        state, rel = line[:2], line[3:].strip().strip('"')
        if rel.endswith("/"):
            for path in (ROOT / rel).rglob("*"):
                if path.is_file() and path.name.endswith(EXTENSIONS):
                    changed[path.relative_to(ROOT).as_posix()] = "NEW"
        elif rel.endswith(EXTENSIONS):
            if "?" in state or "A" in state:
                changed[rel] = "NEW"
            elif "D" in state:
                changed[rel] = "GONE"
            else:
                changed.setdefault(rel, "CHANGED")
    return changed


def main(argv):
    now = fingerprint()
    if "--mark" in argv:
        MANIFEST.write_text(json.dumps(now, indent=1, sort_keys=True), encoding="utf-8")
        print("baseline marked: %d files as they are now. The next list starts from here." % len(now))
        return 0
    since_ref = argv[argv.index("--since") + 1] if "--since" in argv and argv.index("--since") + 1 < len(argv) else None
    if since_ref:
        changes = git_changes(since_ref)
        since = "since git commit %s" % since_ref
    elif MANIFEST.exists():
        before = json.loads(MANIFEST.read_text(encoding="utf-8"))
        changes = {rel: "NEW" for rel in now if rel not in before}
        changes.update({rel: "CHANGED" for rel in now if rel in before and before[rel] != now[rel]})
        changes.update({rel: "GONE" for rel in before if rel not in now})
        since = "since the last --mark"
    else:
        changes = git_changes(None)
        since = "since the last git commit (no baseline yet: run with --mark once you have pasted everything)"
    if not changes:
        print("nothing to paste %s." % since)
        return 0
    print("%d file(s) %s:" % (len(changes), since))
    placed = {rel: studio_place(rel) for rel, state in changes.items() if state != "GONE"}
    for group, heading in GROUPS:
        rows = sorted(rel for rel in placed if placed[rel][0] == group)
        if rows:
            print("\n%s" % heading)
            for rel in rows:
                print("  %-7s %-48s -> %s" % (changes[rel], rel, placed[rel][1]))
    gone = sorted(rel for rel, state in changes.items() if state == "GONE")
    if gone:
        print("\nGone from the repo: delete these in Studio too")
        for rel in gone:
            print("  GONE    %s" % rel)
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
