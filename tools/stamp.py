"""Each module's fingerprint, so the paste check can tell a current copy in Studio from an old one.

    python tools/stamp.py              refresh every stamped module's STAMP, and the list in Bootstrap.server
    python tools/stamp.py --add A B    stamp these modules too (by name)

A stamped module carries `Name.STAMP = "1a2b3c4d"` on the line before its last `return Name` (or a first field
`STAMP = "1a2b3c4d",` when it ends by returning a table it builds there): the first eight hex digits of a SHA-1
of the file with that line taken out, line endings ignored. Bootstrap.server holds what every stamp should be
(between the PASTE STAMPS markers, written here); in Studio the paste check compares the two and names any
module whose STAMP is not the one expected, which is an old copy. check_stamps.py fails when a stamped file has
changed since it was stamped, or when a module changed since the last commit is not stamped: run this then.
"""
import hashlib
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
KINDS = (("shared", SRC / "Shared"), ("server", SRC / "Server" / "Services"), ("client", SRC / "Client" / "Services"))
BOOT = SRC / "Server" / "Bootstrap.server.lua"
STAMP_LINE = re.compile(r'^(?:\w+\.STAMP = "[0-9a-f]{8}"|\tSTAMP = "[0-9a-f]{8}",)\n', re.M)
BEGIN = "-- PASTE STAMPS (written by tools/stamp.py, not by hand): what each module's STAMP says when it is current."
END = "-- END PASTE STAMPS"
BASELINE = "a8c356a"  # the last commit: anything changed since it is part of the next paste, so it is stamped


def modules():
    """name -> (kind, path) for every ModuleScript in src."""
    found = {}
    for kind, folder in KINDS:
        for path in sorted(folder.glob("*.lua")):
            found[path.stem] = (kind, path)
    return found


def read(path):
    raw = path.read_bytes().decode("utf-8")
    return raw.replace("\r\n", "\n"), "\r\n" in raw


def fingerprint(text):
    return hashlib.sha1(STAMP_LINE.sub("", text).encode("utf-8")).hexdigest()[:8]


def stamp_of(text):
    found = re.search(r'^(?:\w+\.STAMP = "([0-9a-f]{8})"|\tSTAMP = "([0-9a-f]{8})",)$', text, re.M)
    return (found.group(1) or found.group(2)) if found else None


def place(name, text, stamp):
    """The file with its stamp line in place (any old one taken out)."""
    lines = STAMP_LINE.sub("", text).split("\n")
    last = len(lines) - 1
    while last >= 0 and not lines[last].strip():
        last -= 1
    if lines[last].strip() == "return " + name:
        lines.insert(last, '%s.STAMP = "%s"' % (name, stamp))
    else:
        opening = [k for k, line in enumerate(lines) if line.rstrip() == "return {"]
        if not opening:
            raise SystemExit("%s does not end in `return %s` or `return {`: it cannot carry a stamp" % (name, name))
        lines.insert(opening[-1] + 1, '\tSTAMP = "%s",' % stamp)
    return "\n".join(lines)


def changed_since_baseline():
    """Module names changed (or new) since BASELINE, by git."""
    names = set()
    out = subprocess.run(["git", "diff", "--name-only", BASELINE, "--", "src"], capture_output=True, text=True,
                         cwd=str(ROOT)).stdout
    out += subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "--", "src"], capture_output=True,
                          text=True, cwd=str(ROOT)).stdout
    for line in out.splitlines():
        path = pathlib.Path(line.strip())
        if path.suffix == ".lua" and not path.name.endswith((".server.lua", ".client.lua")):
            names.add(path.stem)
    return names


def block(stamps):
    """The PASTE STAMPS block for Bootstrap.server."""
    out = [BEGIN, "local PASTE_STAMPS: { [string]: { [string]: string } } = {"]
    for kind, _ in KINDS:
        out.append("\t%s = {" % kind)
        for name in sorted(n for n, (k, _) in stamps.items() if k == kind):
            out.append('\t\t%s = "%s",' % (name, stamps[name][1]))
        out.append("\t},")
    out.append("}")
    out.append(END)
    return "\n".join(out)


def main(argv):
    found = modules()
    add = set(argv[argv.index("--add") + 1:]) if "--add" in argv else set()
    unknown = sorted(add - set(found))
    if unknown:
        raise SystemExit("no module called %s" % ", ".join(unknown))
    stamps = {}
    for name, (kind, path) in found.items():
        text, crlf = read(path)
        if stamp_of(text) is None and name not in add:
            continue
        stamp = fingerprint(text)
        new = place(name, text, stamp)
        if new != text:
            path.write_bytes((new.replace("\n", "\r\n") if crlf else new).encode("utf-8"))
        stamps[name] = (kind, stamp)
    boot, crlf = read(BOOT)
    start, finish = boot.find(BEGIN), boot.find(END)
    if start < 0 or finish < 0:
        raise SystemExit("Bootstrap.server has no PASTE STAMPS block to write into")
    boot = boot[:start] + block(stamps) + boot[finish + len(END):]
    BOOT.write_bytes((boot.replace("\n", "\r\n") if crlf else boot).encode("utf-8"))
    missing = sorted(changed_since_baseline() & set(found) - set(stamps))
    print("%d modules stamped." % len(stamps))
    if missing:
        print("changed since %s and not stamped (python tools/stamp.py --add %s)" % (BASELINE, " ".join(missing)))


if __name__ == "__main__":
    main(sys.argv[1:])
