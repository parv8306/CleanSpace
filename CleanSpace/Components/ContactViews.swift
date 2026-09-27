import SwiftUI
import UIKit

struct ContactAvatar: View {
    let record: ContactRecord
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let data = record.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Theme.Palette.contacts.opacity(0.16)
                    Text(record.initials)
                        .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Palette.contacts)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// One contact's details, used side by side in the duplicate group screen.
struct ContactCard: View {
    let record: ContactRecord
    var badge: String?
    var badgeColor: Color = Theme.Palette.brand
    var isDimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                ContactAvatar(record: record, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.displayName)
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(2)
                    if !record.organization.isEmpty && record.organization != record.displayName {
                        Text(record.organization)
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            if let badge {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor.opacity(0.14), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 6) {
                if record.phones.isEmpty && record.emails.isEmpty {
                    Text("No phone or email")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                ForEach(Array(record.phones.enumerated()), id: \.offset) { _, phone in
                    Label(phone, systemImage: "phone")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(1)
                }
                ForEach(Array(record.emails.enumerated()), id: \.offset) { _, email in
                    Label(email, systemImage: "envelope")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 230, alignment: .leading)
        .card()
        .opacity(isDimmed ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// Overlapping avatars for list rows.
struct AvatarStack: View {
    let records: [ContactRecord]
    var size: CGFloat = 36

    var body: some View {
        HStack(spacing: -size * 0.35) {
            ForEach(records.prefix(3)) { record in
                ContactAvatar(record: record, size: size)
                    .overlay(Circle().stroke(Theme.Palette.surface, lineWidth: 2))
            }
        }
    }
}
