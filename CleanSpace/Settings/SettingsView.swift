import StoreKit
import SwiftUI

struct SettingsView: View {
    private enum Sheet: Identifiable {
        case permission(PermissionKind)
        case changePasscode
        case whatsNew
        case about
        case privacy
        case terms
        case recover

        var id: String {
            switch self {
            case let .permission(kind): "permission-\(kind.rawValue)"
            case .changePasscode: "passcode"
            case .whatsNew: "whatsNew"
            case .about: "about"
            case .privacy: "privacy"
            case .terms: "terms"
            case .recover: "recover"
            }
        }
    }

    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    @State private var sheet: Sheet?
    @State private var limitedOptionsFor: PermissionKind?
    @State private var confirmErase = false
    @State private var biometricsToggle = false
    @State private var reminderOn = false
    @State private var reminderBusy = false
    @State private var showNotificationsDenied = false
    @State private var cacheMessage: String?
    @State private var clearingCache = false
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                appearanceSection
                generalSection
                accessSection
                vaultSection
                historySection
                appSection
                footer
            }
            .padding(Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(AppBackdrop())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .task {
            app.permissions.refresh()
            biometricsToggle = app.vaultLock.biometricsEnabled
            reminderOn = await ScanReminder.isActive()
        }
        .glassCover(item: $sheet) { item in
            sheetContent(item)
        }
        .confirmationDialog("Limited photo access", isPresented: Binding(
            get: { limitedOptionsFor != nil }, set: { if !$0 { limitedOptionsFor = nil } }),
                            titleVisibility: .visible) {
            Button("Select more photos") {
                LimitedLibraryPicker.present { app.photoLibrarySelectionChanged() }
            }
            Button("Allow full access in Settings") { PermissionCenter.openSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("CleanSpace can only see the photos you've shared. Choose more photos, or allow access to your whole library in Settings.")
        }
        .confirmationDialog("Erase the vault?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase everything in the vault", role: .destructive) {
                Task { await app.vaultLock.eraseVault() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every photo and video in the vault is permanently deleted, along with its PIN. Save anything you want to keep to Photos first.")
        }
        .alert("Notifications are off", isPresented: $showNotificationsDenied) {
            Button("Open Settings") { PermissionCenter.openSettings() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("To get scan reminders, allow notifications for CleanSpace in Settings.")
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        SettingsSection(title: "Appearance", footer: "System follows your iPhone's Light or Dark setting.") {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    SettingsIcon(symbol: (AppearanceMode(rawValue: appearance) ?? .system).symbol, tint: Theme.Palette.brand)
                    Text("Appearance")
                        .foregroundStyle(Theme.Palette.ink)
                }
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: appearance)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, 14)
        }
    }

    // MARK: General

    private var generalSection: some View {
        SettingsSection(title: "General") {
            SettingsRowContainer {
                SettingsIcon(symbol: "bell.badge.fill", tint: Theme.Palette.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly scan reminder")
                        .font(.body)
                        .foregroundStyle(Theme.Palette.ink)
                    Text("A gentle nudge on Sunday mornings")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                Spacer()
                Toggle("Weekly scan reminder", isOn: $reminderOn)
                    .labelsHidden()
                    .tint(Theme.Palette.brand)
                    .disabled(reminderBusy)
                    .onChange(of: reminderOn) { _, isOn in updateReminder(isOn) }
            }
            SettingsDivider()
            Button {
                clearCache()
            } label: {
                SettingsRowContainer {
                    SettingsIcon(symbol: "trash.circle.fill", tint: Theme.Palette.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear temporary files")
                            .font(.body)
                            .foregroundStyle(Theme.Palette.ink)
                        Text(cacheMessage ?? "Removes CleanSpace's own cache and leftovers")
                            .font(.caption)
                            .foregroundStyle(cacheMessage == nil ? Theme.Palette.secondaryText : Theme.Palette.success)
                            .contentTransition(.opacity)
                    }
                    Spacer()
                    if clearingCache {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Clear")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.brand)
                    }
                }
            }
            .buttonStyle(SettingsRowButtonStyle())
            .disabled(clearingCache)
            .accessibilityHint("Removes temporary files. Your photos, contacts and vault aren't affected.")
        }
    }

    private func updateReminder(_ isOn: Bool) {
        guard !reminderBusy else { return }
        reminderBusy = true
        Task {
            if isOn {
                if await ScanReminder.isActive() {
                    reminderBusy = false
                    return
                }
                let ok = await ScanReminder.enable()
                if !ok {
                    reminderOn = false
                    showNotificationsDenied = true
                }
            } else {
                ScanReminder.disable()
            }
            reminderBusy = false
        }
    }

    private func clearCache() {
        clearingCache = true
        ThumbnailLoader.shared.clearMemory()
        FingerprintCache.shared.clear()
        AssetSizeCache.shared.clear()
        Task {
            let freed = await Task.detached(priority: .userInitiated) { TemporaryFiles.clear() }.value
            withAnimation(.snappy) {
                cacheMessage = freed > 0 ? "Cleared \(Format.bytes(freed))" : "Already clean"
                clearingCache = false
            }
        }
    }

    // MARK: Access

    private var accessSection: some View {
        SettingsSection(title: "Access",
                        footer: "Tap a row to allow access or change it in the Settings app. CleanSpace only reads what you allow, and only on this iPhone.") {
            ForEach(Array(PermissionKind.allCases.enumerated()), id: \.element) { index, kind in
                accessRow(kind)
                if index < PermissionKind.allCases.count - 1 { SettingsDivider() }
            }
        }
    }

    private func accessRow(_ kind: PermissionKind) -> some View {
        let state = app.permissions.state(kind)
        let badge = PermissionBadge(state: state)
        return Button {
            handleAccessTap(kind, state: state)
        } label: {
            SettingsRowContainer {
                SettingsIcon(symbol: kind.symbol, tint: iconTint(kind))
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.body)
                        .foregroundStyle(Theme.Palette.ink)
                    Label(badge.text, systemImage: badge.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(badge.color)
                        .labelStyle(.titleAndIcon)
                }
                Spacer()
                Text(actionTitle(kind, state: state))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.brand)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.secondaryText.opacity(0.6))
            }
        }
        .buttonStyle(SettingsRowButtonStyle())
        .accessibilityLabel("\(kind.title), \(badge.text)")
        .accessibilityHint(actionHint(kind, state: state))
    }

    private func iconTint(_ kind: PermissionKind) -> Color {
        switch kind {
        case .photos: Theme.Palette.brand
        case .contacts: Theme.Palette.contacts
        case .calendar: Theme.Palette.calendar
        }
    }

    private func actionTitle(_ kind: PermissionKind, state: AccessState) -> String {
        switch state {
        case .notDetermined: "Allow"
        case .limited: kind == .photos ? "Manage" : "Settings"
        case .denied, .restricted: "Open Settings"
        case .full: "Settings"
        }
    }

    private func actionHint(_ kind: PermissionKind, state: AccessState) -> String {
        switch state {
        case .notDetermined: "Explains why CleanSpace needs access, then asks iOS"
        case .limited: kind == .photos ? "Choose more photos or allow full access" : "Opens the Settings app"
        case .denied, .restricted, .full: "Opens CleanSpace in the Settings app"
        }
    }

    private func handleAccessTap(_ kind: PermissionKind, state: AccessState) {
        switch state {
        case .notDetermined:
            sheet = .permission(kind)
        case .limited where kind == .photos:
            limitedOptionsFor = kind
        default:
            PermissionCenter.openSettings()
        }
    }

    // MARK: Vault

    private var vaultSection: some View {
        SettingsSection(title: "Private vault") {
            if app.vaultLock.state == .needsSetup {
                NavigationLink(value: Route.vault) {
                    SettingsRowContainer {
                        SettingsIcon(symbol: "lock.square.stack.fill", tint: Theme.Palette.vault)
                        Text("Set up vault").foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Palette.secondaryText.opacity(0.6))
                    }
                }
                .buttonStyle(SettingsRowButtonStyle())
            } else {
                if app.vaultLock.biometry != .none {
                    SettingsRowContainer {
                        SettingsIcon(symbol: app.vaultLock.biometrySymbol, tint: Theme.Palette.vault)
                        Text("Unlock with \(app.vaultLock.biometryName)").foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        Toggle("Unlock with \(app.vaultLock.biometryName)", isOn: $biometricsToggle)
                            .labelsHidden()
                            .tint(Theme.Palette.brand)
                            .onChange(of: biometricsToggle) { _, isOn in
                                guard isOn != app.vaultLock.biometricsEnabled else { return }
                                if isOn {
                                    Task { biometricsToggle = await app.vaultLock.enableBiometrics() }
                                } else {
                                    app.vaultLock.biometricsEnabled = false
                                }
                            }
                    }
                    SettingsDivider()
                }
                Button { sheet = .changePasscode } label: {
                    SettingsRowContainer {
                        SettingsIcon(symbol: "key.fill", tint: Theme.Palette.vault)
                        Text("Change PIN").foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Palette.secondaryText.opacity(0.6))
                    }
                }
                .buttonStyle(SettingsRowButtonStyle())
                SettingsDivider()
                Button { confirmErase = true } label: {
                    SettingsRowContainer {
                        SettingsIcon(symbol: "trash.fill", tint: Theme.Palette.coral)
                        Text("Erase vault").foregroundStyle(Theme.Palette.coral)
                        Spacer()
                    }
                }
                .buttonStyle(SettingsRowButtonStyle())
            }
        }
    }

    // MARK: History

    private var historySection: some View {
        SettingsSection(title: "History") {
            NavigationLink(value: Route.history) {
                SettingsRowContainer {
                    SettingsIcon(symbol: "clock.arrow.circlepath", tint: Theme.Palette.success)
                    Text("Cleanup history").foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Text(Format.bytes(app.lifetimeFreedBytes))
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.secondaryText)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.secondaryText.opacity(0.6))
                }
            }
            .buttonStyle(SettingsRowButtonStyle())
            SettingsDivider()
            Button { sheet = .recover } label: {
                SettingsRowContainer {
                    SettingsIcon(symbol: "arrow.uturn.backward", tint: Theme.Palette.brand)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recover deleted items").foregroundStyle(Theme.Palette.ink)
                        Text("Recently Deleted keeps them for 30 days")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.secondaryText.opacity(0.6))
                }
            }
            .buttonStyle(SettingsRowButtonStyle())
        }
    }

    // MARK: App

    private var appSection: some View {
        SettingsSection(title: "App") {
            navRow("About CleanSpace", symbol: "info.circle.fill", tint: Theme.Palette.brand) { sheet = .about }
            SettingsDivider()
            navRow("What's New", symbol: "sparkles", tint: Theme.Palette.cyan) { sheet = .whatsNew }
            SettingsDivider()
            navRow("Privacy Policy", symbol: "hand.raised.fill", tint: Theme.Palette.brandDeep) { sheet = .privacy }
            SettingsDivider()
            navRow("Terms of Use", symbol: "doc.text.fill", tint: Theme.Palette.blurry) { sheet = .terms }
            SettingsDivider()
            navRow("Rate CleanSpace", symbol: "star.fill", tint: Theme.Palette.amber, showsChevron: false) {
                requestReview()
            }
            if let url = AppInfo.feedbackURL {
                SettingsDivider()
                navRow("Send Feedback", symbol: "envelope.fill", tint: Theme.Palette.success, showsChevron: false) {
                    openURL(url)
                }
            }
            SettingsDivider()
            SettingsRowContainer {
                SettingsIcon(symbol: "number", tint: Theme.Palette.secondaryText)
                Text("Version").foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text("\(AppInfo.version) (\(AppInfo.build))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func navRow(_ title: String, symbol: String, tint: Color, showsChevron: Bool = true,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsRowContainer {
                SettingsIcon(symbol: symbol, tint: tint)
                Text(title).foregroundStyle(Theme.Palette.ink)
                Spacer()
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.secondaryText.opacity(0.6))
                }
            }
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    private var footer: some View {
        VStack(spacing: Theme.Spacing.s) {
            AppLogoMark(size: 44)
            Text("CleanSpace")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
            Text(AppInfo.tagline)
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
            Text("Your photos, contacts and calendar stay on your iPhone.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.m)
        .accessibilityElement(children: .combine)
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ item: Sheet) -> some View {
        switch item {
        case let .permission(kind):
            PermissionSheet(kind: kind).environment(app)
        case .changePasscode:
            ChangePasscodeView().environment(app)
        case .whatsNew:
            InfoSheet(title: "What's New") { WhatsNewContent() }
        case .about:
            InfoSheet(title: "About") { AboutContent() }
        case .privacy:
            InfoSheet(title: "Privacy Policy") { PolicyContent(sections: PolicyText.privacy) }
        case .terms:
            InfoSheet(title: "Terms of Use") { PolicyContent(sections: PolicyText.terms) }
        case .recover:
            RecoverView().environment(app)
        }
    }
}

// MARK: - Settings building blocks

struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.secondaryText)
                .padding(.leading, Theme.Spacing.s)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content() }
                .glassSurface(cornerRadius: 24)
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .padding(.horizontal, Theme.Spacing.s)
            }
        }
    }
}

struct SettingsRowContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: Theme.Spacing.m) { content() }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
    }
}

struct SettingsIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        CleanSpaceIcon(symbol: symbol, tint: tint, size: 32)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 60)
    }
}

/// Row highlight on press, like a native grouped list.
struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.Palette.brandSoft : Color.clear)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Status wording, icon and color for a permission. Icon and text always accompany the color.
struct PermissionBadge {
    let text: String
    let symbol: String
    let color: Color

    init(state: AccessState) {
        switch state {
        case .full:
            text = "Full Access"; symbol = "checkmark.circle.fill"; color = Theme.Palette.success
        case .limited:
            text = "Limited Access"; symbol = "exclamationmark.circle.fill"; color = Theme.Palette.amber
        case .denied:
            text = "Not Allowed"; symbol = "xmark.circle.fill"; color = Theme.Palette.coral
        case .restricted:
            text = "Restricted on This iPhone"; symbol = "xmark.circle.fill"; color = Theme.Palette.coral
        case .notDetermined:
            text = "Not Asked Yet"; symbol = "questionmark.circle.fill"; color = Theme.Palette.secondaryText
        }
    }
}

// MARK: - Info sheets

struct InfoSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                content()
                    .padding(Theme.Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.clear)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct AboutContent: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.s) {
                AppLogoMark(size: 88)
                    .shadow(color: Theme.Palette.brand.opacity(0.3), radius: 16, y: 8)
                Text("CleanSpace")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(AppInfo.tagline)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                CleanSpaceIcon(symbol: "lock.shield.fill", tint: Theme.Palette.brand, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your privacy matters.")
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.ink)
                    Text("Your photos and contacts are processed on your device. CleanSpace has no servers, accounts, analytics or ads, and nothing is deleted until you confirm it.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Features")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.ink)
                ForEach(AppInfo.features, id: \.text) { feature in
                    Label {
                        Text(feature.text).foregroundStyle(Theme.Palette.ink)
                    } icon: {
                        Image(systemName: feature.symbol).foregroundStyle(Theme.Palette.brand)
                    }
                    .font(.subheadline)
                }
            }
            .card()

            VStack(spacing: 0) {
                NavigationLink {
                    PolicyPage(title: "Privacy Policy", sections: PolicyText.privacy)
                } label: {
                    linkRow("Privacy Policy", symbol: "hand.raised.fill", tint: Theme.Palette.brandDeep)
                }
                .buttonStyle(SettingsRowButtonStyle())
                SettingsDivider()
                NavigationLink {
                    PolicyPage(title: "Terms of Use", sections: PolicyText.terms)
                } label: {
                    linkRow("Terms of Use", symbol: "doc.text.fill", tint: Theme.Palette.blurry)
                }
                .buttonStyle(SettingsRowButtonStyle())
                if let url = AppInfo.feedbackURL {
                    SettingsDivider()
                    Button { openURL(url) } label: {
                        linkRow("Send Feedback", symbol: "envelope.fill", tint: Theme.Palette.success, chevron: false)
                    }
                    .buttonStyle(SettingsRowButtonStyle())
                }
                SettingsDivider()
                Button { requestReview() } label: {
                    linkRow("Rate CleanSpace", symbol: "star.fill", tint: Theme.Palette.amber, chevron: false)
                }
                .buttonStyle(SettingsRowButtonStyle())
            }
            .glassSurface(cornerRadius: 18)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.Palette.separator, lineWidth: 1))

            Text("Version \(AppInfo.version) (\(AppInfo.build))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.secondaryText)
                .frame(maxWidth: .infinity)
        }
    }

    private func linkRow(_ title: String, symbol: String, tint: Color, chevron: Bool = true) -> some View {
        SettingsRowContainer {
            SettingsIcon(symbol: symbol, tint: tint)
            Text(title).foregroundStyle(Theme.Palette.ink)
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.secondaryText.opacity(0.6))
            }
        }
    }
}

private struct PolicyPage: View {
    let title: String
    let sections: [PolicyText.Section]

    var body: some View {
        ScrollView {
            PolicyContent(sections: sections)
                .padding(Theme.Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.clear)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WhatsNewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            ForEach(AppInfo.releases) { release in
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack {
                        Text("Version \(release.version)")
                            .font(.headline)
                            .foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        if release.version == AppInfo.version {
                            Text("Current")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.Palette.brand)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.Palette.brandSoft, in: Capsule())
                        }
                    }
                    ForEach(release.notes, id: \.self) { note in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                            Image(systemName: "sparkle")
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.cyan)
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(Theme.Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .card()
            }
        }
    }
}

enum PolicyText {
    struct Section: Identifiable {
        let heading: String
        let body: String
        var id: String { heading }
    }

    static let privacy: [Section] = [
        Section(heading: "The short version",
                body: "CleanSpace works entirely on your iPhone. It doesn't collect, store or share your personal data, and it has no servers, accounts, analytics, advertising or tracking."),
        Section(heading: "Photos and videos",
                body: "With your permission, CleanSpace reads your photo library on this iPhone to find duplicates, similar shots, screenshots, blurry photos and large videos. Analysis uses small local previews. Nothing is uploaded, and photos stored only in iCloud are never downloaded."),
        Section(heading: "Contacts and calendar",
                body: "With your permission, CleanSpace compares contacts to find duplicates and checks calendars you can edit for old and duplicate events. Changes happen only after you confirm them."),
        Section(heading: "Private vault",
                body: "Items you add to the vault are encrypted and stored only inside CleanSpace on this iPhone. They aren't included in backups and can't be recovered if you delete the app or forget your PIN."),
        Section(heading: "Stored on your iPhone",
                body: "CleanSpace keeps a few things on this iPhone: your last scan date, the total space freed, a list of past cleanups with small thumbnails of the items you deleted (so you can see what was removed), vault settings and reminder settings. Clearing the history removes the thumbnails; deleting the app removes everything."),
        Section(heading: "Notifications",
                body: "If you turn on the weekly scan reminder, CleanSpace schedules a local notification on this iPhone. No notification service or server is involved."),
        Section(heading: "Changes",
                body: "If this policy changes, the new version will appear here in the app.")
    ]

    static let terms: [Section] = [
        Section(heading: "Using CleanSpace",
                body: "CleanSpace helps you find items you may want to remove. You decide what is deleted, and every deletion is confirmed by you and, for photos and videos, by iOS."),
        Section(heading: "Deleted items",
                body: "Deleted photos and videos go to Recently Deleted in the Photos app for 30 days. Contact changes, deleted calendar events and deleted vault items can't be undone from CleanSpace. Please review your selection before confirming."),
        Section(heading: "Estimates",
                body: "Space estimates and compression sizes are based on the information iOS provides and may differ from the final result."),
        Section(heading: "No warranty",
                body: "CleanSpace is provided as is. To the extent permitted by law, the developer isn't liable for data you choose to delete. Keep a backup of anything important.")
    ]
}

private struct PolicyContent: View {
    let sections: [PolicyText.Section]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(section.heading)
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.ink)
                    Text(section.body)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Change passcode

struct ChangePasscodeView: View {
    private enum Step { case current, new, confirm }

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .current
    @State private var current = ""
    @State private var newCode = ""
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch step {
                    case .current:
                        PasscodePad(title: "Enter Your Current PIN", message: message, isError: isError,
                                    isDisabled: app.vaultLock.lockoutRemaining() > 0) { entered in
                            current = entered
                            message = nil
                            isError = false
                            step = .new
                        }
                    case .new:
                        PasscodePad(title: "Create a New PIN", message: message, isError: isError) { entered in
                            newCode = entered
                            message = nil
                            isError = false
                            step = .confirm
                        }
                    case .confirm:
                        PasscodePad(title: "Confirm Your New PIN", message: message, isError: isError,
                                    isDisabled: app.vaultLock.isWorking) { entered in
                            finish(entered)
                        }
                    }
                }
                .padding(Theme.Spacing.l)
                .padding(.top, Theme.Spacing.xl)
            }
            .background(Color.clear)
            .navigationTitle("Change PIN")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func finish(_ entered: String) {
        guard entered == newCode else {
            message = "The PINs didn't match. Choose a new PIN again."
            isError = true
            step = .new
            return
        }
        Task {
            if await app.vaultLock.changePasscode(current: current, new: newCode) {
                dismiss()
            } else {
                message = "Your current PIN wasn't right."
                isError = true
                step = .current
            }
        }
    }
}

// MARK: - History

struct CleanupHistoryView: View {
    private struct Viewing: Identifiable {
        let item: HistoryItem
        let date: Date
        var id: UUID { item.id }
    }

    @Environment(AppState.self) private var app
    @State private var confirmClear = false
    @State private var viewing: Viewing?
    @State private var showRecover = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        Group {
            if app.history.isEmpty {
                EmptyStateView(symbol: "clock.arrow.circlepath",
                               title: "No cleanups yet",
                               message: "Each time you free space, what you removed appears here.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Freed in total")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Palette.secondaryText)
                            Text(Format.bytes(app.lifetimeFreedBytes))
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Palette.brand)
                        }
                        .card()
                        recoverCard
                        ForEach(app.history) { record in
                            recordCard(record)
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
            }
        }
        .background(AppBackdrop())
        .navigationTitle("Cleanup History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if !app.history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { confirmClear = true }
                }
            }
        }
        .confirmationDialog("Clear cleanup history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { app.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The list and its thumbnails are removed. The total freed stays.")
        }
        .glassCover(item: $viewing) { viewing in
            HistoryItemDetail(item: viewing.item, date: viewing.date)
        }
        .glassCover(isPresented: $showRecover) {
            RecoverView().environment(app)
        }
    }

    private var recoverCard: some View {
        Button { showRecover = true } label: {
            HStack(spacing: Theme.Spacing.m) {
                CleanSpaceIcon(symbol: "arrow.uturn.backward", tint: Theme.Palette.brand, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recover deleted items")
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.ink)
                    Text("Deleted photos and videos stay in Recently Deleted for 30 days")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.secondaryText.opacity(0.6))
            }
            .card()
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func recordCard(_ record: CleanupRecord) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(record.description)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                Spacer()
                if record.bytesFreed > 0 {
                    Text(Format.bytes(record.bytesFreed))
                        .font(Theme.Typography.rowNumber)
                        .foregroundStyle(Theme.Palette.brand)
                }
            }
            .accessibilityElement(children: .combine)
            if let items = record.items, !items.isEmpty {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(items) { item in
                        Button { viewing = Viewing(item: item, date: record.date) } label: {
                            HistoryThumbnailTile(item: item)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                    if let more = record.moreItemCount, more > 0 {
                        Text("+\(more.formatted())")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.Palette.brand)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .background(Theme.Palette.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                            .accessibilityLabel("\(more) more items")
                    }
                }
            }
        }
        .card()
    }
}

/// A deleted item's thumbnail, loaded from disk off the main thread.
struct HistoryThumbnailTile: View {
    let item: HistoryItem
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Theme.Palette.surfaceSunken
                        Image(systemName: item.category?.symbol ?? "photo")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(item.category?.tint ?? Theme.Palette.brand)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if item.isVideo {
                    Label(item.duration > 0 ? Format.duration(item.duration) : "Video", systemImage: "play.fill")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(4)
                }
            }
            .task(id: item.id) {
                guard item.hasThumbnail else { return }
                let id = item.id
                let data = await Task.detached(priority: .utility) { HistoryThumbnailStore.data(for: id) }.value
                image = data.flatMap(UIImage.init(data:))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.category?.noun.capitalized ?? "Item"), \(Format.bytes(item.bytes))")
    }
}

/// Larger view of one deleted item.
private struct HistoryItemDetail: View {
    let item: HistoryItem
    let date: Date

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            HistoryThumbnailTile(item: item)
                .frame(maxWidth: 320)
                .shadow(color: Theme.Palette.shadow, radius: 16, y: 8)
            VStack(spacing: Theme.Spacing.s) {
                Text(item.category?.title ?? "Deleted item")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                DetailRow(label: "Deleted", value: date.formatted(date: .long, time: .shortened))
                DetailRow(label: "Size", value: item.bytes > 0 ? Format.bytes(item.bytes) : "Unknown")
                if item.duration > 0 {
                    DetailRow(label: "Length", value: Format.duration(item.duration))
                }
            }
            .card()
            Text("Deleted photos and videos stay in Recently Deleted in the Photos app for 30 days, where you can still recover them.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(Theme.Spacing.l)
    }
}
