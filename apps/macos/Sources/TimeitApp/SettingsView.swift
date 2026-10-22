import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import TimeitCore

struct SettingsView: View {
    @Bindable var store: AppStore
    @State private var name = ""
    @State private var currency = "EUR"
    @State private var goal = 35
    @State private var contributions = "0"
    @State private var incomeTax = "0"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var validation: String?
    @State private var saved = false
    var body: some View {
        TabView {
            Form {
                Section("Votre espace") {
                    TextField("Nom", text: $name)
                    CurrencyPicker(selection: $currency)
                    Stepper("Objectif hebdomadaire : \(goal) h", value: $goal, in: 1...168)
                }
                Section {
                    TextField("Cotisations (%)", text: $contributions)
                    TextField("Impôts (%)", text: $incomeTax)
                } header: {
                    Text("Estimation des prélèvements")
                } footer: {
                    Text(
                        "Les deux pourcentages s’appliquent aux honoraires bruts HT. Ils sont enregistrés avec les nouvelles sessions. Le net affiché est une estimation, distincte des encaissements."
                    )
                }
                if let validation { Text(validation).foregroundStyle(.red) }
                HStack {
                    if saved { Label("Réglages enregistrés", systemImage: "checkmark").foregroundStyle(.secondary) }
                    Spacer()
                    Button("Enregistrer", action: save).buttonStyle(.glassProminent)
                }
            }.formStyle(.grouped).tabItem { Label("Compte", systemImage: "person.crop.circle") }
            Form {
                Section {
                    TextField("Adresse du serveur", text: $store.serverURL).disabled(
                        store.connected || store.isConnecting)
                    HStack {
                        Label(store.syncLabel, systemImage: store.connected ? "checkmark.icloud" : "icloud")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if store.isConnecting {
                            ProgressView().controlSize(.small)
                        } else if store.connected {
                            Button("Synchroniser") { Task { await store.synchronize() } }.disabled(store.isSyncing)
                            Button("Déconnecter") { store.disconnect() }
                        } else {
                            Button("Connecter mon compte") { Task { await store.connect() } }.buttonStyle(
                                .glassProminent
                            ).disabled(store.isDemo)
                        }
                    }
                } header: {
                    Text("Synchronisation")
                } footer: {
                    Text(
                        store.isDemo
                            ? "Quittez l’espace d’exemple pour connecter votre compte."
                            : "La connexion s’ouvre dans le navigateur sécurisé du système. Les fournisseurs Google et Apple sont gérés par votre serveur. Votre travail reste disponible hors ligne."
                    )
                }
                Section("Vos données") {
                    Text(
                        "Les sessions sont sauvegardées immédiatement dans la base SQLite de ce Mac. En cas de conflit, Timeit conserve une copie locale de la version remplacée."
                    ).foregroundStyle(.secondary)
                    Button("Ouvrir le dossier des données") {
                        if let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                            .first?.appendingPathComponent("Timeit")
                        {
                            NSWorkspace.shared.open(folder)
                        }
                    }
                }
            }.formStyle(.grouped).tabItem { Label("Cloud", systemImage: "icloud") }
            Form {
                Section("Au quotidien") {
                    Toggle("Ouvrir Timeit à la connexion", isOn: $launchAtLogin).onChange(of: launchAtLogin) {
                        _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            store.showError(error)
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                    KeyboardShortcuts.Recorder("Démarrer / arrêter le timer", name: .toggleTimer)
                }
                Section("Raccourcis dans l’app") {
                    LabeledContent("Nouvelle session", value: "⌘N")
                    LabeledContent("Choisir un projet", value: "⌘K")
                    LabeledContent("Démarrer / arrêter", value: "⌘↩")
                    LabeledContent("Annuler une suppression", value: "⌘Z")
                }
            }.formStyle(.grouped).tabItem { Label("Général", systemImage: "slider.horizontal.3") }
        }.padding(16).frame(width: 570, height: 470)
            .onAppear {
                name = store.workspace.profile.name
                currency = store.workspace.profile.currency
                goal = store.workspace.profile.weeklyGoal
                let policy = store.workspace.policy(at: .now)
                contributions = policy.contributions
                incomeTax = policy.incomeTax
            }
    }
    private func save() {
        guard let social = Display.decimal(contributions), let tax = Display.decimal(incomeTax),
            contributions.replacingOccurrences(of: ",", with: ".").range(
                of: "^\\d{1,3}(\\.\\d{1,4})?$", options: .regularExpression) != nil,
            incomeTax.replacingOccurrences(of: ",", with: ".").range(
                of: "^\\d{1,3}(\\.\\d{1,4})?$", options: .regularExpression) != nil,
            Decimal.amount(social) + Decimal.amount(tax) <= 100
        else {
            validation = "Saisissez des pourcentages positifs dont la somme ne dépasse pas 100 %."
            return
        }
        guard name.count <= 500 else {
            validation = "Le nom est trop long."
            return
        }
        if store.updateProfile(
            name: name.isEmpty ? "Mon espace" : name, currency: currency, goal: goal, contributions: social,
            incomeTax: tax)
        {
            validation = nil
            saved = true
        }
    }
}
