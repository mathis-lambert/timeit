import AppKit
import SwiftUI
import TimeitCore

/// Design tokens. See DESIGN.md.
enum Theme {
    /// The app accent declared in the asset catalog (`NSAccentColorName`); follows the user's system accent
    /// when they pick one other than multicolor, like every native app.
    static let accent = Color.accentColor
    static let positive = Color(light: 0x16855C, dark: 0x4CC994)
    /// Content surfaces are opaque fills; glass is reserved for floating controls.
    static let surface = Color.primary.opacity(0.035)
    static let divider = Color.primary.opacity(0.08)
    static let hairline = Color.primary.opacity(0.06)
    static let cardRadius: CGFloat = 14
    static let rowRadius: CGFloat = 8
    static let gutter: CGFloat = 28
}

enum Motion {
    /// Glass surfaces changing shape: the composer becoming the running timer.
    static let shell = Animation.spring(duration: 0.28, bounce: 0.08)
    /// Small feedback: hover, the palette appearing.
    static let quick = Animation.easeOut(duration: 0.14)
}

extension View {
    /// Animates `value` changes with the shell spring, or not at all with Reduce Motion.
    func shellAnimation(value: some Equatable) -> some View { modifier(ShellAnimation(value: value)) }
}

private struct ShellAnimation<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : Motion.shell, value: value)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                return NSColor(
                    srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
                    blue: Double(value & 255) / 255, alpha: 1)
            })
    }
}

extension ProjectColor {
    var tint: Color {
        switch self {
        case .coral: Color(light: 0xD9532F, dark: 0xF07A58)
        case .blue: Color(light: 0x2F6FD6, dark: 0x6EA2F2)
        case .green: Color(light: 0x1C8A63, dark: 0x5BC79A)
        case .purple: Color(light: 0x7E58C9, dark: 0xA88BE6)
        case .gold: Color(light: 0xB7800F, dark: 0xE2B456)
        }
    }
    var label: String {
        switch self {
        case .coral: "Corail"
        case .blue: "Bleu"
        case .green: "Vert"
        case .purple: "Prune"
        case .gold: "Ocre"
        }
    }
}

enum Display {
    static func duration(_ seconds: TimeInterval, seconds showSeconds: Bool = false) -> String {
        let total = Int(max(0, seconds))
        if showSeconds { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%dh %02d", total / 3600, total / 60 % 60)
    }
    static func money(_ value: Decimal, currency: String) -> String { value.formatted(.currency(code: currency)) }
    static func decimal(_ string: String) -> String? {
        let normalized = string.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard normalized.range(of: "^\\d{1,10}(\\.\\d{1,8})?$", options: .regularExpression) != nil else { return nil }
        return Decimal.amount(normalized).plainString
    }
    static func time(_ date: Date, calendar: Calendar) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: calendar.timeZone))
    }
    static func timeRange(_ entry: TimeEntry, calendar: Calendar) -> String {
        "\(time(entry.start, calendar: calendar)) – \(entry.end.map { time($0, calendar: calendar) } ?? "en cours")"
    }
}

extension TimeEntry {
    var displayTitle: String { title.isEmpty ? "Sans description" : title }
}

extension Workspace {
    /// "Client · Project", omitting whichever part is missing.
    func label(forProject id: UUID, separator: String = " · ") -> String {
        let project = project(id)
        return [project.flatMap(client(for:))?.name, project?.name].compactMap { $0 }.joined(separator: separator)
    }
}

// MARK: - Surfaces

extension View {
    func card(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(
                    Theme.hairline, lineWidth: 0.5))
    }
    /// Secondary label above a value or for a column, in the system's subheadline style.
    func fieldLabel() -> some View { font(.subheadline).foregroundStyle(.secondary) }
    /// Hover feedback for menu-like rows (menu-bar panel). Lists and tables do not use it.
    func hoverHighlight() -> some View { modifier(HoverHighlight()) }
}

private struct HoverHighlight: ViewModifier {
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovered ? 0.045 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
            .onHover { hovered = $0 }
    }
}

// MARK: - Components

struct ProjectMark: View {
    let color: ProjectColor
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(color.tint).frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct KeyCap: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }
    var body: some View {
        Text(keys)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 18)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

struct CardHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// The system's empty state, with at most one action.
struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var action: String? = nil
    var perform: () -> Void = {}
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(detail)
        } actions: {
            if let action { Button(action, action: perform) }
        }
    }
}
