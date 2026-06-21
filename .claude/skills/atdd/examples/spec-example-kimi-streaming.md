# ATDD Specification: kimi-streaming

## 1. Problem Statement

- **Context:** The Go `llm-gateway` bridge translates Codex CLI Responses API requests (SSE streaming) to Chat Completions upstream calls. Kimi-K2.6 streams beautifully through the bridge (0.55s first chunk), but two wire-format bugs produce incorrect SSE event sequences and dropped system prompts.
- **The Gap / Bug:**
  1. **Double `response.completed`** — When Kimi's upstream SSE stream sends a final chunk with `finish_reason: "stop"`, `ChatChunkToEvents()` emits a `response.completed` event. Then the bridge loop exits and *unconditionally* emits a *second* `response.completed`. Codex's SSE parser may reject or misinterpret the duplicate terminal event.
  2. **Missing `instructions` mapping** — Codex sends `"instructions": "your system prompt here"` as a top-level field in the Responses API request. The `ResponsesRequest` model has no `Instructions` field, so it's silently dropped by `json.Unmarshal`. `ResponsesToChat()` never prepends a system message, so the model receives no system prompt.
- **Impact:** Double completed corrupts the SSE stream contract (Codex may hang, timeout, or ignore the second event when it expects `done`). Missing instructions means the model operates without system context, producing incorrect or incoherent output.

## 2. System Constraints & Environment

- **Runtime:** Go 1.23
- **Frameworks:** stdlib `net/http`, `encoding/json` — no third-party HTTP/SSE libraries
- **External Dependencies:** Upstream Chat Completions API (OpenCode / Kimi-K2.6 endpoint), `github.com/god-lock/llm-gateway` (monorepo-internal)

## 3. Black-Box Test Cases (The "Green" Gates)

### Scenario 1: ChatChunkToEvents emits single completed when finish_reason is present

- **Given:** A `ChatChunk` with one `Choice` where `Delta.Content = "hello"` and `FinishReason = ptr("stop")`, and a fresh `StreamState{OutputText: "", ID: "resp_abc"}`.
- **When:** `ChatChunkToEvents(chunk, state)` is called.
- **Then:** The returned event slice contains exactly one `Event` with `Name = "response.completed"`. No duplicate `response.completed` events appear in the slice.

### Scenario 2: Bridge does not emit second completed when ChatChunkToEvents already did

- **Given:** The SSE stream loop in `Bridge.Stream()` reads chunks, the final chunk has `finish_reason = "stop"`, and `state.Completed = true` after processing.
- **When:** The loop exits (either `!ok` or `[DONE]`).
- **Then:** `Bridge.Stream()` does NOT emit an unconditional `response.completed` event after the loop.

### Scenario 3: Bridge emits fallback completed when stream ends without finish_reason

- **Given:** The upstream SSE stream ends (scanner returns `!ok` or `[DONE]`) without any chunk having set a `finish_reason`.
- **When:** `state.Completed` is still `false` after the loop exits.
- **Then:** `Bridge.Stream()` emits a single unconditional `response.completed` as a fallback.

### Scenario 4: ResponsesToChat maps instructions to system message

- **Given:** A `ResponsesRequest` with `Instructions = "You are a helpful assistant"`, `Input = [{"type":"input_text","text":"Hello"}]`, `Model = "kimi-k2.6"`.
- **When:** `ResponsesToChat(req, "")` is called.
- **Then:** The returned `ChatRequest` has `Messages[0] = {Role: "system", Content: "You are a helpful assistant"}` and `Messages[1] = {Role: "user", Content: "Hello"}`.

### Scenario 5: ResponsesToChat handles empty instructions

- **Given:** A `ResponsesRequest` with `Instructions = ""`, `Input = "Hello"`, `Model = "kimi-k2.6"`.
- **When:** `ResponsesToChat(req, "")` is called.
- **Then:** The returned `ChatRequest` has exactly one message (`{Role: "user", Content: "Hello"}`). No system message is prepended.

### Scenario 6: ResponsesRequest unmarshals instructions from Codex payload

- **Given:** A JSON payload `{"model":"kimi-k2.6","instructions":"Be concise","input":"Hello","stream":true}`.
- **When:** `json.Unmarshal(body, &req)` is called where `req` is a `ResponsesRequest`.
- **Then:** `req.Instructions == "Be concise"`. The `Instructions` field is populated correctly from the wire.

## 4. Definition of Done (DoD)

- [ ] All 6 Scenarios implemented as automated Go tests in the appropriate `internal/translate/` and `internal/service/` test files.
- [ ] Existing regression tests pass unchanged: `go test ./...` is green.
- [ ] Manual verification: Codex CLI against bridge with Kimi-K2.6 produces clean SSE stream with single `response.completed` and the system prompt respected in output.
