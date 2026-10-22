import Foundation

public enum DemoData {
    public static func make(now: Date = .now) -> LocalState {
        var state = LocalState()
        state.document.profile.name = "Alex Martin"
        state.document.taxPolicies = [TaxPolicy(contributions: "25", incomeTax: "5")]
        let clients = [
            Client(name: "Studio Nord", color: .coral), Client(name: "Orbit", color: .blue),
            Client(name: "Atelier", color: .green),
        ]
        let projects = [
            Project(clientID: clients[0].id, name: "Identité & expérience", color: .coral, hourlyRate: "85"),
            Project(clientID: clients[1].id, name: "Application iOS", color: .blue, currency: "USD", hourlyRate: "110"),
            Project(clientID: clients[2].id, name: "Site & direction artistique", color: .green, hourlyRate: "75"),
            Project(clientID: clients[0].id, name: "Administration", color: .gold, hourlyRate: "0", billable: false),
        ]
        state.document.clients = clients
        state.document.projects = projects
        let calendar = state.document.calendar
        let titles = [
            "Explorations & pistes créatives", "Composants et interactions", "Point projet & ajustements",
            "Recherche et conception", "Intégration des écrans", "Revue et finitions",
        ]
        for offset in 0..<18 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)),
                !calendar.isDateInWeekend(day)
            else { continue }
            for slot in 0..<3 {
                let project = projects[(offset + slot) % projects.count]
                let start = calendar.date(
                    bySettingHour: [9, 11, 14][slot], minute: slot == 1 ? 30 : 0, second: 0, of: day)!
                let end = start.addingTimeInterval([7200.0, 5400, 9000][slot] - Double(offset % 3) * 900)
                guard end < now else { continue }
                state.document.entries.append(
                    TimeEntry(
                        project: project, title: titles[(offset + slot) % titles.count], start: start, end: end,
                        policy: state.document.taxPolicies[0]))
            }
            state.rates.append(
                ExchangeRate(
                    base: "USD", quote: "EUR", requestedDate: WireFormat.day(day, calendar: calendar),
                    observedDate: WireFormat.day(day, calendar: calendar), rate: "0.89", source: "Exemple fictif"))
        }
        return state
    }
}
