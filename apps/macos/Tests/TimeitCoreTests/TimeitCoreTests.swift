import Foundation
import Testing

@testable import TimeitCore

private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
private var utc: Calendar {
    var result = Calendar(identifier: .gregorian)
    result.timeZone = TimeZone(secondsFromGMT: 0)!
    return result
}
private func project(currency: String = "EUR", rate: String = "100") -> Project {
    Project(clientID: UUID(), name: "Test", currency: currency, hourlyRate: rate)
}

@Test func exactMoneyAndSeparateDeductions() {
    let entry = TimeEntry(
        project: project(currency: "USD"), title: "Work", start: date("2026-10-16T08:00:00Z"),
        end: date("2026-10-16T10:00:00Z"), policy: TaxPolicy(contributions: "25", incomeTax: "5"))
    let rate = ExchangeRate(
        base: "USD", quote: "EUR", requestedDate: "2026-10-16", observedDate: "2026-10-16", rate: "0.89", source: "test"
    )
    let total = Finance.summarize(
        [entry], currency: "EUR", period: DateInterval(start: entry.start, end: entry.end!), rates: [rate],
        now: entry.end!, calendar: utc)
    #expect(total.gross == Decimal.amount("178"))
    #expect(total.contributions == Decimal.amount("44.5"))
    #expect(total.incomeTax == Decimal.amount("8.9"))
    #expect(total.net == Decimal.amount("124.6"))
}

@Test func projectAndPolicyChangesPreserveHistoricalSnapshots() {
    var workspace = Workspace()
    var original = project(rate: "80")
    let first = TaxPolicy(effectiveFrom: date("2026-01-01T00:00:00Z"), contributions: "20", incomeTax: "5")
    workspace.taxPolicies = [
        first, TaxPolicy(effectiveFrom: date("2026-10-01T00:00:00Z"), contributions: "25", incomeTax: "6"),
    ]
    let entry = TimeEntry(
        project: original, title: "Before", start: date("2026-09-01T09:00:00Z"), end: date("2026-09-01T10:00:00Z"),
        policy: workspace.policy(at: date("2026-09-01T09:00:00Z")))
    original.hourlyRate = "120"
    #expect(entry.hourlyRate == "80")
    #expect(entry.contributions == "20")
    #expect(workspace.policy(at: date("2026-10-02T00:00:00Z")).contributions == "25")
}

@Test func missingExchangeRatesNeverBecomeOneToOne() {
    let entry = TimeEntry(
        project: project(currency: "JPY"), title: "Work", start: date("2026-10-16T08:00:00Z"),
        end: date("2026-10-16T10:00:00Z"), policy: TaxPolicy())
    let total = Finance.summarize(
        [entry], currency: "EUR", period: DateInterval(start: entry.start, end: entry.end!), rates: [], now: entry.end!,
        calendar: utc)
    #expect(total.seconds == 7200)
    #expect(total.gross == 0)
    #expect(total.unconvertedEntries == [entry.id])
}

@Test func periodClippingAndMidnightUseEachDaysExchangeRate() {
    let entry = TimeEntry(
        project: project(currency: "USD"), title: "Late", start: date("2026-10-15T23:00:00Z"),
        end: date("2026-10-16T01:00:00Z"), policy: TaxPolicy())
    let rates = ["2026-10-15": "0.8", "2026-10-16": "0.9"].map {
        ExchangeRate(
            base: "USD", quote: "EUR", requestedDate: $0.key, observedDate: $0.key, rate: $0.value, source: "test")
    }
    let total = Finance.summarize(
        [entry], currency: "EUR", period: DateInterval(start: entry.start, end: entry.end!), rates: rates,
        now: entry.end!, calendar: utc)
    #expect(total.gross == 170)
    let clipped = Finance.summarize(
        [entry], currency: "EUR", period: DateInterval(start: date("2026-10-16T00:00:00Z"), end: entry.end!),
        rates: rates, now: entry.end!, calendar: utc)
    #expect(clipped.gross == 90)
    #expect(clipped.seconds == 3600)
}

@Test func daylightSavingUsesElapsedTimeInsteadOfAssuming24Hours() {
    var paris = utc
    paris.timeZone = TimeZone(identifier: "Europe/Paris")!
    let entry = TimeEntry(
        project: project(rate: "1"), title: "DST", start: date("2026-03-28T23:00:00Z"),
        end: date("2026-03-29T22:00:00Z"), policy: TaxPolicy())
    let segments = Finance.segments(
        of: entry, within: DateInterval(start: entry.start, end: entry.end!), now: entry.end!, calendar: paris)
    #expect(segments.count == 1)
    #expect(segments[0].duration == 23 * 3600)
}

@Test func overlappingClustersShareColumnsAndAdjacentEventsDoNotOverlap() {
    let start = date("2026-10-16T08:00:00Z")
    let first = TimeEntry(
        project: project(), title: "A", start: start, end: start.addingTimeInterval(7200), policy: TaxPolicy())
    let second = TimeEntry(
        project: project(), title: "B", start: start.addingTimeInterval(3600), end: start.addingTimeInterval(10800),
        policy: TaxPolicy())
    let third = TimeEntry(
        project: project(), title: "C", start: start.addingTimeInterval(10800), end: start.addingTimeInterval(14400),
        policy: TaxPolicy())
    let slots = CalendarLayout.slots(for: [third, first, second], now: third.end!)
    #expect(slots.map(\.columns) == [2, 2, 1])
    #expect(slots.map(\.column) == [0, 1, 0])
}

@Test func sqliteRoundTripPreservesRunningTimersAndExactDecimals() throws {
    let database = try LocalDatabase()
    var state = LocalState()
    state.document.projects = [project(currency: "KWD", rate: "32.123")]
    state.document.entries = [
        TimeEntry(
            project: state.document.projects[0], title: "Active", start: date("2026-10-16T08:00:00Z"),
            policy: TaxPolicy())
    ]
    state.sync.localVersion = 3
    try database.save(state)
    let restored = try database.load()
    #expect(restored.document == state.document)
    #expect(restored.document.runningEntry?.hourlyRate == "32.123")
    #expect(restored.sync.hasChanges)
    let encoded = try WireFormat.encoder().encode(restored.document)
    #expect(String(decoding: encoded, as: UTF8.self).contains("\"end\":null"))
}

@Test func entriesOutsideThePeriodAndNonBillableTimeAreHandled() {
    let start = date("2026-10-16T08:00:00Z")
    var entry = TimeEntry(
        project: project(), title: "Admin", start: start, end: start.addingTimeInterval(3600), policy: TaxPolicy())
    entry.billable = false
    let total = Finance.summarize(
        [entry], currency: "EUR", period: DateInterval(start: start, end: start.addingTimeInterval(3600)), rates: [],
        now: entry.end!, calendar: utc)
    #expect(total.seconds == 3600)
    #expect(total.billableSeconds == 0)
    #expect(total.gross == 0)
    #expect(
        EntryValidation.message(
            for: TimeEntry(project: project(), title: "Invalid", start: start, end: start, policy: TaxPolicy()),
            now: start) != nil)
}
