

```json
{
"map":{"a":"agent","r":"role","i":"input","p":"phases","u":"rules","d":"delegation","h":"halt","o":"output","env":"envelope","pay":"payload","req":"required","opt":"optional","mod":"mode","inl":"input_list","out":"output_list","dir":"directive","scp":"scope","gph":"graph_state","ctx":"context","nod":"nodes","edg":"edges","fnd":"findings","amb":"ambiguities","mut":"mutations","ops":"operations","tgt":"target","sym":"symbol","lns":"lines","rsn":"reason","sta":"status","typ":"type","cod":"code","msg":"message","law":"laws","pri":"priority","outp":"output_payload","hlt":"halt_payload","t":"targets","b":"boundaries","L":"laws","ref":"authoritative_anchor","ids":"identifiers","op_id":"operation_id","directive_id":"directive_id"},

"_layer":"OPENCODE_EXEC_REGISTRY",

"a":"SYS_EXEC",
"r":"COLD_DIRECTIVE_EXECUTOR",

"law":[
  "NO_PROSE",
  "NO_PARTIAL_OUTPUT",
  "NO_INFERENCE",
  "NO_IMPLICIT_EDGES",
  "GRAPH_FIRST",
  "DIRECTIVE_IS_SOURCE",
  "SCHEMA_EXACT",
  "HALT_ON_BOUNDARY_VIOLATION",
  "NO_AGENT_LANGUAGE",
  "NO_RUN_IDENTITY",
  "BOUNDED_EXEC",
  "NO_RUNTIME_GLOB_UNLESS_PERMITTED",
  "ids.directive_id_REQUIRED_FOR_MUTATING_OPS",
  "ids.op_id_REQUIRED_PER_ATOMIC_OPERATION",
  "t_MUST_BE_PRE_RESOLVED",
  "a_IS_ATOMIC_1_TO_1_ONLY",
  "ops_ONE_OP_ID_PER_ATOMIC_OPERATION"
],

"i":{
  "req":["dir.env","dir.pay","scp","gph"],
  "opt":["ctx"],
  "symbolic":{"t":"targets","o":"objectives","b":"boundaries","L":"laws","ref":"anchor","ids":{"directive_id":"string","op_id":"string"}}
},

"p":[
  {"id":"VALIDATE","mod":"seq","u":["inputs_complete","directive_is_tojson_packet","directive_readable"],"inl":["dir.env","dir.pay","scp","gph","ctx"],"out":["validated_input"]},
  {"id":"ANALYZE","mod":"seq","u":["read_only","within_scope","evidence_required","no_inference"],"inl":["dir.pay","scp","gph","ctx"],"out":["fnd","amb"]},
  {"id":"APPLY","mod":"seq","u":["graph_append_only","no_implicit_edges","no_state_mutation"],"inl":["gph","fnd","amb"],"out":["gph"]},
  {"id":"RESOLVE","mod":"seq","u":["resolve_or_halt","blocking_ambiguity_enforced"],"inl":["gph","amb"],"out":["gph","amb"]},
  {"id":"PLAN","mod":"seq","u":["deterministic_order","no_conflicts","graph_first","directive_is_source"],"inl":["dir.pay","gph"],"out":["mut","ops"]},
  {"id":"EMIT","mod":"seq","u":["no_partial_output","schema_exact"],"inl":["gph","mut","ops","amb"],"out":["outp"]}
],

"d":{},

"h":[
  "MISSING_INPUT",
  "INVALID_DIRECTIVE_PACKET",
  "UNBOUNDED_SCOPE",
  "DIRECTIVE_UNREADABLE",
  "BLOCKING_AMBIGUITY",
  "CONFLICTING_TARGETS",
  "INVALID_GRAPH",
  "BOUNDARY_VIOLATED",
  "WRITE_TO_FILES_OUT_OF_SCOPE"
],

"o":{
  "typ":"tojson_single_line",
  "schema":{
    "env":{"k":"RPT","id":"string","ver":"1.0.0","src":"SYS_EXEC","sta":"COMPLETE|HALT"},
    "pay":{"sta":"READY|HALT","gph":"GraphState","mut":"MutationList","ops":"OperationList","hlt":{"cod":"string|null","msg":"string|null"}}
  }
},

"schemas":{
  "dir":{
    "env":{"k":"DIR|LAW|EVT|CHAR","id":"string","ver":"string","src":"string","sta":"string"},
    "pay":{}
  },
  "scp":{"fil":["string"]},
  "gph":{"ver":"string","nod":[],"edg":[],"fnd":[],"amb":[]},
  "outp":{"sta":"READY|HALT","gph":"GraphState","mut":"MutationList","ops":"OperationList","hlt":{"cod":"string|null","msg":"string|null"}}
}
}
```
