import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Darwin

/// Odaklı metin alanına yazma: Erişilebilirlik izni gerekir.
/// Sıra: AX (seçili / value sonu) → CGEvent Unicode → pano + ⌘V.
enum FocusedTextInsertion {
    /// Yalnızca henüz güvenilmiyorsa sistem izin penceresini gösterir.
    static func requestAccessibilityPromptIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Kısa kod döner (LLM / araç çıktısı için; uzun Türkçe uyarı verme).
    @MainActor
    static func insertText(_ text: String) -> String {
        guard AXIsProcessTrusted() else { return "AX_NOT_TRUSTED" }
        let t = text
        guard !t.isEmpty else { return "EMPTY" }

        resignActiveIfNeededBeforeTargetingOtherApp()

        if let r = tryAXSelectedText(t) { return r }
        if let r = tryAXAppendToValue(t) { return r }
        if let r = tryPostUnicodeKeyEvents(t) { return r }
        if let r = tryPasteCommandV(t) { return r }

        return "FAILED_FOCUS"
    }

    /// Arayüz için tek satır; `insertText` kodlarını çevirir.
    static func localizedUserMessage(for code: String) -> String {
        switch code {
        case "AX_NOT_TRUSTED":
            return "Accessibility (AX) appears disabled. Grant permission in Settings, restart the app, and check the status line above."
        case "EMPTY":
            return "Empty text."
        case "OK_AX_SEL":
            return "Inserted (Accessibility, selected range)."
        case "OK_AX_APPEND":
            return "Inserted (Accessibility, end of value)."
        case "OK_CG":
            return "Inserted (keyboard event)."
        case "OK_PASTE":
            return "Inserted (paste)."
        case "FAILED_FOCUS":
            return "Could not insert: is focus in a text field? Click in another app and try again."
        default:
            return code
        }
    }

    static func bundlePathForDiagnostics() -> String {
        Bundle.main.bundlePath
    }

    /// Sistem Ayarları → Erişilebilirlik (sürüme göre birden fazla URL dene).
    static func openAccessibilitySettings() {
        let ids = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for s in ids {
            if let u = URL(string: s), NSWorkspace.shared.open(u) { return }
        }
    }

    // MARK: - Ön plan

    private static func resignActiveIfNeededBeforeTargetingOtherApp() {
        let myPid = ProcessInfo.processInfo.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == myPid {
            NSApp.deactivate()
            usleep(150_000)
        }
    }

    // MARK: - Pano + ⌘V (son çare)

    private static func tryPasteCommandV(_ text: String) -> String? {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        pb.clearContents()
        guard pb.setString(text, forType: .string) else {
            if let previous { _ = pb.setString(previous, forType: .string) }
            return nil
        }
        postCommandKey(keyCode: CGKeyCode(kVK_ANSI_V))
        Thread.sleep(forTimeInterval: 0.1)
        pb.clearContents()
        if let previous {
            _ = pb.setString(previous, forType: .string)
        }
        return "OK_PASTE"
    }

    private static func postCommandKey(keyCode: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        let flags = CGEventFlags.maskCommand
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - CGEvent Unicode

    private static func tryPostUnicodeKeyEvents(_ text: String) -> String? {
        let src = CGEventSource(stateID: .hidSystemState)
        for ch in text {
            let chunk = String(ch)
            let utf16 = Array(chunk.utf16)
            guard !utf16.isEmpty else { continue }
            let ok = utf16.withUnsafeBufferPointer { buf -> Bool in
                guard let ptr = buf.baseAddress else { return false }
                guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                      let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
                else { return false }
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: ptr)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: ptr)
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
                return true
            }
            if !ok { return nil }
            Thread.sleep(forTimeInterval: 0.002)
        }
        return "OK_CG"
    }

    // MARK: - Accessibility

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let ax = focused
        else { return nil }
        return (ax as! AXUIElement)
    }

    private static func tryAXSelectedText(_ text: String) -> String? {
        guard let el = focusedElement() else { return nil }
        let r = AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFString)
        if r == .success { return "OK_AX_SEL" }
        return nil
    }

    private static func tryAXAppendToValue(_ text: String) -> String? {
        guard let el = focusedElement() else { return nil }
        var cur: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &cur) == .success else { return nil }
        let existing: String
        if let s = cur as? String {
            existing = s
        } else if let att = cur as? NSAttributedString {
            existing = att.string
        } else {
            return nil
        }
        let newVal = existing + text
        let r = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, newVal as CFString)
        if r == .success { return "OK_AX_APPEND" }
        return nil
    }
}
