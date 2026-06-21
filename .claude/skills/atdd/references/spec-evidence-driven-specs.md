# Evidence-Driven ATDD Specs

## Pattern

When debugging an integration with an external tool (Codex CLI, Claude Code, etc.),
a pure Go/unit test with mocks is **necessary but not sufficient**. The mock
hides the real behavior of the external tool's HTTP client, parser, and timeout
characteristics.

An evidence-driven ATDD spec includes:

1. **Real API captures** — Save the actual response from a working reference
   endpoint (e.g., OpenCode native `/v1/models`) as a JSON file in the spec
   directory. The implementing agent compares against this directly.

2. **Debug harness** — A standalone Python script that:
   - Starts the bridge/server on a known port
   - Runs the external tool (Codex CLI) as a subprocess against it
   - Captures the tool's exit code, stdout, and stderr
   - Captures bridge debug logs
   - Saves everything to a timestamped log file
   - Detects known error signatures and reports PASS/FAIL

3. **Error log capture** — When the external tool fails, its exact error output
   is preserved and referenced in the spec. This lets the implementing agent
   see the exact error string, not a paraphrased description.

## Why This Matters

The Go integration test (`codex_e2e_test.go`) validates the bridge logic in
isolation with a mock upstream. The debug harness validates the **real**
interaction — real Codex binary, real HTTP client, real API endpoint. Both are
needed:

| Test | Ground Truth | CI-safe? |
|---|---|---|
| Go integration test (mock upstream) | Bridge logic | ✅ Yes |
| Debug harness (real tool + real API) | External compatibility | ❌ No (needs tool + API key) |

## File Layout

```
.agent/specs/atdd/<seam>/
├── <seam>.atdd.md          # The ATDD spec
├── EVIDENCE.md              # Compiled evidence with exact error messages
├── opencode-native-models.json  # Real API captures
├── debug-codex-e2e.py       # Debug harness
└── debug-logs/              # Timestamped debug output (gitignored)
```

## Implementation Tips

- The debug harness should be self-contained — one Python file with no external
  dependencies beyond the tool being tested (Codex CLI, etc.)
- Detect known error signatures in the output and report them clearly:
  `"❌ DETECTED: missing field error in models response"`
- Include a timeout guard for the subprocess so it doesn't hang CI
- Write debug logs to a `debug-logs/` subdirectory with timestamps so you can
  compare runs
