import Foundation

public enum ProjectColor: String, Codable, CaseIterable, Sendable {
    case coral, blue, green, purple, gold
}

public struct Client: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var color: ProjectColor
    public init(id: UUID = UUID(), name: String, color: ProjectColor = .coral) {
        self.id = id
        self.name = name
        self.color = color
    }
}

public struct Project: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var clientID: UUID
    public var name: String
    public var color: ProjectColor
    public var currency: String
    public var hourlyRate: String
    public var billable: Bool
    public var archived: Bool
    public init(
        id: UUID = UUID(), clientID: UUID, name: String, color: ProjectColor = .coral, currency: String = "EUR",
        hourlyRate: String = "0", billable: Bool = true, archived: Bool = false
    ) {
        self.id = id
        self.clientID = clientID
        self.name = name
        self.color = color
        self.currency = currency
        self.hourlyRate = hourlyRate
        self.billable = billable
        self.archived = archived
    }
}

public struct TaxPolicy: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var effectiveFrom: Date
    public var contributions: String
    public var incomeTax: String
    public init(
        id: UUID = UUID(), effectiveFrom: Date = .distantPast, contributions: String = "0", incomeTax: String = "0"
    ) {
        self.id = id
        self.effectiveFrom = effectiveFrom
        self.contributions = contributions
        self.incomeTax = incomeTax
    }
}

public struct Profile: Codable, Equatable, Sendable {
    public var name: String = "Mon espace"
    public var currency: String = "EUR"
    public var weeklyGoal: Int = 35
    public var timezone: String = TimeZone.current.identifier
    public init() {}
}

public struct TimeEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var projectID: UUID
    public var title: String
    public var start: Date
    public var end: Date?
    public var currency: String
    public var hourlyRate: String
    public var billable: Bool
    public var contributions: String
    public var incomeTax: String

    public init(id: UUID = UUID(), project: Project, title: String, start: Date, end: Date? = nil, policy: TaxPolicy) {
        self.id = id
        self.projectID = project.id
        self.title = title
        self.start = start
        self.end = end
        self.currency = project.currency
        self.hourlyRate = project.hourlyRate
        self.billable = project.billable
        self.contributions = policy.contributions
        self.incomeTax = policy.incomeTax
    }
    public func duration(at now: Date = .now) -> TimeInterval { max(0, (end ?? now).timeIntervalSince(start)) }

    // Encode a null end explicitly; it is part of the sync contract for a running timer.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(projectID, forKey: .projectID)
        try container.encode(title, forKey: .title)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(currency, forKey: .currency)
        try container.encode(hourlyRate, forKey: .hourlyRate)
        try container.encode(billable, forKey: .billable)
        try container.encode(contributions, forKey: .contributions)
        try container.encode(incomeTax, forKey: .incomeTax)
    }
}

public struct Workspace: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var profile = Profile()
    public var clients: [Client] = []
    public var projects: [Project] = []
    public var taxPolicies = [TaxPolicy()]
    public var entries: [TimeEntry] = []
    public init() {}
    public var runningEntry: TimeEntry? { entries.first { $0.end == nil } }
    public var activeProjects: [Project] {
        projects.filter { !$0.archived }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: profile.timezone) ?? .current
        result.firstWeekday = 2
        return result
    }
    public func project(_ id: UUID) -> Project? { projects.first { $0.id == id } }
    public func client(for project: Project) -> Client? { clients.first { $0.id == project.clientID } }
    public func policy(at date: Date) -> TaxPolicy {
        taxPolicies.filter { $0.effectiveFrom <= date }.max { $0.effectiveFrom < $1.effectiveFrom } ?? TaxPolicy()
    }
}

public struct ExchangeRate: Codable, Equatable, Sendable {
    public var base: String
    public var quote: String
    public var requestedDate: String
    public var observedDate: String
    public var rate: String
    public var source: String
    public init(base: String, quote: String, requestedDate: String, observedDate: String, rate: String, source: String)
    {
        self.base = base
        self.quote = quote
        self.requestedDate = requestedDate
        self.observedDate = observedDate
        self.rate = rate
        self.source = source
    }
    public var key: String { Self.key(base: base, quote: quote, date: requestedDate) }
    public static func key(base: String, quote: String, date: String) -> String { "\(base):\(quote):\(date)" }
}

extension Decimal {
    private static let posix = Locale(identifier: "en_US_POSIX")
    public static func amount(_ string: String) -> Decimal { Decimal(string: string, locale: posix) ?? 0 }
    public var plainString: String { NSDecimalNumber(decimal: self).stringValue }
}

public enum WireFormat {
    public static func encoder() -> JSONEncoder {
        let result = JSONEncoder()
        result.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        result.outputFormatting = [.sortedKeys]
        return result
    }
    public static func decoder() -> JSONDecoder {
        let result = JSONDecoder()
        result.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) { return date }
            return try Date.ISO8601FormatStyle().parse(value)
        }
        return result
    }
    public static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
