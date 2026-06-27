# ATDD Evidence Pattern

When debugging a wire-format compatibility issue (e.g., Codex CLI responses API ↔ bridge), ATDD specs should be paired with captured evidence files that ground the test scenarios in reality.

## The Pattern

```
.agent/specs/atdd/<seam>.atdd.md       # The spec
.agent/specs/atdd/<seam>.EVIDENCE.md    # Captured debug evidence
.agent/specs/atdd/<seam>-debug.py       # Runnable debug harness
.agent/specs/atdd/debug-logs/           # Timestamped run outputs
```

## When to Use

- Codex or Claude sends a request format you're guessing at
- Error messages are iterative (one missing field at a time)
- Two modes produce different results (exec vs TUI)
- The real wire format differs from documented examples

## Example: Kimi models schema mismatch

The bridge returned `{object:"list", models:[{id, slug, display_name, ...}]}`. Codex errored with `missing field 'shell_type'`. Instead of adding fields one at a time, we:

1. Captured the working OpenCode native models response: `{object:"list", data:[{id, object, created, owned_by}]}`
2. Captured the failing bridge response
3. Identified the structural difference: OpenCode uses the `data` key (OpenAI Chat format) while the bridge used `models` (Responses API format)
4. Fixed the bridge to match OpenCode's exact format

The evidence files (`opencode-native-models.json`, `EVIDENCE.md`) let a future agent fix the same issue without re-discovering the format.

## Capturing Evidence

```bash
# Capture upstream working response
curl -s https://provider.com/v1/models -H "Authorization: Bearer $KEY" > upstream-models.json

# Capture bridge response
curl -s http://localhost:4000/v1/models > bridge-models.json

# Document the structural diff
python3 -c "
import json
with open('upstream-models.json') as f: a = json.load(f)
with open('bridge-models.json') as f: b = json.load(f)
print('Root keys:', set(list(a.keys())) - set(list(b.keys())))
print('Model field diff:', ...)
"
```

## Relationship to Debug Harness

The debug harness (e.g., `debug-codex-e2e.py`) is the automated version of evidence capture. It starts the bridge, runs Codex against it, and dumps all outputs to timestamped logs. The evidence reference explains WHY the harness exists and what format to expect.
