"""Every mutation suite, one after another: proof that the checkers catch what they say they catch.

    python blender/mutations/run_all.py            every suite
    python blender/mutations/run_all.py 15 16      just those passes

Each passNN.py plants small, deliberate bugs in the source one at a time (a speed set back, a line
with a dash in it, a remote never made), runs the checker that should notice, and puts the file back
byte for byte, whatever happens. A MISSED line is a checker with a hole in it. Each suite refuses to
start unless its checkers pass first, so run blender/check_all.py before this.

Slow on purpose: every mutation is a full checker run. Expect a few minutes per suite.
"""
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent


def main():
    wanted = {int(arg) for arg in sys.argv[1:] if arg.isdigit()}
    suites = sorted(HERE.glob("pass[0-9][0-9].py"))
    if wanted:
        suites = [s for s in suites if int(s.stem[4:]) in wanted]
    failed = []
    for suite in suites:
        result = subprocess.run([sys.executable, str(suite)], capture_output=True, text=True, cwd=str(HERE))
        out = result.stdout + result.stderr
        summary = re.findall(r"^(\d+ of \d+ caught)$", out, re.M)
        missed = [line for line in out.splitlines() if line.startswith("MISSED")]
        status = summary[-1] if summary else "did not finish: " + (out.strip().splitlines() or ["no output"])[-1]
        print("%-10s %s" % (suite.stem, status))
        for line in missed:
            print("           " + line)
        if result.returncode != 0:
            failed.append(suite.stem)
    if failed:
        print("\nNOT CLEAN: " + ", ".join(failed))
        return 1
    print("\nevery planted bug was caught.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
