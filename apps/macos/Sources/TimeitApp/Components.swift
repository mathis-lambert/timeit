import SwiftUI
import TimeitCore

// The content's own controls, after shadcn/ui: crisp 1 pt borders, a neutral ink primary, quiet fills,
// a 3 pt focus ring and one radius family. The window, sidebar, toolbar and Settings stay native.

enum Control {
    static let height: CGFloat = 30
    static let largeHeight: CGFloat = 34
    static let radius: CGFloat = 7
    /// The only border color, for fields, outline buttons, cards and table rules.
    static let border = Color(light: 0xE4E4E7, dark: 0x3A3A3F)
    /// Neutral fills: `muted` at rest (secondary buttons, tabs), `hover` under the pointer.
    static let muted = Color(light: 0xF4F4F5, dark: 0x2C2C30)
    static let hover = Color.primary.opacity(0.05)
    static let pressed = Color.primary.opacity(0.10)
    /// Raised surfaces: cards, the selected tab, outline buttons and fields.
    static let surface = Color(light: 0xFFFFFF, dark: 0x1F1F22)
    /// Ink for the primary button and its inverse for the label.
    static let ink = Color(light: 0x18181B, dark: 0xFAFAFA)
    static let onInk = Color(light: 0xFAFAFA, dark: 0x18181B)
}

extension View {
    /// The faint shadow under fields and outline buttons.
    func shadowXS() -> some View { shadow(color: .black.opacity(0.05), radius: 1, y: 1) }
}

// MARK: - Buttons

/// Every content button. `primary`: the one main action of a context, in ink. `secondary`: a muted fill.
/// `outline`: a bordered surface. `ghost`: no fill until the pointer is over it. `destructive`: red, and
/// `destructiveGhost` for a red text action beside a dialog's buttons.
struct TimeitButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, outline, ghost, destructive, destructiveGhost }
    var kind: Kind = .outline
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind, large: large)
    }

    private struct StyledButton: View {
        let configuration: Configuration
        let kind: Kind
        let large: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Control.radius, style: .continuous)
            configuration.label
                .font(.body.weight(.medium))
                .lineLimit(1)
                .labelStyle(ButtonLabelStyle())
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .ghost || kind == .destructiveGhost ? 8 : 12)
                .frame(minHeight: large ? Control.largeHeight : Control.height)
                .background(background, in: shape)
                .overlay {
                    if kind == .outline { shape.strokeBorder(Control.border) }
                }
                .overlay {
                    // Hover and press tint whatever fill sits underneath, the ink included.
                    shape.fill(
                        configuration.isPressed ? Control.pressed : hovered && isEnabled ? Control.hover : .clear
                    )
                    .blendMode(kind == .primary ? .plusLighter : .normal)
                }
                .shadow(color: .black.opacity(kind == .primary || kind == .outline ? 0.05 : 0), radius: 1, y: 1)
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.12), value: hovered)
        }

        private var background: Color {
            switch kind {
            case .primary: Control.ink
            case .secondary: Control.muted
            case .outline: Control.surface
            case .ghost, .destructiveGhost: .clear
            case .destructive: .red
            }
        }
        private var foreground: Color {
            switch kind {
            case .primary: Control.onInk
            case .destructive: .white
            case .destructiveGhost: .red
            case .secondary, .outline, .ghost: .primary
            }
        }
    }
}

/// Icon and title close together, as in a push button.
private struct ButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

extension ButtonStyle where Self == TimeitButtonStyle {
    static var primary: TimeitButtonStyle { TimeitButtonStyle(kind: .primary) }
    static var secondary: TimeitButtonStyle { TimeitButtonStyle(kind: .secondary) }
    static var outline: TimeitButtonStyle { TimeitButtonStyle(kind: .outline) }
    static var ghost: TimeitButtonStyle { TimeitButtonStyle(kind: .ghost) }
    static var destructive: TimeitButtonStyle { TimeitButtonStyle(kind: .destructive) }
}

/// A square icon-only ghost button, for row actions.
struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).imageScale(.small).frame(width: 26, height: 26)
        }
        .buttonStyle(IconButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { IconButtonBody(configuration: configuration) }
    private struct IconButtonBody: View {
        let configuration: Configuration
        @State private var hovered = false
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Control.radius - 1, style: .continuous)
            configuration.label
                .foregroundStyle(hovered ? .primary : .secondary)
                .background(shape.fill(configuration.isPressed ? Control.pressed : hovered ? Control.muted : .clear))
                .contentShape(shape)
                .onHover { hovered = $0 }
        }
    }
}

// MARK: - Fields

extension View {
    /// A plain text field drawn as Timeit's input: a bordered surface, and a 3 pt accent ring while focused.
    func timeitField(large: Bool = false) -> some View { modifier(FieldStyle(large: large)) }
    /// The input frame alone, for controls that are not text fields (date pickers, menus).
    func inputFrame(large: Bool = false, focused: Bool = false) -> some View {
        modifier(InputFrame(large: large, focused: focused))
    }
}

private struct FieldStyle: ViewModifier {
    let large: Bool
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .focused($focused)
            .inputFrame(large: large, focused: focused)
    }
}

private struct InputFrame: ViewModifier {
    let large: Bool
    let focused: Bool
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Control.radius, style: .continuous)
        content
            .padding(.horizontal, 10)
            .frame(height: large ? Control.largeHeight : Control.height)
            .background(Control.surface, in: shape)
            .overlay { shape.strokeBorder(focused ? Theme.accent : Control.border) }
            .background {
                if focused {
                    shape.stroke(Theme.accent.opacity(0.25), lineWidth: 6)
                }
            }
            .shadowXS()
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

/// A field with its label above, the way the editors lay out their inputs.
struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.medium))
            content
        }
    }
}

// MARK: - Select fields

/// An input-shaped button showing the current choice, opening a menu of options.
struct SelectField<Options: View>: View {
    let title: String
    var placeholder = false
    var dot: Color? = nil
    var large = false
    @ViewBuilder var options: Options
    var body: some View {
        Menu {
            options
        } label: {
            HStack(spacing: 8) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(title).lineLimit(1).foregroundStyle(placeholder ? .secondary : .primary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(.secondary)
            }
            .inputFrame(large: large)
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .accessibilityValue(title)
    }
}

/// Picks a project, grouped by client, showing the project's color.
struct ProjectMenu: View {
    let store: AppStore
    @Binding var selection: UUID?
    var includeArchived: UUID? = nil
    var large = false
    var body: some View {
        let project = selection.flatMap(store.workspace.project)
        SelectField(
            title: project?.name ?? "Choisir un projet", placeholder: project == nil,
            dot: project?.color.tint ?? .secondary, large: large
        ) {
            ForEach(store.workspace.clients) { client in
                let projects = store.workspace.projects.filter {
                    $0.clientID == client.id && (!$0.archived || $0.id == includeArchived)
                }
                if !projects.isEmpty {
                    Picker(client.name, selection: $selection) {
                        ForEach(projects) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.inline)
                }
            }
        }
        .accessibilityLabel("Projet")
    }
}

/// A label and description on the left, a switch on the right.
struct SwitchRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn).toggleStyle(.switch).labelsHidden()
        }
        .padding(12)
        .overlay { RoundedRectangle(cornerRadius: Control.radius + 2, style: .continuous).strokeBorder(Control.border) }
    }
}

// MARK: - Tabs

/// Options side by side on a muted track; the selected one is a raised tab that slides between them.
struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    @Namespace private var selectionShape
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.body.weight(.medium))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .padding(.horizontal, 12).frame(height: Control.height - 6)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: Control.radius - 2, style: .continuous)
                                    .fill(Control.surface)
                                    .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "selection", in: selectionShape)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Control.muted, in: RoundedRectangle(cornerRadius: Control.radius + 1, style: .continuous))
        .animation(reduceMotion ? nil : Motion.shell, value: selection)
    }
}

// MARK: - Badge

/// A small label for a state ("Non facturable", "En cours", "Archivé").
struct Badge: View {
    let text: String
    var tint: Color? = nil
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint ?? .secondary)
            .padding(.horizontal, 6).frame(height: 18)
            .background(
                (tint ?? .primary).opacity(tint == nil ? 0.06 : 0.12),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

// MARK: - Tables

/// A table row: a rule below, a muted fill under the pointer, an accent wash when highlighted.
struct ListRow<Content: View>: View {
    var highlighted: Color? = nil
    var showsRule = true
    @ViewBuilder var content: Content
    @State private var hovered = false
    var body: some View {
        content
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(highlighted?.opacity(0.10) ?? (hovered ? Control.hover : .clear))
            .overlay(alignment: .bottom) {
                if showsRule { Rectangle().fill(Control.border).frame(height: 1) }
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

/// Column labels above a table, with the rule shadcn tables draw under their header.
struct ColumnHeader<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 12) { content }
            .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).frame(height: 36)
            .overlay(alignment: .bottom) { Rectangle().fill(Control.border).frame(height: 1) }
    }
}

/// A thin bar showing a share of a total.
struct ShareBar: View {
    let value: Double
    let tint: Color
    var width: CGFloat = 56
    var body: some View {
        Capsule().fill(Control.muted).frame(width: width, height: 4)
            .overlay(alignment: .leading) {
                Capsule().fill(tint).frame(width: width * min(1, max(0, value)), height: 4)
            }
            .accessibilityHidden(true)
    }
}
