#!/usr/bin/env python3
"""Private-core synthetic history rebuild, action 7 and action 9 peer."""
import os
import re
import sys
import tty

tty.setraw(sys.stdin.fileno())
for i in range(100):
    sys.stdout.write(f"OLD_HISTORY_{i}\r\n")
sys.stdout.write("CORE_PEER_READY\r\n")
sys.stdout.flush()
pending = b""
while True:
    chunk = os.read(sys.stdin.fileno(), 4096)
    if not chunk:
        break
    pending += chunk
    if b"REBUILD" in pending:
        pending = pending.replace(b"REBUILD", b"")
        cols, rows = os.get_terminal_size()
        sys.stdout.write("\x1b[2J\x1b[3J\x1b[H")
        for i in range(40):
            sys.stdout.write(f"NEW_HISTORY_{i}\r\n")
        sys.stdout.write(f"\x1b]7503;envi-t3-layout=0;cols={cols};rows={rows};frozen=60;reflowed=1\x1b\\")
        sys.stdout.flush()
    while True:
        match = re.search(rb"\x1b\[>777;([79]);([0-9]+)u", pending)
        if not match:
            break
        action, request_id = match.group(1), match.group(2).decode()
        pending = pending[match.end():]
        if action == b"7":
            sys.stdout.write(f"\x1b]7502;envi-t3-escape={request_id};overlay=0\x1b\\")
        else:
            cols, rows = os.get_terminal_size()
            sys.stdout.write(f"\x1b]7503;envi-t3-layout={request_id};cols={cols};rows={rows};frozen={cols};reflowed=0\x1b\\")
        sys.stdout.flush()
