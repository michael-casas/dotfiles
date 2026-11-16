"""Run a program on a real pseudo-terminal and relay its raw output.

  python3 pty-run.py ROWS COLS -- PROGRAM [ARGS...]

stdout: the child's raw terminal output, unmodified.
stdin, one command per line:
  resize ROWS COLS   TIOCSWINSZ on the PTY; the kernel sends SIGWINCH
  input HEX          Send literal hex-encoded input bytes to the PTY
  stop               SIGTERM the child
EOF on stdin also stops the child. Exits with the child's status.
"""
import fcntl
import os
import select
import signal
import struct
import subprocess
import sys
import termios


def winsize(fd, rows, cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


def main():
    rows, cols = int(sys.argv[1]), int(sys.argv[2])
    argv = sys.argv[sys.argv.index("--") + 1:]
    master, slave = os.openpty()
    winsize(slave, rows, cols)

    def controlling_tty():
        # start_new_session already called setsid(); adopt the PTY so the
        # kernel delivers SIGWINCH to this session on resize.
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    child = subprocess.Popen(
        argv, stdin=slave, stdout=slave, stderr=slave, start_new_session=True, preexec_fn=controlling_tty
    )
    os.close(slave)
    out = sys.stdout.buffer
    stdin = sys.stdin.buffer
    pending = b""
    stdin_open = True
    while True:
        fds = [master] + ([stdin] if stdin_open else [])
        ready, _, _ = select.select(fds, [], [], 0.05)
        if master in ready:
            try:
                data = os.read(master, 65536)
            except OSError:
                data = b""
            if not data:
                break
            out.write(data)
            out.flush()
        if stdin_open and stdin in ready:
            chunk = os.read(stdin.fileno(), 4096)
            if not chunk:
                stdin_open = False
                child.send_signal(signal.SIGTERM)
                continue
            pending += chunk
            while b"\n" in pending:
                line, pending = pending.split(b"\n", 1)
                cmd = line.decode().split()
                if cmd and cmd[0] == "resize":
                    winsize(master, int(cmd[1]), int(cmd[2]))
                elif cmd and cmd[0] == "input":
                    os.write(master, bytes.fromhex(cmd[1]))
                elif cmd and cmd[0] == "stop":
                    child.send_signal(signal.SIGTERM)
        if child.poll() is not None and master not in ready:
            # Drain whatever is still buffered, then stop.
            try:
                while True:
                    r, _, _ = select.select([master], [], [], 0.05)
                    if not r:
                        break
                    data = os.read(master, 65536)
                    if not data:
                        break
                    out.write(data)
                    out.flush()
            except OSError:
                pass
            break
    os.close(master)
    sys.exit(child.wait() & 0xFF)


if __name__ == "__main__":
    main()
