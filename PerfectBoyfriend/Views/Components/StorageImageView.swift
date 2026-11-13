import FirebaseStorage
import OSLog
import SwiftUI
import UIKit

/// Loads via the authenticated Firebase Storage SDK rather than a tokenized download URL, so the
/// Storage privacy rules remain effective for follower-only images.
struct StorageImageView: View {
    let path: String
    let contentMode: ContentMode

    @StateObject private var loader: StorageImageLoader

    init(path: String, contentMode: ContentMode = .fill) {
        self.path = path
        self.contentMode = contentMode
        _loader = StateObject(wrappedValue: StorageImageLoader())
    }

    var body: some View {
        // Match LicensedImageView's layout contract: the surrounding card dictates this view's
        // dimensions; decoded image pixels must never enlarge a vertical feed horizontally.
        Color.clear
            .overlay {
                Group {
                    if let image = loader.image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    } else if loader.didFail {
                        Button {
                            Task { await loader.load(path: path, force: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(PBTheme.textSecondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Bild erneut laden")
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .clipped()
            .task(id: path) { await loader.load(path: path) }
    }
}

/// Keeps private Firebase Storage images warm too. Unlike ordinary remote imagery these are
/// fetched through the authenticated SDK, so the same Storage rules apply during preloading.
@MainActor
enum PBStorageImagePrefetcher {
    static func preload(paths: [String]) {
        for path in Set(paths) where PBImageCache.image(for: "storage:\(path)") == nil {
            Task {
                do {
                    let data = try await PBStorageImageDownload.data(for: path)
                    guard let image = UIImage(data: data) else { return }
                    PBImageCache.store(image, for: "storage:\(path)")
                } catch {
                    // A missing or private image simply stays on-demand; the view renders its
                    // regular fallback and no tab transition is interrupted.
                }
            }
        }
    }
}

@MainActor
private final class StorageImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var didFail = false

    private var activePath: String?
    private var isLoading = false

    func load(path: String, force: Bool = false) async {
        guard force || activePath != path || (image == nil && !isLoading) else { return }
        activePath = path
        isLoading = true
        didFail = false
        if force { image = nil }
        let cacheKey = "storage:\(path)"
        if let cached = PBImageCache.image(for: cacheKey) {
            guard activePath == path else { return }
            image = cached
            isLoading = false
            return
        }
        do {
            let data = try await PBStorageImageDownload.data(for: path)
            guard activePath == path else { return }
            guard let loadedImage = UIImage(data: data) else {
                image = nil
                didFail = true
                isLoading = false
                return
            }
            image = loadedImage
            PBImageCache.store(loadedImage, for: cacheKey)
            isLoading = false
        } catch is CancellationError {
            guard activePath == path else { return }
            isLoading = false
        } catch {
            guard activePath == path else { return }
            PBImageLog.loader.error("Storage image failed: \(path, privacy: .private(mask: .hash)); \(error.localizedDescription, privacy: .public)")
            didFail = true
            isLoading = false
        }
    }
}

enum PBStorageImageDownload {
    static func data(for path: String) async throws -> Data {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await withTimeout(seconds: 20) {
                    try await Storage.storage().reference(withPath: path).data(maxSize: 10 * 1024 * 1024)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < 2 {
                    try await Task.sleep(for: .milliseconds(350 * (attempt + 1)))
                }
            }
        }
        throw lastError ?? URLError(.unknown)
    }
}

enum PBImageLog {
    static let loader = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.example.mite",
        category: "ImageLoading"
    )
}

/// An internal URL form used by server-generated visuals. It avoids public download tokens while
/// letting every existing image component use Firebase Storage's authenticated cache and rules.
enum PBStorageImageURL {
    static func path(from urlString: String) -> String? {
        guard let url = URL(string: urlString), url.scheme == "storage", let host = url.host else { return nil }
        let suffix = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return suffix.isEmpty ? host : "\(host)/\(suffix)"
    }
}
