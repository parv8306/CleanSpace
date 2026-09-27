import SwiftUI

struct ContactGroupDetailView: View {
    let groupID: String

    enum Mode: String, CaseIterable, Identifiable {
        case merge, delete
        var id: String { rawValue }
        var title: String { self == .merge ? "Merge" : "Delete" }
    }

    @Environment(AppState.self) private var app
    @State private var mode: Mode = .merge
    @State private var nameSourceID: String?
    @State private var photoSourceID: String?
    @State private var didConfigure = false

    var body: some View {
        Group {
            if let group = app.contacts.group(id: groupID) {
                content(group)
            } else {
                EmptyStateView(symbol: "checkmark.circle",
                               title: "This group is gone",
                               message: "These contacts changed since the last check.")
            }
        }
        .background(AppBackdrop())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CategorySelectionBar(category: .duplicateContacts)
        }
        .navigationTitle("Possible duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: configure)
    }

    private func configure() {
        guard !didConfigure, let group = app.contacts.group(id: groupID) else { return }
        didConfigure = true
        if let plan = app.selection.contactMerges[groupID] {
            mode = .merge
            nameSourceID = plan.nameSourceID
            photoSourceID = plan.photoSourceID
        } else if group.memberIDs.contains(where: { app.selection.contactDeletes.contains($0) }) {
            mode = .delete
        }
        // Default keeper: the card with the most details.
        if nameSourceID == nil {
            nameSourceID = group.contacts.max { a, b in
                (a.phones.count + a.emails.count) < (b.phones.count + b.emails.count)
            }?.id
        }
        if photoSourceID == nil {
            photoSourceID = group.contacts.first { $0.thumbnail != nil }?.id
        }
    }

    private func content(_ group: ContactGroup) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(MatchReason.allCases.filter { group.reasons.contains($0) }, id: \.self) { reason in
                        Label(reason.label, systemImage: reason.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.contacts)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.Palette.contacts.opacity(0.12), in: Capsule())
                    }
                }
                if group.confidence == .review {
                    Label("The names differ. Make sure these really are the same person.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.Palette.amber)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(group.contacts) { record in
                            ContactCard(record: record,
                                        badge: badge(for: record),
                                        badgeColor: mode == .delete ? Theme.Palette.coral : Theme.Palette.brand,
                                        isDimmed: mode == .delete && app.selection.contactDeletes.contains(record.id))
                        }
                    }
                    .padding(.vertical, Theme.Spacing.s)
                }

                Picker("Action", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .merge {
                    mergeSection(group)
                } else {
                    deleteSection(group)
                }
            }
            .padding(Theme.Spacing.l)
        }
    }

    private func badge(for record: ContactRecord) -> String? {
        switch mode {
        case .merge:
            return record.id == nameSourceID ? "Name kept" : nil
        case .delete:
            return app.selection.contactDeletes.contains(record.id) ? "Will be deleted" : nil
        }
    }

    // MARK: Merge

    @ViewBuilder
    private func mergeSection(_ group: ContactGroup) -> some View {
        let planned = app.selection.contactMerges[group.id]
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Merging keeps one card and adds every phone number, email, address and other detail from the others. The other cards are then removed.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)

            Text("Keep this name")
                .font(.headline)
                .foregroundStyle(Theme.Palette.ink)
            VStack(spacing: 0) {
                ForEach(group.contacts) { record in
                    choiceRow(title: record.displayName,
                              subtitle: record.organization.isEmpty ? nil : record.organization,
                              selected: nameSourceID == record.id) {
                        nameSourceID = record.id
                        updatePlanIfNeeded(group)
                    }
                }
            }
            .card(padding: 0)

            let withPhotos = group.contacts.filter { $0.thumbnail != nil }
            if withPhotos.count > 1 {
                Text("Keep this photo")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.ink)
                HStack(spacing: Theme.Spacing.l) {
                    ForEach(withPhotos) { record in
                        Button {
                            photoSourceID = record.id
                            updatePlanIfNeeded(group)
                        } label: {
                            ContactAvatar(record: record, size: 64)
                                .overlay(Circle().stroke(photoSourceID == record.id ? Theme.Palette.brand : Color.clear, lineWidth: 3))
                                .padding(3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo from \(record.displayName)")
                        .accessibilityAddTraits(photoSourceID == record.id ? .isSelected : [])
                    }
                }
            }

            mergedPreview(group)

            Button {
                if planned != nil {
                    app.selection.removeMerge(groupID: group.id)
                } else if let plan = currentPlan(group) {
                    app.selection.setMerge(plan)
                }
            } label: {
                Label(planned != nil ? "Remove merge from review" : "Add merge to review",
                      systemImage: planned != nil ? "minus.circle" : "arrow.triangle.merge")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(planned != nil ? Theme.Palette.brand : Color.white)
                    .background(planned != nil ? Theme.Palette.brandSoft : Theme.Palette.brand, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    private func mergedPreview(_ group: ContactGroup) -> some View {
        let primary = group.contacts.first { $0.id == nameSourceID } ?? group.contacts[0]
        let ordered = [primary] + group.contacts.filter { $0.id != primary.id }
        var seenPhones = Set<String>()
        var phones: [String] = []
        var seenEmails = Set<String>()
        var emails: [String] = []
        for record in ordered {
            for phone in record.phones where seenPhones.insert(ContactNormalizer.phoneKey(phone) ?? phone).inserted {
                phones.append(phone)
            }
            for email in record.emails where seenEmails.insert(email.lowercased()).inserted {
                emails.append(email)
            }
        }
        let photoRecord = group.contacts.first { $0.id == photoSourceID } ?? ordered.first { $0.thumbnail != nil } ?? primary
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Merged card")
                .font(.headline)
                .foregroundStyle(Theme.Palette.ink)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.m) {
                    ContactAvatar(record: ContactRecord(id: primary.id, displayName: primary.displayName,
                                                        organization: primary.organization, phones: [], emails: [],
                                                        thumbnail: photoRecord.thumbnail),
                                  size: 44)
                    Text(primary.displayName)
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.ink)
                }
                ForEach(phones, id: \.self) { Label($0, systemImage: "phone").font(.footnote) }
                ForEach(emails, id: \.self) { Label($0, systemImage: "envelope").font(.footnote) }
                if phones.isEmpty && emails.isEmpty {
                    Text("No phone or email").font(.footnote).foregroundStyle(Theme.Palette.secondaryText)
                }
            }
            .foregroundStyle(Theme.Palette.ink)
            .card()
        }
    }

    private func choiceRow(title: String, subtitle: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(Theme.Palette.ink)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(Theme.Palette.secondaryText)
                    }
                }
                Spacer()
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Theme.Palette.brand : Theme.Palette.secondaryText)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func currentPlan(_ group: ContactGroup) -> ContactMergePlan? {
        guard let nameSourceID else { return nil }
        return ContactMergePlan(groupID: group.id, memberIDs: group.memberIDs,
                                nameSourceID: nameSourceID, photoSourceID: photoSourceID)
    }

    /// Keeps an already-planned merge in sync with the user's name/photo choice.
    private func updatePlanIfNeeded(_ group: ContactGroup) {
        guard app.selection.contactMerges[group.id] != nil, let plan = currentPlan(group) else { return }
        app.selection.setMerge(plan)
    }

    // MARK: Delete

    private func deleteSection(_ group: ContactGroup) -> some View {
        let selectedCount = group.memberIDs.filter { app.selection.contactDeletes.contains($0) }.count
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Choose the cards to delete. Deleting doesn't copy any details across, so use Merge if each card has something worth keeping. At least one card always stays.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
            VStack(spacing: 0) {
                ForEach(group.contacts) { record in
                    let isSelected = app.selection.contactDeletes.contains(record.id)
                    let isLastKept = !isSelected && selectedCount >= group.contacts.count - 1
                    HStack(spacing: Theme.Spacing.m) {
                        ContactAvatar(record: record, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(record.displayName).foregroundStyle(Theme.Palette.ink)
                            Text(detailLine(record))
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        if isLastKept {
                            Text("Kept")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.Palette.brand)
                        } else {
                            CheckboxButton(isSelected: isSelected) {
                                app.selection.toggleContactDelete(record.id, groupID: group.id)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, 6)
                }
            }
            .card(padding: 0)
        }
    }

    private func detailLine(_ record: ContactRecord) -> String {
        let parts = record.phones.prefix(1) + record.emails.prefix(1)
        return parts.isEmpty ? "No phone or email" : parts.joined(separator: ", ")
    }
}
