## RLeon v0.1.1

### Safety & UX

- **Per-call confirmation** for `run_terminal_command` and `type_into_focused_field` (modal with full command / text preview). Defaults **on**; can be disabled per dangerous tool in **Settings → Dangerous tools & MCP** for trusted setups only.
- **Length limits:** shell command ≤ 16 384 chars; typed text ≤ 50 000 chars.
- **Clearer tool errors:** disabled tools, MCP off, user cancel, and Accessibility insertion results return readable messages.
- **Docs:** [`docs/NOTARIZATION.md`](../docs/NOTARIZATION.md) (distribution outline); README / SECURITY / ROADMAP / ARCHITECTURE updated.

Build: same as v0.1.0 — Xcode 15+, macOS 14+.
