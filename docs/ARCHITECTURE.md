# RLeon architecture

High-level data flow (local-first).

## Speech → text

`SpeechTranscriber` uses `SFSpeechRecognizer` + `AVAudioEngine` with **on-device** recognition (`requiresOnDeviceRecognition`). Default locale is `en-US`.

## Images / screen → text

- User-selected images: `NSOpenPanel` → `NSImage` → `VisionOCR` (`VNRecognizeTextRequest`).
- FN long-hold path: `MainDisplayCapture` → `CGImage` → same Vision pipeline.  
- `recognitionLanguages` default: `en-US` first, then `tr-TR` for mixed content.

## LLM

- HTTP client: `OllamaClient` / `OllamaToolCalling` → `POST /api/chat` on the configured base URL (default `http://127.0.0.1:11434`).
- **Tool calling:** OpenAI-shaped `tools` array; assistant `tool_calls` → Swift executes tool → `role: tool` messages → model continues.

## Built-in tools

Implemented in `OllamaToolCalling.executeLocalTool` and registered via `LocalToolStore`. User-facing order and enablement live in `ToolSelectionStore` / `ToolRegistryModels`.

**Safety:** `ToolSafetySettings` gates `run_terminal_command` and `type_into_focused_field` (default **off**). Tools are omitted from the Ollama `tools` payload until allowed in **Settings → Dangerous tools & MCP**, in addition to per-tool enablement in the local tools list. When enabled, **`ToolInvocationConfirmation`** (modal `NSAlert`) can require approval for **each** command or insertion (defaults on; user-configurable).

## FN push-to-talk

`FnPushToTalkCoordinator` monitors the **Fn** key (`keyCode` 63) via `NSEvent` global/local monitors. Short tap arms dictation-only; hold ≥ ~250 ms starts full capture (speech + main display OCR). On release, transcript (+ OCR) is sent to Ollama when not in dictation-only mode.

**Note:** macOS also uses Fn for system shortcuts (e.g. dictation). If you hit conflicts, a future revision may expose a configurable hotkey.

## MCP bridge

`MCPToolBridge` merges `mcp_*` tool definitions into the Ollama payload when enabled. Full client wiring (swift-sdk `tools/list` / `tools/call`) is **not** complete yet; see [README](../README.md) and [CONTRIBUTING](../CONTRIBUTING.md).

Suggested tool naming: `mcp_<serverSlug>_<toolName>` to avoid collisions with built-ins.

## See also

- **[ROADMAP.md](../ROADMAP.md)** — shipped vs planned work and priorities.
