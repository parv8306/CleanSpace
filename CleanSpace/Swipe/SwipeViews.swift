import SwiftUI

/// The piles swipe mode can work through.
enum SwipeSource: String, CaseIterable, Identifiable, Hashable {
    case duplicates, similar, screenshots, chat, blurry, largeVideos

    var id: String { rawValue }

    var category: CleanupCategory {
        switch self {
        case .duplicates: .duplicatePhotos
        case .similar: .similarPhotos
        case .chat: .chatPhotos
        case .screenshots: .screenshots
        case .blurry: .blurryPhotos
        case .largeVideos: .largeVideos
        }
    }

    var title: String {
        switch self {
        case .duplicates: "Duplicate photos"
        case .similar: "Look-alike photos"
        case .chat: "Chat photos"
        case .screenshots: "Screenshots"
        case .blurry: "Blurry photos"
        case .largeVideos: "Large videos"
        }
    }

    var hint: String {
        switch self {
        case .duplicates: "Each extra copy is shown next to the copy that's kept."
        case .similar: "Each photo is shown next to the best shot of its group."
        case .chat: "Photos likely saved from chat apps, newest first."
        case .screenshots: "Newest first."
        case .blurry: "Photos that look out of focus."
        case .largeVideos: "Biggest first. Tap a card to play it."
        }
    }
}

struct SwipeCard: Identifiable, Equatable {
    let item: MediaItem
    /// For look-alikes: the photo being kept, shown for comparison.
    let compareID: String?
    var id: String { item.id }
}

extension AppState {
    func swipeCards(for source: SwipeSource) -> [SwipeCard] {
        switch source {
        case .duplicates:
            similar.duplicateGroups.flatMap { group in group.reclaimableItems.map { SwipeCard(item: $0, compareID: group.bestID) } }
        case .similar:
            similar.groups.flatMap { group in group.reclaimableItems.map { SwipeCard(item: $0, compareID: group.bestID) } }
        case .chat:
            similar.chatPhotos.map { SwipeCard(item: $0, compareID: nil) }
        case .screenshots:
            screenshots.items.map { SwipeCard(item: $0, compareID: nil) }
        case .blurry:
            similar.blurry.map { SwipeCard(item: $0, compareID: nil) }
        case .largeVideos:
            videos.largeVideos.map { SwipeCard(item: $0, compareID: nil) }
        }
    }
}

/// Pick a pile to swipe through.
struct SwipeHubView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Swipe left to mark a photo or video for deletion, right to keep it. Nothing is deleted until you confirm on the review screen.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.secondaryText)
                VStack(spacing: 0) {
                    ForEach(Array(SwipeSource.allCases.enumerated()), id: \.element) { index, source in
                        row(source)
                        if index < SwipeSource.allCases.count - 1 { Divider().padding(.leading, 68) }
                    }
                }
                .card(padding: 0)
            }
            .padding(Theme.Spacing.l)
        }
        .background(AppBackdrop())
        .navigationTitle("Swipe Mode")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            app.ensureScanned(.similarPhotos)
            app.ensureScanned(.screenshots)
            app.ensureScanned(.largeVideos)
        }
    }

    @ViewBuilder
    private func row(_ source: SwipeSource) -> some View {
        let status = app.status(for: source.category)
        let count = app.swipeCards(for: source).count
        let enabled = count > 0
        NavigationLink(value: Route.swipe(source)) {
            HStack(spacing: Theme.Spacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(source.category.tint.opacity(0.15))
                    Image(systemName: source.category.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(source.category.tint)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title).font(.body.weight(.semibold)).foregroundStyle(Theme.Palette.ink)
                    Text(subtitle(status: status, count: count))
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.secondaryText.opacity(0.6))
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    private func subtitle(status: CategoryStatus, count: Int) -> String {
        switch status {
        case .needsAccess: return "Allow photo access first"
        case .accessDenied: return "Photo access is off"
        case .scanning: return "Scanning"
        case .notScanned: return "Not scanned yet"
        case .failed: return "Couldn't scan"
        default: return count > 0 ? Format.count(count, "card") : "Nothing to review"
        }
    }
}

/// One card at a time. Swiping only changes the selection; deletion still goes through Review.
struct SwipeDeckView: View {
    let source: SwipeSource

    private struct Decision {
        let id: String
        let wasSelected: Bool
        let removed: Bool
        let bytes: Int64
    }

    @Environment(AppState.self) private var app
    @State private var cards: [SwipeCard] = []
    @State private var index = 0
    @State private var offset: CGSize = .zero
    @State private var history: [Decision] = []
    @State private var didLoad = false
    @State private var isAnimating = false
    @State private var previewItem: MediaItem?
    @State private var showDemo = false
    @AppStorage("cleanspace.swipeDemoSeen") private var demoSeen = false

    private let threshold: CGFloat = 110

    private var markedCount: Int { history.filter(\.removed).count }
    private var markedBytes: Int64 { history.filter(\.removed).reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            if !didLoad {
                ProgressView().frame(maxHeight: .infinity)
            } else if cards.isEmpty {
                EmptyStateView(symbol: source.category.symbol, message: "There's nothing in this pile to review.")
            } else if index >= cards.count {
                finished
            } else {
                header
                deck
                controls
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackdrop())
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if didLoad && index < cards.count && !history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") { index = cards.count }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: history.count)
        .glassCover(item: $previewItem) { item in
            if source == .largeVideos {
                VideoPreviewView(item: item).environment(app)
            } else {
                PhotoPreviewView(item: item, category: source.category).environment(app)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            cards = app.swipeCards(for: source)
            didLoad = true
            app.discardSuggestions(for: source.category)
            if !demoSeen && !cards.isEmpty { showDemo = true }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showDemo = true } label: { Image(systemName: "questionmark.circle") }
                    .accessibilityLabel("How swiping works")
            }
        }
        .glassCover(isPresented: $showDemo, onDismiss: { demoSeen = true }) {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("How swipe mode works")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                SwipeDemoView()
                Button {
                    showDemo = false
                } label: {
                    PrimaryButtonLabel(title: "Got it")
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(Theme.Spacing.xl)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack {
                Text("\((index + 1).formatted()) of \(cards.count.formatted())")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                if markedCount > 0 {
                    Text("\(markedCount.formatted()) marked, \(Format.bytes(markedBytes))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.coral)
                        .contentTransition(.numericText())
                }
            }
            ProgressView(value: Double(index), total: Double(max(cards.count, 1)))
                .tint(Theme.Palette.swipe)
        }
    }

    private var deck: some View {
        let visible = Array(cards[index..<min(index + 3, cards.count)])
        return ZStack {
            ForEach(Array(visible.enumerated()).reversed(), id: \.element.id) { depth, card in
                cardView(card, isTop: depth == 0)
                    .scaleEffect(1 - CGFloat(depth) * 0.05)
                    .offset(y: CGFloat(depth) * 16)
                    .opacity(depth == 2 ? 0.6 : 1)
                    .allowsHitTesting(depth == 0)
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.spring(duration: 0.35), value: index)
    }

    @ViewBuilder
    private func cardView(_ card: SwipeCard, isTop: Bool) -> some View {
        let dragX = isTop ? offset.width : 0
        AssetThumbnail(id: card.item.id, side: 700)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(alignment: .topLeading) {
                stamp("Keep", color: Theme.Palette.brand, angle: -12)
                    .opacity(Double(max(0, dragX) / threshold))
                    .padding(Theme.Spacing.l)
            }
            .overlay(alignment: .topTrailing) {
                stamp("Delete", color: Theme.Palette.coral, angle: 12)
                    .opacity(Double(max(0, -dragX) / threshold))
                    .padding(Theme.Spacing.l)
            }
            .overlay(alignment: .bottom) { cardFooter(card) }
            .overlay(alignment: .center) {
                if source == .largeVideos {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 6)
                }
            }
            .shadow(color: Theme.Palette.shadow, radius: 16, y: 8)
            .offset(x: dragX, y: isTop ? offset.height * 0.15 : 0)
            .rotationEffect(.degrees(Double(dragX / 20)))
            .onTapGesture { if isTop { previewItem = card.item } }
            .gesture(drag(card))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(source.category.noun.capitalized), \(Format.date(card.item.creationDate)), \(Format.bytes(card.item.fileSize))")
            .accessibilityHint("Swipe left to delete, right to keep, or use the actions menu")
            .accessibilityAction(named: "Delete") { decide(card, remove: true) }
            .accessibilityAction(named: "Keep") { decide(card, remove: false) }
            .accessibilityAction(named: "Preview") { previewItem = card.item }
    }

    private func cardFooter(_ card: SwipeCard) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.item.fileSize > 0 ? Format.bytes(card.item.fileSize) : "Size unknown")
                    .font(.headline)
                Text(source == .largeVideos
                     ? "\(Format.duration(card.item.duration)), \(Format.date(card.item.creationDate))"
                     : Format.date(card.item.creationDate))
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .shadow(radius: 3)
            Spacer()
            if let compareID = card.compareID {
                VStack(spacing: 4) {
                    AssetThumbnail(id: compareID, side: 70)
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white, lineWidth: 2))
                    BestBadge()
                }
            }
        }
        .padding(Theme.Spacing.l)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        )
    }

    private var controls: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.xl) {
                roundButton("xmark", color: Theme.Palette.coral, label: "Delete") {
                    if index < cards.count { decide(cards[index], remove: true) }
                }
                roundButton("arrow.uturn.backward", color: Theme.Palette.secondaryText, label: "Undo", small: true) { undo() }
                    .disabled(history.isEmpty)
                    .opacity(history.isEmpty ? 0.4 : 1)
                roundButton("heart.fill", color: Theme.Palette.brand, label: "Keep") {
                    if index < cards.count { decide(cards[index], remove: false) }
                }
            }
            Text(source.hint)
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
    }

    private var finished: some View {
        VStack(spacing: Theme.Spacing.l) {
            EmptyStateView(symbol: "checkmark.seal.fill",
                           title: "Pile reviewed",
                           message: markedCount > 0
                               ? "\(Format.count(markedCount, source.category.noun)) marked, about \(Format.bytes(markedBytes)). Check them once more on the review screen before anything is deleted."
                               : "You kept everything in this pile.")
            if app.selectedCount(in: source.category) > 0 {
                Button {
                    app.openReview([source.category])
                } label: {
                    Text("Review and delete")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(Theme.Palette.coral, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
            if !history.isEmpty {
                Button("Undo last choice") { undo() }
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    // MARK: Interaction

    private func drag(_ card: SwipeCard) -> some Gesture {
        DragGesture()
            .onChanged { offset = $0.translation }
            .onEnded { value in
                if value.translation.width < -threshold {
                    decide(card, remove: true)
                } else if value.translation.width > threshold {
                    decide(card, remove: false)
                } else {
                    withAnimation(.spring(duration: 0.3)) { offset = .zero }
                }
            }
    }

    private func decide(_ card: SwipeCard, remove: Bool) {
        guard !isAnimating else { return }
        isAnimating = true
        let category = source.category
        history.append(Decision(id: card.id, wasSelected: app.selection.contains(card.id, in: category),
                                removed: remove, bytes: card.item.fileSize))
        if remove {
            app.selection.select([card.id], in: category)
        } else {
            app.selection.deselect([card.id], in: category)
        }
        withAnimation(.easeIn(duration: 0.2)) {
            offset = CGSize(width: remove ? -700 : 700, height: offset.height)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            offset = .zero
            index += 1
            isAnimating = false
        }
    }

    private func undo() {
        guard !isAnimating, let last = history.popLast() else { return }
        let category = source.category
        if last.wasSelected {
            app.selection.select([last.id], in: category)
        } else {
            app.selection.deselect([last.id], in: category)
        }
        offset = .zero
        index = max(index - 1, 0)
    }

    private func stamp(_ text: String, color: Color, angle: Double) -> some View {
        Text(text)
            .font(.system(.title2, design: .rounded, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(angle))
    }

    private func roundButton(_ symbol: String, color: Color, label: String, small: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: small ? 18 : 24, weight: .bold))
                .foregroundStyle(color)
                .frame(width: small ? 48 : 64, height: small ? 48 : 64)
                .background(Theme.Palette.surface, in: Circle())
                .shadow(color: Theme.Palette.shadow, radius: 8, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }
}
