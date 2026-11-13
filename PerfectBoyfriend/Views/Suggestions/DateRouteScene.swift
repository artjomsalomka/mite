import Foundation
import SceneKit
import simd
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// All dimensions are world-space metres. Shared by the iOS presentation and the offscreen
/// design renderer so camera composition can be reviewed without operating the Simulator.
final class DateRouteScene {
    enum CardStyle { case photo, planningDisc }
    let scene = SCNScene()
    let camera = SCNNode()
    private(set) var cards: [SCNNode] = []
    private var faces: [SCNMaterial] = []
    private var cardRoots: [SCNNode] = []
    private(set) var progress: Float = 0
    private(set) var focusedIndex: Int?
    let count: Int
    let cardStyle: CardStyle
    private var cameraProgress: Float = 0
    /// Unlike `progress` (the destination), this tracks the camera during an interrupted flight.
    var visibleProgress: Float { cardStyle == .planningDisc ? cameraProgress : progress }

    static let navy = CGColor(srgbRed: 0.023, green: 0.070, blue: 0.115, alpha: 1)

    private func nativeColor(_ color: CGColor) -> Any {
        #if canImport(UIKit)
        return UIColor(cgColor: color)
        #else
        return NSColor(cgColor: color) ?? NSColor.black
        #endif
    }

    init(count: Int, cardStyle: CardStyle = .photo) {
        self.count = max(0, count)
        self.cardStyle = cardStyle
        scene.background.contents = Self.navy
        scene.fogColor = Self.navy
        scene.fogStartDistance = cardStyle == .planningDisc ? 22 : 34
        scene.fogEndDistance = cardStyle == .planningDisc ? 57 : max(64, CGFloat(count) * 9 + 28)
        scene.fogDensityExponent = 1.8
        configureCamera()
        configureLighting()
        buildGround()
        if cardStyle == .planningDisc { buildOldTown() }
        else { buildRoad() }
        for index in 0..<self.count { buildCard(index: index) }
        move(to: 0, focus: nil, animated: false)
    }

    func setPhoto(_ image: CGImage, at index: Int) {
        guard faces.indices.contains(index) else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        faces[index].diffuse.contents = image
        SCNTransaction.commit()
    }

    /// The paid image request has an intentional, recognisable in-between state. Replacing all
    /// local fallbacks here prevents a generic stock image from being mistaken for the route's
    /// own motif while the final visual is being composed.
    #if canImport(UIKit)
    func setLoadingArtwork(for stops: [DateRouteStop], phase: Int) {
        guard cardStyle == .photo else { return }
        for index in faces.indices where stops.indices.contains(index) {
            faces[index].diffuse.contents = Self.loadingArtwork(
                symbol: stops[index].station.category.routeSymbolName,
                phase: (phase + index * 2) % 8
            )
        }
    }
    #endif

    func move(to requestedProgress: Float, focus: Int?, animated: Bool) {
        progress = min(Float(max(0, count - 1)), max(0, requestedProgress))
        focusedIndex = focus
        if cardStyle == .planningDisc {
            moveThroughOldTown(to: progress, focus: focus, animated: animated)
            return
        }
        let distance = progress * 8.5
        let centre = centreline(at: 5 + distance)
        let pose = SCNNode()
        if let focus, cards.indices.contains(focus) {
            let card = cardRoots[focus].position
            // Look below the photograph: it lands in the top half, leaving room for the
            // SwiftUI detail panel over the lower portion of the scene.
            pose.position = SCNVector3(card.x * 0.74, 4.5, card.z + 8.8)
            pose.look(at: SCNVector3(card.x * 0.86, 0.75, card.z - 0.8))
        } else {
            pose.position = SCNVector3(Float(centre.x) * 0.25, 6.4, 5.0 - distance)
            pose.look(at: SCNVector3(Float(centre.x) * 0.25, 0.5, -18.0 - distance))
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.85 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        camera.position = pose.position
        camera.orientation = pose.orientation
        for (index, node) in cards.enumerated() {
            let selected = focus == index
            node.scale = SCNVector3(selected ? 1.055 : 1, selected ? 1.055 : 1, 1)
        }
        SCNTransaction.commit()
    }

    func stationIndex(for hit: SCNNode) -> Int? {
        var node: SCNNode? = hit
        while let current = node {
            if let name = current.name, name.hasPrefix("station-"),
               let index = Int(name.dropFirst(8)) { return index }
            node = current.parent
        }
        return nil
    }

    private func configureCamera() {
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 52
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 180
        camera.camera?.wantsHDR = true
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = 0.1
        camera.camera?.bloomIntensity = 0
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.5
        camera.camera?.screenSpaceAmbientOcclusionRadius = 1.3
        scene.rootNode.addChildNode(camera)
    }

    private func configureLighting() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = nativeColor(CGColor(srgbRed: 0.62, green: 0.73, blue: 0.89, alpha: 1))
        ambient.light?.intensity = 520
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = nativeColor(CGColor(srgbRed: 0.93, green: 0.91, blue: 0.86, alpha: 1))
        key.light?.intensity = 1350
        key.light?.castsShadow = true
        key.light?.shadowMode = .deferred
        key.light?.shadowColor = nativeColor(CGColor(gray: 0, alpha: 0.42))
        key.light?.shadowRadius = 7
        key.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.light?.orthographicScale = CGFloat(max(30, count * 10))
        key.position = SCNVector3(-12, 20, 5)
        key.look(at: SCNVector3(0, 0, -12))
        scene.rootNode.addChildNode(key)
    }

    private func material(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, roughness: CGFloat = 0.8,
                          metalness: CGFloat = 0) -> SCNMaterial {
        let result = SCNMaterial()
        result.diffuse.contents = nativeColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        result.lightingModel = .physicallyBased
        result.roughness.contents = roughness
        result.metalness.contents = metalness
        return result
    }

    private func buildGround() {
        let floor = SCNFloor()
        floor.reflectivity = 0
        let ground = material(0.035, 0.080, 0.125, roughness: 1)
        // A matte, non-specular ground keeps the midnight palette at grazing camera angles.
        ground.lightingModel = .lambert
        if cardStyle == .planningDisc {
            ground.lightingModel = .constant
            ground.diffuse.contents = nativeColor(Self.navy)
        }
        floor.materials = [ground]
        let node = SCNNode(geometry: floor)
        node.position.y = -0.25
        scene.rootNode.addChildNode(node)
    }

    private func centreline(at distance: Float) -> SCNVector3 {
        // Continuous sinusoidal bends, sampled densely into an actual ribbon mesh. Each stop
        // sits at an alternating apex instead of on a straight polyline segment.
        SCNVector3(-3.0 * cos((distance - 5) * .pi / 8.5), 0, -distance)
    }

    private func surfacePoint(_ distance: Float, lateral: Float, height: Float) -> SCNVector3 {
        let point = centreline(at: distance)
        let dx = 3.0 * (.pi / 8.5) * sin((distance - 5) * .pi / 8.5)
        let divisor = sqrt(1 + dx * dx)
        return SCNVector3(Float(point.x) + lateral / divisor, height + townElevation(distance), Float(point.z) + lateral * dx / divisor)
    }

    private func ribbon(from start: Float, to end: Float, left: Float, right: Float, height: Float,
                        material: SCNMaterial, steps: Int? = nil) -> SCNNode {
        let segments = steps ?? max(2, Int((end - start) * 22))
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        for i in 0...segments {
            let distance = start + (end - start) * Float(i) / Float(segments)
            vertices.append(surfacePoint(distance, lateral: left, height: height))
            vertices.append(surfacePoint(distance, lateral: right, height: height))
            if i < segments {
                let base = Int32(i * 2)
                indices += [base, base + 1, base + 2, base + 1, base + 3, base + 2]
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(normals: Array(repeating: SCNVector3(0, 1, 0), count: vertices.count))],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private func buildRoad() {
        let start: Float = -14
        let end = Float(max(1, count) - 1) * 8.5 + 20
        let asphalt = material(0.18, 0.25, 0.32, roughness: 0.97)
        // A subtle procedural grain varies the lit surface without a downloaded material asset.
        asphalt.shaderModifiers = [.surface: """
        float grain = fract(sin(dot(_surface.position.xz, float2(127.1, 311.7))) * 43758.5453);
        _surface.diffuse.rgb *= 0.96 + grain * 0.08;
        """]
        let edging = material(0.70, 0.72, 0.70, roughness: 0.48, metalness: 0.2)
        let line = material(0.85, 0.81, 0.70, roughness: 0.65)
        let side = material(0.065, 0.12, 0.19)
        scene.rootNode.addChildNode(ribbon(from: start, to: end, left: -1.16, right: 1.16, height: 0.15, material: asphalt))
        for edge: Float in [-1.13, 1.13] {
            scene.rootNode.addChildNode(ribbon(from: start, to: end, left: edge - 0.018, right: edge + 0.018,
                                              height: 0.157, material: edging))
            // Vertical fascia gives the raised road a visible physical edge.
            var vertices: [SCNVector3] = []
            var indices: [Int32] = []
            let steps = Int((end - start) * 22)
            for i in 0...steps {
                let distance = start + (end - start) * Float(i) / Float(steps)
                vertices += [surfacePoint(distance, lateral: edge.sign == .minus ? -1.16 : 1.16, height: 0.15),
                             surfacePoint(distance, lateral: edge.sign == .minus ? -1.16 : 1.16, height: -0.20)]
                if i < steps {
                    let n = Int32(i * 2)
                    indices += [n, n + 2, n + 1, n + 1, n + 2, n + 3]
                }
            }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            side.isDoubleSided = true
            geometry.materials = [side]
            scene.rootNode.addChildNode(SCNNode(geometry: geometry))
        }
        var distance = start
        while distance < end {
            scene.rootNode.addChildNode(ribbon(from: distance, to: min(end, distance + 0.27),
                left: -0.013, right: 0.013, height: 0.16, material: line, steps: 4))
            distance += 0.73
        }
    }

    private func buildCard(index: Int) {
        let point = centreline(at: 5 + Float(index) * 8.5)
        let root = SCNNode()
        root.name = "station-\(index)"
        // Large photo circles keep the old card height as their diameter. Bring them slightly
        // inward so the extra width stays on screen without zooming the scene out.
        if cardStyle == .planningDisc {
            root.position = surfacePoint(5 + Float(index) * 8.5,
                lateral: index.isMultiple(of: 2) ? -0.55 : 0.55, height: 0.18)
        } else {
            root.position = SCNVector3(point.x * 0.45, 0.15, point.z)
        }
        scene.rootNode.addChildNode(root)
        cardRoots.append(root)
        addContactShadow(to: root)

        let foot = SCNCylinder(radius: 0.18, height: 0.045)
        foot.materials = [material(0.12, 0.17, 0.21, roughness: 0.5, metalness: 0.65)]
        let footNode = SCNNode(geometry: foot)
        footNode.position.y = 0.04
        root.addChildNode(footNode)
        let stem = SCNCylinder(radius: 0.012, height: 0.92)
        stem.materials = [material(0.59, 0.61, 0.58, roughness: 0.45, metalness: 0.7)]
        let stemNode = SCNNode(geometry: stem)
        stemNode.position.y = 0.49
        root.addChildNode(stemNode)

        let board = SCNNode()
        board.position.y = cardStyle == .planningDisc ? 1.9 : 2.5
        // Alternating gentle angles reveal the rounded edge during camera travel, while
        // leaving the face close enough to front-on for small text to stay readable.
        board.eulerAngles.y = index.isMultiple(of: 2) ? 0.19 : -0.19
        board.eulerAngles.x = -0.045
        root.addChildNode(board)
        if cardStyle == .planningDisc {
            let facing = SCNBillboardConstraint()
            facing.freeAxes = .Y
            board.constraints = [facing]
        }
        cards.append(board)

        let isPlanning = cardStyle == .planningDisc
        let radius: CGFloat = isPlanning ? 1.045 : 1.66
        let depth: CGFloat = isPlanning ? 0.24 : 0.34
        let bevel: CGFloat = isPlanning ? 0.045 : 0.065
        let bounds = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        #if canImport(UIKit)
        let outline = UIBezierPath(ovalIn: bounds)
        #else
        let outline = NSBezierPath(ovalIn: bounds)
        #endif
        outline.flatness = 0.005
        let body = SCNShape(path: outline, extrusionDepth: depth)
        body.chamferRadius = bevel
        body.chamferMode = .both
        body.materials = [isPlanning
            ? material(0.84, 0.90, 0.96, roughness: 0.36, metalness: 0.16)
            : material(0.16, 0.23, 0.31, roughness: 0.32, metalness: 0.48)]
        board.addChildNode(SCNNode(geometry: body))

        let faceRadius = radius - bevel
        let face = SCNPlane(width: faceRadius * 2, height: faceRadius * 2)
        face.cornerRadius = faceRadius
        // A fine, physical lip catches the key light; no bloom or glow is used.
        let lip = SCNTorus(ringRadius: faceRadius + 0.006, pipeRadius: 0.009)
        lip.ringSegmentCount = 128
        lip.pipeSegmentCount = 12
        lip.materials = [material(0.85, 0.89, 0.92, roughness: 0.28, metalness: 0.45)]
        let lipNode = SCNNode(geometry: lip)
        lipNode.eulerAngles.x = .pi / 2
        lipNode.position = SCNVector3(0, 0, Float(depth / 2))
        board.addChildNode(lipNode)
        let photoMaterial = SCNMaterial()
        photoMaterial.lightingModel = .constant
        photoMaterial.diffuse.contents = cardStyle == .planningDisc
            ? nativeColor(CGColor(gray: 1, alpha: 1)) : nativeColor(Self.navy)
        photoMaterial.isDoubleSided = true
        face.materials = [photoMaterial]
        faces.append(photoMaterial)
        let faceNode = SCNNode(geometry: face)
        faceNode.position = SCNVector3(0, 0, Float(depth / 2 + 0.004))
        board.addChildNode(faceNode)
    }

    private func addContactShadow(to root: SCNNode) {
        // A soft local contact shadow anchors each floating disc. The directional light
        // still renders the actual silhouette and self-shadowing from the thicker geometry.
        let size = 128
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [CGColor(gray: 0, alpha: 0.28), CGColor(gray: 0, alpha: 0)] as CFArray,
                locations: [0, 1]) else { return }
        context.drawRadialGradient(gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                   endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        let surface = SCNPlane(width: cardStyle == .photo ? 2.2 : 1.5, height: 0.85)
        let ink = SCNMaterial()
        ink.lightingModel = .constant
        ink.diffuse.contents = context.makeImage()
        ink.writesToDepthBuffer = false
        surface.materials = [ink]
        let shadow = SCNNode(geometry: surface)
        shadow.eulerAngles.x = -.pi / 2
        shadow.position = SCNVector3(0, 0.025, 0.1)
        shadow.castsShadow = false
        root.addChildNode(shadow)
    }

    // MARK: - Oberstadt: actual geometry, drawn with a small number of batched ink meshes

    private func townElevation(_ distance: Float) -> Float {
        cardStyle == .planningDisc ? max(-0.4, distance * 0.065) : 0
    }

    private func moveThroughOldTown(to destination: Float, focus: Int?, animated: Bool) {
        camera.removeAction(forKey: "town-travel")
        let start = cameraProgress
        if !animated {
            cameraProgress = destination
            applyTownCamera(progress: destination)
        } else {
            // Sample the curved route throughout the flight, rather than interpolating the
            // two endpoint transforms (which cuts straight across a bend).
            let duration = min(1.35, 0.68 + Double(abs(destination - start)) * 0.12)
            let flight = SCNAction.customAction(duration: duration) { [weak self] _, elapsed in
                guard let self else { return }
                let t = min(1, Float(elapsed) / Float(duration))
                let eased = t * t * (3 - 2 * t)
                let position = start + (destination - start) * eased
                self.cameraProgress = position
                self.applyTownCamera(progress: position)
            }
            camera.runAction(flight, forKey: "town-travel")
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.25 : 0
        for (index, node) in cards.enumerated() {
            let scale: Float = focus == index ? 1.045 : 1
            node.scale = SCNVector3(scale, scale, 1)
        }
        SCNTransaction.commit()
    }

    private func applyTownCamera(progress: Float) {
        let stationDistance = 5 + progress * 8.5
        let station = surfacePoint(stationDistance, lateral: 0, height: 1.55)
        let behind = surfacePoint(stationDistance - 8.8, lateral: 0, height: 6.1)
        // The camera follows the lane's sweep with damped lateral movement. The selected
        // disc stays comfortably in view while nearby facades move with visible parallax.
        camera.position = SCNVector3(Float(behind.x) * 0.18 + Float(station.x) * 0.82,
            Float(behind.y), Float(behind.z))
        let lateral = -0.55 * cos(progress * .pi)
        let aim = surfacePoint(stationDistance, lateral: lateral * 0.8, height: 0)
        let arrival = max(0, min(1, (progress - Float(max(0, count - 3))) / 2))
        camera.look(at: SCNVector3(Float(aim.x) + arrival * arrival * 0.6,
            townElevation(stationDistance) + 1.05 + arrival * arrival * 1.4, Float(station.z) - 4.3))
    }

    private func townInk(_ opacity: CGFloat = 1) -> SCNMaterial {
        let ink = SCNMaterial()
        ink.lightingModel = .constant
        ink.diffuse.contents = nativeColor(CGColor(srgbRed: 0.76, green: 0.83, blue: 0.87, alpha: 1))
        ink.transparency = opacity
        ink.isDoubleSided = true
        return ink
    }

    private func townFill(_ raised: Bool = false) -> SCNMaterial {
        let ink = SCNMaterial()
        ink.lightingModel = .constant
        ink.diffuse.contents = nativeColor(raised
            ? CGColor(srgbRed: 0.04, green: 0.105, blue: 0.165, alpha: 1) : Self.navy)
        ink.isDoubleSided = true
        return ink
    }

    private func buildOldTown() {
        let end = 5 + Float(max(0, count - 1)) * 8.5 + 19
        let start: Float = -15
        let halfWidth: Float = 1.8
        let paving = TownInkMesh()
        let edges = TownInkMesh()
        scene.rootNode.addChildNode(ribbon(from: start, to: end, left: -halfWidth, right: halfWidth,
            height: 0.15, material: townFill(true), steps: Int((end - start) * 12)))

        for side: Float in [-1, 1] {
            // Low walls are dark, opaque geometry. Their outlines occlude correctly when
            // the camera rounds a corner; no background illustration is being scrolled.
            var vertices: [SCNVector3] = []
            var indices: [Int32] = []
            let segments = Int((end - start) * 8)
            for index in 0...segments {
                let d = start + (end - start) * Float(index) / Float(segments)
                vertices.append(surfacePoint(d, lateral: side * halfWidth, height: 0.15))
                vertices.append(surfacePoint(d, lateral: side * halfWidth, height: 0.56))
                if index < segments {
                    let n = Int32(index * 2)
                    indices += [n, n + 1, n + 2, n + 1, n + 3, n + 2]
                    let next = start + (end - start) * Float(index + 1) / Float(segments)
                    for height: Float in [0.17, 0.38, 0.57] {
                        edges.line(surfacePoint(d, lateral: side * halfWidth, height: height),
                                   surfacePoint(next, lateral: side * halfWidth, height: height), width: 0.013)
                    }
                }
            }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            geometry.materials = [townFill()]
            scene.rootNode.addChildNode(SCNNode(geometry: geometry))
            for index in 0..<Int((end - start) / 0.8) {
                let d = start + Float(index) * 0.8
                edges.line(surfacePoint(d, lateral: side * halfWidth, height: 0.16),
                           surfacePoint(d + 0.05, lateral: side * halfWidth, height: 0.56), width: 0.010)
            }
        }
        // Hand-drawn, staggered paving: only contour marks, no asphalt or lane markings.
        for row in 0..<Int((end - start) / 0.55) {
            let d = start + Float(row) * 0.55
            for column in 0..<6 {
                let offset = row.isMultiple(of: 2) ? Float(0) : 0.25
                let x = -1.65 + Float(column) * 0.56 + offset
                guard x < 1.65 else { continue }
                let jitter = Float(sin(Double(row * 13 + column * 7))) * 0.05
                let points = [(x - 0.20, d + 0.06), (x + 0.17, d + jitter),
                              (x + 0.24, d + 0.22), (x + 0.12, d + 0.43),
                              (x - 0.21, d + 0.38), (x - 0.25, d + 0.18)]
                paving.polyline(points.map { surfacePoint($0.1, lateral: $0.0, height: 0.163) },
                                closed: true, width: 0.009)
            }
        }
        addTownMesh(paving, material: townInk(0.43))
        addTownMesh(edges, material: townInk(0.76))

        for index in 0..<count {
            let distance = Float(index) * 8.5 + 8
            for side: Float in [-1, 1] {
                // Keep architecture outside the entire swept lane, including the camera's
                // backwards offset. A local normal alone can put a house across the next bend.
                let houseDistance = distance + (side > 0 ? 2.8 : 0)
                let position = SCNVector3(side * (7.6 + Float(index % 2) * 0.8),
                    townElevation(houseDistance) - 0.05, -houseDistance)
                buildTownHouse(at: position, width: index.isMultiple(of: 2) ? 3.4 : 2.9,
                    height: 4.3 + Float(index % 3) * 0.65, angle: side * 0.14,
                    variant: index + (side > 0 ? 1 : 0))
                buildTownTree(at: SCNVector3(side * 6.2, townElevation(distance-3), -distance+3),
                    height: 3.0 + Float(index % 2), variant: index)
            }
        }
        buildTownCastle(at: surfacePoint(end + 1, lateral: 0, height: 0.1))
    }

    private func addTownMesh(_ mesh: TownInkMesh, material: SCNMaterial, to parent: SCNNode? = nil) {
        guard !mesh.vertices.isEmpty else { return }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: mesh.vertices)],
            elements: [SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)])
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.castsShadow = false
        (parent ?? scene.rootNode).addChildNode(node)
    }

    private func townBox(width: Float, height: Float, depth: Float, at position: SCNVector3,
                         parent: SCNNode, ink: TownInkMesh) {
        let geometry = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(depth), chamferRadius: 0)
        geometry.materials = [townFill()]
        let body = SCNNode(geometry: geometry)
        body.position = position
        parent.addChildNode(body)
        let x = Float(position.x), y = Float(position.y), z = Float(position.z)
        let corners = [SCNVector3(x-width/2,y-height/2,z-depth/2), SCNVector3(x+width/2,y-height/2,z-depth/2),
                       SCNVector3(x+width/2,y+height/2,z-depth/2), SCNVector3(x-width/2,y+height/2,z-depth/2),
                       SCNVector3(x-width/2,y-height/2,z+depth/2), SCNVector3(x+width/2,y-height/2,z+depth/2),
                       SCNVector3(x+width/2,y+height/2,z+depth/2), SCNVector3(x-width/2,y+height/2,z+depth/2)]
        for (a,b) in [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)] {
            ink.line(corners[a], corners[b], width: 0.022)
        }
    }

    private func townRoof(width: Float, height: Float, depth: Float, base: Float,
                          x: Float = 0, parent: SCNNode, ink: TownInkMesh) {
        let w = width / 2, d = depth / 2
        let v = [SCNVector3(x-w,base,-d), SCNVector3(x+w,base,-d), SCNVector3(x,base+height,-d),
                 SCNVector3(x-w,base,d), SCNVector3(x+w,base,d), SCNVector3(x,base+height,d)]
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: v)],
            elements: [SCNGeometryElement(indices: [Int32(0),2,1,3,4,5,0,3,5,0,5,2,1,2,5,1,5,4], primitiveType: .triangles)])
        geometry.materials = [townFill()]
        parent.addChildNode(SCNNode(geometry: geometry))
        for (a,b) in [(0,1),(1,2),(2,0),(3,4),(4,5),(5,3),(0,3),(1,4),(2,5)] { ink.line(v[a],v[b],width: 0.025) }
    }

    private func townWindow(x: Float, y: Float, z: Float, width: Float = 0.5, height: Float = 0.75, ink: TownInkMesh) {
        ink.polyline([SCNVector3(x-width/2,y,z), SCNVector3(x+width/2,y,z),
                      SCNVector3(x+width/2,y+height,z), SCNVector3(x-width/2,y+height,z)], closed: true, width: 0.016)
        ink.line(SCNVector3(x,y,z), SCNVector3(x,y+height,z), width: 0.010)
    }

    private func buildTownHouse(at position: SCNVector3, width: Float, height: Float, angle: Float, variant: Int) {
        let root = SCNNode()
        root.position = position
        root.eulerAngles = SCNVector3(0,angle,0)
        scene.rootNode.addChildNode(root)
        let ink = TownInkMesh()
        let depth: Float = 3.1
        townBox(width: width, height: height, depth: depth, at: SCNVector3(0,height/2,0), parent: root, ink: ink)
        townRoof(width: width + 0.32, height: 2, depth: depth + 0.3, base: height, parent: root, ink: ink)
        let front = depth / 2 + 0.025
        for level in 1...2 {
            let y = Float(level) * height / 3
            ink.line(SCNVector3(-width/2,y,front), SCNVector3(width/2,y,front), width: 0.030)
            for x: Float in [-width/3, 0, width/3] {
                townWindow(x: x, y: y + 0.23, z: front, width: 0.43, height: height/3-0.45, ink: ink)
            }
        }
        for side: Float in [-1,1] {
            ink.line(SCNVector3(side*width/6,0,front), SCNVector3(side*width/6,height,front), width: 0.029)
            // A few diagonal timber beams on the side wall are enough to read as Fachwerk.
            let x = side * (width/2 + 0.022)
            for floor in 0..<3 {
                let y = Float(floor)*height/3
                ink.line(SCNVector3(x,y,-depth/2), SCNVector3(x,y+height/3,depth/2), width: 0.025)
                ink.line(SCNVector3(x,y,depth/2), SCNVector3(x,y+height/3,-depth/2), width: 0.025)
                ink.line(SCNVector3(x,y,-depth/2), SCNVector3(x,y,depth/2), width: 0.028)
            }
        }
        townWindow(x: 0, y: 0.03, z: front, width: 0.68, height: 1.12, ink: ink)
        ink.line(SCNVector3(0,height,front+0.16),SCNVector3(0,height+1.95,front+0.16),width:0.024)
        addTownMesh(ink, material: townInk(0.72), to: root)
    }

    private func buildTownTree(at position: SCNVector3, height: Float, variant: Int) {
        let root = SCNNode()
        root.position = position
        scene.rootNode.addChildNode(root)
        let ink = TownInkMesh()
        ink.line(SCNVector3(0,0,0),SCNVector3(0,height*0.78,0),width:0.025)
        for axis in 0..<3 {
            let angle = Float(axis) * .pi / 3
            var outline: [SCNVector3] = []
            for step in 0..<40 {
                let t = Float(step) * .pi * 2 / 40
                let r = (0.88 + 0.10 * sin(t*7+Float(variant))) * sin(t)
                outline.append(SCNVector3(r*cos(angle),height*0.64 + cos(t)*height*0.40,r*sin(angle)))
            }
            ink.polyline(outline,closed:true,width:0.013)
            ink.line(SCNVector3(0,height*0.35,0),SCNVector3(cos(angle)*0.55,height*0.69,sin(angle)*0.55),width:0.015)
        }
        addTownMesh(ink,material:townInk(0.34),to:root)
    }

    private func buildTownCastle(at position: SCNVector3) {
        let root = SCNNode()
        root.name = "oberstadt-castle"
        root.position = position
        // A distant landmark, not an oversized backdrop: its roofline fits above the final
        // station and gradually emerges through the depth haze during the approach.
        root.scale = SCNVector3(0.46, 0.46, 0.46)
        scene.rootNode.addChildNode(root)
        let ink = TownInkMesh()
        townBox(width: 14, height: 1.8, depth: 6, at: SCNVector3(0,0.9,0), parent: root, ink: ink)
        townBox(width: 10.8, height: 4.3, depth: 4.2, at: SCNVector3(0,3.95,0), parent: root, ink: ink)
        townRoof(width:11.2,height:2.8,depth:4.5,base:6.1,parent:root,ink:ink)
        for side: Float in [-1,1] {
            townBox(width:2.3,height:6.3,depth:3.6,at:SCNVector3(side*5.6,4.95,0),parent:root,ink:ink)
            townRoof(width:2.65,height:2.2,depth:3.9,base:8.1,x:side*5.6,parent:root,ink:ink)
        }
        townBox(width:1.7,height:3.1,depth:1.7,at:SCNVector3(0,9.0,0),parent:root,ink:ink)
        townRoof(width:2.0,height:1.9,depth:2,base:10.55,parent:root,ink:ink)
        ink.line(SCNVector3(0,12.45,0),SCNVector3(0,13.0,0),width:0.025)
        for level in 0..<3 {
            for column in -5...5 {
                townWindow(x: Float(column)*0.85,y:2.2+Float(level)*1.17,z:2.13,width:0.28,height:0.52,ink:ink)
            }
        }
        addTownMesh(ink,material:townInk(0.9),to:root)
    }

    #if canImport(UIKit)
    private static func loadingArtwork(symbol: String, phase: Int) -> UIImage {
        let size = CGSize(width: 768, height: 768)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            let navy = UIColor(cgColor: Self.navy)
            let ink = UIColor(red: 0.91, green: 0.93, blue: 0.90, alpha: 1)
            context.setFillColor(navy.cgColor)
            context.fill(CGRect(origin: .zero, size: size))

            // The former orbit and travelling dot still read as a stock spinner. A few open
            // route segments now compose calmly from left to right and visually belong to the
            // itinerary that follows.
            let points = [
                CGPoint(x: 116, y: 402), CGPoint(x: 205, y: 324), CGPoint(x: 300, y: 366),
                CGPoint(x: 390, y: 272), CGPoint(x: 494, y: 326), CGPoint(x: 646, y: 224),
            ]
            let reveal = min(points.count - 1, max(1, phase + 1))
            for index in 0..<reveal {
                let start = points[index]
                let end = points[index + 1]
                let localProgress: CGFloat = index == reveal - 1 ? 0.52 + CGFloat(phase % 2) * 0.22 : 1
                let point = CGPoint(x: start.x + (end.x - start.x) * localProgress,
                                    y: start.y + (end.y - start.y) * localProgress)
                context.setStrokeColor(ink.withAlphaComponent(index == reveal - 1 ? 0.92 : 0.54).cgColor)
                context.setLineWidth(index == reveal - 1 ? 4 : 2.2)
                context.setLineCap(.round)
                context.move(to: start)
                context.addLine(to: point)
                context.strokePath()
            }

            if let icon = UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 116, weight: .thin)
            )?.withTintColor(ink, renderingMode: .alwaysOriginal) {
                icon.draw(in: CGRect(x: 326, y: 267, width: 116, height: 116))
            }

            let style = NSMutableParagraphStyle()
            style.alignment = .center
            ("MOTIV WIRD KOMPOSIERT" as NSString).draw(
                in: CGRect(x: 104, y: 583, width: 560, height: 32),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 20, weight: .medium),
                    .foregroundColor: ink.withAlphaComponent(0.78),
                    .kern: 3.4,
                    .paragraphStyle: style,
                ]
            )
        }
    }
    #endif
}

/// Each pen stroke is a tiny four-sided tube. All strokes of one object share one mesh and
/// draw call; unlike thousands of cylinder nodes this stays practical on a physical iPhone.
private final class TownInkMesh {
    var vertices: [SCNVector3] = []
    var indices: [Int32] = []

    func polyline(_ points: [SCNVector3], closed: Bool = false, width: Float) {
        guard points.count > 1 else { return }
        for index in 1..<points.count { line(points[index-1],points[index],width:width) }
        if closed { line(points[points.count-1],points[0],width:width) }
    }

    func line(_ a: SCNVector3, _ b: SCNVector3, width: Float) {
        let start = SIMD3<Float>(Float(a.x),Float(a.y),Float(a.z))
        let end = SIMD3<Float>(Float(b.x),Float(b.y),Float(b.z))
        guard simd_length_squared(end-start) > 0.000001 else { return }
        let direction = simd_normalize(end-start)
        let up = abs(direction.y) > 0.9 ? SIMD3<Float>(1,0,0) : SIMD3<Float>(0,1,0)
        let u = simd_normalize(simd_cross(direction,up)) * width / 2
        let v = simd_normalize(simd_cross(direction,u)) * width / 2
        let base = Int32(vertices.count)
        for point in [start,end] {
            for offset in [u+v,-u+v,-u-v,u-v] {
                let p = point+offset
                vertices.append(SCNVector3(p.x,p.y,p.z))
            }
        }
        for index in 0..<4 {
            let a = base+Int32(index), b = base+Int32((index+1)%4)
            indices += [a,b,a+4,b,b+4,a+4]
        }
    }
}
