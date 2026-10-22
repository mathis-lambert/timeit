import AppKit
import SwiftUI
import TimeitCore

/// Design tokens. See DESIGN.md.
enum Theme {
    static let accent = Color(light: 0xD9482A, dark: 0xF57352)
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
    /// State changes the user waits on: screen content, composer morph, palette.
    static let standard = Animation.smooth(duration: 0.28)
    /// Small feedback: hover, selection, press.
    static let quick = Animation.easeOut(duration: 0.14)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255, opacity: 1)
    }
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
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
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
    /// Small uppercase label used for column headers and metric names.
    func eyebrow() -> some View {
        font(.system(size: 10.5, weight: .semibold)).tracking(0.6).textCase(.uppercase).foregroundStyle(.secondary)
    }
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

// MARK: - Identity

/// The Timeit mark: a ring that fills with the week's progress toward the weekly goal.
struct BrandMark: View {
    var size: CGFloat = 22
    var progress: Double
    var body: some View {
        let line = max(2, size * 0.13)
        ZStack {
            Circle().stroke(Theme.accent.opacity(0.2), lineWidth: line)
            Circle().trim(from: 0, to: max(0.04, min(1, progress)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle().fill(Theme.accent).frame(width: size * 0.3, height: size * 0.3)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct Wordmark: View {
    var size: CGFloat = 19
    var body: some View {
        Text("timeit").font(.system(size: size, weight: .bold, design: .rounded)).tracking(-size * 0.03)
    }
}

/// Recording indicator. Static on purpose: a repeating effect here forces the whole
/// glass window to recomposite every frame (≈100 % CPU while a timer runs).
struct LiveDot: View {
    var color: Color = Theme.accent
    var size: CGFloat = 8
    var body: some View {
        Image(systemName: "record.circle.fill")
            .font(.system(size: size + 2))
            .foregroundStyle(color)
            .accessibilityLabel("En cours")
    }
}

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
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 18)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

struct ProgressRing: View {
    let value: Double
    var tint: Color = Theme.accent
    var size: CGFloat = 36
    var line: CGFloat = 4
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: line)
            Circle().trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

/// Page header shared by every screen.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 26, weight: .bold)).tracking(-0.6)
                if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

struct CardHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                if let subtitle { Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary) }
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

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var action: String? = nil
    var perform: () -> Void = {}
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 26, weight: .regular)).foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            if let action {
                Button(action, action: perform).buttonStyle(.glassProminent).controlSize(.large).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(36)
    }
}
