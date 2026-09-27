import SwiftUI

/// How much chrome a glass cover adds on top of its content.
enum GlassCoverChrome {
    /// Grab handle and a close button. For popups without their own Done or Close button.
    case full
    /// Grab handle only. For popups whose navigation bar already has Done, Cancel or Close.
    case handle
    /// Nothing. For flows that must not be dismissed by a gesture (deleting, compressing).
    case none
}

extension View {
    /// Presents content full screen, sliding up from the bottom, on a frosted glass background.
    /// Every popup in CleanSpace uses this so they look and behave the same.
    func glassCover<Item: Identifiable, Content: View>(item: Binding<Item?>,
                                                       chrome: GlassCoverChrome = .full,
                                                       onDismiss: (() -> Void)? = nil,
                                                       @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        fullScreenCover(item: item, onDismiss: onDismiss) { value in
            GlassCoverContainer(chrome: chrome) { content(value) }
        }
    }

    func glassCover<Content: View>(isPresented: Binding<Bool>,
                                   chrome: GlassCoverChrome = .full,
                                   onDismiss: (() -> Void)? = nil,
                                   @ViewBuilder content: @escaping () -> Content) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            GlassCoverContainer(chrome: chrome, content: content)
        }
    }
}

/// The glass layer: the app shows through a translucent material, with a light tint so text on
/// top stays readable. A top grab handle can be dragged down to dismiss.
struct GlassCoverContainer<Content: View>: View {
    let chrome: GlassCoverChrome
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                if chrome != .none { header }
            }
            .background(Theme.Palette.glassTint.ignoresSafeArea())
            .offset(y: dragOffset)
            .presentationBackground(.ultraThinMaterial)
    }

    private var header: some View {
        ZStack {
            Capsule()
                .fill(Theme.Palette.secondaryText.opacity(0.35))
                .frame(width: 40, height: 5)
                .frame(width: 120, height: 30)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in dragOffset = max(0, value.translation.height) }
                        .onEnded { value in
                            if value.translation.height > 120 || value.predictedEndTranslation.height > 280 {
                                dismiss()
                            } else {
                                withAnimation(.spring(duration: 0.3)) { dragOffset = 0 }
                            }
                        }
                )
                .accessibilityHidden(true)
            if chrome == .full {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Palette.ink)
                            .frame(width: 40, height: 40)
                            .csGlass(in: Circle(), interactive: true)
                            .frame(width: 48, height: 48)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, Theme.Spacing.m)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: chrome == .full ? 56 : 30)
        .accessibilityAction(named: "Close") { dismiss() }
    }
}
