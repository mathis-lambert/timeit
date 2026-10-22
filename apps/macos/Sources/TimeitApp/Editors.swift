import SwiftUI
import TimeitCore

/// Every ISO currency, searchable by code or name.
struct CurrencyPicker: View {
    @Binding var selection: String
    /// Currencies in circulation; withdrawn ones (ADP, AFA…) are left out.
    private static let options = Locale.commonISOCurrencyCodes.sorted().map { code in
        ComboboxOption(id: code, title: code, detail: Locale.current.localizedString(forCurrencyCode: code))
    }
    var body: some View {
        Combobox(
            options: Self.options,
            selection: Binding(get: { selection }, set: { if let code = $0 { selection = code } }),
            searchPrompt: "Code ou nom de devise…"
        )
        .accessibilityLabel("Devise")
    }
}

struct EntryEditor: View {
    let store: AppStore
    let request: EntryEditorRequest
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var projectID: UUID?
    @State private var start: Date
    @State private var end: Date
    @State private var running: Bool
    @State private var billable: Bool
    @State private var validation: String?
    @FocusState private var focused: Bool
    private let editsRunningEntry: Bool

    init(store: AppStore, request: EntryEditorRequest) {
        self.store = store
        self.request = request
        let projectID = request.entry?.projectID ?? store.nextTimerProject?.id
        editsRunningEntry = request.entry.map { $0.end == nil } ?? false
        _title = State(initialValue: request.entry?.title ?? "")
        _projectID = State(initialValue: projectID)
        _start = State(initialValue: request.entry?.start ?? request.start ?? .now.addingTimeInterval(-3600))
        _end = State(
            initialValue: request.entry?.end ?? request.end
                ?? min(.now, (request.start ?? .now).addingTimeInterval(3600)))
        _running = State(initialValue: editsRunningEntry)
        _billable = State(
            initialValue: request.entry?.billable ?? projectID.flatMap(store.workspace.project)?.billable ?? true)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(
                title: request.entry == nil ? "Ajouter une session" : "Modifier la session",
                subtitle: "Le tarif et les prélèvements sont figés avec la session.")
            FieldRow(label: "Activité") {
                TextField("Sur quoi avez-vous travaillé ?", text: $title).timeitField().focused($focused)
            }
            FieldRow(label: "Projet") {
                ProjectMenu(store: store, selection: $projectID, includeArchived: request.entry?.projectID)
            }
            HStack(alignment: .top, spacing: 12) {
                FieldRow(label: "Début") { DateTimeField(date: $start, calendar: store.calendar) }
                if !running {
                    FieldRow(label: "Fin") { DateTimeField(date: $end, calendar: store.calendar) }
                }
            }
            if let project = projectID.flatMap(store.workspace.project) {
                HStack(spacing: 8) {
                    Badge(text: Display.duration((running ? Date.now : end).timeIntervalSince(start)))
                    Badge(
                        text:
                            "\(Display.money(.amount(request.entry?.projectID == project.id ? request.entry!.hourlyRate : project.hourlyRate), currency: project.currency)) / h"
                    )
                }
                .monospacedDigit()
            }
            SwitchRow(title: "Facturable", detail: "Compte dans les honoraires et le net estimé.", isOn: $billable)
            if editsRunningEntry {
                SwitchRow(title: "Timer en cours", detail: "Désactivez pour fixer une heure de fin.", isOn: $running)
            }
            if let validation {
                Label(validation, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                if let entry = request.entry {
                    Button {
                        store.delete(entry)
                        dismiss()
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                    .buttonStyle(TimeitButtonStyle(kind: .destructiveGhost))
                }
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.outline)
                Button("Enregistrer", action: save).keyboardShortcut(.defaultAction).buttonStyle(.primary)
                    .disabled(projectID == nil)
            }
            .padding(.top, 4)
        }
        .padding(24).frame(width: 480)
        .onAppear { focused = true }
        .onChange(of: projectID) { _, id in
            if let project = id.flatMap(store.workspace.project) { billable = project.billable }
        }
    }
    private func save() {
        guard let project = projectID.flatMap(store.workspace.project) else { return }
        var entry =
            request.entry
            ?? TimeEntry(
                project: project, title: title, start: start, end: end, policy: store.workspace.policy(at: start))
        if entry.projectID != project.id {
            entry.projectID = project.id
            entry.currency = project.currency
            entry.hourlyRate = project.hourlyRate
        }
        entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.start = start
        entry.end = running ? nil : end
        entry.billable = billable
        if let message = EntryValidation.message(for: entry) {
            validation = message
            return
        }
        if store.save(entry: entry) { dismiss() }
    }
}

struct ProjectEditor: View {
    let store: AppStore
    let request: ProjectEditorRequest
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var clientID: UUID?
    @State private var newClient = ""
    @State private var currency: String
    @State private var hourlyRate: String
    @State private var color: ProjectColor
    @State private var billable: Bool
    @State private var validation: String?
    @FocusState private var focused: Bool

    init(store: AppStore, request: ProjectEditorRequest) {
        self.store = store
        self.request = request
        _name = State(initialValue: request.project?.name ?? "")
        _clientID = State(initialValue: request.project?.clientID ?? store.workspace.clients.first?.id)
        _currency = State(initialValue: request.project?.currency ?? store.workspace.profile.currency)
        _hourlyRate = State(initialValue: request.project?.hourlyRate ?? "")
        _color = State(initialValue: request.project?.color ?? .coral)
        _billable = State(initialValue: request.project?.billable ?? true)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(
                title: request.project == nil ? "Nouveau projet" : "Modifier le projet",
                subtitle: "Un client, un tarif, et vous êtes prêt à commencer.")
            FieldRow(label: "Nom") {
                TextField("Refonte du site", text: $name).timeitField().focused($focused)
            }
            FieldRow(label: "Client") {
                Combobox(
                    options: store.workspace.clients.map { ComboboxOption(id: $0.id, title: $0.name) },
                    selection: $clientID,
                    placeholder: newClient.isEmpty ? "Choisir ou créer un client" : "Nouveau : \(newClient)",
                    searchPrompt: "Rechercher ou créer un client…"
                ) { name in
                    clientID = nil
                    newClient = name
                }
            }
            FieldRow(label: "Couleur") { ColorSwatches(selection: $color) }
            SwitchRow(title: "Temps facturable", detail: "Les sessions comptent dans les honoraires.", isOn: $billable)
            if billable {
                HStack(alignment: .top, spacing: 12) {
                    FieldRow(label: "Tarif horaire HT") {
                        TextField("85,00", text: $hourlyRate).timeitField().monospacedDigit()
                    }
                    .frame(width: 150)
                    FieldRow(label: "Devise") { CurrencyPicker(selection: $currency) }
                }
                Text("Un nouveau tarif s’applique aux sessions suivantes ; l’historique garde le sien.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let validation {
                Label(validation, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.outline)
                Button(request.project == nil ? "Créer le projet" : "Enregistrer", action: save)
                    .keyboardShortcut(.defaultAction).buttonStyle(.primary)
            }
            .padding(.top, 4)
        }
        .padding(24).frame(width: 480)
        .onAppear { focused = true }
    }
    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanClient = newClient.trimmingCharacters(in: .whitespacesAndNewlines)
        // Typing a client that already exists picks it instead of creating a twin.
        let existing = store.workspace.clients.first {
            $0.name.compare(cleanClient, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard !cleanName.isEmpty, cleanName.count <= 150,
            clientID != nil || (!cleanClient.isEmpty && cleanClient.count <= 150)
        else {
            validation = "Renseignez un nom de projet et un client (150 caractères maximum)."
            return
        }
        guard let rate = Display.decimal(billable ? hourlyRate : "0") else {
            validation = "Saisissez un tarif positif, par exemple 85 ou 85,50."
            return
        }
        let clientID = clientID ?? existing?.id
        let client = clientID == nil ? Client(name: cleanClient, color: color) : nil
        let project = Project(
            id: request.project?.id ?? UUID(), clientID: clientID ?? client!.id, name: cleanName, color: color,
            currency: currency, hourlyRate: rate, billable: billable, archived: request.project?.archived ?? false)
        if store.save(project: project, client: client) { dismiss() }
    }
}

struct SheetHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}

struct ColorSwatches: View {
    @Binding var selection: ProjectColor
    var body: some View {
        HStack(spacing: 6) {
            ForEach(ProjectColor.allCases, id: \.self) { color in
                let selected = color == selection
                Button {
                    selection = color
                } label: {
                    Circle().fill(color.tint).frame(width: 20, height: 20)
                        .overlay {
                            if selected {
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                            }
                        }
                        .padding(3)
                        .overlay(Circle().strokeBorder(selected ? color.tint : .clear, lineWidth: 1.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(color.label)
                .accessibilityLabel(color.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
