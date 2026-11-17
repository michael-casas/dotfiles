#!/usr/bin/env python3
"""Synthetic raw PTY peer; implements only fixed action 9, never hc/T3."""
import os
import re
import signal
import sys
import termios
import tty

tty.setraw(sys.stdin.fileno())
count = 0


def resized(_sig, _frame):
    global count
    count += 1
    sys.stdout.write(f"\r\nWINCH={count}\r\n")
    sys.stdout.flush()


signal.signal(signal.SIGWINCH, resized)
sys.stdout.write("LAYOUT_READY\r\n")
sys.stdout.flush()
pending = b""
while True:
    chunk = os.read(sys.stdin.fileno(), 4096)
    if not chunk:
        break
    pending += chunk
    while True:
        match = re.search(rb"\x1b\[>777;9;([0-9]+)u", pending)
        if not match:
            break
        request_id = match.group(1).decode()
        pending = pending[match.end():]
        cols, rows = os.get_terminal_size(sys.stdout.fileno())
        sys.stdout.write(
            f"\x1b]7503;envi-t3-layout={request_id};cols={cols};rows={rows};frozen=60;reflowed=0\x1b\\"
        )
        sys.stdout.flush()
