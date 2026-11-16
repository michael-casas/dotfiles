import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {realpathSync,mkdtempSync,writeFileSync,rmSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {diagramProfile} from '../profile.mjs';
import {DiagramRenderer,sandboxPolicy} from '../renderer.mjs';
const fixtures={
 flowchart:'flowchart LR\n A[Start] --> B{Ready?}\n B -->|yes| C[Ship]\n',
 sequence:'sequenceDiagram\n participant A as Alice\n participant B as Bob\n A->>B: Request\n B-->>A: Response\n',
 class:'classDiagram\n class Animal {\n +String name\n +move() void\n }\n class Duck {\n +quack() void\n }\n Animal <|-- Duck : extends\n',
 state:'stateDiagram-v2\n [*] --> Idle\n Idle --> Running : start\n Running --> [*] : finish\n',
 er:'erDiagram\n CUSTOMER ||--o{ ORDER : places\n CUSTOMER {\n int id PK\n string name\n }\n ORDER {\n int id PK\n }\n',
 gantt:'gantt\n title Release\n dateFormat YYYY-MM-DD\n section Build\n Design :d1, 2026-01-01, 2d\n Implement :d2, 2026-01-03, 1w\n',
};
test('all six corpus-profiled families render locally with original source; cache preserves revision',async()=>{
 const renderer=new DiagramRenderer();try{for(const [family,source]of Object.entries(fixtures)){assert.equal(diagramProfile(source).supported,true,`${family}: ${JSON.stringify(diagramProfile(source))}`);const start=performance.now();const r=await renderer.render(source,{revision:'a'});assert.equal(r.kind,'text-approximate',`${family}: ${JSON.stringify(r)}`);assert.equal(r.source,source);assert.ok(r.lines.length>0);assert.equal(r.family,family);assert.ok(performance.now()-start<5000);const warm=await renderer.render(source,{revision:'b'});assert.equal(warm.revision,'b');assert.deepEqual(warm.lines,r.lines);}}finally{renderer.close();}
});
test('complete allowlist rejects unprofiled tokens, configuration/resource channels and lost semantics',async()=>{
 const bad=['flowchart LR\n A --> B\n click A "https://example.invalid"','flowchart LR\n A --> B\n invalid @@ syntax','sequenceDiagram\n participant A\n alt valid\n end','stateDiagram-v2\n state A {\n [*] --> B\n }','classDiagram\n namespace Space {','erDiagram\n A ||--o{ B : <b>label</b>','gantt\n dateFormat YYYY-MM-DD HH:mm','gantt\n Task :done, a1, 2026-01-01, 2d','---\nconfig: x\n---\nflowchart LR\nA --> B','%%{init: {}}%%\nflowchart LR\nA --> B','flowchart LR\n A[<img src=x>] --> B','flowchart LR\n A[bad\x1b] --> B','flowchart LR\n A --> B; B --> C'];
 const r=new DiagramRenderer();try{for(const source of bad){assert.equal(diagramProfile(source).supported,false,source);const result=await r.render(source);assert.equal(result.kind,'unsupported');assert.equal(result.source,source);assert.equal(result.lines,undefined);}}finally{r.close();}
});
test('limits, incompatible Ruby, closed queue, timeout and output failure never publish partial graphs',async()=>{
 assert.equal(diagramProfile('flowchart LR\n'+Array.from({length:501},(_,i)=>` A${i} --> A${i+1}`).join('\n')).supported,false);
 assert.equal(diagramProfile('x'.repeat(51201)).supported,false);
 for(const opts of [{ruby:'/no/such/ruby'},{timeout:1},{maxOutput:1}]) {const r=new DiagramRenderer(opts);const value=await r.render(fixtures.flowchart);assert.equal(value.kind,'error');assert.equal(value.lines,undefined);r.close();r.close();}
 const r=new DiagramRenderer();r.close();assert.equal((await r.render(fixtures.flowchart)).kind,'unsupported');
});
test('actual isolation denies unrelated file read/write and child exec without attempting network',()=>{
 const dir=mkdtempSync(join(tmpdir(),'board-isolation-'));try {
 const file=join(dir,'sentinel');writeFileSync(file,'synthetic sentinel');
 const ruby=realpathSync('/opt/homebrew/opt/ruby/bin/ruby'),policy=sandboxPolicy(dirname(dirname(ruby)));
 const run=code=>spawnSync('/usr/bin/sandbox-exec',['-p',policy,ruby,'--disable-gems','-e',code],{encoding:'utf8',env:{PATH:'/usr/bin:/bin'},timeout:3000});
 assert.notEqual(run(`File.read(${JSON.stringify(file)})`).status,0);
 assert.notEqual(run(`File.write(${JSON.stringify(file)}, 'changed')`).status,0);
 assert.notEqual(run('exec "/bin/echo", "child"').status,0);
 assert.equal(readFileSync(file,'utf8'),'synthetic sentinel');
 assert.ok(!policy.includes('allow network'));
 }finally{rmSync(dir,{recursive:true});}
});
