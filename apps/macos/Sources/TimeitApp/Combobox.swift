import SwiftUI

/// One choice in a `Combobox`.
struct ComboboxOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    var detail: String? = nil
    var dot: Color? = nil
    /// Options with the same section are listed under one header, in the order given.
    var section: String? = nil
    /// Extra text matched by the search, beyond the title and detail.
    var keywords = ""
}

/// A select with a search field, after shadcn's combobox: an input-shaped trigger opens a popover where typing
/// filters the options, ↑↓ moves, Return picks and Escape closes. `create`, when given, offers the typed text
/// as a new value when nothing matches it exactly.
struct Combobox<ID: Hashable>: View {
    let options: [ComboboxOption<ID>]
    @Binding var selection: ID?
    var placeholder = "Choisir…"
    var searchPrompt = "Rechercher…"
    var large = false
    var create: ((String) -> Void)? = nil
    @State private var open = false

    var body: some View {
        let selected = options.first { $0.id == selection }
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 8) {
                if let dot = selected?.dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(selected?.title ?? placeholder).lineLimit(1)
                    .foregroundStyle(selected == nil ? .secondary : .primary)
                if let detail = selected?.detail { Text(detail).lineLimit(1).foregroundStyle(.secondary) }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(.secondary)
            }
            .inputFrame(large: large, focused: open)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected?.title ?? placeholder)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ComboboxList(
                options: options, selection: selection, searchPrompt: searchPrompt, create: create
            ) { id in
                selection = id
                open = false
            } onCreate: { text in
                create?(text)
                open = false
            } onClose: {
                open = false
            }
        }
    }
}

struct ComboboxList<ID: Hashable>: View {
    let options: [ComboboxOption<ID>]
    let selection: ID?
    let searchPrompt: String
    let create: ((String) -> Void)?
    let onPick: (ID) -> Void
    let onCreate: (String) -> Void
    let onClose: () -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    /// A row is either an option or the "create" action at the end.
    private enum Row: Hashable {
        case option(Int)
        case create(String)
    }

    var body: some View {
        let matches = options.indices.filter { self.matches(options[$0]) }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let offersCreate =
            create != nil && !trimmed.isEmpty
            && !options.contains {
                $0.title.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        let rows = matches.map(Row.option) + (offersCreate ? [Row.create(trimmed)] : [])
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(searchPrompt, text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { pick(rows) }
                    .onKeyPress(.downArrow) {
                        move(1, count: rows.count)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        move(-1, count: rows.count)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        onClose()
                        return .handled
                    }
            }
            .padding(.horizontal, 12).frame(height: 38)
            .overlay(alignment: .bottom) { Rectangle().fill(Control.border).frame(height: 1) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if rows.isEmpty {
                            Text("Aucun résultat.").foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 20)
                        }
                        ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                            if case .option(let optionIndex) = row, let section = options[optionIndex].section,
                                index == 0 || sectionOf(rows[index - 1]) != section
                            {
                                Text(section).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 8).padding(.top, index == 0 ? 2 : 8).padding(.bottom, 2)
                            }
                            rowView(row, highlighted: index == highlighted)
                                .id(index)
                                .onHover { if $0 { highlighted = index } }
                                .onTapGesture {
                                    highlighted = index
                                    pick(rows)
                                }
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 280)
                .onChange(of: highlighted) { _, value in proxy.scrollTo(value) }
            }
        }
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            highlighted = matches.firstIndex { options[$0].id == selection } ?? 0
            focused = true
        }
        .onChange(of: query) { highlighted = 0 }
    }

    @ViewBuilder private func rowView(_ row: Row, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            switch row {
            case .option(let index):
                let option = options[index]
                if let dot = option.dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(option.title).lineLimit(1)
                    // Short codes beside a name line up in a column.
                    .frame(minWidth: option.detail != nil && option.title.count <= 4 ? 40 : nil, alignment: .leading)
                if let detail = option.detail { Text(detail).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 4)
                if option.id == selection { Image(systemName: "checkmark").imageScale(.small) }
            case .create(let text):
                Image(systemName: "plus").imageScale(.small).foregroundStyle(.secondary)
                Text("Créer « \(text) »").lineLimit(1)
                Spacer(minLength: 4)
            }
        }
        .padding(.horizontal, 8).frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: Control.radius - 2, style: .continuous)
                .fill(highlighted ? Control.muted : .clear)
        )
        .contentShape(Rectangle())
    }

    private func matches(_ option: ComboboxOption<ID>) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return [option.title, option.detail ?? "", option.section ?? "", option.keywords]
            .contains { $0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
    private func sectionOf(_ row: Row) -> String? {
        if case .option(let index) = row { return options[index].section }
        return nil
    }
    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        highlighted = (highlighted + delta + count) % count
    }
    private func pick(_ rows: [Row]) {
        guard rows.indices.contains(highlighted) else { return }
        switch rows[highlighted] {
        case .option(let index): onPick(options[index].id)
        case .create(let text): onCreate(text)
        }
    }
}
