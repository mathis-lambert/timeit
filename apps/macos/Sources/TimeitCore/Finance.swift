import Foundation

public struct FinancialSummary: Sendable {
    public var seconds: TimeInterval = 0
    public var billableSeconds: TimeInterval = 0
    public var gross: Decimal = 0
    public var contributions: Decimal = 0
    public var incomeTax: Decimal = 0
    public var unconvertedEntries: Set<UUID> = []
    public var net: Decimal { gross - contributions - incomeTax }
    public init() {}
}

public enum Finance {
    public static func segments(of entry: TimeEntry, within period: DateInterval, now: Date, calendar: Calendar)
        -> [DateInterval]
    {
        let start = max(entry.start, period.start)
        let end = min(entry.end ?? now, period.end, now)
        guard start < end else { return [] }
        var cursor = start
        var result: [DateInterval] = []
        while cursor < end {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) else {
                break
            }
            let next = min(nextDay, end)
            result.append(DateInterval(start: cursor, end: next))
            cursor = next
        }
        return result
    }

    /// Elapsed time of `entry` inside `period`.
    public static func seconds(of entry: TimeEntry, within period: DateInterval, now: Date, calendar: Calendar)
        -> TimeInterval
    {
        segments(of: entry, within: period, now: now, calendar: calendar).reduce(0) { $0 + $1.duration }
    }

    /// The exchange rate a billable segment converts with: the entry's currency on the segment's local day.
    public static func rateKey(for entry: TimeEntry, segment: DateInterval, currency: String, calendar: Calendar)
        -> String
    {
        ExchangeRate.key(base: entry.currency, quote: currency, date: WireFormat.day(segment.start, calendar: calendar))
    }

    public static func summarize(
        _ entries: [TimeEntry], currency: String, period: DateInterval, rates: [ExchangeRate], now: Date = .now,
        calendar: Calendar = .current
    ) -> FinancialSummary {
        let lookup = Dictionary(rates.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var result = FinancialSummary()
        for entry in entries {
            for segment in segments(of: entry, within: period, now: now, calendar: calendar) {
                result.seconds += segment.duration
                guard entry.billable else { continue }
                result.billableSeconds += segment.duration
                let original = Decimal(segment.duration) / 3600 * .amount(entry.hourlyRate)
                let multiplier: Decimal
                if entry.currency == currency {
                    multiplier = 1
                } else if let rate = lookup[
                    rateKey(for: entry, segment: segment, currency: currency, calendar: calendar)]
                {
                    multiplier = .amount(rate.rate)
                } else {
                    if original > 0 { result.unconvertedEntries.insert(entry.id) }
                    continue
                }
                let gross = original * multiplier
                result.gross += gross
                result.contributions += gross * .amount(entry.contributions) / 100
                result.incomeTax += gross * .amount(entry.incomeTax) / 100
            }
        }
        return result
    }
}

public enum EntryValidation {
    public static func message(for entry: TimeEntry, now: Date = .now) -> String? {
        if entry.title.count > 500 { return "La description est limitée à 500 caractères." }
        if entry.start > now { return "Le début doit être dans le passé." }
        if let end = entry.end {
            if end <= entry.start { return "La fin doit être après le début." }
            if end > now { return "La fin doit être dans le passé." }
        }
        if Decimal.amount(entry.hourlyRate) < 0 { return "Le tarif doit être positif." }
        return nil
    }
}

public enum CalendarLayout {
    public struct Slot: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let column: Int
        public var columns: Int
    }
    /// Interval partitioning: adjacent events do not overlap, and every member
    /// of an overlapping cluster receives the same column count.
    public static func slots(for entries: [TimeEntry], now: Date) -> [Slot] {
        let sorted = entries.sorted { $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start }
        var result: [Slot] = []
        var active: [(end: Date, column: Int)] = []
        var clusterStart = 0
        var clusterWidth = 0
        for entry in sorted {
            active.removeAll { $0.end <= entry.start }
            if active.isEmpty {
                for index in clusterStart..<result.count { result[index].columns = clusterWidth }
                clusterStart = result.count
                clusterWidth = 0
            }
            let used = Set(active.map(\.column))
            let column = (0...).first { !used.contains($0) } ?? 0
            active.append((entry.end ?? now, column))
            clusterWidth = max(clusterWidth, column + 1)
            result.append(Slot(id: entry.id, column: column, columns: 1))
        }
        for index in clusterStart..<result.count { result[index].columns = clusterWidth }
        return result
    }
}
