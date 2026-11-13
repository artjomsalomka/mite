import SceneKit
import SwiftUI
import UIKit

@MainActor
final class DateRoutePresentation: ObservableObject {
    @Published private(set) var world: DateRouteScene
    @Published private(set) var stops: [DateRouteStop]
    @Published private(set) var progress: Float = 0
    @Published private(set) var detailIndex: Int?
    @Published private(set) var displayedPhotos: [Int: LicensedImage] = [:]
    private var photoTasks: [Task<Void, Never>] = []
    private var loadingArtworkTask: Task<Void, Never>?
    private var generation = UUID()
    private var isShowingVisualPlaceholder: Bool

    var selectedIndex: Int { min(max(0, Int(progress.rounded())), max(0, stops.count - 1)) }
    var selectedStop: DateRouteStop? { stops.indices.contains(selectedIndex) ? stops[selectedIndex] : nil }
    var detailStop: DateRouteStop? {
        guard let detailIndex, stops.indices.contains(detailIndex) else { return nil }
        return stops[detailIndex]
    }

    init(stations: [DateStation], startingAt: Date, isShowingVisualPlaceholder: Bool = false) {
        let initialStops = DateSchedule.stops(stations, startingAt: startingAt)
        stops = initialStops
        world = DateRouteScene(count: initialStops.count)
        self.isShowingVisualPlaceholder = isShowingVisualPlaceholder
        if isShowingVisualPlaceholder {
            showLoadingArtwork()
        } else {
            loadPhotos()
        }
    }

    func update(stations: [DateStation], startingAt: Date) {
        let updated = DateSchedule.stops(stations, startingAt: startingAt)
        guard updated.map(\.station) != stops.map(\.station) || updated.map(\.startsAt) != stops.map(\.startsAt) else { return }
        let countChanged = updated.count != stops.count
        stops = updated
        if countChanged {
            world = DateRouteScene(count: stops.count)
            progress = 0
            detailIndex = nil
        }
        if isShowingVisualPlaceholder {
            showLoadingArtwork()
        } else {
            loadPhotos()
        }
    }

    func travel(to value: Float, animated: Bool, reduceMotion: Bool) {
        detailIndex = nil
        progress = min(Float(max(0, stops.count - 1)), max(0, value))
        world.move(to: progress, focus: nil, animated: animated && !reduceMotion)
    }

    func open(_ index: Int, reduceMotion: Bool) {
        guard stops.indices.contains(index) else { return }
        progress = Float(index)
        detailIndex = index
        world.move(to: progress, focus: index, animated: !reduceMotion)
    }

    func close(reduceMotion: Bool) {
        detailIndex = nil
        world.move(to: progress, focus: nil, animated: !reduceMotion)
    }

    func stopLoading() {
        photoTasks.forEach { $0.cancel() }
        photoTasks.removeAll()
        loadingArtworkTask?.cancel()
        loadingArtworkTask = nil
    }

    func resumeLoading() {
        if isShowingVisualPlaceholder {
            showLoadingArtwork()
        } else if photoTasks.isEmpty {
            loadPhotos()
        }
    }

    func setVisualLoading(_ isLoading: Bool) {
        guard isShowingVisualPlaceholder != isLoading else { return }
        isShowingVisualPlaceholder = isLoading
        if isLoading {
            stopLoading()
            displayedPhotos.removeAll()
            showLoadingArtwork()
        } else {
            loadingArtworkTask?.cancel()
            loadingArtworkTask = nil
            loadPhotos()
        }
    }

    private func loadPhotos() {
        guard !isShowingVisualPlaceholder else { return }
        stopLoading()
        generation = UUID()
        let token = generation
        for (index, stop) in stops.enumerated() {
            guard let requested = stop.station.licensedImage else { continue }
            // Install a route-specific local image synchronously, before the first rendered frame.
            if let immediate = Self.localImage(requested) { install(immediate, metadata: requested, stop: stop, at: index) }
            guard Self.localImage(requested) == nil else { continue }
            if let path = PBStorageImageURL.path(from: requested.url) {
                photoTasks.append(Task { [weak self] in
                    do {
                        let data = try await PBStorageImageDownload.data(for: path)
                        guard let photo = UIImage(data: data), !Task.isCancelled,
                              let self, self.generation == token else { return }
                        PBImageCache.store(photo, for: requested.url)
                        self.install(photo, metadata: requested, stop: stop, at: index)
                    } catch {
                        // The regular bundled image remains visible when Storage is unavailable.
                    }
                })
                continue
            }
            guard requested.url.hasPrefix("https://"), let url = URL(string: requested.url) else { continue }
            photoTasks.append(Task { [weak self] in
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 12
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
                          let photo = UIImage(data: data), !Task.isCancelled,
                          let self, self.generation == token else { return }
                    PBImageCache.store(photo, for: requested.url)
                    self.install(photo, metadata: requested, stop: stop, at: index)
                } catch {
                    // The existing local photo and its matching attribution remain visible.
                }
            })
        }
    }

    private func showLoadingArtwork() {
        guard isShowingVisualPlaceholder else { return }
        loadingArtworkTask?.cancel()
        var phase = 0
        world.setLoadingArtwork(for: stops, phase: phase)
        loadingArtworkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 520_000_000)
                guard !Task.isCancelled, let self, self.isShowingVisualPlaceholder else { return }
                phase = (phase + 1) % 8
                self.world.setLoadingArtwork(for: self.stops, phase: phase)
            }
        }
    }

    private func install(_ photo: UIImage, metadata: LicensedImage, stop: DateRouteStop, at index: Int) {
        guard let texture = DateRoutePhotoTexture.make(photo: photo, stop: stop, contextual: metadata.contextLabel != nil).cgImage else { return }
        world.setPhoto(texture, at: index)
        displayedPhotos[index] = metadata
    }

    private static func localImage(_ metadata: LicensedImage) -> UIImage? {
        if let cached = PBImageCache.image(for: metadata.url) { return cached }
        guard let url = URL(string: metadata.url), url.scheme == "bundle", let name = url.host,
              let file = Bundle.main.url(forResource: name, withExtension: "jpg") else { return nil }
        return UIImage(contentsOfFile: file.path)
    }

    deinit {
        photoTasks.forEach { $0.cancel() }
        loadingArtworkTask?.cancel()
    }
}

/// Photos are the materials on real 3D planes, including their typography. Only the selected
/// stop's detailed text is native SwiftUI, which keeps it accessible and readable at every size.
@MainActor
private enum DateRoutePhotoTexture {
    static func make(photo: UIImage, stop: DateRouteStop, contextual: Bool) -> UIImage {
        let size = CGSize(width: 768, height: 768)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            let scale = max(size.width / photo.size.width, size.height / photo.size.height)
            let rect = CGRect(x: (size.width - photo.size.width * scale) / 2,
                              y: (size.height - photo.size.height * scale) / 2,
                              width: photo.size.width * scale, height: photo.size.height * scale)
            photo.draw(in: rect)
            let colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.16).cgColor,
                          UIColor.black.withAlphaComponent(0.88).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 320), end: CGPoint(x: 0, y: 768), options: [])
            }
            let ivory = UIColor(red: 0.98, green: 0.95, blue: 0.89, alpha: 1)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            paragraph.alignment = .center
            let title = stop.station.resolvedPlace?.name ?? stop.station.title
            (stop.startsAt.miteTimeText as NSString).draw(
                in: CGRect(x: 124, y: 492, width: 520, height: 62),
                withAttributes: [.font: UIFont.systemFont(ofSize: 50, weight: .light),
                                 .foregroundColor: ivory, .paragraphStyle: paragraph])
            // Keep both lines inside the circle's narrowing lower portion, not at square edges.
            (title as NSString).draw(in: CGRect(x: 124, y: 560, width: 520, height: 102),
                withAttributes: [.font: UIFont.systemFont(ofSize: 42, weight: .light),
                                 .foregroundColor: ivory, .paragraphStyle: paragraph])
            if contextual {
                ("STIMMUNGSFOTO" as NSString).draw(in: CGRect(x: 224, y: 674, width: 320, height: 28),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 17, weight: .medium),
                                     .kern: 2, .foregroundColor: ivory.withAlphaComponent(0.72),
                                     .paragraphStyle: paragraph])
            }
        }
    }
}

struct DateRouteSceneView: View {
    @ObservedObject var presentation: DateRoutePresentation
    let reduceMotion: Bool
    let isActive: Bool
    let allowsVerticalNavigation: Bool

    var body: some View {
        SpatialRouteSceneView(world: presentation.world, progress: presentation.progress,
            reduceMotion: reduceMotion, isActive: isActive, allowsVerticalNavigation: allowsVerticalNavigation,
            onSelect: { presentation.open($0, reduceMotion: reduceMotion) },
            onTravel: { presentation.travel(to: $0, animated: $1, reduceMotion: reduceMotion) },
            onMount: { presentation.resumeLoading() }, onUnmount: { presentation.stopLoading() })
    }
}

/// Shared spatial input surface for both itinerary exploration and planning settings.
struct SpatialRouteSceneView: UIViewRepresentable {
    let world: DateRouteScene
    let progress: Float
    let reduceMotion: Bool
    let isActive: Bool
    var allowsVerticalNavigation = true
    let onSelect: (Int) -> Void
    let onTravel: (Float, Bool) -> Void
    var onMount: () -> Void = {}
    var onUnmount: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = world.scene
        view.pointOfView = world.camera
        view.backgroundColor = UIColor(cgColor: DateRouteScene.navy)
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.isPlaying = isActive
        onMount()
        view.accessibilityElementsHidden = true
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        tap.require(toFail: pan)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.parent = self
        if view.scene !== world.scene {
            view.scene = world.scene
            view.pointOfView = world.camera
        }
        view.isPlaying = isActive
        view.scene?.isPaused = !isActive
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.isPlaying = false
        view.scene = nil
        coordinator.parent.onUnmount()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SpatialRouteSceneView
        private var initialProgress: Float = 0
        private var initialCameraProgress: Float = 0
        private var usesVerticalAxis = true
        private let feedback = UISelectionFeedbackGenerator()
        init(_ parent: SpatialRouteSceneView) { self.parent = parent }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.isActive else { return false }
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            if parent.world.cardStyle == .planningDisc {
                return abs(velocity.y) > abs(velocity.x)
            }
            guard !parent.allowsVerticalNavigation else { return true }
            // Embedded routes live in a ScrollView. Vertical gestures belong to that page.
            return abs(velocity.x) > abs(velocity.y)
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard parent.isActive, let view = gesture.view as? SCNView else { return }
            let hits = view.hitTest(gesture.location(in: view), options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            for hit in hits {
                if let index = parent.world.stationIndex(for: hit.node) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    parent.onSelect(index)
                    return
                }
            }
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            let velocity = gesture.velocity(in: view)
            // The dominant axis decides: dragging up (or left) moves to the next stop, dragging
            // down (or right) to the previous one.
            let movement = Float(usesVerticalAxis ? translation.y : translation.x)
            let axisVelocity = Float(usesVerticalAxis ? velocity.y : velocity.x)

            switch gesture.state {
            case .began:
                initialProgress = parent.progress.rounded()
                initialCameraProgress = parent.world.visibleProgress
                usesVerticalAxis = parent.world.cardStyle == .planningDisc ||
                    (parent.allowsVerticalNavigation && abs(velocity.y) >= abs(velocity.x))
                feedback.prepare()
            case .changed:
                guard !parent.reduceMotion else { return }
                // The scene follows the finger, but never further than one stop from where the
                // drag began, so a stop is always a clear, single step.
                let followed = initialCameraProgress - movement / Float(max(220, view.bounds.height * 0.65))
                parent.onTravel(min(initialProgress + 0.92, max(initialProgress - 0.92, followed)), false)
            case .ended, .cancelled:
                // A short drag or a light flick is enough for the next or previous stop; nothing
                // has to be dragged past the halfway point any more.
                let isFlick = abs(axisVelocity) > 240 && abs(movement) > 8
                let isFarEnough = abs(movement) > 30
                var target = initialProgress
                if gesture.state == .ended, isFlick || isFarEnough {
                    let direction = isFlick ? axisVelocity : movement
                    target += direction < 0 ? 1 : -1
                }
                target = min(Float(max(0, parent.world.count - 1)), max(0, target))
                if target != initialProgress { feedback.selectionChanged() }
                parent.onTravel(target, true)
            default: break
            }
        }
    }
}
