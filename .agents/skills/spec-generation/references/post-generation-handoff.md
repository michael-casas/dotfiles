# Post-Generation Handoff

Session-derived rule for GOD-LOCK spec work:

- After generating `.agent/specs/<SPEC>/{requirements.md,design.md,tasks.md}`, run `code-quality-check` on the generated spec before handoff.
- Treat the audit as the handoff gate, not a separate optional review.
- Keep repo steering instructions (for example `AGENTS.md`) terse and operational: say what to do first, what to do next, and what to use for the audit.
- If a delegated runtime was used, wait for the final completion signal/log before reconciling status.

This note is intentionally small and operational; the canonical execution contract remains in `spec-generation/SKILL.md` and `code-quality-check/SKILL.md`.