---
description: >-
  Helpful Coding agent.
mode: primary
model: ollama/qwen2.5-coder
tools:
  webfetch: false
  websearch: false
permission:
  read: "allow"
  edit: "allow"
  write: "allow"
  patch: "allow"
  bash:
    "*": "allow"
  task:
    "*": "allow"
---
