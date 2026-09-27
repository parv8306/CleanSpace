import SwiftUI

/// The one and only place where anything is removed. Every cleaner opens this screen.
struct ReviewCleanupView: View {
    let request: ReviewRequest

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model = CleanupViewModel()
    @State private var plan: CleanupPlan?
    @State private var confirmContacts = false
    /// A few thumbnails captured before anything is deleted, for the cleanup animation.
    @State private var previewImages: [UIImage] = []
    /// Small JPEGs of the items about to be deleted, for Cleanup History.
    @State private var historyThumbnails: [String: Data] = [:]

    var body: some View {
        NavigationStack {
            Group {
                switch model.stage {
                case let .done(summary):
                    CleanupSummaryView(summary: summary, doneTitle: "Back to Dashboard", previewImages: previewImages) { app.finishCleanupFlow() }
                case .review, .working:
                    if let plan {
                        if plan.isEmpty {
                            EmptyStateView(symbol: "checklist",
                                           title: "Nothing selected",
                                           message: "Select photos, videos or contacts first, then come back here to review them.")
                        } else {
                            reviewContent(plan)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle(isDone ? "" : "Review Cleanup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isDone {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(model.isWorking)
                    }
                }
            }
        }
        .interactiveDismissDisabled(model.isWorking || isDone)
        .onAppear {
            if plan == nil {
                let built = CleanupPlan.build(from: app, categories: request.categories)
                plan = built
                let ids = Array(built.media.flatMap(\.items).prefix(HistoryThumbnailStore.maxItemsPerCleanup).map(\.id))
                Task { await loadPreviews(ids) }
            }
        }
    }

    /// Captures thumbnails before anything is deleted: a few for the cleanup animation, and a
    /// small JPEG of each (up to the history limit) for Cleanup History.
    private func loadPreviews(_ ids: [String]) async {
        var images: [UIImage] = []
        var thumbnails: [String: Data] = [:]
        for id in ids {
            guard let image = await ThumbnailLoader.shared.finalImage(id: id, pixelSize: CGSize(width: 180, height: 180)) else { continue }
            if images.count < 8 {
                images.append(image)
                if images.count == 8 { previewImages = images }
            }
            if let data = image.jpegData(compressionQuality: 0.72) { thumbnails[id] = data }
        }
        previewImages = images
        historyThumbnails = thumbnails
    }

    private var isDone: Bool {
        if case .done = model.stage { return true }
        return false
    }

    private func reviewContent(_ plan: CleanupPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                hero(plan)
                if let notice = model.notice {
                    Label(notice, systemImage: "info.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.Palette.amber)
                        .card(padding: Theme.Spacing.m)
                }
                ForEach(plan.media) { entry in
                    MediaReviewCard(entry: entry)
                }
                if plan.hasContactChanges {
                    ContactReviewCard(plan: plan)
                }
                if plan.hasEventChanges {
                    EventReviewCard(events: plan.events)
                }
                notes(plan)
            }
            .padding(Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar(plan)
        }
        .confirmationDialog(permanentTitle(plan), isPresented: $confirmContacts, titleVisibility: .visible) {
            Button(contactConfirmTitle(plan), role: .destructive) { start(plan) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These changes are permanent and sync to any account they belong to, such as iCloud. CleanSpace can't undo them.")
        }
    }

    private func hero(_ plan: CleanupPlan) -> some View {
        var rows: [(symbol: String, tint: Color, label: String, count: Int)] = plan.media.map {
            (symbol: $0.category.symbol, tint: $0.category.tint, label: $0.category.title, count: $0.items.count)
        }
        if plan.contactsRemovedCount > 0 {
            rows.append((symbol: "person.2.fill", tint: Theme.Palette.contacts, label: "Contacts", count: plan.contactsRemovedCount))
        }
        if !plan.events.isEmpty {
            rows.append((symbol: "calendar", tint: Theme.Palette.calendar, label: "Calendar events", count: plan.events.count))
        }
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("You selected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.secondaryText)
            VStack(spacing: 10) {
                ForEach(rows, id: \.label) { row in
                    HStack(spacing: Theme.Spacing.m) {
                        CleanSpaceIcon(symbol: row.symbol, tint: row.tint, size: 32)
                        Text(row.label)
                            .font(.body)
                            .foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        Text(row.count.formatted())
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.Palette.ink)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if plan.mediaCount > 0 {
                Divider()
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Estimated space freed")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                        Text(Format.bytes(plan.mediaBytes))
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.brandGradient)
                    }
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Theme.Palette.cyan)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card(padding: Theme.Spacing.lg)
    }

    private func notes(_ plan: CleanupPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if plan.mediaCount > 0 {
                Label("iOS will ask you to confirm once more before photos and videos are deleted.",
                      systemImage: "hand.raised")
                Label("Deleted photos and videos stay in Recently Deleted in the Photos app for 30 days. The space is fully released after that, or sooner if you empty it there.",
                      systemImage: "trash")
            }
            if plan.hasContactChanges {
                Label("Contact changes can't be undone from CleanSpace.", systemImage: "person.crop.circle.badge.exclamationmark")
            }
            if plan.hasEventChanges {
                Label("Deleted events are removed from every device your calendar syncs to.", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.Palette.secondaryText)
    }

    private func actionBar(_ plan: CleanupPlan) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            if case let .working(message) = model.stage {
                HStack(spacing: Theme.Spacing.m) {
                    ProgressView()
                    Text(message)
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                Button {
                    if plan.hasPermanentChanges {
                        confirmContacts = true
                    } else {
                        start(plan)
                    }
                } label: {
                    Text(deleteTitle(plan))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(Theme.Palette.coral, in: Capsule())
                        .shadow(color: Theme.Palette.coral.opacity(0.25), radius: 10, y: 5)
                }
                .buttonStyle(PressableButtonStyle())
                Button("Cancel") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func deleteTitle(_ plan: CleanupPlan) -> String {
        if plan.mediaCount > 0 {
            return "Delete \(Format.count(plan.totalCount, "item")), free \(Format.bytes(plan.mediaBytes))"
        }
        return "Delete Selected (\(Format.count(plan.totalCount, "item")))"
    }

    private func permanentTitle(_ plan: CleanupPlan) -> String {
        switch (plan.hasContactChanges, plan.hasEventChanges) {
        case (true, true): return "Change your contacts and calendar?"
        case (false, true): return "Delete these events?"
        default: return "Change your contacts?"
        }
    }

    private func contactConfirmTitle(_ plan: CleanupPlan) -> String {
        var parts: [String] = []
        if !plan.merges.isEmpty { parts.append("merge \(Format.count(plan.merges.count, "group"))") }
        if !plan.contactDeletes.isEmpty { parts.append("delete \(Format.count(plan.contactDeletes.count, "contact"))") }
        if !plan.events.isEmpty { parts.append("delete \(Format.count(plan.events.count, "event"))") }
        let text = parts.joined(separator: " and ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func start(_ plan: CleanupPlan) {
        let thumbnails = historyThumbnails
        Task { await model.run(plan, app: app, thumbnails: thumbnails) }
    }
}

private struct MediaReviewCard: View {
    let entry: CleanupPlan.MediaEntry

    private let rows = [GridItem(.fixed(64), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: entry.category.symbol)
                    .foregroundStyle(entry.category.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Format.count(entry.items.count, entry.category.noun))
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.ink)
                    Text(entry.category.title)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                Spacer()
                Text(Format.bytes(entry.bytes))
                    .font(Theme.Typography.rowNumber)
                    .foregroundStyle(Theme.Palette.ink)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 4) {
                    ForEach(entry.items) { item in
                        AssetThumbnail(id: item.id, side: 64)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
            .frame(height: 64)
        }
        .card()
    }
}

private struct ContactReviewCard: View {
    let plan: CleanupPlan

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: CleanupCategory.duplicateContacts.symbol)
                    .foregroundStyle(CleanupCategory.duplicateContacts.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Format.count(plan.contactsRemovedCount, "contact card"))
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.ink)
                    Text("Duplicate Contacts")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }
            ForEach(plan.merges) { merge in
                HStack(spacing: Theme.Spacing.m) {
                    AvatarStack(records: merge.group.contacts, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Merge into \(merge.keptName)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.Palette.ink)
                        Text("\(merge.group.contacts.count.formatted()) cards become one")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                }
            }
            ForEach(plan.contactDeletes) { record in
                HStack(spacing: Theme.Spacing.m) {
                    ContactAvatar(record: record, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Delete \(record.displayName)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.Palette.ink)
                        Text((record.phones.prefix(1) + record.emails.prefix(1)).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
        }
        .card()
    }
}

private struct EventReviewCard: View {
    let events: [CalendarEventItem]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: CleanupCategory.calendarEvents.symbol)
                    .foregroundStyle(CleanupCategory.calendarEvents.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Format.count(events.count, "event"))
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.ink)
                    Text("Calendar Events")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }
            ForEach(expanded ? events : Array(events.prefix(5))) { event in
                HStack(spacing: Theme.Spacing.m) {
                    Circle()
                        .fill(Color(uiColor: UIColor(hex: event.calendarColor)))
                        .frame(width: 8, height: 8)
                    Text(event.displayTitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(event.startDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }
            if events.count > 5 {
                Button(expanded ? "Show less" : "Show all \(events.count.formatted())") {
                    withAnimation(.snappy) { expanded.toggle() }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .card()
    }
}
