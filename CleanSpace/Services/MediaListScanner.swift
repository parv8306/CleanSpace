import Foundation
import Photos

enum MediaListKind: Sendable {
    case screenshots
    case videos
}

/// Streams screenshots or videos with their file sizes. Sizes are read in batches on a background
/// task, so even libraries with thousands of videos never block the UI.
enum MediaListScanner {
    enum Event: Sendable {
        case items([MediaItem], done: Int, total: Int)
        case progress(done: Int, total: Int)
        case finished([MediaItem])
    }

    static func events(for kind: MediaListKind) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let worker = Task.detached(priority: .userInitiated) {
                let fetch = kind == .screenshots
                    ? PhotoLibraryService.fetchScreenshots()
                    : PhotoLibraryService.fetchVideos()
                let total = fetch.count
                var items: [MediaItem] = []
                items.reserveCapacity(total)
                for i in 0..<total {
                    items.append(PhotoLibraryService.makeItem(from: fetch.object(at: i)))
                }

                // Screenshots are shown straight away (newest first) while sizes fill in;
                // videos are only meaningful once sorted by size, so we just report progress.
                if kind == .screenshots {
                    continuation.yield(.items(items, done: 0, total: total))
                } else {
                    continuation.yield(.progress(done: 0, total: total))
                }

                var done = 0
                var lastPublished = 0
                while done < total {
                    if Task.isCancelled { continuation.finish(); return }
                    let end = min(done + 200, total)
                    let chunk = (done..<end).map { fetch.object(at: $0) }
                    var sizes = [Int64](repeating: 0, count: chunk.count)
                    sizes.withUnsafeMutableBufferPointer { buffer in
                        let output = buffer
                        DispatchQueue.concurrentPerform(iterations: chunk.count) { k in
                            autoreleasepool { output[k] = AssetSizeCache.shared.size(for: chunk[k]) }
                        }
                    }
                    for (k, i) in (done..<end).enumerated() { items[i].fileSize = sizes[k] }
                    done = end
                    if kind == .screenshots && done - lastPublished >= 1000 {
                        lastPublished = done
                        continuation.yield(.items(items, done: done, total: total))
                    } else {
                        continuation.yield(.progress(done: done, total: total))
                    }
                }
                if kind == .videos {
                    continuation.yield(.progress(done: total, total: total))
                    items.sort { $0.fileSize > $1.fileSize }
                }
                AssetSizeCache.shared.save()
                continuation.yield(.finished(items))
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
}
