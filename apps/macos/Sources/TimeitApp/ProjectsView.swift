import SwiftUI
import TimeitCore

/// Projects grouped by client, each client a card holding a table: project, rate, this week, total.
struct ProjectsView: View {
    @Bindable var store: AppStore
    @State private var showArchived = false
    @State private var editingClient: Client?

    var body: some View {
        let weekSeconds = store.weekSecondsByProject
        let totals = Dictionary(grouping: store.workspace.entries, by: \.projectID).mapValues {
            $0.reduce(0) { $0 + $1.duration() }
        }
        let groups = store.workspace.clients.compactMap { client -> (Client, [Project])? in
            let projects = store.workspace.projects.filter { $0.clientID == client.id && $0.archived == showArchived }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return projects.isEmpty ? nil : (client, projects)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if groups.isEmpty {
                    EmptyState(
                        symbol: showArchived ? "archivebox" : "folder",
                        title: showArchived ? "Aucune archive" : "Aucun projet",
                        detail: showArchived
                            ? "Les projets archivés gardent leur historique dans les rapports."
                            : "Créez un projet pour commencer à suivre votre temps.",
                        action: showArchived ? nil : "Nouveau projet"
                    ) { store.projectEditor = ProjectEditorRequest() }
                    .frame(minHeight: 360)
                }
                ForEach(groups, id: \.0.id) { client, projects in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Text(client.name).font(.headline)
                            Badge(text: "\(projects.count)")
                            Spacer()
                            Menu {
                                Button("Renommer le client…") { editingClient = client }
                            } label: {
                                Image(systemName: "ellipsis").frame(width: 26, height: 26).contentShape(Rectangle())
                            }
                            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                            .foregroundStyle(.secondary)
                            .help("Actions du client")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        ColumnHeader {
                            Text("Projet").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Tarif").frame(width: 130, alignment: .leading)
                            Text("Cette semaine").frame(width: 100, alignment: .trailing)
                            Text("Total").frame(width: 80, alignment: .trailing)
                            Color.clear.frame(width: 56)
                        }
                        ForEach(projects) { project in
                            ProjectRow(
                                store: store, project: project, week: weekSeconds[project.id] ?? 0,
                                total: totals[project.id] ?? 0, isLast: project.id == projects.last?.id)
                        }
                    }
                    .card(padding: 0)
                }
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 1160).frame(maxWidth: .infinity)
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

private struct ProjectRow: View {
    let store: AppStore
    let project: Project
    let week: TimeInterval
    let total: TimeInterval
    let isLast: Bool
    var body: some View {
        let live = store.running?.projectID == project.id
        ListRow(highlighted: live ? project.color.tint : nil, showsRule: !isLast) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Circle().fill(project.color.tint).frame(width: 8, height: 8)
                    Text(project.name).lineLimit(1)
                    if live { Badge(text: "En cours", tint: project.color.tint) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if project.billable {
                        Text("\(Display.money(.amount(project.hourlyRate), currency: project.currency)) / h")
                            .monospacedDigit().foregroundStyle(.secondary)
                    } else {
                        Badge(text: "Non facturable")
                    }
                }
                .frame(width: 130, alignment: .leading)
                Text(Display.duration(week)).monospacedDigit().frame(width: 100, alignment: .trailing)
                Text(Display.duration(total)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                HStack(spacing: 2) {
                    if !project.archived {
                        IconButton(symbol: "play.fill", label: "Démarrer \(project.name)") {
                            store.start(project: project)
                        }
                    }
                    IconButton(symbol: "pencil", label: "Modifier \(project.name)") {
                        store.projectEditor = ProjectEditorRequest(project: project)
                    }
                }
                .frame(width: 56, alignment: .trailing)
            }
        }
        .onTapGesture(count: 2) { store.projectEditor = ProjectEditorRequest(project: project) }
        .contextMenu {
            Button("Modifier…") { store.projectEditor = ProjectEditorRequest(project: project) }
            if !project.archived { Button("Démarrer") { store.start(project: project) } }
            Divider()
            Button(project.archived ? "Restaurer" : "Archiver") { store.archive(project) }
        }
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
            TextField("Nom du client", text: $name).timeitField()
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.outline)
                Button("Enregistrer") {
                    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if store.change({ document in
                        if let index = document.clients.firstIndex(where: { $0.id == client.id }) {
                            document.clients[index].name = clean
                        }
                    }) {
                        dismiss()
                    }
                }.keyboardShortcut(.defaultAction).buttonStyle(.primary).disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 150)
            }
        }.padding(20).frame(width: 360)
    }
}
