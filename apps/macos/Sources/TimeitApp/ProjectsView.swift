import SwiftUI
import TimeitCore

/// Projects as a native table: name, client, rate, this week and total; actions in the context menu.
struct ProjectsView: View {
    @Bindable var store: AppStore
    @State private var showArchived = false
    @State private var selection: Set<UUID> = []
    @State private var editingClient: Client?

    private struct Row: Identifiable {
        let project: Project
        let client: Client?
        let week: TimeInterval
        let total: TimeInterval
        var id: UUID { project.id }
    }

    var body: some View {
        let weekSeconds = store.weekSecondsByProject
        let totals = Dictionary(grouping: store.workspace.entries, by: \.projectID).mapValues {
            $0.reduce(0) { $0 + $1.duration() }
        }
        let rows = store.workspace.projects.filter { $0.archived == showArchived }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map {
                Row(
                    project: $0, client: store.workspace.client(for: $0), week: weekSeconds[$0.id] ?? 0,
                    total: totals[$0.id] ?? 0)
            }
        Table(rows, selection: $selection) {
            TableColumn("Projet") { row in
                Label {
                    Text(row.project.name)
                } icon: {
                    Image(systemName: store.running?.projectID == row.id ? "record.circle" : "circle.fill")
                        .foregroundStyle(row.project.color.tint).imageScale(.small)
                }
            }
            TableColumn("Client") { row in Text(row.client?.name ?? "").foregroundStyle(.secondary) }
            TableColumn("Tarif") { row in
                Text(
                    row.project.billable
                        ? "\(Display.money(.amount(row.project.hourlyRate), currency: row.project.currency)) / h"
                        : "Non facturable"
                )
                .monospacedDigit().foregroundStyle(.secondary)
            }
            TableColumn("Cette semaine") { row in
                Text(Display.duration(row.week)).monospacedDigit()
            }
            .width(min: 90, ideal: 110)
            .alignment(.trailing)
            TableColumn("Total") { row in
                Text(Display.duration(row.total)).monospacedDigit().foregroundStyle(.secondary)

            }
            .width(min: 80, ideal: 100)
            .alignment(.trailing)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let project = store.workspace.project(id) {
                Button("Modifier…") { store.projectEditor = ProjectEditorRequest(project: project) }
                if !project.archived { Button("Démarrer") { store.start(project: project) } }
                if let client = store.workspace.client(for: project) {
                    Button("Renommer « \(client.name) »…") { editingClient = client }
                }
                Divider()
                Button(project.archived ? "Restaurer" : "Archiver") { store.archive(project) }
            }
        } primaryAction: { ids in
            if let id = ids.first, let project = store.workspace.project(id) {
                store.projectEditor = ProjectEditorRequest(project: project)
            }
        }
        .overlay {
            if rows.isEmpty {
                EmptyState(
                    symbol: showArchived ? "archivebox" : "folder",
                    title: showArchived ? "Aucune archive" : "Aucun projet",
                    detail: showArchived
                        ? "Les projets archivés gardent leur historique dans les rapports."
                        : "Créez un projet pour commencer à suivre votre temps.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Affichage", selection: $showArchived) {
                    Text("Actifs").tag(false)
                    Text("Archives").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.projectEditor = ProjectEditorRequest()
                } label: {
                    Label("Nouveau projet", systemImage: "folder.badge.plus")
                }
                .help("Nouveau projet (⌘⇧N)")
            }
        }
        .sheet(item: $editingClient) { client in ClientEditor(store: store, client: client) }
    }
}

private struct ClientEditor: View {
    let store: AppStore
    let client: Client
    @State private var name: String
    @Environment(\.dismiss) private var dismiss
    init(store: AppStore, client: Client) {
        self.store = store
        self.client = client
        _name = State(initialValue: client.name)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(title: "Renommer le client")
            TextField("Nom du client", text: $name)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if store.change({ document in
                        if let index = document.clients.firstIndex(where: { $0.id == client.id }) {
                            document.clients[index].name = clean
                        }
                    }) {
                        dismiss()
                    }
                }.keyboardShortcut(.defaultAction).disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 150)
            }
        }.padding(20).frame(width: 360)
    }
}
