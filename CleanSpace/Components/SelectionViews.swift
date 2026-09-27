import SwiftUI

/// Round check used on every selectable tile. Selected means "marked for removal".
struct SelectionCheck: View {
    let isSelected: Bool
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Theme.Palette.brand : Color.black.opacity(0.25))
            Circle()
                .strokeBorder(.white, lineWidth: isSelected ? 0 : 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isSelected ? 1.08 : 1)
        .animation(.spring(duration: 0.3, bounce: 0.5), value: isSelected)
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

/// Square checkbox for list rows.
struct CheckboxButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(isSelected ? Theme.Palette.brand : Theme.Palette.secondaryText.opacity(0.6))
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(isSelected ? 1.08 : 1)
                .animation(.spring(duration: 0.3, bounce: 0.5), value: isSelected)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(isSelected ? "Selected for removal" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Sticky bottom summary: "12 selected, 340 MB" plus the button that opens the Review screen.
struct SelectionBar: View {
    let count: Int
    let noun: String
    let bytes: Int64?
    var buttonTitle = "Review Changes"
    /// Shows a clear button that drops the selection.
    var onClear: (() -> Void)?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .frame(width: 32, height: 32)
                        .background(Theme.Palette.surfaceSunken.opacity(0.9), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Clear selection")
            }
            summary
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(0)
            Spacer(minLength: 6)
            Button(action: action) {
                Text(buttonTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .modifier(TintedGlassCapsule(tint: Theme.Palette.brand))
                    .frame(minHeight: 44)
            }
            .buttonStyle(PressableButtonStyle())
            .layoutPriority(1)
            .accessibilityHint("Opens the review screen. Nothing is deleted until you confirm there.")
        }
        .padding(.leading, onClear == nil ? 16 : 4)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .glassSurface(cornerRadius: 30)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.xs)
        .animation(.snappy, value: count)
        .sensoryFeedback(.selection, trigger: count)
    }

    /// "12 items selected, 1.2 GB" on one line.
    private var summary: Text {
        let chosen = Text("\(Format.count(count, noun)) selected")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(Theme.Palette.ink)
        guard let bytes, bytes > 0 else { return chosen }
        return chosen + Text(", \(Format.bytes(bytes))")
            .font(.subheadline)
            .foregroundColor(Theme.Palette.secondaryText)
    }
}

/// Bottom bar shown only when something in the category is selected.
struct CategorySelectionBar: View {
    let category: CleanupCategory
    @Environment(AppState.self) private var app

    var body: some View {
        let count = app.selectedCount(in: category)
        if count > 0 {
            SelectionBar(count: count,
                         noun: category.noun,
                         bytes: category.isMedia ? app.selectedBytes(in: category) : nil,
                         onClear: { withAnimation(.snappy) { app.clearSelection(in: category) } }) {
                app.openReview([category])
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct SizeBadge: View {
    let bytes: Int64

    var body: some View {
        Text(Format.bytes(bytes))
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.45), in: Capsule())
    }
}
