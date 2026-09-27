import SwiftUI

struct CalendarCleanupView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case old, duplicates
        var id: String { rawValue }
        var title: String { self == .old ? "Old events" : "Duplicates" }
    }

    @Environment(AppState.self) private var app
    @State private var tab: Tab = .old

    var body: some View {
        let model = app.calendar
        Group {
            if !model.hasResults {
                ScanningStateView(title: "Checking your calendar", phase: model.phase,
                                  onCancel: model.phase.isScanning ? { model.cancel() } : nil)
            } else if model.writableCalendarCount == 0 {
                EmptyStateView(symbol: "calendar",
                               title: "No calendars to tidy",
                               message: "CleanSpace only changes calendars you can edit. Subscribed, holiday and birthday calendars are left alone.")
            } else if model.pastEvents.isEmpty && model.duplicateGroups.isEmpty {
                EmptyStateView(symbol: "calendar.badge.checkmark",
                               message: "No old or duplicate events in your calendars.",
                               actionTitle: "Check again") { model.scan() }
            } else {
                content(model)
            }
        }
        .background(AppBackdrop())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CategorySelectionBar(category: .calendarEvents)
        }
        .animation(.snappy, value: app.selectedCount(in: .calendarEvents) > 0)
        .sensoryFeedback(.selection, trigger: app.selection.events)
        .task { app.ensureScanned(.calendarEvents) }
    }

    private func content(_ model: CalendarModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                SummaryHeader(title: Format.count(model.oldEvents.count + model.duplicateExtraCount, "event"),
                              subtitle: "could go from \(Format.count(model.writableCalendarCount, "calendar")) you can edit. Repeating events are never touched.")
                Picker("Show", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                switch tab {
                case .old: oldEvents(model)
                case .duplicates: duplicates(model)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .refreshable { model.scan() }
    }

    // MARK: Old events

    @ViewBuilder
    private func oldEvents(_ model: CalendarModel) -> some View {
        @Bindable var bindable = model
        let events = model.oldEvents
        HStack {
            Text("Ended more than")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryText)
            Picker("Ended more than", selection: $bindable.cutoff) {
                ForEach(OldEventCutoff.allCases) { Text("\($0.title) ago").tag($0) }
            }
            .pickerStyle(.menu)
            Spacer()
            if !events.isEmpty {
                selectToggle(ids: events.map(\.id))
            }
        }
        if events.isEmpty {
            EmptyStateView(symbol: "calendar.badge.checkmark",
                           message: "No events ended more than \(model.cutoff.title) ago.")
                .frame(minHeight: 260)
        } else {
            let years = Dictionary(grouping: events) { Calendar.current.component(.year, from: $0.startDate) }
            ForEach(years.keys.sorted(by: >), id: \.self) { year in
                let yearEvents = years[year] ?? []
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(String(year))
                            .font(.headline)
                            .foregroundStyle(Theme.Palette.ink)
                        Text(yearEvents.count.formatted())
                            .font(.subheadline)
                            .foregroundStyle(Theme.Palette.secondaryText)
                        Spacer()
                        selectToggle(ids: yearEvents.map(\.id))
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.m)
                    Divider()
                    LazyVStack(spacing: 0) {
                        ForEach(yearEvents) { event in
                            EventRow(event: event, isSelected: app.selection.events.contains(event.id)) {
                                app.selection.toggleEvent(event.id)
                            }
                        }
                    }
                }
                .card(padding: 0)
            }
        }
    }

    // MARK: Duplicates

    @ViewBuilder
    private func duplicates(_ model: CalendarModel) -> some View {
        if model.duplicateGroups.isEmpty {
            EmptyStateView(symbol: "calendar.badge.checkmark",
                           message: "No duplicate events found.")
                .frame(minHeight: 260)
        } else {
            HStack {
                Text("The original of each event is kept.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
                Spacer()
                selectToggle(ids: model.duplicateGroups.flatMap { $0.extras.map(\.id) }, title: "copies")
            }
            ForEach(model.duplicateGroups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.keeper.displayTitle)
                            .font(.headline)
                            .foregroundStyle(Theme.Palette.ink)
                        Text("\(group.keeper.whenText), \(Format.count(group.events.count, "copy", "copies"))")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    .padding(Theme.Spacing.l)
                    Divider()
                    ForEach(group.events) { event in
                        if event.id == group.keeper.id {
                            EventRow(event: event, isSelected: false, keptLabel: "Kept", onToggle: {})
                        } else {
                            EventRow(event: event, isSelected: app.selection.events.contains(event.id)) {
                                app.selection.toggleEvent(event.id)
                            }
                        }
                    }
                }
                .card(padding: 0)
            }
        }
    }

    private func selectToggle(ids: [String], title: String = "") -> some View {
        let allSelected = !ids.isEmpty && ids.allSatisfy { app.selection.events.contains($0) }
        return Button(allSelected ? "Deselect" : (title.isEmpty ? "Select all" : "Select \(title)")) {
            if allSelected {
                app.selection.events.subtract(ids)
            } else {
                app.selection.events.formUnion(ids)
            }
        }
        .font(.subheadline.weight(.semibold))
    }
}

struct EventRow: View {
    let event: CalendarEventItem
    let isSelected: Bool
    var keptLabel: String?
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Circle()
                .fill(Color(uiColor: UIColor(hex: event.calendarColor)))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                Text([event.whenText, event.calendarTitle, event.location].compactMap { $0 }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            if let keptLabel {
                Text(keptLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.brand)
                    .padding(.trailing, Theme.Spacing.s)
            } else {
                CheckboxButton(isSelected: isSelected, action: onToggle)
            }
        }
        .padding(.leading, Theme.Spacing.l)
        .padding(.trailing, Theme.Spacing.s)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if keptLabel == nil { onToggle() } }
        .accessibilityElement(children: .combine)
    }
}
