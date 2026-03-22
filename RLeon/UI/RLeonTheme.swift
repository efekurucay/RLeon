import SwiftUI

/// RLeon visual identity: calm teal accent, cards, type hierarchy.
enum RLeonTheme {
    static let accent = Color(red: 0.11, green: 0.44, blue: 0.54)
    static let accentSecondary = Color(red: 0.18, green: 0.52, blue: 0.62)
}

struct RLeonCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func rleonCard() -> some View {
        modifier(RLeonCardModifier())
    }
}

struct RLeonSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum RLeonToolLabel {
    static func title(_ id: String) -> String {
        LocalToolStore.effectiveTitle(for: id, default: defaultTitle(id))
    }

    static func subtitle(_ id: String) -> String {
        LocalToolStore.effectiveSubtitle(for: id, default: defaultSubtitle(id))
    }

    static func defaultTitle(_ id: String) -> String {
        switch id {
        case "copy_to_clipboard": return "Copy to clipboard"
        case "get_app_info": return "App info"
        case "open_application": return "Open application"
        case "open_url": return "Open URL"
        case "whatsapp_compose": return "WhatsApp"
        case "run_terminal_command": return "Terminal command"
        case "type_into_focused_field": return "Type into focused field"
        default: return id
        }
    }

    static func defaultSubtitle(_ id: String) -> String {
        switch id {
        case "copy_to_clipboard": return "Text to pasteboard"
        case "get_app_info": return "RLeon name / version"
        case "open_application": return "Name or bundle ID"
        case "open_url": return "Safari or default browser"
        case "whatsapp_compose": return "whatsapp://"
        case "run_terminal_command": return "New Terminal window"
        case "type_into_focused_field": return "Requires Accessibility"
        default: return ""
        }
    }

    static func symbol(_ id: String) -> String {
        switch id {
        case "copy_to_clipboard": return "doc.on.doc"
        case "get_app_info": return "info.circle"
        case "open_application": return "app.badge"
        case "open_url": return "safari"
        case "whatsapp_compose": return "message"
        case "run_terminal_command": return "terminal"
        case "type_into_focused_field": return "text.cursor"
        default: return "wrench"
        }
    }
}
