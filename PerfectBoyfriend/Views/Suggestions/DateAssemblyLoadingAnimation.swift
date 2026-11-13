import SwiftUI
import UIKit

enum DateAssemblyLoadingKind {
    case date
    case group

    var title: String {
        self == .group ? "Euer Treffen entsteht gerade …" : "Euer Abend entsteht gerade …"
    }

    var finishedTitle: String {
        self == .group ? "Fast fertig für eure Runde …" : "Fast fertig für euch …"
    }

    var subtitle: String {
        self == .group ? "Wir verbinden eure Wünsche zu einem gemeinsamen Plan." : "Wir verbinden eure Wünsche mit echten Orten."
    }
}

/// A small editorial interlude while the recommendation engine connects the chosen stops.
/// Both variants share the exact same hand-drawn animation; only the story changes from a
/// couple on the Schlossblick to friends gathering at the Ufercafé.
struct DateAssemblyLoadingAnimation: View {
    let kind: DateAssemblyLoadingKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(kind: DateAssemblyLoadingKind = .date) {
        self.kind = kind
    }

    var body: some View {
        Group {
            if reduceMotion {
                loadingContent(progress: 1)
            } else {
                TimelineView(.animation) { timeline in
                    loadingContent(progress: drawingProgress(at: timeline.date))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind == .group ? "Gruppenplan wird erstellt" : "Date-Vorschläge werden erstellt")
        .accessibilityValue("Bitte warten")
    }

    private func loadingContent(progress: CGFloat) -> some View {
        VStack(spacing: PBTheme.Spacing.lg) {
            MarburgDateAssemblyIllustration(progress: progress, kind: kind)
                .frame(maxWidth: 344)
                .frame(height: 498)

            VStack(spacing: PBTheme.Spacing.xs) {
                Text(progress < 0.80 ? kind.title : kind.finishedTitle)
                    .font(PBTheme.Typography.title)
                    .foregroundStyle(PBTheme.textOnDark)
                Text(kind.subtitle)
                    .font(PBTheme.Typography.body)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func drawingProgress(at date: Date) -> CGFloat {
        let cycle: TimeInterval = 8.0
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        // Keep the complete scene on screen long enough for it to feel like a finished drawing.
        return min(1, max(0, CGFloat(time / 6.35)))
    }
}

private struct MarburgDateAssemblyIllustration: View {
    let progress: CGFloat
    let kind: DateAssemblyLoadingKind

    /// Twenty-four small regions retain the scene's natural top-to-bottom rhythm, but no longer
    /// reveal it as four large image panels. Each region is itself inked stroke by stroke.
    private let stages: [ArtworkStage] = {
        let columns = 4
        let rows = 6
        return (0..<rows).flatMap { row in
            (0..<columns).map { column in
                let drawingColumn = row.isMultiple(of: 2) ? column : (columns - 1 - column)
                let order = CGFloat(row * columns + drawingColumn) / CGFloat(rows * columns - 1)
                return ArtworkStage(
                    id: "\(row)-\(column)",
                    start: 0.015 + order * 0.73,
                    duration: 0.19,
                    rect: CGRect(
                        x: CGFloat(column) / CGFloat(columns),
                        y: CGFloat(row) / CGFloat(rows),
                        width: 1 / CGFloat(columns),
                        height: 1 / CGFloat(rows)
                    )
                )
            }
        }
    }()

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                if let illustration = DateAssemblyArtwork.image(for: kind) {
                    // Only the ink is composited. The actual screen background stays visible
                    // through the original raster's navy paper, including its outer edges.
                    artwork(illustration, in: size)
                        .opacity(0.045)

                    artwork(illustration, in: size)
                        .mask(ArtworkRevealMask(stages: stages, overallProgress: progress))
                } else {
                    // The app remains graceful if a development build was created without bundled resources.
                    Color.clear
                }

                VStack {
                    Spacer()
                    HStack(spacing: 7) {
                        ForEach(0..<4, id: \.self) { index in
                            Circle()
                                .fill(index <= completedDot ? PBTheme.textOnDark : PBTheme.textOnDark.opacity(0.25))
                                .frame(width: index == completedDot ? 7 : 5, height: index == completedDot ? 7 : 5)
                                .animation(.easeOut(duration: 0.24), value: completedDot)
                        }
                    }
                    .padding(.bottom, 19)
                }
            }
        }
    }

    private var completedDot: Int {
        min(3, max(0, Int((progress * 4).rounded(.down))))
    }

    @ViewBuilder
    private func artwork(_ image: UIImage, in size: CGSize) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
    }

}

private struct ArtworkStage: Identifiable {
    let id: String
    let start: CGFloat
    let duration: CGFloat
    let rect: CGRect
}

private struct ArtworkRevealMask: View {
    let stages: [ArtworkStage]
    let overallProgress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                for (stageIndex, stage) in stages.enumerated() {
                    let rawProgress = min(1, max(0, (overallProgress - stage.start) / stage.duration))
                    let stageProgress = rawProgress * rawProgress * (3 - 2 * rawProgress)
                    guard stageProgress > 0 else { continue }

                    let bounds = CGRect(
                        x: size.width * stage.rect.minX,
                        y: size.height * stage.rect.minY,
                        width: size.width * stage.rect.width,
                        height: size.height * stage.rect.height
                    )
                    let strokeCount = max(18, Int(bounds.height / 2.1))

                    // The illustration is a raster asset, but this mask reveals it through many
                    // imperfect pencil strokes. The smaller regions make the scene accumulate in
                    // fine fragments, never as a few large rectangular image panels.
                    for index in 0..<strokeCount {
                        let seed = CGFloat((index * 37 + stageIndex * 19 + 17) % 101) / 101
                        let order = CGFloat((index * 53 + stageIndex * 29 + 11) % strokeCount) / CGFloat(strokeCount)
                        let strokeProgress = min(1, max(0, (stageProgress - order * 0.70) / 0.30))
                        guard strokeProgress > 0 else { continue }

                        let y = bounds.minY + (CGFloat(index) + 0.5) / CGFloat(strokeCount) * bounds.height
                        let startX = bounds.minX + bounds.width * seed * 0.20
                        let available = max(1, bounds.maxX - startX)
                        let endX = startX + available * strokeProgress
                        let wobble = sin(CGFloat(index + stageIndex) * 0.77) * 0.72
                        var stroke = Path()
                        stroke.move(to: CGPoint(x: startX, y: y - wobble))
                        stroke.addCurve(
                            to: CGPoint(x: endX, y: y + wobble),
                            control1: CGPoint(x: startX + (endX - startX) * 0.34, y: y + wobble * 0.5),
                            control2: CGPoint(x: startX + (endX - startX) * 0.71, y: y - wobble * 0.65)
                        )
                        context.stroke(
                            stroke,
                            with: .color(.white),
                            style: StrokeStyle(lineWidth: 2.35, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
            }
        }
    }
}

private enum DateAssemblyArtwork {
    static func image(for kind: DateAssemblyLoadingKind) -> UIImage? {
        let resource = kind == .group ? "date-assembly-ufcafe-group" : "date-assembly-marburg"
        guard let url = Bundle.main.url(forResource: resource, withExtension: "png") else {
            return nil
        }
        guard let source = UIImage(contentsOfFile: url.path) else { return nil }
        return extractInk(from: source)
    }

    /// The asset contains warm pencil marks on dark-blue paper. Extracting those marks once
    /// gives them a genuine alpha channel, so the app's live Midnight background continues
    /// behind the animation instead of forming a rectangular image panel.
    private static func extractInk(from image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width
        let height = cgImage.height
        let byteCount = width * height * 4
        guard let input = calloc(byteCount, 1), let output = calloc(byteCount, 1) else { return image }
        defer { free(input); free(output) }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: input, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: width * 4, space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let resultContext = CGContext(data: output, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: width * 4, space: colorSpace,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let source = input.assumingMemoryBound(to: UInt8.self)
        let destination = output.assumingMemoryBound(to: UInt8.self)
        for pixel in stride(from: 0, to: byteCount, by: 4) {
            let red = Float(source[pixel]) / 255
            let blue = Float(source[pixel + 2]) / 255
            // Blue paper has red lower than blue; warm pencil ink and the small stars invert it.
            let warmth = max(0, red - blue * 0.70)
            let alpha = UInt8(min(1, max(0, (warmth - 0.018) / 0.26)) * 255)
            destination[pixel] = UInt8(Float(alpha) * 0.94)
            destination[pixel + 1] = UInt8(Float(alpha) * 0.89)
            destination[pixel + 2] = UInt8(Float(alpha) * 0.79)
            destination[pixel + 3] = alpha
        }
        guard let result = resultContext.makeImage() else { return image }
        return UIImage(cgImage: result, scale: image.scale, orientation: image.imageOrientation)
    }
}
