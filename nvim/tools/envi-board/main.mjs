#!/usr/bin/env node
import { resolve } from 'node:path';
import { readBoard,BoardSession } from './session.mjs';
import { project } from './view.mjs';
import { safeText } from './document.mjs';

function options(args) {
  const opts={bindings:{}};let end=false;
  for(let i=0;i<args.length;i++) {const arg=args[i];
    if(!end&&arg==='--'){end=true;continue;}
    if(!end&&['--json','--strict','--render-check'].includes(arg)){opts[arg.slice(2)]=true;continue;}
    if(!end&&arg==='--bind'){const value=args[++i]??'',at=value.indexOf('=');if(at<1)throw Error('Expected --bind alias=/absolute/git/root');const name=value.slice(0,at),path=value.slice(at+1);if(!/^[a-z][a-z0-9-]{0,63}$/.test(name)||!path.startsWith('/'))throw Error('Binding needs alias and absolute root');opts.bindings[name]=path;continue;}
    if(!end&&arg.startsWith('-'))throw Error('Unknown option');
    if(opts.path)throw Error('Expected one board path');opts.path=resolve(arg);
  }return opts;
}

async function main() {
  const [op,...args]=process.argv.slice(2),opts=options(args);
  if(!['validate','render','open','worker'].includes(op)||(!opts.path&&op!=='worker'))throw Error('Usage: envi-board validate|render|open [--json] [--strict] [--bind alias=/root] -- path.wb.md');
  if(op==='open') {
    if(!process.stdin.isTTY||!process.stdout.isTTY)throw Error('open requires an interactive TTY; use render');
    const {openTui}=await import('./tui.mjs');await openTui(opts);return;
  }
  if(op==='worker') {const {worker}=await import('./worker.mjs');await worker();return;}
  const document=await readBoard(opts.path);
  const valid=document.valid && !(opts.strict&&document.diagnostics.some(d=>['source-unbound','attachment','unsupported'].includes(d.code)));
  if(op==='validate') {
    const output={valid,opaque:document.opaque,hash:document.hash,diagnostics:document.diagnostics};
    console.log(opts.json?JSON.stringify(output):`${valid?'VALID':'INVALID'}\n${output.diagnostics.map(d=>`[${d.code}] ${d.message}`).join('\n')}`);
    if(!valid)process.exitCode=1;
  } else {const snapshot={document,diagnostics:document.diagnostics};console.log(project(snapshot).rows.join('\n'));if(!document.valid)process.exitCode=1;}
}
main().catch(()=>{process.stderr.write(safeText('envi-board: invalid arguments or board unavailable; use validate|render|open [--json] [--strict] [--bind alias=/absolute/root] -- path.wb.md\n'));process.exitCode=2;});
