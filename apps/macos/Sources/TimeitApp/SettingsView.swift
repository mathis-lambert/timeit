import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import TimeitCore

struct SettingsView: View {
    @Bindable var store: AppStore
    @Bindable var updater: AppUpdater
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
                    Button("Enregistrer", action: save).keyboardShortcut(.defaultAction)
                }
            }.formStyle(.grouped).tabItem { Label("Compte", systemImage: "person.crop.circle") }
            Form {
                Section("Synchronisation et sauvegarde cloud") {
                    Label("Pas encore disponible", systemImage: "icloud.slash")
                    Text(
                        "La connexion à un compte, la synchronisation entre Macs et la sauvegarde cloud ne sont pas encore disponibles. Aucune donnée n’est envoyée à un serveur."
                    )
                    .foregroundStyle(.secondary)
                }
                Section("Vos données") {
                    Text(
                        "Vos sessions sont enregistrées sur ce Mac. Pensez à sauvegarder ce dossier, par exemple avec Time Machine."
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
            UpdateSettingsView(updater: updater)
                .tabItem { Label("Mises à jour", systemImage: "arrow.triangle.2.circlepath") }
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
                    ForEach(AppShortcut.allCases, id: \.self) { LabeledContent($0.title, value: $0.label) }
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
    /// A percentage with at most 3 integer digits and 4 decimals, normalized like other amounts.
    private func percent(_ text: String) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard normalized.range(of: "^\\d{1,3}(\\.\\d{1,4})?$", options: .regularExpression) != nil else { return nil }
        return Display.decimal(normalized)
    }
    private func save() {
        guard let social = percent(contributions), let tax = percent(incomeTax),
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
