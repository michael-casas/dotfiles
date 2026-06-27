# Evidence Template

When debugging protocol/server integration issues, capture REAL evidence before dispatching to an implementing agent. Copy this structure into `.agent/specs/atdd/EVIDENCE.md` alongside your spec.

## Working Reference

The system that already works. Capture its EXACT output.

```json
{
  "object": "list",
  "data": [
    {"id": "model-name", "object": "model", "created": 1234567890, "owned_by": "provider"}
  ]
}
```

Root keys: object, data
Entry keys: id, object, created, owned_by

## Current Broken Output

What your code actually returns instead.

```json
{
  "object": "list",
  "models": [
    {"id": "model-name", "object": "model", "created": 1234567890, "owned_by": "system",
     "slug": "model-name", "display_name": "model-name", "extra_field": []}
  ]
}
```

Key differences: `models` instead of `data`, extra fields (`slug`, `display_name`, etc.)

## Client Error

The exact error from the real client.

```
ERROR: failed to decode response: missing field `shell_type` at line 1 column 181
body: {"object":"list","models":[{"id":"kimi-k2.6","object":"model","created":1677610602,
       "owned_by":"system","slug":"kimi-k2.6","display_name":"kimi-k2.6",
       "supported_reasoning_levels":[]}]}
```

## Root Cause

1-2 sentence analysis of what's actually wrong.

The client's strict deserializer enters a different code path when it sees extra fields or non-standard root keys. It then walks through required fields one-by-one, failing on each missing one. This cascading failure corrupts internal state and breaks subsequent operations.

## Fix

The specific code change. Include before/after.

```go
// BEFORE — wrong format with extra fields
type ModelsResponse struct {
    Models []Model `json:"models"`
}

// AFTER — matches working reference exactly
type ModelsResponse struct {
    Data   []Model `json:"data"`
}
```
