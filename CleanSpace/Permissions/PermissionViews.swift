import SwiftUI

/// Wraps any feature that needs Photos or Contacts access and renders the right state:
/// explanation before asking, a friendly dead-end with a Settings link when denied, and a banner
/// when access is limited. The wrapped content is only built once reading is allowed.
struct PermissionGate<Content: View>: View {
    let kind: PermissionKind
    @ViewBuilder var content: () -> Content

    @Environment(AppState.self) private var app

    var body: some View {
        let state = app.permissions.state(kind)
        switch state {
        case .notDetermined:
            ScrollView {
                PrePermissionView(kind: kind) {
                    await app.requestAccess(kind)
                }
                .padding(Theme.Spacing.l)
            }
            .background(AppBackdrop())
        case .denied, .restricted:
            PermissionDeniedView(kind: kind, state: state)
        case .full, .limited:
            content()
                .safeAreaInset(edge: .top, spacing: 0) {
                    if state == .limited {
                        LimitedAccessBanner(kind: kind)
                    }
                }
        }
    }
}

/// The short, honest explanation shown before the system permission dialog.
struct PrePermissionView: View {
    let kind: PermissionKind
    var onContinue: () async -> Void
    var onSkip: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(Theme.Palette.brand.opacity(0.14))
                    .frame(width: 112, height: 112)
                Image(systemName: kind.symbol)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Theme.Palette.brand)
            }
            .padding(.top, Theme.Spacing.xl)
            .accessibilityHidden(true)

            VStack(spacing: Theme.Spacing.m) {
                Text(kind.headline)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Palette.ink)
                Text(kind.explanation)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(kind.promises, id: \.self) { promise in
                    Label {
                        Text(promise.text).foregroundStyle(Theme.Palette.ink)
                    } icon: {
                        Image(systemName: promise.symbol)
                            .foregroundStyle(Theme.Palette.brand)
                            .frame(width: 28)
                    }
                    .font(.subheadline)
                }
            }
            .card()

            VStack(spacing: Theme.Spacing.s) {
                Button {
                    guard !isRequesting else { return }
                    isRequesting = true
                    Task {
                        await onContinue()
                        isRequesting = false
                    }
                } label: {
                    HStack {
                        if isRequesting { ProgressView().tint(.white) }
                        Text("Continue")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(Theme.Palette.brand, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(isRequesting)

                Button("Not now") {
                    if let onSkip { onSkip() } else { dismiss() }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Palette.secondaryText)
                .padding(.vertical, Theme.Spacing.s)
            }
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}

/// Sheet version used by the dashboard's Scan Now flow.
struct PermissionSheet: View {
    let kind: PermissionKind
    @Environment(AppState.self) private var app

    @Environment(\.dismiss) private var dismissSheet

    var body: some View {
        ScrollView {
            PrePermissionView(kind: kind, onContinue: {
                await app.requestAccess(kind)
                app.permissionPrompt = nil
                dismissSheet()
            }, onSkip: {
                app.permissionPrompt = nil
                dismissSheet()
            })
            .padding(Theme.Spacing.l)
        }
        .background(Color.clear)
    }
}

struct PermissionDeniedView: View {
    let kind: PermissionKind
    let state: AccessState

    private var deniedSymbol: String {
        switch kind {
        case .photos: "photo.badge.exclamationmark"
        case .contacts: "person.crop.circle.badge.exclamationmark"
        case .calendar: "calendar.badge.exclamationmark"
        }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer(minLength: Theme.Spacing.xxl)
            Image(systemName: deniedSymbol)
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(Theme.Palette.secondaryText)
                .accessibilityHidden(true)
            Text("\(kind.title) access is off")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
            Text(state == .restricted ? kind.restrictedMessage : kind.deniedMessage)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Palette.secondaryText)
                .padding(.horizontal, Theme.Spacing.l)
            if state == .denied {
                Button {
                    PermissionCenter.openSettings()
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                        .font(.headline)
                        .padding(.horizontal, Theme.Spacing.xl)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Theme.Palette.brand, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, Theme.Spacing.s)
            }
            Spacer()
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackdrop())
    }
}

struct LimitedAccessBanner: View {
    let kind: PermissionKind
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.Palette.amber)
                .accessibilityHidden(true)
            Text(kind == .photos
                 ? "CleanSpace can only scan the photos you've allowed. Results cover those photos only."
                 : "Limited access: results only cover the contacts you've shared with CleanSpace.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(kind == .photos ? "Manage" : "Settings") {
                if kind == .photos {
                    LimitedLibraryPicker.present { app.photoLibrarySelectionChanged() }
                } else {
                    PermissionCenter.openSettings()
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.Palette.brand)
            .accessibilityLabel(kind == .photos ? "Manage selected photos" : "Open Settings")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .background(.bar)
    }
}
