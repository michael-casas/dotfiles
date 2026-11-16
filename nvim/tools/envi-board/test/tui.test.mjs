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

test("Ink resize/theme reuse settled success and failure without renderer calls or Ruby jobs", () => {
  const script = String.raw`
import os,pty,subprocess,select,time,fcntl,struct,sys,tempfile,json,signal,termios
with tempfile.TemporaryDirectory(prefix='board-ink-noop-') as folder:
 log=folder+'/jobs.log';board=folder+'/demo.wb.md';theme=folder+'/theme.json'
 open(log,'w').close()
 with open(sys.argv[3]) as f: text=f.read()
 start=text.index('sequenceDiagram');end=text.index('\x60\x60\x60',start)
 text=text[:start]+'flowchart LR\n A[First] --> B\n A[Second] --> C\n'+text[end:]
 with open(board,'w') as f: f.write(text)
 with open(sys.argv[4]) as f: hub=json.load(f)
 hub['active']='nord'
 with open(theme,'w') as f: json.dump(hub,f)
 master,slave=pty.openpty()
 fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',24,80,0,0))
 p=subprocess.Popen([sys.argv[1],sys.argv[2],'open','--',board],stdin=slave,stdout=slave,stderr=slave,
  env={**os.environ,'TERM':'xterm-256color','ENVI_THEME_FILE':theme,'ENVI_BOARD_TEST_RENDER_LOG':log,'NODE_OPTIONS':'--import='+sys.argv[5]})
 out=b''
 def pump(seconds):
  global out
  end=time.monotonic()+seconds
  while time.monotonic()<end:
   ready,_,_=select.select([master],[],[],0.02)
   if ready: out+=os.read(master,65536)
   assert p.poll() is None, out[-2000:]
 def jobs():
  with open(log) as f: return f.read().splitlines()
 try:
  deadline=time.monotonic()+6
  while len([x for x in jobs() if x.startswith('settled:')])<2 and time.monotonic()<deadline: pump(.05)
  before=jobs()
  assert before.count('ruby')==2 and before.count('render')==2,before
  assert 'settled:error' in before and 'settled:text-approximate' in before,before
  for width in [100,120,80]:
   fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',24,width,0,0));os.kill(p.pid,signal.SIGWINCH);pump(.15)
  hub['active']='gruvbox-dark'
  with open(theme,'w') as f: json.dump(hub,f)
  pump(.5)
  assert b'gruvbox-dark' in out,out[-2000:]
  assert jobs()==before, jobs()
  # A genuinely changed board still gets a pass; renderer cache reuses both outcomes.
  with open(board,'w') as f: f.write(text.replace('# File-first board viewer','# Changed board title'))
  deadline=time.monotonic()+4
  while jobs().count('render')<4 and time.monotonic()<deadline: pump(.05)
  pump(.15)
  assert jobs().count('render')==4,jobs()
  assert jobs().count('ruby')==2,jobs()
  os.write(master,b'q');p.wait(timeout=4);assert p.returncode==0
 finally:
  if p.poll() is None: p.kill();p.wait()
  os.close(master);os.close(slave)
`;
  const result = spawnSync(
    "python3",
    [
      "-c",
      script,
      process.execPath,
      main,
      path,
      new URL("../../../../theme/theme.json", import.meta.url).pathname,
      new URL("./fixtures/render-probe.mjs", import.meta.url).href,
    ],
    { encoding: "utf8", timeout: 15000 },
  );
  assert.equal(result.status, 0, result.stderr);
});

test("Ink resize and R recover a transient timeout without restarting successful diagrams", () => {
  const script = String.raw`
import os,pty,subprocess,select,time,fcntl,struct,sys,tempfile,signal,termios
for action in ['resize','R']:
 with tempfile.TemporaryDirectory(prefix='board-ink-retry-') as folder:
  log=folder+'/jobs.log';open(log,'w').close()
  master,slave=pty.openpty()
  fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',24,80,0,0))
  p=subprocess.Popen([sys.argv[1],sys.argv[2],'open','--',sys.argv[3]],stdin=slave,stdout=slave,stderr=slave,
   env={**os.environ,'TERM':'xterm-256color','ENVI_BOARD_TEST_RENDER_LOG':log,'ENVI_BOARD_TEST_TIMEOUT_ONCE':'1','NODE_OPTIONS':'--import='+sys.argv[4]})
  out=b''
  def jobs():
   with open(log) as f: return f.read().splitlines()
  def pump():
   global out
   ready,_,_=select.select([master],[],[],.03)
   if ready: out+=os.read(master,65536)
   assert p.poll() is None,out[-2000:]
  def settled(count):
   deadline=time.monotonic()+6
   while sum(x.startswith('settled:') for x in jobs())<count and time.monotonic()<deadline: pump()
   assert sum(x.startswith('settled:') for x in jobs())==count,jobs()
   # Drain Ink's repaint after the test probe records the promise settlement.
   for _ in range(4): pump()
  try:
   settled(2)
   assert jobs().count('ruby')==2 and 'settled:error' in jobs(),jobs()
   def trigger():
    if action=='R': os.write(master,b'R')
    else:
     fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',24,110,0,0));os.kill(p.pid,signal.SIGWINCH)
   trigger();settled(3)
   assert jobs().count('ruby')==3 and jobs().count('render')==3,jobs()
   assert jobs().count('settled:text-approximate')==2,jobs()
   trigger()
   for _ in range(10): pump()
   assert jobs().count('render')==3,jobs()
   os.write(master,b'q');p.wait(timeout=4);assert p.returncode==0
  finally:
   if p.poll() is None: p.kill();p.wait()
   os.close(master);os.close(slave)
`;
  const result = spawnSync(
    "python3",
    [
      "-c",
      script,
      process.execPath,
      main,
      path,
      new URL("./fixtures/render-probe.mjs", import.meta.url).href,
    ],
    { encoding: "utf8", timeout: 20000 },
  );
  assert.equal(result.status, 0, result.stderr);
});
