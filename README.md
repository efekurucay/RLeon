<p align="center">
  <img src="SwiftSpeechVisionDemo/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="RLeon" />
</p>

<h1 align="center">RLeon</h1>

<p align="center">
  <strong>On-device speech · Vision OCR · Ollama LLM · macOS tool calling</strong><br/>
  Single window, menu bar + FN push-to-talk.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014+-blue?style=flat-square" alt="macOS" />
  <img src="https://img.shields.io/badge/Swift-5.0-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License" />
  <img src="https://img.shields.io/badge/Ollama-tool%20calling-00ADD8?style=flat-square" alt="Ollama" />
</p>

---

## Overview

**RLeon** is an open-source **macOS** assistant that combines microphone dictation (Speech), **Vision** OCR from images or the main display, a local **Ollama** chat, and **built-in tools** the model can call (pasteboard, open URL/app, Terminal, type into the focused field, and more). Tool order, on/off state, and labels are managed in **Settings**.

The UI and default LLM prompts are **English**. Core inference stays **on your machine** when you use local Ollama.

**Docs:** [ARCHITECTURE.md](ARCHITECTURE.md) · [SECURITY.md](SECURITY.md) · [CONTRIBUTING.md](CONTRIBUTING.md) · [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) · [Research prompt](docs/DEEP_RESEARCH_PROMPT.md) (optional)

## Features

| Area | Summary |
|------|---------|
| **Speech** | On-device recognition (default locale `en-US`) |
| **OCR** | Main display capture + Vision text extraction |
| **LLM** | Ollama [`/api/chat`](https://github.com/ollama/ollama/blob/main/docs/api.md), optional **tool calling** ([tool support](https://ollama.com/blog/tool-support)) |
| **Tools** | Native Swift tools + **MCP bridge** hook (`mcp_*` names) |
| **FN / Menu** | Hold-to-capture flow, menu bar status |

## Requirements

- macOS **14+**, **Xcode 15+** (app target)
- [Ollama](https://ollama.com) (optional, for local LLM) — use a **tool-capable** model for function calling
- Microphone, screen recording, and Accessibility permissions when using related features

## Build

```bash
git clone https://github.com/YOUR_USERNAME/RLeon.git
cd RLeon
open SwiftSpeechVisionDemo.xcodeproj
```

1. Scheme: **SwiftSpeechVisionDemo**, destination: **My Mac**
2. **⌘B** to build; output: **`RLeon.app`**
3. Release: **Product → Scheme → Edit Scheme → Run → Build Configuration → Release**, or:

```bash
xcodebuild -scheme SwiftSpeechVisionDemo -configuration Release -destination 'platform=macOS' build
```

Output path (typical):

`~/Library/Developer/Xcode/DerivedData/SwiftSpeechVisionDemo-*/Build/Products/Release/RLeon.app`

### App icon (optional)

```bash
cd RLeon
swift scripts/generate_app_icon.swift
```

---

## Architecture (short)

| Path | Flow |
|------|------|
| Microphone | `SFSpeechRecognizer` → transcript |
| Screen / image | Capture or file → `VNRecognizeTextRequest` → text |
| Chat | Text + optional `tools` → Ollama → `tool_calls` → Swift → `role: tool` → model |

See **[ARCHITECTURE.md](ARCHITECTURE.md)** for detail.

---

## Built-in tools (reference)

Sent to Ollama as OpenAI-compatible `tools` when enabled in Settings.

| Tool ID | Description | Risk |
|---------|-------------|------|
| `copy_to_clipboard` | Copy text to the pasteboard | Low |
| `get_app_info` | RLeon name / version | Low |
| `open_application` | Launch app by name or bundle ID | Medium |
| `open_url` | Open URL (Safari or default browser) | Medium |
| `whatsapp_compose` | Open WhatsApp desktop via `whatsapp://` | Medium |
| `run_terminal_command` | Run shell in a new Terminal window | **High** |
| `type_into_focused_field` | Type into focused UI via Accessibility / events | **High** |

### Dangerous tools (safety gates)

`run_terminal_command` and `type_into_focused_field` are **off by default**. They are **not** exposed to the model until you enable them under **Settings → Dangerous tools & MCP** (with a confirmation dialog). You must still add each tool to the **Local tools** list and turn it on there for it to be used when safety allows.

---

## MCP (Model Context Protocol)

- Spec: [modelcontextprotocol.io](https://modelcontextprotocol.io)
- Swift SDK: [github.com/modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) (**Swift 6.0+, Xcode 16+**)

**Status in this repo:** `MCPToolBridge` is a **stub** — no live `tools/list` / `tools/call` yet. Tool IDs should follow `mcp_<serverSlug>_<toolName>` (parsed in code for future wiring).

To implement: in Xcode use **File → Add Package Dependencies…** → `https://github.com/modelcontextprotocol/swift-sdk.git` → add product **MCP** to the RLeon target (requires **Swift 6 / Xcode 16+** per upstream). Then connect a transport (`StdioTransport`, HTTP/SSE, etc.) inside `MCPToolBridge` and map MCP tool schemas to Ollama’s `tools` format.

---

## Security & privacy

- **Local LLM by default** — traffic goes to your Ollama URL (typically localhost).
- **Dangerous tools** stay disabled until you explicitly allow them in Settings; the model cannot invoke them beforehand.
- **MCP bridge** is experimental — only enable for trusted servers.
- **Reporting vulnerabilities:** see **[SECURITY.md](SECURITY.md)**.

---

## Contributing

See **[CONTRIBUTING.md](CONTRIBUTING.md)** and **[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)**. Small, focused PRs are welcome; MCP bridge contributions are especially valuable.

---

## License

**MIT** — see [LICENSE](LICENSE).

---

<p align="center">
  <sub>RLeon — local-first Ollama assistant for macOS.</sub>
</p>
