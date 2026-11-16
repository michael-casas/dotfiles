import { LIMITS } from './document.mjs';

// Complete-line productions, not a forbidden-word blacklist. Anything not
// consumed by this tiny grammar remains source, including newer Mermaid syntax.
const ID='[A-Za-z][A-Za-z0-9_]{0,63}';
const LABEL='[\\p{L}\\p{N} _.,?!()\\-]{1,120}';
const match=(line,pattern)=>line.match(new RegExp(`^${pattern}$`,'u'));
export const PROFILE='envi-text-v0.1';
export function diagramProfile(source) {
  const no=reason=>({supported:false,reason});
  if(Buffer.byteLength(source)>LIMITS.diagram)return no('diagram byte limit');
  const lines=source.replaceAll('\r\n','\n').split('\n').map(s=>s.trim()).filter(Boolean);
  const first=lines.shift();let family,nodes=new Set(),edges=0;
  const node=`(${ID})(?:\\[(${LABEL})\\]|\\{(${LABEL})\\})?`;
  if(match(first??'','(?:flowchart|graph) (?:LR|RL|TD|TB|BT)')) {
    family='flowchart';
    for(const line of lines) {
      const m=match(line,`${node} --> (?:\\|(${LABEL})\\| )?${node}`)??match(line,`${node} -->\\|(${LABEL})\\| ${node}`);
      if(!m)return no('flowchart: only single --> edges with basic rectangular/decision nodes and plain labels');
      nodes.add(m[1]); // Count IDs lexically; each accepted edge has two endpoints.
      const right=line.split(/-->(?:\|[^|]+\|)?/).at(-1).trim().match(/^[A-Za-z][A-Za-z0-9_]*/);if(right)nodes.add(right[0]);edges++;
    }
  } else if(first==='sequenceDiagram') {
    family='sequence';const declared=new Set();
    for(const line of lines) {
      const p=match(line,`participant (${ID})(?: as (${LABEL}))?`);
      if(p){declared.add(p[1]);nodes.add(p[1]);continue;}
      const m=match(line,`(${ID})(?:->>|-->>)(${ID}): (${LABEL})`);
      if(!m||!declared.has(m[1])||!declared.has(m[2]))return no('sequence: declared participants and basic ->>/-->> messages only; no frames or activation');edges++;
    }
  } else if(first==='classDiagram') {
    family='class';let inside=false;
    for(const line of lines) {
      const c=match(line,`class (${ID}) \\{`);
      if(!inside&&c){inside=true;nodes.add(c[1]);continue;}
      if(inside&&line==='}'){inside=false;continue;}
      if(inside&&match(line,`[+~-]?(?:${ID} ${ID}|${ID}\\(\\)(?: ${ID})?)`))continue;
      const relation=match(line,`(${ID}) <\\|-- (${ID})(?: : (${LABEL}))?`);
      if(!inside&&relation&&nodes.has(relation[1])&&nodes.has(relation[2])){edges++;continue;}
      return no('class: simple class members/no-argument methods and declared inheritance only');
    }if(inside)return no('class: unclosed compartment');
  } else if(first==='stateDiagram-v2') {
    family='state';
    for(const line of lines) {
      const m=match(line,`(${ID}|\\[\\*\\]) --> (${ID}|\\[\\*\\])(?: : (${LABEL}))?`);
      if(!m)return no('state: flat transitions only; no composites/choice/fork');nodes.add(m[1]);nodes.add(m[2]);edges++;
    }
  } else if(first==='erDiagram') {
    family='er';let inside=false;
    for(const line of lines) {
      const c=match(line,`(${ID}) \\{`);if(!inside&&c){inside=true;nodes.add(c[1]);continue;}
      if(inside&&line==='}'){inside=false;continue;}
      if(inside&&match(line,`${ID} ${ID}(?: (?:PK|FK|UK))?`))continue;
      const m=match(line,`(${ID}) (?:\\|\\||o\\||\\|o|\\}o|\\}\\|)(?:--)(?:\\|\\||\\|o|o\\||o\\{|\\|\\{) (${ID}) : (${LABEL})`);
      if(!inside&&m){nodes.add(m[1]);nodes.add(m[2]);edges++;continue;}
      return no('ER: basic entities, scalar attributes/keys and simple cardinalities only');
    }if(inside)return no('ER: unclosed entity');
  } else if(first==='gantt') {
    // The research exposed omitted done/active semantics. Reject status flags,
    // dependency scheduling and milestones, rather than claiming a full chart.
    family='gantt';
    for(const line of lines) {
      if(line==='dateFormat YYYY-MM-DD'||match(line,`(?:title|section) ${LABEL}`))continue;
      const m=match(line,`(${LABEL}) :(${ID}), (\\d{4}-\\d{2}-\\d{2}), ([1-9]\\d{0,2})([dw])`);
      if(!m||Number.isNaN(Date.parse(m[3]))||new Date(m[3]).toISOString().slice(0,10)!==m[3])return no('gantt: day/week dated summary only, no states/milestones/after/hourly axis');nodes.add(m[2]);
    }
  } else return no('unknown or unprofiled Mermaid family/configuration');
  if(!lines.length)return no('empty diagram');
  if(nodes.size>500||edges>500)return no('diagram node/edge limit');
  return {supported:true,family,nodes:nodes.size,edges,profile:PROFILE};
}
