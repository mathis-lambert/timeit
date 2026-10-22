import SwiftUI
import TimeitCore

struct CurrencyPicker: View {
    @Binding var selection: String
    private static let options = Locale.Currency.isoCurrencies.map(\.identifier).sorted().map { code in
        (code, "\(code) · \(Locale.current.localizedString(forCurrencyCode: code) ?? code)")
    }
    var body: some View {
        Picker("Devise", selection: $selection) {
            ForEach(Self.options, id: \.0) { code, label in Text(label).tag(code) }
        }
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
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(title: request.entry == nil ? "Ajouter une session" : "Modifier la session")
            Form {
                TextField("Activité", text: $title).focused($focused)
                Picker("Projet", selection: $projectID) {
                    ForEach(store.workspace.projects.filter { !$0.archived || $0.id == request.entry?.projectID }) {
                        project in
                        Text(store.workspace.label(forProject: project.id, separator: " / ")).tag(
                            Optional(project.id))
                    }
                }
                DatePicker("Début", selection: $start, displayedComponents: [.date, .hourAndMinute])
                if !running { DatePicker("Fin", selection: $end, displayedComponents: [.date, .hourAndMinute]) }
                Toggle("Facturable", isOn: $billable)
                if editsRunningEntry { Toggle("Timer en cours", isOn: $running) }
            }.formStyle(.grouped).scrollDisabled(true).frame(height: running ? 230 : 260)
            if let project = projectID.flatMap(store.workspace.project) {
                HStack(spacing: 18) {
                    Label(
                        Display.duration((running ? Date.now : end).timeIntervalSince(start)), systemImage: "timer")
                    Label(
                        "\(Display.money(.amount(request.entry?.projectID == project.id ? request.entry!.hourlyRate : project.hourlyRate), currency: project.currency)) / h",
                        systemImage: "eurosign")
                }
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            if let validation {
                Label(validation, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            }
            HStack {
                if let entry = request.entry {
                    Button("Supprimer", systemImage: "trash", role: .destructive) {
                        store.delete(entry)
                        dismiss()
                    }
                }
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer", action: save).keyboardShortcut(.defaultAction)
                    .disabled(projectID == nil)
            }
        }.padding(20).frame(width: 460).onAppear { focused = true }
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
            Form {
                Section {
                    TextField("Nom du projet", text: $name).focused($focused)
                    Picker("Client", selection: $clientID) {
                        Text("Nouveau client…").tag(Optional<UUID>.none)
                        ForEach(store.workspace.clients) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if clientID == nil { TextField("Nom du client", text: $newClient) }
                    LabeledContent("Couleur") {
                        ColorSwatches(selection: $color)
                    }
                }
                Section {
                    Toggle("Temps facturable", isOn: $billable)
                    CurrencyPicker(selection: $currency)
                    TextField("Tarif horaire HT", text: $hourlyRate).disabled(!billable)
                } footer: {
                    Text(
                        "Un changement de tarif s’applique aux nouvelles sessions. L’historique conserve son tarif d’origine."
                    )
                }
            }.formStyle(.grouped).scrollDisabled(true).frame(height: clientID == nil ? 360 : 320)
            if let validation {
                Label(validation, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.project == nil ? "Créer le projet" : "Enregistrer", action: save).keyboardShortcut(
                    .defaultAction
                )
            }
        }.padding(20).frame(width: 460)
            .onAppear { focused = true }
    }
    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanClient = newClient.trimmingCharacters(in: .whitespacesAndNewlines)
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
            Text(title).font(.title2.weight(.semibold))
            if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
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
                    Circle().fill(color.tint).frame(width: 18, height: 18)
                        .padding(3)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.5 : 0), lineWidth: 1.5))
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
