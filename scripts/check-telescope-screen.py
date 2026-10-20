"""Run Telescope checks in a real terminal, including composed screen contents."""

import fcntl
import os
import pathlib
import pty
import select
import struct
import subprocess
import termios
import time


root = pathlib.Path(__file__).resolve().parent.parent
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 45, 180, 0, 0))
env = dict(os.environ, TERM="xterm-256color", TELESCOPE_CHECK_SCREEN="1")
process = subprocess.Popen(
    ["nvim", "-u", "NONE", "-i", "NONE", "-c", "luafile scripts/check-telescope.lua"],
    cwd=root,
    env=env,
    stdin=slave,
    stdout=slave,
    stderr=slave,
    start_new_session=True,
)
os.close(slave)
output = bytearray()
deadline = time.monotonic() + 30
try:
    while time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.1)
        if ready:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            output.extend(chunk)
        elif process.poll() is not None:
            break
    else:
        process.kill()
        raise RuntimeError("Telescope screen checks timed out")
    status = process.wait(timeout=5)
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    os.close(master)

if status:
    print(output.decode(errors="replace")[-6000:])
    raise SystemExit(status)
print("Telescope terminal screen checks passed")
