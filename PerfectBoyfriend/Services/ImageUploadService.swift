import FirebaseStorage
import Foundation
import UIKit
@preconcurrency import AVFoundation

enum PostMediaDraftKind: String {
    case image
    case video
}

/// Raw picker output is kept only until the user publishes. Images are re-rendered to remove
/// EXIF metadata; videos receive a separate poster image so no clip needs to auto-play in feeds.
struct PostMediaDraft: Identifiable {
    let id: UUID
    let data: Data
    let kind: PostMediaDraftKind
    let filenameExtension: String
    let contentType: String
    let previewImage: UIImage?

    init(
        id: UUID = UUID(),
        data: Data,
        kind: PostMediaDraftKind,
        filenameExtension: String = "jpg",
        contentType: String = "image/jpeg",
        previewImage: UIImage? = nil
    ) {
        self.id = id
        self.data = data
        self.kind = kind
        self.filenameExtension = filenameExtension
        self.contentType = contentType
        self.previewImage = previewImage
    }
}

enum ImageUploadError: LocalizedError {
    case invalidImage
    case tooManyImages
    case invalidVideo
    case videoTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Das ausgewählte Foto konnte nicht verarbeitet werden."
        case .tooManyImages: return "Ein Beitrag kann höchstens acht Fotos enthalten."
        case .invalidVideo: return "Dieses Video konnte nicht verarbeitet werden."
        case .videoTooLarge: return "Ein Video darf höchstens 45 MB groß sein."
        }
    }
}

/// Re-renders every image before upload. Besides controlling file size, this removes the source
/// file's EXIF metadata (including any embedded location), which is mandatory for social posts.
enum ImageUploadService {
    /// A personal avatar is deliberately separate from the couple's community-facing profile
    /// image. The Storage rule permits it only to the person and their active partner.
    static func uploadPersonalAvatar(_ imageData: Data, uid: String) async throws -> String {
        let normalizedData = try normalizedJPEG(from: imageData, maximumDimension: 900)
        let path = "userImages/\(uid)/avatar.jpg"
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await withTimeout(seconds: 30) {
            try await Storage.storage().reference(withPath: path).putDataAsync(normalizedData, metadata: metadata)
        }
        return path
    }

    static func uploadAvatar(_ imageData: Data, coupleId: String) async throws -> String {
        let normalizedData = try normalizedJPEG(from: imageData, maximumDimension: 900)
        let path = "profileImages/\(coupleId)/avatar.jpg"
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await withTimeout(seconds: 30) {
            try await Storage.storage().reference(withPath: path).putDataAsync(normalizedData, metadata: metadata)
        }
        return path
    }

    /// A voluntary community avatar lives in a separate, public-safe namespace. It is never
    /// copied from the account-only personal avatar.
    static func uploadPublicAvatar(_ imageData: Data, uid: String) async throws -> String {
        let normalizedData = try normalizedJPEG(from: imageData, maximumDimension: 900)
        let path = "socialProfileImages/\(uid)/avatar.jpg"
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await withTimeout(seconds: 30) {
            try await Storage.storage().reference(withPath: path).putDataAsync(normalizedData, metadata: metadata)
        }
        return path
    }

    /// Matching photos have their own opt-in namespace and are never reused as public social
    /// avatars or private account images.
    static func uploadSingleProfileAvatar(_ imageData: Data, uid: String) async throws -> String {
        let normalizedData = try normalizedJPEG(from: imageData, maximumDimension: 1_200)
        let path = "singleProfileImages/\(uid)/avatar.jpg"
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await withTimeout(seconds: 30) {
            try await Storage.storage().reference(withPath: path).putDataAsync(normalizedData, metadata: metadata)
        }
        return path
    }

    /// A group-plan cover belongs to the event rather than to a later public post. Like every
    /// photo upload it is re-rendered first, so original location metadata never leaves the app.
    static func uploadGroupEventCover(_ imageData: Data, eventId: String) async throws -> String {
        let normalizedData = try normalizedJPEG(from: imageData, maximumDimension: 1_800)
        let path = "groupEventImages/\(eventId)/cover.jpg"
        try await upload(data: normalizedData, to: path, contentType: "image/jpeg")
        return path
    }

    /// Photos are written only after a server-created draft supplies an owned post ID. The
    /// re-rendering step deliberately strips EXIF metadata before anything reaches Storage.
    static func uploadPostImages(_ imageData: [Data], coupleId: String, postId: String) async throws -> [String] {
        guard imageData.count <= 8 else {
            throw ImageUploadError.tooManyImages
        }

        var paths: [String] = []
        for (index, data) in imageData.enumerated() {
            let normalizedData = try normalizedJPEG(from: data, maximumDimension: 1_800)
            let path = "postImages/\(coupleId)/\(postId)/\(index).jpg"
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await withTimeout(seconds: 30) {
                try await Storage.storage().reference(withPath: path).putDataAsync(normalizedData, metadata: metadata)
            }
            paths.append(path)
        }
        return paths
    }

    static func uploadPostMedia(_ media: [PostMediaDraft], coupleId: String, postId: String) async throws -> [SocialPostMedia] {
        guard media.count <= 8 else { throw ImageUploadError.tooManyImages }

        var uploaded: [SocialPostMedia] = []
        for (index, item) in media.enumerated() {
            switch item.kind {
            case .image:
                let normalizedData = try normalizedJPEG(from: item.data, maximumDimension: 1_800)
                let path = "postImages/\(coupleId)/\(postId)/\(index).jpg"
                try await upload(data: normalizedData, to: path, contentType: "image/jpeg")
                uploaded.append(SocialPostMedia(path: path, kind: .image, thumbnailPath: nil))
            case .video:
                guard item.data.count <= 45 * 1_024 * 1_024 else { throw ImageUploadError.videoTooLarge }
                guard let preview = item.previewImage else { throw ImageUploadError.invalidVideo }
                // A picker result can still contain location, device and creation metadata.
                // Exporting a fresh MP4 with an explicitly empty metadata array keeps the
                // social post useful while preventing those private source details from upload.
                let normalizedVideo = try await normalizedVideoData(
                    from: item.data,
                    inputExtension: safeVideoExtension(item.filenameExtension)
                )
                guard normalizedVideo.count <= 45 * 1_024 * 1_024 else { throw ImageUploadError.videoTooLarge }
                let videoPath = "postVideos/\(coupleId)/\(postId)/\(index).mp4"
                let posterPath = "postImages/\(coupleId)/\(postId)/\(index)-poster.jpg"
                guard let rawPosterData = preview.jpegData(compressionQuality: 0.82) else { throw ImageUploadError.invalidVideo }
                let posterData = try normalizedJPEG(from: rawPosterData, maximumDimension: 1_800)
                try await upload(data: normalizedVideo, to: videoPath, contentType: "video/mp4")
                try await upload(data: posterData, to: posterPath, contentType: "image/jpeg")
                uploaded.append(SocialPostMedia(path: videoPath, kind: .video, thumbnailPath: posterPath))
            }
        }
        return uploaded
    }

    static func videoPoster(from data: Data) throws -> UIImage {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("moment-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url, options: .atomic)
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
            throw ImageUploadError.invalidVideo
        }
        return UIImage(cgImage: image)
    }

    private static func upload(data: Data, to path: String, contentType: String) async throws {
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        _ = try await withTimeout(seconds: 60) {
            try await Storage.storage().reference(withPath: path).putDataAsync(data, metadata: metadata)
        }
    }

    private static func safeVideoExtension(_ value: String) -> String {
        let normalized = value.lowercased()
        return ["mp4", "mov", "m4v"].contains(normalized) ? normalized : "mov"
    }

    private static func normalizedVideoData(from data: Data, inputExtension: String) async throws -> Data {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mite-video-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let inputURL = directory.appendingPathComponent("source.\(inputExtension)")
        let outputURL = directory.appendingPathComponent("sanitized.mp4")
        try data.write(to: inputURL, options: .atomic)

        let asset = AVURLAsset(url: inputURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ImageUploadError.invalidVideo
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.metadata = []

        let exporterBox = ExportSessionBox(exporter)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                let exporter = exporterBox.value
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(throwing: exporter.error ?? ImageUploadError.invalidVideo)
                }
            }
        }
        guard let sanitized = try? Data(contentsOf: outputURL), !sanitized.isEmpty else {
            throw ImageUploadError.invalidVideo
        }
        return sanitized
    }

    /// AVFoundation's iOS 17 completion API marks its closure Sendable although the framework
    /// session itself predates Sendable annotations. The closure is the session's sole owner
    /// during export, so this narrow wrapper documents and contains that boundary.
    private final class ExportSessionBox: @unchecked Sendable {
        let value: AVAssetExportSession
        init(_ value: AVAssetExportSession) { self.value = value }
    }

    static func normalizedJPEG(from data: Data, maximumDimension: CGFloat) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw ImageUploadError.invalidImage
        }
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, maximumDimension / longestSide)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: size)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.82) else {
            throw ImageUploadError.invalidImage
        }
        return jpeg
    }
}
