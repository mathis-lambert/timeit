import SwiftUI
import TimeitCore

/// The event being dragged and where it would land, owned by the grid.
private struct CalendarDrag {
    let entry: TimeEntry
    var move: CalendarMove
}

struct CalendarView: View {
    @Bindable var store: AppStore
    @State private var drag: CalendarDrag?
    private let hourHeight: CGFloat = 60
    private var days: [DateInterval] {
        let calendar = store.calendar
        return (0..<7).map { offset in
            calendar.dateInterval(
                of: .day, for: calendar.date(byAdding: .day, value: offset, to: store.calendarWeek.start)!)!
        }
    }
    var body: some View {
        let days = days
        let week = store.calendarWeek
        // One pass over the filtered history; each column then only sees its own week.
        let weekEntries = store.filteredEntries.filter { $0.start < week.end && ($0.end ?? .now) > week.start }
        // Full bleed, like Calendar: the grid is the content.
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 58)
                ForEach(days, id: \.start) { day in dayHeader(day, entries: weekEntries) }
            }
            .padding(.trailing, 12).padding(.vertical, 12)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    // Only the current week has a moving "now" line.
                    TimelineView(.periodic(from: .now, by: week.contains(.now) ? 60 : 3600)) { context in
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 0) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text(String(format: "%02d:00", hour))
                                        .font(.caption2).monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: 50, height: hourHeight, alignment: .topTrailing)
                                        .padding(.trailing, 8).offset(y: -6)
                                        .id("hour-\(hour)")
                                }
                            }
                            ForEach(days, id: \.start) { day in
                                DayColumn(
                                    store: store, day: day.start, nextDay: day.end, hourHeight: hourHeight,
                                    now: context.date,
                                    entries: weekEntries.filter {
                                        $0.start < day.end && ($0.end ?? context.date) > day.start
                                    },
                                    drag: $drag
                                )
                            }
                        }
                        .padding(.top, 10).padding(.trailing, 12)
                    }
                }
                .onAppear { proxy.scrollTo("hour-8", anchor: .top) }
            }
        }
        .toolbar { PeriodToolbar(store: store, showsPeriod: false) }
    }
    private func dayHeader(_ interval: DateInterval, entries: [TimeEntry]) -> some View {
        let day = interval.start
        let today = store.calendar.isDateInToday(day)
        let seconds = store.trackedSeconds(entries, in: interval)
        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.callout)
                    .foregroundStyle(today ? Theme.accent : .secondary)
                Text(day.formatted(.dateTime.day()))
                    .font(.title3.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(today ? .white : .primary)
                    .frame(minWidth: 24, minHeight: 24)
                    .background { if today { Circle().fill(Theme.accent) } }
            }
            Text(seconds > 0 ? Display.duration(seconds) : " ")
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DayColumn: View {
    let store: AppStore
    let day: Date
    let nextDay: Date
    let hourHeight: CGFloat
    let now: Date
    /// Entries overlapping this day.
    let entries: [TimeEntry]
    @Binding var drag: CalendarDrag?
    var body: some View {
        let preview = drag.map { $0.move.applied(to: $0.entry, calendar: store.calendar) }
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let clipped = entries.map { entry in
            var copy = entry
            copy.start = max(entry.start, day)
            copy.end = min(entry.end ?? now, nextDay)
            return copy
        }
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(
                    store.calendar.isDateInToday(day)
                        ? Theme.accent.opacity(0.03)
                        : store.calendar.isDateInWeekend(day) ? Color.primary.opacity(0.02) : .clear)
                ForEach(0..<24, id: \.self) { hour in
                    Rectangle().fill(Theme.hairline).frame(height: 0.5).offset(y: CGFloat(hour) * hourHeight)
                }
                Rectangle().fill(Theme.hairline).frame(width: 0.5)
                Color.clear.contentShape(Rectangle()).onTapGesture(count: 2, coordinateSpace: .local) { point in
                    let minute = min(1425, max(0, Int((point.y / hourHeight * 60 / 15).rounded()) * 15))
                    guard let date = store.calendar.date(byAdding: .minute, value: minute, to: day), date < .now else {
                        return
                    }
                    store.entryEditor = EntryEditorRequest(start: date)
                }
                ForEach(CalendarLayout.slots(for: clipped, now: now)) { slot in
                    if let entry = byID[slot.id] {
                        let top = offset(max(entry.start, day))
                        let bottom =
                            min(entry.end ?? now, nextDay) >= nextDay ? 24 * hourHeight : offset(entry.end ?? now)
                        let width = max(20, (geometry.size.width - 8) / CGFloat(slot.columns))
                        CalendarEntry(
                            store: store, entry: entry, hourHeight: hourHeight, dayWidth: geometry.size.width, now: now,
                            drag: $drag
                        )
                        .frame(width: width - 3, height: max(28, bottom - top - 3))
                        .position(
                            x: 5 + CGFloat(slot.column) * width + (width - 3) / 2,
                            y: top + max(28, bottom - top - 3) / 2)
                    }
                }
                // The landing spot is drawn in the column it lands in, so no column needs to sit above another.
                if let preview, let end = preview.end, preview.start < nextDay, end > day {
                    let top = offset(max(preview.start, day))
                    let bottom = end >= nextDay ? 24 * hourHeight : offset(end)
                    DropPreview(store: store, entry: preview)
                        .frame(width: geometry.size.width - 8, height: max(28, bottom - top - 3))
                        .position(x: geometry.size.width / 2, y: top + max(28, bottom - top - 3) / 2)
                        .allowsHitTesting(false)
                }
                if store.calendar.isDateInToday(day) {
                    HStack(spacing: 0) {
                        Circle().fill(Theme.accent).frame(width: 7, height: 7).offset(x: -3.5)
                        Rectangle().fill(Theme.accent).frame(height: 1)
                    }
                    .offset(y: offset(now) - 3.5).allowsHitTesting(false)
                }
            }.frame(height: 24 * hourHeight)
        }.frame(height: 24 * hourHeight)
    }
    private func offset(_ date: Date) -> CGFloat {
        let components = store.calendar.dateComponents([.hour, .minute], from: date)
        return (CGFloat(components.hour ?? 0) + CGFloat(components.minute ?? 0) / 60) * hourHeight
    }
}

private struct DropPreview: View {
    let store: AppStore
    let entry: TimeEntry
    var body: some View {
        let tint = store.workspace.project(entry.projectID)?.color.tint ?? Theme.accent
        Text(Display.timeRange(entry, calendar: store.calendar))
            .font(.caption.weight(.semibold)).monospacedDigit()
            .padding(.horizontal, 7).padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(tint, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            )
    }
}

private struct CalendarEntry: View {
    let store: AppStore
    let entry: TimeEntry
    let hourHeight: CGFloat
    let dayWidth: CGFloat
    let now: Date
    @Binding var drag: CalendarDrag?
    @State private var hovered = false
    var body: some View {
        let project = store.workspace.project(entry.projectID)
        let tint = project?.color.tint ?? Theme.accent
        let dragging = drag?.entry.id == entry.id
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? project?.name ?? "Session" : entry.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(geometry.size.height > 70 ? 3 : 1)
                if geometry.size.height > 46 {
                    Text(project?.name ?? "").font(.caption).lineLimit(1).foregroundStyle(.secondary)
                }
                if geometry.size.height > 72 {
                    Text(entry.end == nil ? "En cours" : Display.duration(entry.duration(at: now)))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(tint.opacity(hovered ? 0.26 : 0.17), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(dragging ? 0.4 : 1)
            .overlay(alignment: .bottom) {
                if entry.end != nil {
                    Color.clear.frame(height: 8).contentShape(Rectangle())
                        .pointerStyle(.frameResize(position: .bottom))
                        .highPriorityGesture(dragGesture(resizing: true, minimumDistance: 3))
                }
            }
            .gesture(dragGesture(resizing: false, minimumDistance: 5))
            .onTapGesture { store.entryEditor = EntryEditorRequest(entry: entry) }
            .onHover { hovered = $0 }
            .contextMenu {
                Button("Modifier…", systemImage: "pencil") { store.entryEditor = EntryEditorRequest(entry: entry) }
                Button("Reprendre", systemImage: "play") { store.resume(entry) }.disabled(!store.canResume(entry))
                Divider()
                Button("Supprimer", systemImage: "trash", role: .destructive) { store.delete(entry) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(entry.title), \(project?.name ?? ""), \(Display.duration(entry.duration(at: now)))"
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { store.entryEditor = EntryEditorRequest(entry: entry) }
            .help(
                "\(entry.displayTitle)\n\(Display.timeRange(entry, calendar: store.calendar))\nCliquer pour modifier"
            )
        }
    }

    /// Finished entries can be moved or resized; the running one keeps its live end.
    private func dragGesture(resizing: Bool, minimumDistance: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: minimumDistance)
            .onChanged { value in
                guard entry.end != nil else { return }
                let move = CalendarMove(
                    dx: value.translation.width, dy: value.translation.height, hourHeight: hourHeight,
                    dayWidth: dayWidth, resizing: resizing)
                if drag?.move != move { drag = CalendarDrag(entry: entry, move: move) }
            }
            .onEnded { _ in
                if let drag, drag.entry.id == entry.id { store.move(entry, drag.move) }
                drag = nil
            }
    }
}
