# Browser Harness Setup

## What It Is

Browser Harness (`browser-use/browser-harness`, 14.3k ⭐) connects an LLM directly to a real Chrome instance via CDP WebSocket. Unlike cmux's WKWebView (limited to capture/click), Browser Harness gives full CDP control — coordinate clicks, screenshots, tab management, network interception, remote cloud browsers.

## Install

```bash
# Clone
cd ~ && git clone https://github.com/browser-use/browser-harness

# Install with uv (Python 3.11+)
cd browser-harness && uv tool install -e .

# Register as Hermes skill (so the agent can find it)
mkdir -p ~/.hermes/skills/browser-harness
ln -sf ~/browser-harness/SKILL.md ~/.hermes/skills/browser-harness/SKILL.md
ln -sf ~/browser-harness/interaction-skills ~/.hermes/skills/browser-harness/interaction-skills
ln -sf ~/browser-harness/domain-skills ~/.hermes/skills/browser-harness/domain-skills
```

## Chrome Remote Debugging

Browser Harness connects to the user's already-running Chrome. User must:

1. Launch Chrome with remote debugging:
   ```bash
   /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --remote-debugging-port=9222
   ```
   Or open `chrome://inspect/#remote-debugging` and tick "Discover network targets"

2. The daemon auto-starts on first `browser-harness` invocation (no manual setup)

## Usage from an Agent

```bash
browser-harness <<'PY'
new_tab("https://example.com")       # always use new_tab, not goto_url
wait_for_load()
capture_screenshot()                  # visual-first approach
print(page_info())                    # text verification
PY
```

## Key Design

- **Coordinate clicks first** — `click_at_xy(x, y)` works through iframes, shadow DOM, cross-origin. No selector hunting.
- **Screenshots first** — capture to understand the page visually, then act.
- **Self-healing** — writes missing helpers to `agent-workspace/agent_helpers.py` during execution.
- **Remote/cloud browsers** — `start_remote_daemon("name")` for parallel sub-agents via Browser Use Cloud (free tier, 3 concurrent browsers).

## Domain Skills (Opt-in)

Set `BH_DOMAIN_SKILLS=1` to enable per-site playbooks under `agent-workspace/domain-skills/`. Community-contributed for LinkedIn, Amazon, GitHub, etc. Agent writes new skills during execution — not hand-authored.

## vs. cmux Browser (WKWebView)

| Capability | cmux WKWebView | Browser Harness |
|-----------|---------------|-----------------|
| Network mocking | ❌ | ❌ |
| Viewport emulation | ❌ | ❌ |
| Coordinate clicks | ❌ | ✅ |
| Screenshots | ✅ | ✅ |
| Tab management | ❌ | ✅ |
| Uploads | ❌ | ✅ |
| iframes / shadow DOM | ❌ | ✅ (click‑through) |
| Remote/cloud browsers | ❌ | ✅ |
| Session resume | ✅ (cmux) | ❌ |
| Visible in cmux | ✅ | ❌ |

## Reference

- `~/browser-harness/SKILL.md` — full usage docs, gotchas, design constraints
- `~/browser-harness/install.md` — first-time setup and troubleshooting
- `~/browser-harness/interaction-skills/` — reusable helpers for tabs, dialogs, uploads, iframes, shadow DOM
