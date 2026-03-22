# Deep research brief — RLeon (SwiftSpeechVisionDemo)

**How to use:** Paste everything below into your research tool (or split into sections). When done, send the synthesized notes back so implementation can be validated and the roadmap updated.

---

## 1. Purpose

You are researching **RLeon**, a macOS SwiftUI app that combines:

- On-device speech dictation (Speech framework)
- Vision-based OCR (images + main display capture)
- Local **Ollama** chat at `http://127.0.0.1:11434` with optional **OpenAI-style tool calling**
- **FN key** push-to-talk: short tap arms dictation-only; hold ~250ms → speech + screen OCR → release → Ollama
- **Built-in local tools** executed in Swift (clipboard, open app/URL, Terminal, WhatsApp deep link, type into focused field via Accessibility)
- **MCP (Model Context Protocol)** extension point: `MCPToolBridge` is currently a **stub** (empty `tools` definitions; `executeIfNeeded` returns a placeholder). Intended integration: [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk), `tools/list` → OpenAI-shaped tool defs, `tools/call` for `mcp_*` prefixed names.

**Goals of this research:**

1. **Validate** what the codebase already does (architecture, security boundaries, gaps).
2. **Plan** next steps: MCP client, UX for dangerous tools, testing, distribution.
3. **Open source & README:** Best practices for a small macOS Swift repo (LICENSE, CONTRIBUTING, security disclosure, badges, screenshots, “production-ready” README sections).
4. **Risk review:** `run_terminal_command`, future MCP tools, model trust, sandboxing limits on macOS.

---

## 2. Current built-in tools (for model / reviewer)

These IDs are registered in `LocalToolStore.allToolIds` and exposed to Ollama when enabled:

| Tool ID | Role |
|--------|------|
| `copy_to_clipboard` | Copy text to pasteboard |
| `get_app_info` | Return RLeon bundle name / version |
| `open_application` | Launch app by name or `bundle_id` |
| `open_url` | Open URL in Safari or default browser |
| `whatsapp_compose` | Open WhatsApp desktop via `whatsapp://` |
| `run_terminal_command` | Run shell in new Terminal window (AppleScript) — **high risk** |
| `type_into_focused_field` | Insert text via Accessibility / CG events / paste — requires AX trust |

**MCP:** Tools prefixed with `mcp_` are routed through `MCPToolBridge` when `rleonMCPBridgeEnabled` is true (UserDefaults); implementation is placeholder until swift-sdk is wired.

---

## 3. Technical questions to answer

### Architecture & correctness

- Does Ollama’s `/api/chat` tool-calling format match what Swift builds (message shape, `tool_calls`, `tool` role messages)? Any version quirks (Ollama 0.4+)?
- Is the FN global key monitor approach on macOS still valid under recent macOS versions? What Accessibility / Input Monitoring permissions are required for **global** FN vs foreground-only?
- Vision OCR: recommended `recognitionLanguages` and tradeoffs for English-primary apps.

### MCP

- Current state of **swift-sdk**: transport options (stdio vs HTTP+SSE), client API surface, threading model with SwiftUI `@MainActor`.
- Recommended pattern: one MCP server connection vs multiple; naming `mcp_<server>_<tool>` for collision avoidance.
- Security: approving servers, path to least-privilege, user-visible consent before `tools/call`.

### Open source & distribution

- Standard files: `LICENSE` (MIT already present), `CONTRIBUTING.md`, `SECURITY.md` / GitHub Security Advisories, issue templates.
- macOS app distribution: unsigned dev build vs Developer ID notarization; what to document for contributors.
- README sections reviewers expect: features, requirements, build steps, architecture diagram or folder table, tool list, MCP status, **security warning** for shell/MCP, contributing, code of conduct (optional).

### Product / UX

- English-only UI: any localization strategy later (String catalogs) vs hard-coded English.
- Safe defaults: tool calling off by default vs on; warnings before first `run_terminal_command`.

---

## 4. Deliverables from your research

Please produce:

1. **Validation checklist** — bullet list: “implemented / partial / missing” for speech, OCR, Ollama, tools, FN, MCP stub.
2. **Prioritized roadmap** — e.g. P0 MCP transport + minimal server, P1 settings UI for MCP, P2 tests, P3 notarization.
3. **Open-source package** — concrete README outline + any missing repo files.
4. **Risks & mitigations** — especially command execution and MCP.
5. **References** — links to Ollama tool docs, MCP spec, swift-sdk, Apple Speech/Vision/Accessibility docs you relied on.

---

## 5. Constraints (do not contradict)

- App targets **macOS 14+**, Swift / SwiftUI.
- Local-first: Ollama on localhost; no cloud requirement for core features.
- **English** is the product language for UI and default LLM system prompts in the shipping app.

---

_End of prompt — paste research results below this line when sharing back._
