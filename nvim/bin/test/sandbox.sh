# shellcheck shell=bash
# Sourced by the launcher and migration suites: a throwaway HOME with every
# XDG folder inside it, a fake `hc` that logs each core call, and helpers.
# Nothing here reads or writes the real ~/.config, ~/.local or herdr-core.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/envi-prod-sandbox.XXXXXX")"
sandbox="$(cd "$sandbox" && pwd -P)"
trap 'rm -rf "$sandbox"' EXIT

export HOME="$sandbox/home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
export TMPDIR="$sandbox/tmp"
unset NVIM_APPNAME ENVI_DEV ENVI_SESSION ENVI_RELOAD_SESSION ENVI_RELOAD_FILE ENVI_INSTANCE_FILE HCMUX_SESSION
unset NVIM NVIM_LISTEN_ADDRESS HC_TERMINAL_ID
mkdir -p "$HOME" "$TMPDIR" "$XDG_DATA_HOME/nvim" "$sandbox/bin"

# Fake herdr-core: `hc connect` answers doc.get/doc.set from a JSON file and
# logs "<method> <name>"; every other call is logged and answered empty.
export HC_LOG="$sandbox/hc.log" HC_DOCS="$sandbox/hc-docs.json"
: >"$HC_LOG"
cat >"$sandbox/bin/hc" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = connect ]; then
  exec python3 -I -c '
import json, os, sys
log, store = os.environ["HC_LOG"], os.environ["HC_DOCS"]
docs = json.load(open(store)) if os.path.exists(store) else {}
for line in sys.stdin:
    if not line.strip():
        continue
    req = json.loads(line)
    p = req.get("params") or {}
    name = p.get("name", "")
    open(log, "a").write("%s %s\n" % (req["method"], name))
    if req["method"] == "doc.get":
        d = docs.get(name) or {}
        res = {"value": d.get("value"), "version": d.get("version", 0)}
    elif req["method"] == "doc.set":
        ver = (docs.get(name) or {}).get("version", 0) + 1
        if p.get("value") is None:
            docs.pop(name, None)
        else:
            docs[name] = {"value": p["value"], "version": ver}
        json.dump(docs, open(store, "w"))
        res = {"version": ver}
    else:
        res = {}
    print(json.dumps({"jsonrpc": "2.0", "id": req.get("id"), "result": res}))
'
fi
echo "cli $*" >>"$HC_LOG"
echo '{"terminals":[]}'
EOF
chmod +x "$sandbox/bin/hc"
# Every nvim started in here quits on its own after 30 s, whatever it runs.
real_nvim="$(command -v nvim)"
cat >"$sandbox/bin/nvim" <<WRAP
#!/bin/sh
exec "$real_nvim" --cmd 'lua vim.defer_fn(function() vim.cmd("cquit 3") end, 30000)' "\$@"
WRAP
chmod +x "$sandbox/bin/nvim"
# No real launcher-started nvim exists in here, whatever runs outside.
printf '#!/bin/sh\nexit 1\n' >"$sandbox/bin/pgrep"
chmod +x "$sandbox/bin/pgrep"
export PATH="$sandbox/bin:$PATH"

# A config tree: this checkout's launchers and hcmux, and a probe init.lua
# that attaches the launcher's session, saves it, and records what it saw.
export PROBE_OUT="$sandbox/probe.log"
make_config() { # <dir>: <dir>/nvim
  mkdir -p "$1/nvim/lua"
  cp -R "$repo/nvim/bin" "$1/nvim/bin"
  cp -R "$repo/nvim/lua/hcmux" "$1/nvim/lua/hcmux"
  cat >"$1/nvim/init.lua" <<'EOF'
local s = require("hcmux.session")
if vim.env.HCMUX_SESSION then
  s.attach(vim.env.HCMUX_SESSION)
  s.save({ sync = true, force = true, release = true })
end
vim.cmd("wshada")
vim.fn.writefile({
  table.concat({
    "appname=" .. (vim.env.NVIM_APPNAME or ""),
    "config=" .. vim.fn.resolve(vim.fn.stdpath("config")),
    "state=" .. vim.fn.stdpath("state"),
    "session=" .. (s.name or ""),
    "reloadable=" .. tostring(s.reloadable()),
    "envi_dev=" .. (vim.env.ENVI_DEV or ""),
    "cwd=" .. vim.fn.getcwd(),
  }, " "),
}, vim.env.PROBE_OUT, "a")
local once = vim.env.PROBE_RELOAD_ONCE
if once and vim.fn.filereadable(once) == 0 then
  vim.fn.writefile({}, once)
  s.restart() -- :reload: the launcher starts nvim again on this session
elseif once then
  vim.cmd("qa!") -- the restarted nvim: done
end
EOF
}

# A fake nvim for the launcher's own logic: records env, emulates --cmd's PID.
make_fake_nvim() {
  mkdir -p "$sandbox/fake"
  cat >"$sandbox/fake/nvim" <<'EOF'
#!/usr/bin/env bash
[ -n "${ENVI_INSTANCE_FILE:-}" ] && printf '%s\n' "$$" >"$ENVI_INSTANCE_FILE"
shift 2 # --cmd <lua>
printf 'appname=%s session=%s cwd=%s envi_dev=%s args=%s\n' "${NVIM_APPNAME-<unset>}" \
  "${HCMUX_SESSION-<unset>}" "$PWD" "${ENVI_DEV-<unset>}" "$*" >>"$FAKE_LOG"
EOF
  chmod +x "$sandbox/fake/nvim"
  export FAKE_LOG="$sandbox/fake.log"
}

pass=0
fail=0
ok() {
  pass=$((pass + 1))
  echo "PASS $*"
}
bad() {
  fail=$((fail + 1))
  echo "FAIL $*"
}
check() { # <name> <command...>
  local name="$1"
  shift
  if "$@"; then ok "$name"; else bad "$name"; fi
}
has() { grep -q -- "$2" "$1"; }
lacks() { ! grep -q -- "$2" "$1"; }
finish() {
  echo "$pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}
