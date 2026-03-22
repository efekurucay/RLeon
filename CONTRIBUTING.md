# Contributing

Thanks for your interest in RLeon.

## Getting started

1. Fork and clone the repository.
2. Open `SwiftSpeechVisionDemo.xcodeproj` in **Xcode 15+** (macOS 14+).
3. Build the **SwiftSpeechVisionDemo** scheme for **My Mac** (product: **RLeon.app**).

Optional: [Ollama](https://ollama.com) on `http://127.0.0.1:11434` for LLM features.

## MCP Swift SDK (optional / future)

The official [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) targets **Swift 6.0+** and **Xcode 16+**. If you work on `MCPToolBridge`, use a compatible toolchain or keep changes behind clear `#if canImport(MCP)` gates until the project standardizes on Swift 6.

Add the package in Xcode: **File → Add Package Dependencies…** → `https://github.com/modelcontextprotocol/swift-sdk.git` → product **MCP**.

## Pull requests

- Keep PRs **focused** (one feature or fix per PR when possible).
- Match existing Swift style and project layout (`App/`, `UI/`, `LLM/`, etc.).
- Update **README** or **ARCHITECTURE.md** if you change user-visible behavior or data flow.
- Do not commit secrets, API keys, or personal paths.

## Issues

When reporting bugs, include: macOS version, Xcode version, steps to reproduce, and what you expected vs. what happened. For crashes, attach relevant Console or crash logs if you can.

## Publishing this repo to GitHub (`RLeon`)

From the repository root (this folder):

```bash
git init
git add -A
git commit -m "Initial commit: RLeon macOS assistant"
```

Create the remote repository named **`RLeon`** on GitHub (empty, no README if you already have one here), then:

```bash
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/RLeon.git
git push -u origin main
```

Or with [GitHub CLI](https://cli.github.com/): `gh repo create RLeon --public --source=. --remote=origin --push`

## License

By contributing, you agree your contributions are licensed under the same terms as the project ([LICENSE](LICENSE)).
