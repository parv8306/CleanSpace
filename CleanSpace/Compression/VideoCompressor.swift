import AVFoundation
import Foundation
import Observation
import Photos

/// How much smaller the person wants the video. Each option is a real size target: the encoder
/// is given the bitrate that produces that size, and the resolution is chosen to suit it.
enum CompressionQuality: String, CaseIterable, Identifiable, Sendable {
    case high, balanced, small

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: "High quality"
        case .balanced: "Balanced"
        case .small: "Smallest"
        }
    }

    var detail: String {
        switch self {
        case .high: "About 60% of the original, up to 1080p"
        case .balanced: "About a third of the original, up to 720p"
        case .small: "About a fifth of the original, up to 540p"
        }
    }

    /// Target size as a share of the original file.
    var targetRatio: Double {
        switch self {
        case .high: 0.6
        case .balanced: 0.35
        case .small: 0.2
        }
    }

    /// Longest edge of the output, in pixels. Videos are never upscaled.
    var maxLongEdge: CGFloat {
        switch self {
        case .high: 1920
        case .balanced: 1280
        case .small: 960
        }
    }

    var audioBitRate: Int {
        self == .small ? 96_000 : 128_000
    }
}

enum CompressionEstimator {
    /// Below this the picture falls apart, so targets are never set lower.
    static let minimumVideoBitRate: Double = 450_000
    /// MP4 container and index overhead, as a share of the stream.
    static let containerOverhead = 0.03
    /// A result has to save at least this share of the original to be kept.
    static let minimumSavingRatio = 0.05

    /// The size CleanSpace aims for, never above the original.
    static func estimatedBytes(duration: TimeInterval, originalBytes: Int64, quality: CompressionQuality) -> Int64 {
        guard duration.isFinite, duration > 0, originalBytes > 0 else { return originalBytes }
        let desired = Double(originalBytes) * quality.targetRatio
        let floor = (minimumVideoBitRate + Double(quality.audioBitRate)) * duration / 8 * (1 + containerOverhead)
        return min(Int64(max(desired, floor)), originalBytes)
    }

    static func estimatedSavings(duration: TimeInterval, originalBytes: Int64, quality: CompressionQuality) -> Int64 {
        max(originalBytes - estimatedBytes(duration: duration, originalBytes: originalBytes, quality: quality), 0)
    }

    /// Video bitrate (bits per second) that lands the file on `targetBytes`.
    static func videoBitRate(targetBytes: Int64, duration: TimeInterval, quality: CompressionQuality) -> Int {
        guard duration > 0 else { return Int(minimumVideoBitRate) }
        let total = Double(targetBytes) * 8 / duration / (1 + containerOverhead)
        return Int(max(total - Double(quality.audioBitRate), minimumVideoBitRate))
    }

    /// Lower bitrates look better at lower resolutions, so the resolution follows the bitrate.
    static func maxLongEdge(for quality: CompressionQuality, videoBitRate: Int) -> CGFloat {
        let fitting: CGFloat
        switch videoBitRate {
        case ..<1_000_000: fitting = 960
        case ..<2_200_000: fitting = 1280
        default: fitting = 1920
        }
        return min(quality.maxLongEdge, fitting)
    }

    /// Output dimensions: aspect preserved, never upscaled, even numbers (required by encoders).
    static func outputSize(for size: CGSize, maxLongEdge: CGFloat) -> CGSize {
        let width = abs(size.width), height = abs(size.height)
        guard width > 0, height > 0 else { return CGSize(width: 1280, height: 720) }
        let scale = min(1, maxLongEdge / max(width, height))
        func even(_ value: CGFloat) -> CGFloat { max(2, (value * scale / 2).rounded() * 2) }
        return CGSize(width: even(width), height: even(height))
    }
}

enum TranscodeError: LocalizedError {
    case noVideoTrack
    case cannotRead
    case cannotWrite

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "This file doesn't contain a video track."
        case .cannotRead: "The video couldn't be read."
        case .cannotWrite: "The compressed video couldn't be written."
        }
    }
}

/// Re-encodes a video with AVAssetReader and AVAssetWriter at an explicit bitrate.
///
/// Frames go through a video composition, which applies the video's orientation and converts HDR
/// (HLG and Dolby Vision) to standard dynamic range, so the result looks right everywhere. HEVC is
/// used when the device can encode it, H.264 otherwise. Audio is re-encoded as stereo AAC.
final class VideoTranscoder: @unchecked Sendable {
    struct Plan: Sendable {
        let videoBitRate: Int
        let audioBitRate: Int
        let maxLongEdge: CGFloat
    }

    private let asset: AVAsset
    private let outputURL: URL
    private let plan: Plan
    private let lock = NSLock()
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?
    private var cancelFlag = false

    init(asset: AVAsset, outputURL: URL, plan: Plan) {
        self.asset = asset
        self.outputURL = outputURL
        self.plan = plan
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelFlag
    }

    func cancel() {
        lock.lock()
        cancelFlag = true
        let reader = self.reader
        let writer = self.writer
        lock.unlock()
        reader?.cancelReading()
        writer?.cancelWriting()
    }

    func run(progress: @escaping @Sendable (Double) -> Void) async throws {
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let firstVideo = videoTracks.first else { throw TranscodeError.noVideoTrack }
        let frameRate = try await firstVideo.load(.nominalFrameRate)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        try? FileManager.default.removeItem(at: outputURL)
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        // Video
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        videoOutput.videoComposition = composition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw TranscodeError.cannotRead }
        reader.add(videoOutput)

        let size = CompressionEstimator.outputSize(for: composition.renderSize, maxLongEdge: plan.maxLongEdge)
        let fps = frameRate > 0 ? Int(frameRate.rounded()) : 30
        let colorProperties: [String: Any] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
        ]
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoColorPropertiesKey: colorProperties,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: plan.videoBitRate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2
            ] as [String: Any]
        ]
        if !writer.canApply(outputSettings: videoSettings, forMediaType: .video) {
            videoSettings[AVVideoCodecKey] = AVVideoCodecType.h264
            videoSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: plan.videoBitRate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ] as [String: Any]
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw TranscodeError.cannotWrite }
        writer.add(videoInput)

        var pumps = [TrackPump(reader: reader, output: videoOutput, input: videoInput, reportsProgress: true)]

        // Audio (mixed down to stereo so any source layout encodes cleanly)
        if !audioTracks.isEmpty {
            let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: plan.audioBitRate
            ])
            audioInput.expectsMediaDataInRealTime = false
            if reader.canAdd(audioOutput) && writer.canAdd(audioInput) {
                reader.add(audioOutput)
                writer.add(audioInput)
                pumps.append(TrackPump(reader: reader, output: audioOutput, input: audioInput, reportsProgress: false))
            }
        }

        let cancelledEarly = lock.withLock { () -> Bool in
            self.reader = reader
            self.writer = writer
            return cancelFlag
        }
        if cancelledEarly { throw CancellationError() }

        guard reader.startReading() else { throw reader.error ?? TranscodeError.cannotRead }
        guard writer.startWriting() else { throw writer.error ?? TranscodeError.cannotWrite }
        writer.startSession(atSourceTime: .zero)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for pump in pumps {
                group.enter()
                pump.start(duration: duration,
                           isCancelled: { [weak self] in self?.isCancelled ?? true },
                           progress: progress,
                           done: { group.leave() })
            }
            group.notify(queue: .global(qos: .userInitiated)) { continuation.resume() }
        }

        if isCancelled {
            writer.cancelWriting()
            throw CancellationError()
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? TranscodeError.cannotRead
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? TranscodeError.cannotWrite }
        progress(1)
    }

    /// Opens the finished file and checks it really is a playable video of the right length.
    static func verifyPlayable(_ url: URL, expectedDuration: TimeInterval) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            let playable = try await asset.load(.isPlayable)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let duration = try await asset.load(.duration).seconds
            return playable && !tracks.isEmpty && duration >= expectedDuration * 0.9
        } catch {
            return false
        }
    }
}

/// Moves samples from one reader output to one writer input on its own queue.
private final class TrackPump: @unchecked Sendable {
    let reader: AVAssetReader
    let output: AVAssetReaderOutput
    let input: AVAssetWriterInput
    let reportsProgress: Bool
    private let queue: DispatchQueue
    private var finished = false

    init(reader: AVAssetReader, output: AVAssetReaderOutput, input: AVAssetWriterInput, reportsProgress: Bool) {
        self.reader = reader
        self.output = output
        self.input = input
        self.reportsProgress = reportsProgress
        queue = DispatchQueue(label: "cleanspace.transcode.\(reportsProgress ? "video" : "audio")")
    }

    func start(duration: Double, isCancelled: @escaping @Sendable () -> Bool,
               progress: @escaping @Sendable (Double) -> Void, done: @escaping @Sendable () -> Void) {
        input.requestMediaDataWhenReady(on: queue) { [self] in
            guard !finished else { return }
            while input.isReadyForMoreMediaData {
                if isCancelled() || reader.status != .reading {
                    finish(done)
                    return
                }
                guard let sample = output.copyNextSampleBuffer() else {
                    finish(done)
                    return
                }
                if reportsProgress, duration > 0 {
                    progress(min(max(CMSampleBufferGetPresentationTimeStamp(sample).seconds / duration, 0), 0.99))
                }
                if !input.append(sample) {
                    finish(done)
                    return
                }
            }
        }
    }

    private func finish(_ done: () -> Void) {
        guard !finished else { return }
        finished = true
        input.markAsFinished()
        done()
    }
}

/// Compresses one video from the library to the chosen size, verifies the result plays, saves it
/// as a new video (keeping the original's date, location and favorite flag), then lets the person
/// decide whether to delete the original.
@Observable
@MainActor
final class VideoCompressionJob {
    enum Stage: Equatable {
        case ready
        case preparing
        case exporting(Double)
        case verifying
        case saving
        case compressed(originalBytes: Int64, newBytes: Int64, newID: String?)
        case notWorthIt(originalBytes: Int64, newBytes: Int64)
        case deletingOriginal
        case failed(String)
    }

    let item: MediaItem
    var quality: CompressionQuality = .balanced
    private(set) var stage: Stage = .ready
    /// The size this run aimed for, shown next to the result.
    private(set) var targetBytes: Int64 = 0

    @ObservationIgnored private var transcoder: VideoTranscoder?
    @ObservationIgnored private var cancelled = false

    init(item: MediaItem) {
        self.item = item
    }

    var isBusy: Bool {
        switch stage {
        case .preparing, .exporting, .verifying, .saving, .deletingOriginal: true
        default: false
        }
    }

    var estimatedBytes: Int64 {
        CompressionEstimator.estimatedBytes(duration: item.duration, originalBytes: item.fileSize, quality: quality)
    }

    /// False when even the smallest sensible size wouldn't save anything worthwhile.
    var canSaveSpace: Bool {
        guard item.fileSize > 0 else { return true }
        return Double(item.fileSize - estimatedBytes) >= Double(item.fileSize) * CompressionEstimator.minimumSavingRatio
    }

    func start() async {
        guard !isBusy else { return }
        cancelled = false
        stage = .preparing
        guard let asset = ThumbnailLoader.shared.asset(for: item.id) else {
            stage = .failed("This video is no longer in your library.")
            return
        }
        guard let avAsset = await Self.loadAVAsset(asset) else {
            stage = .failed("This video is stored in iCloud. Download it in the Photos app first, then try again. CleanSpace never downloads your media.")
            return
        }
        let duration = await Self.duration(of: avAsset, fallback: item.duration)
        let original = item.fileSize
        let target = CompressionEstimator.estimatedBytes(duration: duration, originalBytes: original, quality: quality)
        targetBytes = target
        let bitRate = CompressionEstimator.videoBitRate(targetBytes: target, duration: duration, quality: quality)
        let plan = VideoTranscoder.Plan(videoBitRate: bitRate,
                                        audioBitRate: quality.audioBitRate,
                                        maxLongEdge: CompressionEstimator.maxLongEdge(for: quality, videoBitRate: bitRate))
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleanspace-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        let transcoder = VideoTranscoder(asset: avAsset, outputURL: output, plan: plan)
        self.transcoder = transcoder

        stage = .exporting(0)
        do {
            try await transcoder.run { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case let .exporting(current) = self.stage,
                          fraction - current >= 0.01 || fraction >= 1 else { return }
                    self.stage = .exporting(fraction)
                }
            }
        } catch {
            self.transcoder = nil
            try? FileManager.default.removeItem(at: output)
            if cancelled || error is CancellationError {
                stage = .ready
            } else {
                stage = .failed("Compression didn't finish: \(error.localizedDescription) Your original is untouched.")
            }
            return
        }
        self.transcoder = nil

        stage = .verifying
        guard await VideoTranscoder.verifyPlayable(output, expectedDuration: duration) else {
            try? FileManager.default.removeItem(at: output)
            stage = .failed("The compressed video didn't play back correctly, so it wasn't saved. Your original is untouched.")
            return
        }

        let newBytes = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value ?? 0
        if original > 0, Double(original - newBytes) < Double(original) * CompressionEstimator.minimumSavingRatio {
            try? FileManager.default.removeItem(at: output)
            stage = .notWorthIt(originalBytes: original, newBytes: newBytes)
            return
        }

        stage = .saving
        do {
            let newID = try await Self.saveToLibrary(output, copying: asset)
            stage = .compressed(originalBytes: original, newBytes: newBytes, newID: newID)
        } catch {
            try? FileManager.default.removeItem(at: output)
            stage = .failed("The compressed copy couldn't be saved to Photos. Your original is untouched.")
        }
    }

    func cancel() {
        cancelled = true
        transcoder?.cancel()
    }

    /// Deletes the original through PhotoKit (iOS asks to confirm). Returns what was actually removed.
    func deleteOriginal() async -> MediaDeletionOutcome {
        let previous = stage
        stage = .deletingOriginal
        let outcome = await PhotoLibraryService.deleteAssets(ids: [item.id])
        if outcome.deleted.isEmpty { stage = previous }
        return outcome
    }

    // MARK: Helpers

    private static func duration(of asset: AVAsset, fallback: TimeInterval) async -> TimeInterval {
        do {
            let seconds = try await asset.load(.duration).seconds
            return seconds.isFinite && seconds > 0 ? seconds : fallback
        } catch {
            return fallback
        }
    }

    private static func loadAVAsset(_ asset: PHAsset) async -> AVAsset? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.version = .current
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }

    private final class IDBox: @unchecked Sendable {
        var id: String?
    }

    private static func saveToLibrary(_ url: URL, copying original: PHAsset) async throws -> String? {
        let box = IDBox()
        let creationDate = original.creationDate
        let location = original.location
        let isFavorite = original.isFavorite
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = true
            request.addResource(with: .video, fileURL: url, options: options)
            request.creationDate = creationDate
            request.location = location
            request.isFavorite = isFavorite
            box.id = request.placeholderForCreatedAsset?.localIdentifier
        }
        return box.id
    }
}
