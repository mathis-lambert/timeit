import SwiftUI

/// A date and a time side by side: a button that opens a month calendar, and a time field.
/// Changing one keeps the other. Days after `latest` cannot be picked.
struct DateTimeField: View {
    @Binding var date: Date
    let calendar: Calendar
    var latest: Date? = .now
    var body: some View {
        HStack(spacing: 6) {
            DateButton(date: $date, calendar: calendar, latest: latest)
            TimeField(date: $date, calendar: calendar).frame(width: 74)
        }
    }
}

/// Shows the day; opens a calendar in a popover.
private struct DateButton: View {
    @Binding var date: Date
    let calendar: Calendar
    let latest: Date?
    @State private var open = false
    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar").imageScale(.small).foregroundStyle(.secondary)
                Text(
                    calendar.isDate(date, equalTo: .now, toGranularity: .year)
                        ? date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        : date.formatted(.dateTime.day().month(.abbreviated).year())
                )
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .inputFrame(focused: open)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Date")
        .accessibilityValue(date.formatted(date: .complete, time: .omitted))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            MonthCalendar(selection: date, calendar: calendar, latest: latest) { day in
                date = Self.combine(day: day, time: date, calendar: calendar)
                open = false
            }
            .padding(12)
        }
    }

    /// The picked day at the current time of day.
    static func combine(day: Date, time: Date, calendar: Calendar) -> Date {
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: day) ?? day
    }
}

/// A month grid, Monday first, with today ringed and the selection filled with ink.
struct MonthCalendar: View {
    let selection: Date
    let calendar: Calendar
    var latest: Date? = nil
    let onPick: (Date) -> Void
    @State private var month: Date

    init(selection: Date, calendar: Calendar, latest: Date? = nil, onPick: @escaping (Date) -> Void) {
        self.selection = selection
        self.calendar = calendar
        self.latest = latest
        self.onPick = onPick
        _month = State(initialValue: calendar.dateInterval(of: .month, for: selection)?.start ?? selection)
    }

    var body: some View {
        let days = gridDays
        VStack(spacing: 8) {
            HStack {
                IconButton(symbol: "chevron.left", label: "Mois précédent") { shift(-1) }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.body.weight(.medium))
                Spacer()
                IconButton(symbol: "chevron.right", label: "Mois suivant") { shift(1) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption).foregroundStyle(.secondary).frame(height: 24)
                }
                ForEach(days, id: \.self) { day in dayCell(day) }
            }
        }
        .frame(width: 7 * 32 + 6 * 2)
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let selected = calendar.isDate(day, inSameDayAs: selection)
        let today = calendar.isDateInToday(day)
        let disabled = latest.map { calendar.startOfDay(for: day) > calendar.startOfDay(for: $0) } ?? false
        return Button {
            onPick(day)
        } label: {
            Text(day.formatted(.dateTime.day()))
                .monospacedDigit()
                .foregroundStyle(selected ? Control.onInk : inMonth ? .primary : .secondary)
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: Control.radius - 1, style: .continuous)
                        .fill(selected ? Control.ink : .clear)
                }
                .overlay {
                    if today && !selected {
                        RoundedRectangle(cornerRadius: Control.radius - 1, style: .continuous)
                            .strokeBorder(Theme.accent, lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(DayButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
    }

    /// Six weeks covering the month, starting on the calendar's first weekday.
    private var gridDays: [Date] {
        let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        guard let first = calendar.date(byAdding: .day, value: -lead, to: month) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }
    private var weekdaySymbols: [String] {
        var formatter = calendar
        formatter.locale = .current
        let symbols = formatter.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
    private func shift(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: month) { month = next }
    }
}

private struct DayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { DayButtonBody(configuration: configuration) }
    private struct DayButtonBody: View {
        let configuration: Configuration
        @State private var hovered = false
        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: Control.radius - 1, style: .continuous)
                        .fill(configuration.isPressed ? Control.pressed : hovered ? Control.muted : .clear)
                )
                .onHover { hovered = $0 }
        }
    }
}

/// A time of day typed freely ("9", "930", "9h30", "9:30"); ↑ and ↓ move it by a quarter hour.
struct TimeField: View {
    @Binding var date: Date
    let calendar: Calendar
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField("hh:mm", text: $text)
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .focused($focused)
            .timeitField()
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onKeyPress(.upArrow) {
                step(15)
                return .handled
            }
            .onKeyPress(.downArrow) {
                step(-15)
                return .handled
            }
            .onAppear { text = Display.time(date, calendar: calendar) }
            .onChange(of: date) { _, value in if !focused { text = Display.time(value, calendar: calendar) } }
            .accessibilityLabel("Heure")
    }

    private func commit() {
        if let (hour, minute) = Display.parseTime(text),
            let value = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
        {
            date = value
        }
        text = Display.time(date, calendar: calendar)
    }
    private func step(_ minutes: Int) {
        commit()
        let clock = calendar.dateComponents([.hour, .minute], from: date)
        let total = ((clock.hour ?? 0) * 60 + (clock.minute ?? 0))
        let snapped = (total / 15) * 15 + (minutes > 0 ? 15 : (total % 15 == 0 ? -15 : 0))
        let wrapped = (snapped + 24 * 60) % (24 * 60)
        if let value = calendar.date(bySettingHour: wrapped / 60, minute: wrapped % 60, second: 0, of: date) {
            date = value
            text = Display.time(value, calendar: calendar)
        }
    }
}

extension Display {
    /// Reads a typed time of day: "9", "09", "930", "0930", "9:30", "9h", "9h30", "9.30".
    static func parseTime(_ text: String) -> (hour: Int, minute: Int)? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).lowercased()
        let parts = cleaned.split(whereSeparator: { ":h.".contains($0) }).map(String.init)
        let hour: Int?
        let minute: Int?
        switch parts.count {
        case 1 where parts[0].count <= 2:
            hour = Int(parts[0])
            minute = 0
        case 1 where parts[0].count <= 4:
            hour = Int(parts[0].dropLast(2))
            minute = Int(parts[0].suffix(2))
        case 2:
            hour = Int(parts[0])
            minute = Int(parts[1])
        default:
            return nil
        }
        guard let hour, let minute, (0..<24).contains(hour), (0..<60).contains(minute),
            parts.allSatisfy({ $0.allSatisfy(\.isNumber) })
        else { return nil }
        return (hour, minute)
    }
}
