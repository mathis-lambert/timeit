import SwiftUI
import TimeitCore

struct ProjectsView: View {
    @Bindable var store: AppStore
    @State private var showArchived = false
    @State private var editingClient: Client?
    var body: some View {
        let weekSeconds = store.weekSecondsByProject
        let totals = Dictionary(grouping: store.workspace.entries, by: \.projectID).mapValues {
            $0.reduce(0) { $0 + $1.duration() }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "Clients & projets",
                    subtitle:
                        "\(store.workspace.clients.count) clients · \(store.workspace.activeProjects.count) projets actifs"
                ) {
                    Picker("Affichage", selection: $showArchived) {
                        Text("Actifs").tag(false)
                        Text("Archives").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Button("Nouveau projet", systemImage: "plus") { store.projectEditor = ProjectEditorRequest() }
                        .buttonStyle(.glassProminent)
                }
                ForEach(store.workspace.clients) { client in
                    let projects = store.workspace.projects.filter {
                        $0.clientID == client.id && $0.archived == showArchived
                    }
                    if !projects.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(client.name).font(.system(size: 15, weight: .semibold))
                                Text("\(projects.count) projet\(projects.count > 1 ? "s" : "")")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                                Spacer()
                                Button("Renommer") { editingClient = client }
                                    .buttonStyle(.link).font(.system(size: 12))
                                    .accessibilityLabel("Renommer \(client.name)")
                            }
                            .padding(.horizontal, 4)
                            VStack(spacing: 0) {
                                ForEach(projects) { project in
                                    ProjectRow(
                                        store: store, project: project, week: weekSeconds[project.id] ?? 0,
                                        total: totals[project.id] ?? 0)
                                    if project.id != projects.last?.id { Divider().padding(.leading, 34) }
                                }
                            }
                            .card(padding: 6)
                        }
                    }
                }
                if showArchived && !store.workspace.projects.contains(where: \.archived) {
                    EmptyState(
                        symbol: "archivebox", title: "Aucune archive",
                        detail:
                            "Les projets terminés pourront être archivés. Leur historique restera dans vos rapports."
                    ).frame(height: 300)
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 12).padding(.bottom, 64)
            .frame(maxWidth: 1160).frame(maxWidth: .infinity)
        }
        .sheet(item: $editingClient) { client in ClientEditor(store: store, client: client) }
    }
}

private struct ProjectRow: View {
    let store: AppStore
    let project: Project
    let week: TimeInterval
    let total: TimeInterval
    @State private var hovered = false
    var body: some View {
        let live = store.running?.projectID == project.id
        HStack(spacing: 12) {
            ProjectMark(color: project.color, size: 10).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(project.name).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                    if live { LiveDot(color: project.color.tint, size: 6) }
                }
                Text(
                    project.billable
                        ? "\(Display.money(.amount(project.hourlyRate), currency: project.currency)) / h"
                        : "Non facturable"
                )
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Display.duration(week)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                Text("cette semaine").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            .frame(width: 90, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Display.duration(total)).font(.system(size: 13)).monospacedDigit().foregroundStyle(.secondary)
                Text("au total").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .trailing)
            HStack(spacing: 2) {
                if !project.archived {
                    Button {
                        store.start(project: project)
                    } label: {
                        Image(systemName: "play.fill").font(.system(size: 10))
                    }
                    .foregroundStyle(Theme.accent)
                    .help("Démarrer sur ce projet").accessibilityLabel("Démarrer \(project.name)")
                }
                Menu {
                    Button("Modifier…", systemImage: "pencil") {
                        store.projectEditor = ProjectEditorRequest(project: project)
                    }
                    Button(
                        project.archived ? "Restaurer le projet" : "Archiver le projet",
                        systemImage: project.archived ? "arrow.uturn.backward" : "archivebox"
                    ) { store.archive(project) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button).menuIndicator(.hidden).fixedSize()
                .help("Actions du projet")
            }
            .buttonStyle(.borderless)
            .frame(width: 56, alignment: .trailing)
            .opacity(hovered ? 1 : 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .hoverHighlight()
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) { store.projectEditor = ProjectEditorRequest(project: project) }
        .contextMenu {
            Button("Modifier…", systemImage: "pencil") { store.projectEditor = ProjectEditorRequest(project: project) }
            if !project.archived {
                Button("Démarrer", systemImage: "play") { store.start(project: project) }
            }
            Divider()
            Button(project.archived ? "Restaurer" : "Archiver", systemImage: "archivebox") { store.archive(project) }
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
            SheetHeader(title: "Modifier le client")
            TextField("Nom du client", text: $name).textFieldStyle(.roundedBorder).controlSize(.large)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.glass)
                Button("Enregistrer") {
                    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if store.change({ document in
                        if let index = document.clients.firstIndex(where: { $0.id == client.id }) {
                            document.clients[index].name = clean
                        }
                    }) {
                        dismiss()
                    }
                }.keyboardShortcut(.defaultAction).buttonStyle(.glassProminent).disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 150)
            }.controlSize(.large)
        }.padding(28).frame(width: 400)
    }
}
