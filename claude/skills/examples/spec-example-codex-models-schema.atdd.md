# ATDD Specification: codex-models-schema

## 1. Problem Statement

- **Context:** The `llm-gateway` bridge translates Codex Responses API requests to upstream Chat Completions. Codex queries `GET /v1/models` at startup to discover available models. The bridge returns a models response that Codex v0.137.0 cannot parse.
- **The Gap / Bug:** Codex reports `failed to decode models response: missing field 'shell_type'` (and previously `slug`, `display_name`, `supported_reasoning_levels` as each was added). This appears to be a cascading deserialization failure — Codex's Responses API models parser requires specific fields that are different from the OpenAI Chat Completions models format. The OpenCode native endpoint (`https://opencode.ai/zen/go/v1/models`) returns `{object:"list", data:[{id, object, created, owned_by}]}` with NO extra fields and Codex works fine with it, suggesting the parser uses a different schema path when `data` vs `models` key is present.
- **Impact:** Codex cannot discover the model through the bridge. The models endpoint error causes a cascade failure where Codex's internal state is corrupted, leading to stream failures on subsequent requests. No models are usable through the bridge from Codex.

## 2. System Constraints & Environment

- **Runtime:** Go 1.23 (bridge), Rust (Codex CLI v0.137.0)
- **Frameworks:** stdlib `net/http`, `encoding/json`
- **External Dependencies:** Codex CLI at `/opt/homebrew/bin/codex`. OpenCode API at `https://opencode.ai/zen/go/v1/models` (native Responses API endpoint that works with Codex).

## 3. Black-Box Test Cases (The "Green" Gates)

### Scenario 1: Models response matches the format Codex accepts from OpenCode

- **Given:** Codex works correctly with the OpenCode provider at `https://opencode.ai/zen/go/v1` — its `GET /v1/models` endpoint.
- **When:** A Go test fetches the models list from the OpenCode native endpoint (via `curl` or `net/http`) AND from the bridge's `/v1/models` endpoint.
- **Then:** The bridge's response has IDENTICAL JSON structure to the OpenCode native response at the top level: `{"object":"list","data":[...]}` with the `data` key (not `models`). Each model entry has AT MINIMUM: `id`, `object`, `created`, `owned_by`. The bridge must NOT include extra fields like `slug`, `display_name`, `supported_reasoning_levels`, `shell_type` that are not in the OpenCode native response, as these cause Codex to use a different (stricter) parser code path.
- **Verification:** Read `GET https://opencode.ai/zen/go/v1/models` (with auth) and `GET http://localhost:4000/v1/models`. Compare the root keys and first model entry's keys. They must match structurally.

### Scenario 2: Codex CLI models refresh succeeds against bridge

- **Given:** The bridge is running on port 4000 with `models.go` returning the exact same format as OpenCode's native models endpoint.
- **When:** Codex is started with `--profile bridge-kimi exec -` (which calls `GET /v1/models` at startup).
- **Then:** The Codex log does NOT contain `"failed to refresh available models"`. No `"missing field"` errors. The models refresh succeeds silently.

### Scenario 3: Codex streaming request completes against bridge

- **Given:** The bridge models endpoint returns Codex-compatible format. The bridge has keepalive SSE comments every 200ms.
- **When:** Codex runs a prompt like `echo "Say hello" | codex --profile bridge-kimi exec -`.
- **Then:** Codex exits with code 0. The output contains a valid response text. No `"Reconnecting..."` log lines. No `"stream closed before response.completed"`.

### Scenario 4: Integration test validates exact response equality

- **Given:** The test suite has network access to `opencode.ai`.
- **When:** The test `TestCodex_ModelsMatchOpenCodeFormat` starts the bridge and compares the JSON response to the OpenCode native response.
- **Then:** The test asserts:
  - Both responses have `"object":"list"`
  - Both use `"data"` as the model array key
  - The first model entry in the bridge response has NO keys beyond `id`, `object`, `created`, `owned_by`
  - If OpenCode adds extra fields in the future, the test is updated to match

## 4. Definition of Done (DoD)

- [ ] Scenario 1: Bridge returns `{object:"list", data:[{id, object, created, owned_by}]}` — exact structural match to OpenCode native format. NO extra fields.
- [ ] Scenario 2: `codex exec` against bridge reports no models refresh errors.
- [ ] Scenario 3: `codex exec` exits 0 with valid response, no reconnection attempts.
- [ ] Scenario 4: Automated test fetches both endpoints and asserts structural equality.
- [ ] Existing regressions pass: `go test ./...` is green.
- [ ] No files outside `internal/handler/models.go`, `internal/handler/codex_e2e_test.go` are changed.
