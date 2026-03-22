# Notarization & distribution (macOS)

RLeon is **open source** and usually built from Xcode. To share a **pre-built `.app`** outside the Mac App Store, Apple expects **code signing** and **notarization** so Gatekeeper does not block users.

This is **optional** for contributors who only run locally; it matters for **GitHub Releases** or direct downloads.

## Prerequisites

- **Apple Developer Program** membership (paid) for notarization and Developer ID signing.
- Xcode with your **Developer ID Application** certificate installed.

## Outline

1. **Archive** the app in Xcode (**Product → Archive**), or build Release and sign manually.
2. **Sign** the `.app` with your Developer ID: use `codesign` for all nested binaries and frameworks (Xcode “Sign to Run Locally” is not enough for distribution).
3. **Notarize**: submit with `xcrun notarytool submit` (or `altool` legacy) and **staple** the ticket: `xcrun stapler staple RLeon.app`.
4. **Distribute** a **zip** or **dmg** containing the stapled app; document the minimum **macOS** version (see README).

## References

- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/customizing_the_notarization_workflow)

When this project publishes signed builds, this document can be expanded with exact `xcodebuild` / `notarytool` commands used in CI.
