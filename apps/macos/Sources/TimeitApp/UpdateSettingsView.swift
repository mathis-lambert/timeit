import SwiftUI

struct UpdateSettingsView: View {
    @Bindable var updater: AppUpdater

    var body: some View {
        Form {
            Section {
                Picker("Canal", selection: Binding(get: { updater.channel }, set: { updater.select($0) })) {
                    ForEach(UpdateChannel.allCases) { Text($0.title).tag($0) }
                }
                .disabled(updater.sessionInProgress)
                Text(updater.channel.explanation).foregroundStyle(.secondary)
            } header: {
                Text("Versions reçues")
            } footer: {
                Text(
                    "Tous les canaux utilisent la même app et les mêmes données. Revenir à Stable conserve la version installée jusqu’à la prochaine stable plus récente."
                )
            }
            if updater.channel != .stable {
                Section {
                    Label(
                        "Ces versions peuvent contenir des erreurs. Gardez une sauvegarde de vos données.",
                        systemImage: "exclamationmark.triangle")
                }
            }
            Section("Recherche de mises à jour") {
                if let reason = updater.unavailableReason {
                    Text(reason).foregroundStyle(.secondary)
                } else {
                    Toggle(
                        "Rechercher automatiquement",
                        isOn: Binding(
                            get: { updater.automaticallyChecks }, set: { updater.setAutomaticChecks($0) }))
                    if let date = updater.lastCheck {
                        LabeledContent(
                            "Dernière recherche", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Button("Rechercher des mises à jour…", action: updater.check).disabled(!updater.canCheck)
            }
        }.formStyle(.grouped)
    }
}
