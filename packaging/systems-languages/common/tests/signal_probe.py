#!/usr/bin/env python3
import os
import subprocess
import sys
import time


def main() -> int:
    if sys.argv[1:] != ["--signal-probe"]:
        return 2
    evidence = os.environ.get("SSHFLING_SIGNAL_EVIDENCE", "")
    if not evidence:
        return 2
    child = subprocess.Popen(
        [sys.executable, "-c", "import time; time.sleep(300)"],
        stdin=subprocess.DEVNULL,
    )
    with open(evidence, "w", encoding="ascii") as handle:
        handle.write(f"{child.pid}\n")
        handle.flush()
        os.fsync(handle.fileno())
    while True:
        time.sleep(300)


if __name__ == "__main__":
    raise SystemExit(main())
