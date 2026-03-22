# RLeon roadmap

This document describes **what is already in place**, **what we plan next**, and **how priorities are reasoned**. It is a living document; [issues](https://github.com/efekurucay/RLeon/issues) and focused PRs shape the order of work.

---

## Vision

**RLeon** stays **local-first**: on-device speech and OCR, optional **Ollama** on the same machine, and **explicit, user-controlled** tool calling — including a path toward **MCP** (Model Context Protocol) without hiding risk behind defaults.

---

## Current state (shipped)

### Product & UX

| Area | Status |
| --- | --- |
| **Speech → text** | On-device `SFSpeechRecognizer` pipeline (`SpeechTranscriber`), default `en-US`. |
| **Screen / image → text** | Vision `VNRecognizeTextRequest`; main display capture + image picker; FN long-hold flow. |
| **Ollama chat** | `POST /api/chat`, configurable base URL and model name. |
| **Tool calling** | OpenAI-shaped `tools` / `tool_calls` round-trip; Swift execution → `role: tool` follow-up. |
| **Built-in tools** | Clipboard, app info, open app/URL, WhatsApp compose, Terminal (high risk), type into focused field (high risk). |
| **Safety** | Dangerous tools **off** by default; **Settings → Dangerous tools & MCP** before the model sees `run_terminal_command` / `type_into_focused_field`. **Per-call** modal confirmation for each Terminal command and cross-app typing (default on; optional opt-out). Length limits: command 16k chars, typed text 50k. |
| **FN + menu bar** | `FnPushToTalkCoordinator`: short tap vs hold for dictation vs full pipeline. |
| **MCP hook** | `MCPToolBridge` + `mcp_*` naming convention; **stub only** (no live `tools/list` / `tools/call`). |

### Platform & maintenance

| Area | Status |
| --- | --- |
| **macOS** | Target **14+**; Xcode **15+** for build. |
| **CI** | GitHub Actions: `xcodebuild` Debug build on macOS runner (`.github/workflows/ci.yml`). |
| **Community** | `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, issue templates, PR template. |
| **Docs** | Root README (with screenshots); [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md); [`docs/NOTARIZATION.md`](docs/NOTARIZATION.md) (distribution outline). |
| **Releases** | **v0.1.0**, **v0.1.1** on GitHub (source-first); notes in [`.github/release-notes-v0.1.0.md`](.github/release-notes-v0.1.0.md) and [`.github/release-notes-v0.1.1.md`](.github/release-notes-v0.1.1.md). |

### Recent repo / docs cleanup (already done)

- Removed optional **research prompt** and **app icon generator** script; leaner tree.
- **`ARCHITECTURE.md`** lives under **`docs/`**; root keeps GitHub-standard files (README, contributing, security, CoC).
- README oriented toward **open-source** discoverability (features, setup, tools table, doc index).
- **Screenshots:** illustrative preview in README; `scripts/capture_screenshot.sh` for a real local capture (`main-window-real.png`, gitignored).

---

## Near term (next milestones)

Work that is **still open**; items already shipped live in [Current state](#current-state-shipped) above.

### 1. Quality & CI

| Item | Rationale |
| --- | --- |
| **Unit / integration tests** | Tool calling round-trip, `ToolSafetySettings` + confirmation paths, mocks for Ollama HTTP. |
| **CI hardening** | Optional **Release** configuration and/or second Xcode/macOS version if maintenance cost stays low. |
| **Dependency hygiene** | e.g. Dependabot for GitHub Actions; add when the workflow grows beyond checkout + build. |

### 2. Safety polish

| Item | Rationale |
| --- | --- |
| **Stronger validation** | **Partial today:** length limits only. Optional: denylists / safer quoting for shell, argument allowlists for risky tools. |
| **Edge-case UX** | Clearer messages for rare failure modes; optional timeout around modal + LLM round-trip. |

### 3. Distribution (optional)

| Item | Rationale |
| --- | --- |
| **Signed / notarized `.app` in CI** | Documented in [`docs/NOTARIZATION.md`](docs/NOTARIZATION.md); automation TBD (needs Apple ID / certs). |
| **Short demo video or GIF** | Lowers onboarding friction; optional polish. |

---

## Mid term

Features that need more design or dependencies.

### MCP as a first-class connector

| Track | Work |
| --- | --- |
| **Dependency** | Integrate [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) (`MCP` product) — upstream expects **Swift 6 / Xcode 16+**; align project toolchain or gate with `#if canImport(MCP)`. |
| **Transport** | Stdio for local servers; evaluate HTTP/SSE for remote per MCP spec evolution. |
| **Settings UI** | “Add MCP server” (name, command + args, env, or URL), enable/disable, trust warnings. |
| **Runtime** | `tools/list` → map to OpenAI-style functions; on `tool_calls` → `tools/call` with structured errors back to the model. |
| **Security** | Same stance as today: only trusted servers; document blast radius in `SECURITY.md`. |

### Ergonomics

| Item | Notes |
| --- | --- |
| **Configurable hotkey** | Alternative to Fn if system dictation or other shortcuts conflict. |
| **Tool presets / profiles** | Quick switch between “safe only” vs “full tools” for power users. |

---

## Long term / exploratory

Ideas that depend on adoption, contributors, or ecosystem direction.

| Idea | Notes |
| --- | --- |
| **Plugin or script hooks** | Beyond MCP — only if there is clear demand and a security model. |
| **Broader i18n** | UI and default prompts today are English-centric; locale-aware defaults possible later. |
| **Windows / Linux** | Not current focus; architecture would diverge (speech, capture, permissions). |

---

## Out of scope (for now)

- Replacing Ollama with hosted-only APIs as the **default** (local-first stays core).
- Silent execution of arbitrary shell without user understanding of risk.
- Bundling third-party MCP servers without explicit user install and trust.

---

## How to use this roadmap

1. **Pick an item** in Near term or Mid term and open an issue (or comment on an existing one) so work isn’t duplicated.
2. **Small PRs** preferred: one feature or fix per PR when possible.
3. **Update this file** when a milestone ships or priorities change — keep README’s short [Roadmap](README.md#roadmap) section in sync or rely on this document as the source of truth.

---

## Summary table

| Horizon | Themes |
| --- | --- |
| **Done** | Local speech/OCR/Ollama, tool calling, safety gates + **per-call** Terminal/typing confirmation, MCP stub, CI, community docs, README screenshots, **v0.1.x** releases, `docs/ARCHITECTURE` + `docs/NOTARIZATION`. |
| **Near** | Automated tests, CI hardening, optional shell validation / UX polish, optional signed build pipeline. |
| **Mid** | Full MCP client + Settings, configurable hotkey, optional tool profiles. |
| **Long** | Plugins/i18n/cross-platform only if justified. |

When in doubt, prefer **safety**, **clarity**, and **small iterative changes** over breadth.
