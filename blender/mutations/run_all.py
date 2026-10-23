"""Every mutation suite, one after another: proof that the checkers catch what they say they catch.

    python blender/mutations/run_all.py            every suite
    python blender/mutations/run_all.py 15 16      just those passes

Each passNN.py plants small, deliberate bugs in the source one at a time (a speed set back, a line
with a dash in it, a remote never made), runs the checker that should notice, and puts the file back
byte for byte, whatever happens. A MISSED line is a checker with a hole in it. Each suite refuses to
start unless its checkers pass first, so run blender/check_all.py before this.

Slow on purpose: every mutation is a full checker run. Expect a few minutes per suite.

SRC IS GUARDED HERE AS WELL. A suite puts its own files back, but on Windows a write can fail for a moment
(the file held open by a virus scanner or an indexer) and leave a planted bug in src, and then every suite
after it refuses to start. So this keeps a copy of every file under src from before the first suite, checks
src against it after each one, and puts back anything that differs (trying again for a few seconds if the
write fails), saying so. It ends by checking once more, and says loudly if src could not be put back.

AND WHAT THE SUITES MUTATE OUTSIDE SRC (since the hundred-and-twenty-second pass's run, when pass09's write failed on
blender/gen_serpent.py and left its planted bug there, so every Sunken City suite after it refused to start): the
Blender scripts and their measurements (blender/*.py, blender/*.json) and the sound generators (audio/*.py) are kept and
put back the same way.
"""
import pathlib
import re
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SRC = ROOT / "src"
OUTSIDE = (ROOT / "blender", "*.py"), (ROOT / "blender", "*.json"), (ROOT / "audio", "*.py")


def take_copy():
    kept = {path: path.read_bytes() for path in SRC.rglob("*") if path.is_file()}
    for folder, pattern in OUTSIDE:
        kept.update({path: path.read_bytes() for path in folder.glob(pattern) if path.is_file()})
    return kept


def write_back(path, data):
    for _ in range(20):
        try:
            path.write_bytes(data)
            return True
        except OSError:
            time.sleep(0.5)
    return False


def repair(kept):
    """Puts back every file under src that differs from `kept`; returns (repaired, could not)."""
    repaired, stuck = [], []
    for path, data in kept.items():
        try:
            same = path.exists() and path.read_bytes() == data
        except OSError:
            same = False
        if not same:
            (repaired if write_back(path, data) else stuck).append(path)
    for path in SRC.rglob("*"):
        if path.is_file() and path not in kept:
            stuck.append(path)
    return repaired, stuck


def main():
    wanted = {int(arg) for arg in sys.argv[1:] if arg.isdigit()}
    # Two digits, and from the hundredth pass three: every passNN.py, in the order of its number (by name, pass100
    # would come before pass11, and the old pattern left it out altogether).
    suites = sorted((p for p in HERE.glob("pass[0-9]*.py") if p.stem[4:].isdigit()), key=lambda p: int(p.stem[4:]))
    if wanted:
        suites = [s for s in suites if int(s.stem[4:]) in wanted]
    failed = []
    kept = take_copy()
    for suite in suites:
        # A SUITE THAT DIED ON A FILE ERROR (OSError: the file held for a moment by a virus scanner or an indexer) is
        # run again, after src is put back, up to twice: it says nothing about the checkers. Twice in a row on the
        # Sunken City's files in the sixty-fourth pass's run, and clean when run again.
        for attempt in range(3):
            result = subprocess.run([sys.executable, str(suite)], capture_output=True, text=True, cwd=str(HERE))
            out = result.stdout + result.stderr
            if result.returncode == 0 or "OSError" not in out or re.search(r"^\d+ of \d+ caught$", out, re.M):
                break
            repaired, stuck = repair(kept)
            if stuck:
                break
            print("%-10s a file error (%s); src put back, running it again" % (
                suite.stem, (out.strip().splitlines() or ["?"])[-1][:90]))
            time.sleep(2)
        summary = re.findall(r"^(\d+ of \d+ caught)$", out, re.M)
        missed = [line for line in out.splitlines() if line.startswith("MISSED")]
        status = summary[-1] if summary else "did not finish: " + (out.strip().splitlines() or ["no output"])[-1]
        print("%-10s %s" % (suite.stem, status))
        for line in missed:
            print("           " + line)
        if result.returncode != 0:
            failed.append(suite.stem)
        # SRC AS IT WAS, before the next suite starts on it.
        repaired, stuck = repair(kept)
        for path in repaired:
            print("           PUT BACK %s (the suite left it changed)" % path.relative_to(ROOT))
        if repaired and suite.stem not in failed:
            failed.append(suite.stem)
        if stuck:
            for path in stuck:
                print("           COULD NOT PUT BACK %s" % path.relative_to(ROOT))
            print("\nSTOPPED: src is not as it was; put those files back before going on.")
            return 2
    if failed:
        print("\nNOT CLEAN: " + ", ".join(failed))
        return 1
    print("\nevery planted bug was caught.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
