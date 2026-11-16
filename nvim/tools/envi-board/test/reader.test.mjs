import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync,readFileSync,writeFileSync,renameSync,unlinkSync,rmSync,statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
const main=new URL('../main.mjs',import.meta.url).pathname;
const example=readFileSync(new URL('./fixtures/example.wb.md',import.meta.url));
const cli=(...args)=>spawnSync(process.execPath,[main,...args],{encoding:'utf8',timeout:10000});

test('CLI render always escapes terminal bytes and preserves original Mermaid source',()=>{
 const dir=mkdtempSync(join(tmpdir(),'board-'));try {const path=join(dir,'demo.wb.md');writeFileSync(path,Buffer.concat([example,Buffer.from('\n\x1b]52;c;hostile\x07\n')])); const before=statSync(path);const r=cli('render','--',path);assert.equal(r.status,0,r.stderr);assert.ok(!r.stdout.includes('\x1b'));assert.match(r.stdout,/U\+001B/);assert.match(r.stdout,/flowchart LR/);assert.equal(statSync(path).mtimeMs,before.mtimeMs);}finally{rmSync(dir,{recursive:true});}
});
test('CLI strict unresolved references, unknown switches and non-TTY interactive refusal',()=>{
 const path=new URL('./fixtures/example.wb.md',import.meta.url).pathname;
 assert.equal(cli('validate','--json','--',path).status,0);
 assert.equal(cli('validate','--json','--strict','--',path).status,1);
 assert.equal(cli('open','--',path).status,2);
 assert.equal(cli('validate','--unrecognized','--',path).status,2);
});
test('session retains last good marked STALE on invalid/delete, recovers atomic saves, suppresses no-op, closes twice',async()=>{
 const { BoardSession }=await import('../session.mjs');
 const dir=mkdtempSync(join(tmpdir(),'board-')),path=join(dir,'demo.wb.md');writeFileSync(path,example);
 const s=new BoardSession({path});let count=0;const events=[];s.subscribe(x=>{count++;events.push(x);});
 try {await s.refresh();const hash=s.snapshot.document.hash;await s.refresh();assert.equal(count,1);
 writeFileSync(path,'broken');await s.refresh();assert.equal(s.snapshot.stale,true);assert.equal(s.snapshot.document.hash,hash);
 unlinkSync(path);await s.refresh();assert.equal(s.snapshot.stale,true);
 writeFileSync(path+'.tmp',example.toString().replace('# File-first board viewer','# New title'));renameSync(path+'.tmp',path);await s.refresh();assert.equal(s.snapshot.stale,false);assert.notEqual(s.snapshot.document.hash,hash);
 s.close();s.close();await s.refresh();assert.equal(s.closed,true);
 }finally{s.close();rmSync(dir,{recursive:true});}
});
test('directory watcher sees atomic replacement/deletion/recreation; initial invalid is raw safe source',async()=>{
 const {BoardSession}=await import('../session.mjs');const dir=mkdtempSync(join(tmpdir(),'board-')),path=join(dir,'demo.wb.md');writeFileSync(path,'invalid\x1b');
 const s=new BoardSession({path});s.start();
 const wait=async(fn)=>{for(let i=0;i<100;i++){if(fn())return;await new Promise(r=>setTimeout(r,20));}assert.fail('watch event not published');};
 try {await wait(()=>s.snapshot);assert.equal(s.snapshot.document.valid,false);
 writeFileSync(path+'.tmp',example);renameSync(path+'.tmp',path);await wait(()=>s.snapshot.document.valid);
 unlinkSync(path);await wait(()=>s.snapshot.stale);writeFileSync(path,example);await wait(()=>!s.snapshot.stale);
 }finally{s.close();rmSync(dir,{recursive:true});}
});
test('Ink viewport is bounded at short/80x24/wide sizes, safe and horizontally pans graph/source',async()=>{
 const {viewport}=await import('../view.mjs');
 for(const [width,height] of [[80,24],[150,40],[20,5]]) {const rows=viewport(['x'.repeat(1000),'🙂'.repeat(100),'last'],{width,height,top:0,left:0});assert.ok(rows.length<height);assert.ok(rows.every(s=>Array.from(s).length<=width));}
 assert.equal(viewport(['abcdef'],{width:3,height:5,left:2})[0],'cde');
});
