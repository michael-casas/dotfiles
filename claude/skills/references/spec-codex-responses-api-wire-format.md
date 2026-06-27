# Codex Responses API Wire Format Reference

Codex CLI v0.137.0 speaks the Responses API wire format. This reference documents the exact schema requirements discovered by probing Codex with a local bridge.

## Models Endpoint (`GET /v1/models`)

**This format is not yet fully resolved.** Codex v0.137.0 appears to use different parser paths depending on the provider name in the profile. What follows is the current best-known format; probing with the actual Codex binary is the definitive oracle.

Codex parses the models response with **strict field-level deserialization**. Missing fields produce: `missing field '<name>' at line N column M`.

Required fields discovered iteratively (with `models` key):
1. `id` (string) — model identifier
2. `object` (string) — always `"model"`
3. `created` (int64) — Unix timestamp
4. `owned_by` (string) — owner name
5. `slug` (string) — URL-friendly identifier
6. `display_name` (string) — human-readable name
7. `supported_reasoning_levels` (array of strings) — e.g. `["low", "medium", "high"]`

**Key uncertainty:** The OpenCode native endpoint at `https://opencode.ai/zen/go/v1` returns `{"object":"list","data":[...]}` with only `id`, `object`, `created`, `owned_by` — NO extra fields. Codex works with this endpoint via the `opencode-go` provider. But when our bridge returns the same `data`-key format, Codex reports `missing field 'models'`. Possible explanations:
- Codex uses a **provider-specific parser** — the `opencode-go` provider has lenient parsing, while unknown/custom providers use a strict generic parser
- Codex tries **both `data` and `models` paths** and reports the first failure
- The `base_url` format or response headers trigger different code paths

**Probe strategy:** When tuning the models response, always test with the real `codex --profile <name> exec -` binary, not just curl. Each missing field is revealed one at a time per Codex run.

The top-level response shape:
```json
{
  "object": "list",
  "models": [
    {
      "id": "kimi-k2.6",
      "object": "model",
      "created": 1677610602,
      "owned_by": "system",
      "slug": "kimi-k2.6",
      "display_name": "Kimi K2.6",
      "supported_reasoning_levels": ["low", "medium", "high"]
    }
  ]
}
```

Note: The key is `"models"` (plural), not `"data"` (which is the OpenAI Chat Completions format).

## Streaming Endpoint (`POST /v1/responses`)

Codex sends a POST with `stream: true` and expects SSE events in this order:

```
event: response.created
data: {"response":{"id":"resp_xxx"},"type":"response.created"}

event: response.in_progress
data: {"response":{"id":"resp_xxx"},"type":"response.in_progress"}

event: response.output_item.added
data: {"item":{"id":"resp_yyy","type":"message","role":"assistant","status":"in_progress"},"type":"response.output_item.added"}

event: response.output_text.delta
data: {"delta":"Hello","type":"response.output_text.delta"}

...more deltas...

event: response.completed
data: {"output_text":"Hello world","stop_reason":"stop","type":"response.completed"}

event: done
data: "[DONE]"
```

Key requirements:
- All initial batch events (created, in_progress, output_item.added) must be sent atomically before any upstream request — Codex starts counting idle time from the last SSE event received.
- `response.completed` must be a single event (no duplicates).
- `response.completed` data shape: `{"type":"response.completed","response":{"id":"...","status":"completed","output_text":"..."}}` OR `{"type":"response.completed","output_text":"...","stop_reason":"..."}`. Both shapes work.
- `event: done\n\ndata: "[DONE]"` must be the final event.

## SSE Heartbeat

Codex's `reqwest` HTTP client (Rust) has an idle timeout that triggers after ~1-2s of no data on the SSE stream. If the bridge needs to wait for an upstream connection or model inference, it MUST send SSE comment events to keep the connection alive:

```
: keepalive\n\n
```

These are ignored by Codex's SSE parser but reset the idle timer. Send one every 200-500ms during gaps between meaningful events.

## Request Wire Format

Codex sends requests in this shape:
```json
{
  "model": "kimi-k2.6",
  "instructions": "You are a concise assistant. Answer in 5 words or fewer.",
  "input": [{"type": "input_text", "text": "Say hello"}],
  "stream": true,
  "max_output_tokens": 1024,
  "tools": [...],
  "temperature": null,
  "top_p": null
}
```

Key differences from Chat Completions:
- `instructions` maps to system message role
- `input` is an array of content blocks or a string, not `messages`
- `max_output_tokens` not `max_tokens`
- `stream` is boolean at top level, not inside a `stream_options` block