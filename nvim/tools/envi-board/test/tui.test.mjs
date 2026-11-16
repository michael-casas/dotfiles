import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
const main = new URL("../main.mjs", import.meta.url).pathname;
const path = new URL("./fixtures/example.wb.md", import.meta.url).pathname;

test("real foreground Ink owns/restores raw mode, renders at 80x24 and exits on q; no alternate screen/mouse", () => {
  const script = String.raw`
import os,pty,subprocess,select,time,termios,fcntl,struct,sys
master,slave=pty.openpty()
fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',24,80,0,0))
before=termios.tcgetattr(slave)
p=subprocess.Popen([sys.argv[1],sys.argv[2],'open','--',sys.argv[3]],stdin=slave,stdout=slave,stderr=slave,env={**os.environ,'TERM':'xterm-256color'})
out=b''; end=time.monotonic()+6; sent=False
while time.monotonic()<end and p.poll() is None:
 ready,_,_=select.select([master],[],[],0.05)
 if ready:
  out+=os.read(master,65536)
  if b'BOARD' in out and not sent:
   fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',12,60,0,0))
   os.kill(p.pid,28)
   os.write(master,b'q');sent=True
if p.poll() is None:
 p.kill();p.wait();raise Exception('foreground did not exit')
after=termios.tcgetattr(slave)
assert sent and p.returncode==0,(p.returncode,out[-2000:])
assert before[3]&termios.ICANON==after[3]&termios.ICANON
assert before[3]&termios.ECHO==after[3]&termios.ECHO
assert b'\x1b[?1049' not in out
assert b'\x1b[?100' not in out
os.close(master);os.close(slave)
print('foreground PTY/raw-mode smoke passed')
`;
  const r = spawnSync("python3", ["-c", script, process.execPath, main, path], {
    encoding: "utf8",
    timeout: 10000,
  });
  assert.equal(r.status, 0, r.stderr);
});
