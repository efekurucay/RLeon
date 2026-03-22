# Security policy

## Supported versions

Security updates are applied to the **default branch** of this repository. Use the latest tag or commit when deploying builds.

## Reporting a vulnerability

Please **do not** open a public issue for security-sensitive reports.

1. Open a **private** [GitHub Security Advisory](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) for this repository (if enabled), or  
2. Contact the maintainers with a clear description, reproduction steps, and affected component (Speech, OCR, Ollama client, tools, MCP bridge).

We aim to acknowledge reports within a few business days.

## Scope and threat model

RLeon is designed for **local-first** use with [Ollama](https://ollama.com) on `localhost`. By default, the app does not send your speech or screen content to a remote LLM.

High-impact areas:

| Area | Risk |
|------|------|
| **`run_terminal_command`** | Runs shell commands in a new Terminal window via AppleScript. Treat as **arbitrary code execution** with user privileges. **Disabled by default**; when enabled, each run shows a **confirmation dialog** with the command unless you opt out in Settings. |
| **`type_into_focused_field`** | Types into the frontmost app using Accessibility / synthetic events. Can modify data in other applications. **Disabled by default**; when enabled, each insertion can require **confirmation** (default on). |
| **MCP (`mcp_*` tools)** | Untrusted MCP servers can expose tools that read files, use the network, or perform other side effects. Only connect servers you trust. |
| **Tool calling** | The local model chooses when to invoke tools. Prompt injection (e.g. via OCR text) could influence tool selection—dangerous tools use **explicit prompts** plus optional per-call confirmation. |

## Recommendations

- Use a **tool-capable** Ollama model only from sources you trust.
- **Do not** enable MCP or high-risk tools when experimenting with untrusted models or prompts.
- Review **System Settings → Privacy & Security** for Microphone, Speech Recognition, Screen Recording, Accessibility, and Input Monitoring as appropriate.

## Disclosure

We follow coordinated disclosure: we will work with reporters on a fix timeline before public details, unless immediate public notice is required to protect users.
