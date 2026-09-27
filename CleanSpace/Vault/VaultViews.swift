import AVKit
import PhotosUI
import SwiftUI

/// Entry point for the private vault: setup, lock screen, or contents.
struct VaultView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            switch app.vaultLock.state {
            case .needsSetup: VaultSetupView()
            case .locked: VaultLockView()
            case .unlocked: VaultContentView()
            }
        }
        .id(app.vaultLock.state)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .background(
            LinearGradient(colors: [Theme.Palette.vaultTop, Theme.Palette.vaultBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .sensoryFeedback(.success, trigger: app.vaultLock.state) { _, new in new == .unlocked }
        .navigationTitle("Private Vault")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy, value: app.vaultLock.state)
        .onDisappear {
            app.vaultLock.lock()
            app.vault.clear()
        }
    }
}

// MARK: - Setup

struct VaultSetupView: View {
    private enum Step: Int { case intro, create, confirm, biometrics }

    @Environment(AppState.self) private var app
    @State private var step: Step = .intro
    @State private var firstEntry = ""
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                if step == .create || step == .confirm {
                    VaultHero(size: 84, symbol: step == .confirm ? "checkmark.shield.fill" : "lock.shield.fill")
                    stepIndicator
                }
                Group {
                    switch step {
                    case .intro: intro
                    case .create:
                        PasscodePad(title: "Create Your PIN",
                                    message: message ?? "Your private space is protected by a 6-digit PIN.",
                                    isError: isError) { entered in
                            firstEntry = entered
                            message = nil
                            isError = false
                            go(to: .confirm)
                        }
                    case .confirm:
                        PasscodePad(title: "Confirm Your PIN",
                                    message: message ?? "Enter the same 6 digits again.",
                                    isError: isError,
                                    isDisabled: app.vaultLock.isWorking) { entered in
                            confirm(entered)
                        }
                    case .biometrics: biometricsOffer
                    }
                }
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .padding(Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(Theme.Palette.brand)
                .frame(width: 26, height: 5)
            Capsule()
                .fill(step == .confirm ? Theme.Palette.brand : Theme.Palette.track)
                .frame(width: 26, height: 5)
        }
        .animation(.snappy, value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step == .confirm ? "Step 2 of 2" : "Step 1 of 2")
    }

    private func go(to next: Step) {
        withAnimation(.snappy(duration: 0.35)) { step = next }
    }

    private var intro: some View {
        VStack(spacing: Theme.Spacing.l) {
            VaultHero()
                .padding(.top, Theme.Spacing.s)
            VStack(spacing: Theme.Spacing.s) {
                Text("Your private vault")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("A locked place for photos and videos you'd rather keep out of your main library.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                promise("lock.shield.fill", "Encrypted and stored only inside CleanSpace on this iPhone")
                promise("faceid", "Opens with your 6-digit PIN or Face ID")
                promise("icloud.slash", "Never uploaded, never included in backups")
                promise("exclamationmark.triangle.fill", "If you delete CleanSpace or forget your PIN, the vault can't be recovered")
            }
            .glassCard()
            Button {
                go(to: .create)
            } label: {
                PrimaryButtonLabel(title: "Create PIN", systemImage: "lock.fill")
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    private var biometricsOffer: some View {
        VStack(spacing: Theme.Spacing.l) {
            VaultHero(symbol: app.vaultLock.biometrySymbol)
                .padding(.top, Theme.Spacing.l)
            Text("Unlock with \(app.vaultLock.biometryName)?")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Your PIN is set. You can also open the vault with \(app.vaultLock.biometryName); your PIN always works too.")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    _ = await app.vaultLock.enableBiometrics()
                    app.vaultLock.finishSetup()
                }
            } label: {
                PrimaryButtonLabel(title: "Use \(app.vaultLock.biometryName)")
            }
            .buttonStyle(PressableButtonStyle())
            Button("Not now") {
                app.vaultLock.biometricsEnabled = false
                app.vaultLock.finishSetup()
            }
            .font(.subheadline.weight(.medium))
        }
    }

    private func promise(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(Theme.Palette.ink)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.Palette.brand).frame(width: 28)
        }
        .font(.subheadline)
    }

    private func confirm(_ entered: String) {
        guard entered == firstEntry else {
            message = "The PINs didn't match. Let's start again."
            isError = true
            firstEntry = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                isError = false
                withAnimation(.snappy(duration: 0.35)) { step = .create }
            }
            return
        }
        Task {
            if await app.vaultLock.createPasscode(entered) {
                if app.vaultLock.biometry != .none {
                    go(to: .biometrics)
                } else {
                    app.vaultLock.finishSetup()
                }
            } else {
                message = "Your PIN couldn't be saved. Please try again."
                isError = true
                go(to: .create)
            }
        }
    }
}

// MARK: - Lock screen

struct VaultLockView: View {
    @Environment(AppState.self) private var app
    @State private var message: String?
    @State private var isError = false
    @State private var didPromptBiometrics = false
    @State private var now = Date()

    var body: some View {
        let lock = app.vaultLock
        let remaining = lock.lockoutRemaining(now: now)
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                VaultHero(size: 76)
                    .padding(.top, Theme.Spacing.m)
                PasscodePad(title: "Enter Your PIN",
                            message: remaining > 0
                                ? "Too many attempts. Try again in \(Int(remaining.rounded(.up))) s."
                                : message,
                            isError: isError,
                            biometricSymbol: lock.canUseBiometrics ? lock.biometrySymbol : nil,
                            onBiometric: lock.canUseBiometrics ? { tryBiometrics() } : nil,
                            isDisabled: remaining > 0 || lock.isWorking) { entered in
                    Task {
                        isError = false
                        if !(await lock.unlock(with: entered)) {
                            message = "Wrong PIN. Try again."
                            isError = true
                        }
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .task {
            // Ticks once a second so the lockout countdown stays current.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = Date()
            }
        }
        .onAppear {
            guard !didPromptBiometrics, lock.canUseBiometrics else { return }
            didPromptBiometrics = true
            tryBiometrics()
        }
    }

    private func tryBiometrics() {
        Task { _ = await app.vaultLock.unlockWithBiometrics() }
    }
}

// MARK: - Contents

struct VaultContentView: View {
    @Environment(AppState.self) private var app
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var viewing: VaultItem?
    @State private var importedIDs: [String] = []
    @State private var askToRemoveOriginals = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        let vault = app.vault
        Group {
            if vault.isLoading && vault.items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vault.items.isEmpty {
                EmptyStateView(symbol: "lock.square.stack",
                               title: "Your vault is empty",
                               message: "Add photos or videos you'd rather keep out of your main library. They're encrypted on this iPhone.")
                    .overlay(alignment: .bottom) { addButton.padding(Theme.Spacing.xl) }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        HStack {
                            Label("\(Format.count(vault.items.count, "item")), \(Format.bytes(vault.totalBytes))",
                                  systemImage: "lock.shield.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.Palette.vault)
                            Spacer()
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.top, Theme.Spacing.m)
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(vault.items) { item in
                                Button { viewing = item } label: { VaultTile(item: item) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(item.kind == .video ? "Video" : "Photo")
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if let progress = vault.importProgress {
                VStack(spacing: Theme.Spacing.m) {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .tint(Theme.Palette.vault)
                    Text("Encrypting \(progress.done + 1 > progress.total ? progress.total : progress.done + 1) of \(progress.total)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.ink)
                }
                .padding(Theme.Spacing.xl)
                .frame(maxWidth: 280)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !vault.items.isEmpty { addButtonCompact }
                Button {
                    app.vaultLock.lock()
                    app.vault.clear()
                } label: {
                    Image(systemName: "lock")
                }
                .accessibilityLabel("Lock vault")
            }
        }
        .task { await vault.load() }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let ids = await vault.importItems(items)
                pickerItems = []
                if !ids.isEmpty, app.permissions.photos.canRead {
                    importedIDs = ids
                    askToRemoveOriginals = true
                }
            }
        }
        .confirmationDialog("Remove the originals from Photos?", isPresented: $askToRemoveOriginals,
                            titleVisibility: .visible) {
            Button("Delete \(Format.count(importedIDs.count, "original"))", role: .destructive) {
                let ids = importedIDs
                Task { await app.deleteOriginalsAfterVaultImport(ids) }
            }
            Button("Keep originals", role: .cancel) {}
        } message: {
            Text("The copies in your vault are safe. iOS will ask you to confirm, and deleted originals stay in Recently Deleted for 30 days.")
        }
        .alert("Vault", isPresented: Binding(get: { vault.errorMessage != nil },
                                             set: { if !$0 { vault.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vault.errorMessage ?? "")
        }
        .glassCover(item: $viewing) { item in
            VaultItemViewer(item: item).environment(app)
        }
    }

    private var addButton: some View {
        PhotosPicker(selection: $pickerItems, matching: .any(of: [.images, .videos]),
                     preferredItemEncoding: .current, photoLibrary: .shared()) {
            Label("Add from Photos", systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(Theme.Palette.vault, in: Capsule())
        }
    }

    private var addButtonCompact: some View {
        PhotosPicker(selection: $pickerItems, matching: .any(of: [.images, .videos]),
                     preferredItemEncoding: .current, photoLibrary: .shared()) {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add from Photos")
    }
}

struct VaultTile: View {
    let item: VaultItem
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Theme.Palette.placeholder)
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if item.kind == .video {
                    Label(Format.duration(item.duration), systemImage: "play.fill")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(5)
                }
            }
            .task(id: item.id) {
                if let data = await VaultStore.shared.thumbnail(for: item.id) {
                    image = UIImage(data: data)
                }
            }
    }
}

struct VaultItemViewer: View {
    let item: VaultItem

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var tempURL: URL?
    @State private var confirmDelete = false
    @State private var savedMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.l) {
                ZStack {
                    Color.black
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else if let player {
                        VideoPlayer(player: player)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                .frame(maxHeight: .infinity)

                VStack(spacing: Theme.Spacing.s) {
                    DetailRow(label: "Taken", value: item.originalDate.map { $0.formatted(date: .long, time: .shortened) } ?? "Unknown")
                    DetailRow(label: "Added to vault", value: item.addedAt.formatted(date: .abbreviated, time: .shortened))
                    DetailRow(label: "Size", value: Format.bytes(item.byteCount))
                }
                .card()

                if let savedMessage {
                    Label(savedMessage, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.Palette.brand)
                }

                HStack(spacing: Theme.Spacing.m) {
                    Button {
                        Task {
                            isSaving = true
                            if await app.vault.exportToPhotos(item) { savedMessage = "Saved a copy to Photos" }
                            isSaving = false
                        }
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding(Theme.Spacing.l)
            .navigationTitle(item.kind == .video ? "Video" : "Photo")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete from vault?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete permanently", role: .destructive) {
                    Task {
                        await app.vault.delete([item.id])
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Vault items don't go to Recently Deleted. This can't be undone.")
            }
        }
        .task { await loadContent() }
        .onDisappear {
            player?.pause()
            if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        }
    }

    private func loadContent() async {
        do {
            switch item.kind {
            case .photo:
                let data = try await VaultStore.shared.photoData(for: item)
                image = UIImage(data: data)
            case .video:
                let url = try await VaultStore.shared.decryptedFile(for: item)
                tempURL = url
                player = AVPlayer(url: url)
            }
        } catch {
            app.vault.errorMessage = (error as? LocalizedError)?.errorDescription ?? "This item couldn't be opened."
            dismiss()
        }
    }
}
