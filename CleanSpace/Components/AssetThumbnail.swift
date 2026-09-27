import Photos
import SwiftUI

/// Local-only PhotoKit thumbnail. Loads when it appears, cancels when it scrolls away.
struct AssetThumbnail: View {
    let id: String
    var side: CGFloat = 120
    var contentMode: ContentMode = .fill

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var loadedID: String?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        Rectangle()
            .fill(Theme.Palette.placeholder)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: max(min(side / 5, 28), 12)))
                        .foregroundStyle(Theme.Palette.secondaryText.opacity(0.5))
                }
            }
            .clipped()
            .onAppear(perform: load)
            .onDisappear(perform: cancel)
            .onChange(of: id) { _, _ in
                cancel()
                image = nil
                load()
            }
            .accessibilityHidden(true)
    }

    private func load() {
        guard loadedID != id || image == nil else { return }
        let target = id
        let pixels = CGSize(width: side * displayScale, height: side * displayScale)
        requestID = ThumbnailLoader.shared.requestImage(
            id: target,
            pixelSize: pixels,
            contentMode: contentMode == .fill ? .aspectFill : .aspectFit
        ) { result in
            guard target == id else { return }
            if let result { image = result }
            loadedID = target
        }
    }

    private func cancel() {
        if let requestID { ThumbnailLoader.shared.cancel(requestID) }
        requestID = nil
    }
}

/// A square tile that crops its thumbnail, for grids.
struct SquareThumbnail: View {
    let id: String
    var side: CGFloat = 120

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { AssetThumbnail(id: id, side: side) }
            .clipped()
    }
}
