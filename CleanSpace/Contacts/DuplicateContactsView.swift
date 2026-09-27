import SwiftUI

struct DuplicateContactsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let model = app.contacts
        Group {
            if let message = model.phase.failureMessage, !model.hasResults {
                ErrorStateView(message: message) { model.scan() }
            } else if !model.hasResults {
                ScanningStateView(title: "Comparing contacts", phase: model.phase,
                                  onCancel: model.phase.isScanning ? { model.cancel() } : nil)
            } else if model.groups.isEmpty {
                EmptyStateView(symbol: "person.2",
                               title: "No duplicate contacts found",
                               message: "Checked \(Format.count(model.totalContacts, "contact")).",
                               actionTitle: "Check again") { model.scan() }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        SummaryHeader(title: Format.count(model.duplicateCount, "duplicate"),
                                      subtitle: "found among \(Format.count(model.totalContacts, "contact")). Nothing changes until you confirm on the review screen.")
                            .padding(.bottom, Theme.Spacing.s)
                        if !model.likelyGroups.isEmpty {
                            groupSection(title: "Likely duplicates",
                                         footer: "Same person, matched by phone, email or name.",
                                         groups: model.likelyGroups)
                        }
                        if !model.reviewGroups.isEmpty {
                            groupSection(title: "Worth a closer look",
                                         footer: "These share a phone number or email but have different names, like a shared family line. Check before merging.",
                                         groups: model.reviewGroups)
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
                .refreshable { model.scan() }
            }
        }
        .background(AppBackdrop())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CategorySelectionBar(category: .duplicateContacts)
        }
        .animation(.snappy, value: app.selectedCount(in: .duplicateContacts) > 0)
        .task { app.ensureScanned(.duplicateContacts) }
    }

    private func groupSection(title: String, footer: String, groups: [ContactGroup]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            .padding(.top, Theme.Spacing.s)
            ForEach(groups) { group in card(group) }
        }
    }

    private func card(_ group: ContactGroup) -> some View {
        let phone = group.contacts.lazy.compactMap { $0.phones.first }.first
        let email = group.contacts.lazy.compactMap { $0.emails.first }.first
        return NavigationLink(value: Route.contactGroup(group.id)) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Label("Possible duplicate", systemImage: "person.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.contacts)
                    Spacer()
                    Text("\(group.contacts.count.formatted()) cards")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.secondaryText.opacity(0.6))
                }
                HStack(spacing: Theme.Spacing.m) {
                    AvatarStack(records: group.contacts, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.contacts.first?.displayName ?? "Contact")
                            .font(.headline)
                            .foregroundStyle(Theme.Palette.ink)
                            .lineLimit(1)
                        if let phone {
                            Label(phone, systemImage: "phone.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.secondaryText)
                                .lineLimit(1)
                        }
                        if let email {
                            Label(email, systemImage: "envelope.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                HStack {
                    Text("Matched by \(reasonText(group))")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .lineLimit(1)
                    Spacer()
                    if let plan = planText(group) {
                        Text(plan)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.brand)
                    }
                }
            }
            .card()
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
    }

    private func reasonText(_ group: ContactGroup) -> String {
        MatchReason.allCases.filter { group.reasons.contains($0) }.map { $0.label.lowercased() }.joined(separator: ", ")
    }

    private func planText(_ group: ContactGroup) -> String? {
        if app.selection.contactMerges[group.id] != nil { return "Merge planned" }
        let deletes = group.memberIDs.filter { app.selection.contactDeletes.contains($0) }.count
        return deletes > 0 ? "\(deletes.formatted()) to delete" : nil
    }
}
