"""Every checker in one go, with one line each and one exit code.

    python blender/check_all.py

The checkers catch, without opening Studio, what has cost a round of play before: a file that will
not parse or reads a name that does not exist, a local limit Luau refuses to load past, a level whose
route meets itself or hangs a platform in the air, a remote that is never made, a line with a dash
in it. Run this before pasting anything, and blender/mutations/run_all.py to prove the checkers
themselves still catch what they say they do.
"""
import pathlib
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
CHECKERS = [
    "check_luau_syntax", "check_lua", "check_story", "check_hub", "check_chunk_forms", "check_plan_shapes",
    "check_halls", "check_skypools", "check_sunkencity",
]


def main():
    failed = []
    for name in CHECKERS:
        began = time.time()
        result = subprocess.run([sys.executable, str(HERE / (name + ".py"))], capture_output=True, text=True, cwd=str(HERE))
        lines = [line for line in (result.stdout + result.stderr).strip().splitlines() if line.strip()]
        last = lines[-1] if lines else "(no output)"
        mark = "ok  " if result.returncode == 0 else "FAIL"
        print("%s %-18s %4.1fs  %s" % (mark, name, time.time() - began, last[:110]))
        if result.returncode != 0:
            failed.append(name)
            for line in lines[-12:]:
                print("       " + line)
    if failed:
        print("\n%d of %d checkers failed: %s" % (len(failed), len(CHECKERS), ", ".join(failed)))
        return 1
    print("\nall %d checkers pass." % len(CHECKERS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
