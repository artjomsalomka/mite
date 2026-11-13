import Foundation
import OSLog
import SwiftUI
import UIKit

/// A remote Wikimedia Commons image with its provenance kept one tap away. The image reference
/// is intentionally a model value rather than a bare URL, so credits cannot be lost when a
/// generated suggestion becomes a saved date.
struct LicensedImageView: View {
    let image: LicensedImage
    var contentMode: ContentMode = .fill
    @StateObject private var loader: LicensedImageLoader

    init(image: LicensedImage, contentMode: ContentMode = .fill) {
        self.image = image
        self.contentMode = contentMode
        _loader = StateObject(wrappedValue: LicensedImageLoader())
    }

    var body: some View {
        // The clear base view owns the component's size. Its overlay receives exactly that
        // proposed size, so a large source image cannot report its original width back into a
        // vertical ScrollView and push the rest of the screen sideways.
        Color.clear
            .overlay {
                Group {
                    if let loadedImage = loader.image {
                        Image(uiImage: loadedImage)
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    } else if loader.didFail {
                        Button {
                            Task { await loader.load(urlString: image.url, force: true) }
                        } label: {
                            fallback
                                .overlay {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Bild erneut laden")
                    } else {
                        ZStack {
                            PBTheme.midnightRaised
                            ProgressView().tint(PBTheme.textOnDark)
                        }
                    }
                }
            }
            .clipped()
            .task(id: image.url) { await loader.load(urlString: image.url) }
    }

    private var fallback: some View {
        ZStack {
            PBTheme.midnightRaised
            Image(systemName: "photo")
                .foregroundStyle(PBTheme.textOnDarkSecondary)
        }
    }
}

/// A small process-lifetime image cache makes tab paging feel immediate once an image has been
/// seen. It deliberately keeps only decoded UIImages in memory; Firebase Storage remains the
/// source of truth and no user image is written to disk outside the SDK cache.
@MainActor
enum PBImageCache {
    private static let images = NSCache<NSString, UIImage>()

    static func image(for key: String) -> UIImage? {
        images.object(forKey: key as NSString)
    }

    static func store(_ image: UIImage, for key: String) {
        images.setObject(image, forKey: key as NSString)
    }

    static func remove(_ key: String) {
        images.removeObject(forKey: key as NSString)
    }

    static func preload(urlStrings: [String]) {
        for urlString in Set(urlStrings) where image(for: urlString) == nil {
            Task {
                if let path = PBStorageImageURL.path(from: urlString) {
                    guard let data = try? await PBStorageImageDownload.data(for: path),
                          let image = UIImage(data: data) else { return }
                    store(image, for: urlString)
                    return
                }
                guard let url = URL(string: urlString),
                      url.scheme != "bundle",
                      let data = try? await RemoteImageDownload.data(from: url),
                      let image = UIImage(data: data) else { return }
                store(image, for: urlString)
            }
        }
    }
}

@MainActor
private final class LicensedImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var didFail = false

    private var activeURLString: String?
    private var isLoading = false

    func load(urlString: String, force: Bool = false) async {
        guard force || activeURLString != urlString || (image == nil && !isLoading) else { return }
        activeURLString = urlString
        isLoading = true
        didFail = false
        if force { image = nil }

        if let cached = PBImageCache.image(for: urlString) {
            guard activeURLString == urlString else { return }
            image = cached
            isLoading = false
            return
        }

        if let bundleAsset = URL(string: urlString)?.host,
           let assetURL = Bundle.main.url(forResource: bundleAsset, withExtension: "jpg"),
           let bundledImage = UIImage(contentsOfFile: assetURL.path) {
            guard activeURLString == urlString else { return }
            PBImageCache.store(bundledImage, for: urlString)
            image = bundledImage
            isLoading = false
            return
        }

        if let path = PBStorageImageURL.path(from: urlString) {
            do {
                let data = try await PBStorageImageDownload.data(for: path)
                guard activeURLString == urlString else { return }
                guard let loadedImage = UIImage(data: data) else {
                    didFail = true
                    isLoading = false
                    return
                }
                PBImageCache.store(loadedImage, for: urlString)
                image = loadedImage
                isLoading = false
            } catch is CancellationError {
                guard activeURLString == urlString else { return }
                isLoading = false
            } catch {
                guard activeURLString == urlString else { return }
                PBImageLog.loader.error("Generated image failed: \(urlString, privacy: .private(mask: .hash)); \(error.localizedDescription, privacy: .public)")
                didFail = true
                isLoading = false
            }
            return
        }

        guard let url = URL(string: urlString) else {
            didFail = true
            isLoading = false
            return
        }

        do {
            let data = try await RemoteImageDownload.data(from: url)
            guard activeURLString == urlString else { return }
            guard let loadedImage = UIImage(data: data) else {
                didFail = true
                isLoading = false
                return
            }
            PBImageCache.store(loadedImage, for: urlString)
            image = loadedImage
            isLoading = false
        } catch is CancellationError {
            guard activeURLString == urlString else { return }
            isLoading = false
        } catch {
            guard activeURLString == urlString else { return }
            PBImageLog.loader.error("Remote image failed: \(urlString, privacy: .private(mask: .hash)); \(error.localizedDescription, privacy: .public)")
            didFail = true
            isLoading = false
        }
    }
}

private enum RemoteImageDownload {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 35
        configuration.httpAdditionalHeaders = [
            "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
            // Wikimedia rejects anonymous clients without a useful user agent. A stable product
            // identifier also makes the request work consistently on physical iPhones.
            "User-Agent": "Mite-iOS/1.0 (mobile image client)",
        ]
        return URLSession(configuration: configuration)
    }()

    private enum DownloadError: Error {
        case invalidResponse
        case httpStatus(Int)
        case unexpectedContentType(String?)
    }

    static func data(from url: URL) async throws -> Data {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await withTimeout(seconds: 25) {
                    var request = URLRequest(url: url)
                    request.cachePolicy = .returnCacheDataElseLoad
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else { throw DownloadError.invalidResponse }
                    guard (200..<300).contains(http.statusCode) else { throw DownloadError.httpStatus(http.statusCode) }
                    let contentType = http.value(forHTTPHeaderField: "Content-Type")
                    guard contentType?.lowercased().hasPrefix("image/") == true else {
                        throw DownloadError.unexpectedContentType(contentType)
                    }
                    return data
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

struct LicensedImageCredit: View {
    let image: LicensedImage
    var foregroundColor: Color = PBTheme.textSecondary

    var body: some View {
        Group {
            if let sourceURL = URL(string: image.sourcePageURL) {
                VStack(alignment: .leading, spacing: 3) {
                    if let label = image.contextLabel {
                        Text(label)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: PBTheme.Spacing.xs) {
                        Link(image.creditLine, destination: sourceURL)
                        if let licenseURL = image.licenseURL, let url = URL(string: licenseURL) {
                            Text("·")
                            Link("Lizenz", destination: url)
                        }
                    }
                }
                .font(PBTheme.Typography.micro)
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
            }
        }
    }
}
