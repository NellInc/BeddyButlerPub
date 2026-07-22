import AppKit
import SpriteKit
import SwiftUI

enum ButlerRigContentMode {
    case fit
    case upperBody
}

/// A lightweight 2D skeletal rig. The original 4K character is bound to a
/// deformable mesh, then animated by personality-specific bones rather than by
/// moving the finished picture as one rigid rectangle.
struct ButlerRiggedView: NSViewRepresentable {
    let personality: ButlerPersonality
    let motionEnabled: Bool
    let isVisible: Bool
    let contentMode: ButlerRigContentMode
    let intensity: Float

    func makeNSView(context: Context) -> ButlerRigSKView {
        let view = ButlerRigSKView()
        view.configure(
            personality: personality,
            motionEnabled: motionEnabled,
            isVisible: isVisible,
            contentMode: contentMode,
            intensity: intensity
        )
        return view
    }

    func updateNSView(_ nsView: ButlerRigSKView, context: Context) {
        nsView.configure(
            personality: personality,
            motionEnabled: motionEnabled,
            isVisible: isVisible,
            contentMode: contentMode,
            intensity: intensity
        )
    }

    static func dismantleNSView(_ nsView: ButlerRigSKView, coordinator: ()) {
        nsView.stopRendering()
    }
}

final class ButlerRigSKView: SKView {
    private let rigScene = ButlerRigScene()
    private let permitsOccludedRendering =
        ProcessInfo.processInfo.environment["BEDDY_BUTLER_CAPTURE_UI_DIR"] != nil
        || ProcessInfo.processInfo.environment["BEDDY_BUTLER_RIG_CAPTURE"] == "1"
    private var motionEnabled = true
    private var requestedVisibility = true
    private var renderGeneration = 0
    private weak var observedClipView: NSClipView?
    private var visibilityTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowsTransparency = true
        preferredFramesPerSecond = 60
        ignoresSiblingOrder = true
        shouldCullNonVisibleNodes = true
        presentScene(rigScene)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func configure(
        personality: ButlerPersonality,
        motionEnabled: Bool,
        isVisible: Bool,
        contentMode: ButlerRigContentMode,
        intensity: Float
    ) {
        self.motionEnabled = motionEnabled
        requestedVisibility = isVisible
        rigScene.configure(
            personality: personality,
            motionEnabled: motionEnabled,
            contentMode: contentMode,
            intensity: intensity
        )
        updateRenderingState()
    }

    func stopRendering() {
        renderGeneration += 1
        isPaused = true
        visibilityTimer?.invalidate()
        visibilityTimer = nil
        NotificationCenter.default.removeObserver(self)
        presentScene(nil)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeScrollVisibility()
        updateVisibilityTimer()
        updateRenderingState()
    }

    override func layout() {
        super.layout()
        updateRenderingState()
    }

    @objc private func scrollBoundsDidChange(_ notification: Notification) {
        updateRenderingState()
    }

    @objc private func checkVisibility(_ timer: Timer) {
        updateRenderingState()
    }

    private func updateVisibilityTimer() {
        visibilityTimer?.invalidate()
        visibilityTimer = nil
        guard window != nil else { return }
        let timer = Timer(
            timeInterval: 0.4,
            target: self,
            selector: #selector(checkVisibility),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        visibilityTimer = timer
    }

    private func observeScrollVisibility() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSView.boundsDidChangeNotification,
            object: observedClipView
        )
        observedClipView = enclosingScrollView?.contentView
        observedClipView?.postsBoundsChangedNotifications = true
        if let observedClipView {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollBoundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: observedClipView
            )
        }
    }

    private func updateRenderingState() {
        renderGeneration += 1
        let generation = renderGeneration
        guard window != nil else {
            isPaused = true
            return
        }
        let rectInWindow = convert(bounds, to: nil)
        let windowContentRect =
            window?.contentView.map { contentView in
                contentView.convert(contentView.bounds, to: nil)
            } ?? .zero
        let isWithinVisibleLayout =
            window?.isVisible == true
            && requestedVisibility
            && !isHidden
            && !visibleRect.isEmpty
            && rectInWindow.intersects(windowContentRect)

        guard isWithinVisibleLayout else {
            isPaused = true
            if scene != nil {
                presentScene(nil)
            }
            return
        }

        if scene == nil {
            presentScene(rigScene)
        }

        guard
            permitsOccludedRendering
                || window?.occlusionState.contains(.visible) == true
        else {
            // Keep the most recent rendered frame attached for snapshots and
            // instant restoration, while avoiding an occluded Metal display loop.
            isPaused = true
            return
        }
        isPaused = false
        guard !motionEnabled else { return }

        // Render the new identity pose once, then stop the SpriteKit display loop.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.renderGeneration == generation, !self.motionEnabled else { return }
            self.isPaused = true
        }
    }
}

final class ButlerRigScene: SKScene {
    private static let motionActionKey = "butler.mesh.rig"

    private var characterNode: SKSpriteNode?
    private var personality: ButlerPersonality?
    private var motionEnabled = true
    private var intensity: Float = 1
    private var contentMode: ButlerRigContentMode = .fit
    private var artworkAspect: CGFloat = 0.75

    override init() {
        super.init(size: CGSize(width: 300, height: 400))
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutCharacter()
    }

    func configure(
        personality requestedPersonality: ButlerPersonality,
        motionEnabled requestedMotionEnabled: Bool,
        contentMode requestedContentMode: ButlerRigContentMode,
        intensity requestedIntensity: Float
    ) {
        let clampedIntensity = min(max(requestedIntensity, 0), 1.25)
        let personalityChanged = personality != requestedPersonality
        let motionChanged = motionEnabled != requestedMotionEnabled
        let intensityChanged = abs(intensity - clampedIntensity) > 0.001
        let contentModeChanged = contentMode != requestedContentMode

        personality = requestedPersonality
        motionEnabled = requestedMotionEnabled
        intensity = clampedIntensity
        contentMode = requestedContentMode
        if personalityChanged || characterNode == nil {
            replaceCharacter(with: requestedPersonality)
        } else if motionChanged || intensityChanged {
            applyMotion(to: characterNode)
        }
        if contentModeChanged {
            layoutCharacter()
        }
    }

    private func replaceCharacter(with personality: ButlerPersonality) {
        guard let image = NSImage(named: personality.rigAssetName) else { return }

        let (texture, aspect) = makeDisplayTexture(from: image)
        texture.filteringMode = .linear
        let newNode = SKSpriteNode(texture: texture)
        newNode.name = "rigged-\(personality.rawValue)-butler"
        newNode.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        newNode.blendMode = .alpha
        newNode.subdivisionLevels = 2

        artworkAspect = aspect

        let oldNode = characterNode
        characterNode = newNode
        addChild(newNode)
        layoutCharacter()
        applyMotion(to: newNode)

        guard let oldNode else { return }
        if motionEnabled {
            newNode.alpha = 0
            newNode.setScale(0.985)
            newNode.run(
                .group([
                    .fadeIn(withDuration: 0.22),
                    .scale(to: 1, duration: 0.28),
                ])
            )
            oldNode.run(
                .sequence([
                    .group([
                        .fadeOut(withDuration: 0.18),
                        .scale(to: 0.985, duration: 0.18),
                    ]),
                    .removeFromParent(),
                ])
            )
        } else {
            oldNode.removeFromParent()
        }
    }

    private func makeDisplayTexture(from image: NSImage) -> (SKTexture, CGFloat) {
        let pixelSize =
            image.representations
            .map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) }
            .first { $0.width > 0 && $0.height > 0 } ?? image.size
        let aspect = pixelSize.height > 0 ? pixelSize.width / pixelSize.height : 0.75
        if pixelSize.height <= 1_024 {
            return (SKTexture(image: image), aspect)
        }
        let targetHeight = min(max(Int(pixelSize.height.rounded()), 1), 1_024)
        let targetWidth = max(Int((CGFloat(targetHeight) * aspect).rounded()), 1)

        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: targetWidth,
                pixelsHigh: targetHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            return (SKTexture(image: image), aspect)
        }

        bitmap.size = CGSize(width: targetWidth, height: targetHeight)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = bitmap.cgImage else {
            return (SKTexture(image: image), aspect)
        }
        return (SKTexture(cgImage: cgImage), aspect)
    }

    private func layoutCharacter() {
        guard let characterNode, size.width > 0, size.height > 0 else { return }
        let margin = max(1, min(size.width, size.height) * 0.025)
        let available = CGSize(
            width: max(1, size.width - margin * 2),
            height: max(1, size.height - margin * 2)
        )
        switch contentMode {
        case .fit:
            let heightForWidth = available.width / max(artworkAspect, 0.01)
            if heightForWidth <= available.height {
                characterNode.size = CGSize(width: available.width, height: heightForWidth)
            } else {
                characterNode.size = CGSize(
                    width: available.height * artworkAspect,
                    height: available.height
                )
            }
            characterNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        case .upperBody:
            let artworkWidth = available.width * 1.42
            let artworkHeight = artworkWidth / max(artworkAspect, 0.01)
            characterNode.size = CGSize(width: artworkWidth, height: artworkHeight)
            characterNode.position = CGPoint(
                x: size.width / 2,
                y: size.height - margin - artworkHeight / 2
            )
        }
    }

    private func applyMotion(to node: SKSpriteNode?) {
        guard let node, let personality else { return }
        node.removeAction(forKey: Self.motionActionKey)

        if !motionEnabled {
            node.warpGeometry = ButlerRigMotion.identityWarp
            return
        }

        let warps = ButlerRigMotion.warps(
            for: personality,
            intensity: intensity
        )
        let duration = ButlerRigMotion.cycleDuration(for: personality)
        let step = duration / Double(max(warps.count - 1, 1))
        let times = warps.indices.map { NSNumber(value: Double($0) * step) }
        guard
            let action = SKAction.animate(
                withWarps: warps,
                times: times,
                restore: false
            )
        else { return }

        node.warpGeometry = warps.first
        node.run(.repeatForever(action), withKey: Self.motionActionKey)
    }
}

struct ButlerRigBone {
    let center: SIMD2<Float>
    let pivot: SIMD2<Float>
    let radius: SIMD2<Float>
}

struct ButlerRigSkeleton {
    let head: ButlerRigBone
    let chest: ButlerRigBone
    let primaryHand: ButlerRigBone
    let secondaryHand: ButlerRigBone
    let accent: ButlerRigBone?
}

struct ButlerRigPose {
    var rootAngle: Float = 0
    var rootShift: SIMD2<Float> = .zero
    var chestAngle: Float = 0
    var chestShift: SIMD2<Float> = .zero
    var chestScale: SIMD2<Float> = .zero
    var headAngle: Float = 0
    var headShift: SIMD2<Float> = .zero
    var headScale: SIMD2<Float> = .zero
    var primaryHandAngle: Float = 0
    var primaryHandShift: SIMD2<Float> = .zero
    var secondaryHandAngle: Float = 0
    var secondaryHandShift: SIMD2<Float> = .zero
    var accentScale: SIMD2<Float> = .zero
}

enum ButlerRigMotion {
    static let columns = 8
    static let rows = 12
    static let sampleCount = 32

    static let sourcePositions: [SIMD2<Float>] = {
        (0...rows).flatMap { row in
            (0...columns).map { column in
                SIMD2(
                    Float(column) / Float(columns),
                    Float(row) / Float(rows)
                )
            }
        }
    }()

    static var identityWarp: SKWarpGeometryGrid {
        SKWarpGeometryGrid(
            columns: columns,
            rows: rows,
            sourcePositions: sourcePositions,
            destinationPositions: sourcePositions
        )
    }

    static func cycleDuration(for personality: ButlerPersonality) -> TimeInterval {
        switch personality {
        case .shy: 5.8
        case .insistent: 4.6
        case .zombie: 6.4
        }
    }

    static func warps(
        for personality: ButlerPersonality,
        intensity: Float = 1
    ) -> [SKWarpGeometryGrid] {
        (0...sampleCount).map { sample in
            let phase = Float(sample) / Float(sampleCount)
            let destinations = destinationPositions(
                for: personality,
                phase: phase,
                intensity: intensity
            )
            return SKWarpGeometryGrid(
                columns: columns,
                rows: rows,
                sourcePositions: sourcePositions,
                destinationPositions: destinations
            )
        }
    }

    static func destinationPositions(
        for personality: ButlerPersonality,
        phase: Float,
        intensity: Float = 1
    ) -> [SIMD2<Float>] {
        let skeleton = skeleton(for: personality)
        let pose = pose(for: personality, phase: phase)
        let clampedIntensity = min(max(intensity, 0), 1.25)

        return sourcePositions.map { source in
            var point = applyRoot(pose, to: source, intensity: clampedIntensity)
            point = apply(
                skeleton.chest,
                angle: pose.chestAngle,
                shift: pose.chestShift,
                scale: pose.chestScale,
                to: point,
                intensity: clampedIntensity
            )
            point = apply(
                skeleton.head,
                angle: pose.headAngle,
                shift: pose.headShift,
                scale: pose.headScale,
                to: point,
                intensity: clampedIntensity
            )
            point = apply(
                skeleton.primaryHand,
                angle: pose.primaryHandAngle,
                shift: pose.primaryHandShift,
                to: point,
                intensity: clampedIntensity
            )
            point = apply(
                skeleton.secondaryHand,
                angle: pose.secondaryHandAngle,
                shift: pose.secondaryHandShift,
                to: point,
                intensity: clampedIntensity
            )
            if let accent = skeleton.accent {
                point = apply(
                    accent,
                    scale: pose.accentScale,
                    to: point,
                    intensity: clampedIntensity
                )
            }
            return point
        }
    }

    private static func skeleton(for personality: ButlerPersonality) -> ButlerRigSkeleton {
        switch personality {
        case .shy:
            ButlerRigSkeleton(
                head: .init(center: .init(0.53, 0.82), pivot: .init(0.57, 0.66), radius: .init(0.37, 0.26)),
                chest: .init(center: .init(0.53, 0.49), pivot: .init(0.54, 0.38), radius: .init(0.40, 0.27)),
                primaryHand: .init(center: .init(0.34, 0.68), pivot: .init(0.40, 0.55), radius: .init(0.23, 0.22)),
                secondaryHand: .init(center: .init(0.55, 0.46), pivot: .init(0.66, 0.41), radius: .init(0.22, 0.15)),
                accent: nil
            )
        case .insistent:
            ButlerRigSkeleton(
                head: .init(center: .init(0.66, 0.81), pivot: .init(0.69, 0.68), radius: .init(0.31, 0.24)),
                chest: .init(center: .init(0.66, 0.48), pivot: .init(0.65, 0.38), radius: .init(0.37, 0.29)),
                primaryHand: .init(center: .init(0.27, 0.70), pivot: .init(0.38, 0.58), radius: .init(0.27, 0.20)),
                secondaryHand: .init(center: .init(0.36, 0.50), pivot: .init(0.51, 0.44), radius: .init(0.29, 0.18)),
                accent: nil
            )
        case .zombie:
            ButlerRigSkeleton(
                head: .init(center: .init(0.50, 0.82), pivot: .init(0.58, 0.68), radius: .init(0.32, 0.25)),
                chest: .init(center: .init(0.65, 0.49), pivot: .init(0.62, 0.37), radius: .init(0.38, 0.30)),
                primaryHand: .init(center: .init(0.27, 0.60), pivot: .init(0.39, 0.52), radius: .init(0.23, 0.19)),
                secondaryHand: .init(center: .init(0.45, 0.58), pivot: .init(0.54, 0.51), radius: .init(0.22, 0.19)),
                accent: .init(center: .init(0.50, 0.96), pivot: .init(0.50, 0.89), radius: .init(0.28, 0.12))
            )
        }
    }

    private static func pose(for personality: ButlerPersonality, phase: Float) -> ButlerRigPose {
        let tau = Float.pi * 2
        let wave = sin(tau * phase)
        let breath = sin(tau * phase - .pi / 2)

        switch personality {
        case .shy:
            let yawn = circularPulse(phase, center: 0.57, width: 0.22)
            return ButlerRigPose(
                rootAngle: radians(0.50 * wave),
                chestAngle: radians(0.65 * sin(tau * phase + 0.5)),
                chestShift: .init(0, 0.0015 * breath),
                chestScale: .init(0.002 * breath, 0.007 * breath),
                headAngle: radians(0.70 * wave - 2.6 * yawn),
                headShift: .init(-0.002 * yawn, -0.010 * yawn),
                headScale: .init(0.004 * yawn, 0.007 * yawn),
                primaryHandAngle: radians(1.0 * wave + 4.8 * yawn),
                primaryHandShift: .init(0.004 * yawn, 0.011 * yawn),
                secondaryHandAngle: radians(-0.8 * wave),
                secondaryHandShift: .init(0.002 * wave, 0.002 * breath)
            )
        case .insistent:
            let flourish = circularPulse(phase, center: 0.43, width: 0.24)
            let counterWave = sin(tau * phase + 1.1)
            return ButlerRigPose(
                rootAngle: radians(0.50 * wave),
                rootShift: .init(0.001 * wave, 0),
                chestAngle: radians(-0.45 * wave),
                chestShift: .init(0, 0.001 * breath),
                chestScale: .init(0.001 * breath, 0.005 * breath),
                headAngle: radians(-0.35 * wave + 2.0 * flourish),
                headShift: .init(-0.002 * flourish, -0.006 * flourish),
                primaryHandAngle: radians(-1.0 * counterWave - 4.5 * flourish),
                primaryHandShift: .init(-0.006 * flourish, 0.009 * flourish),
                secondaryHandAngle: radians(0.8 * counterWave + 2.8 * flourish),
                secondaryHandShift: .init(-0.003 * flourish, 0.004 * flourish)
            )
        case .zombie:
            let lurch = circularPulse(phase, center: 0.68, width: 0.18)
            let stagger = sin(tau * phase + 0.7) + 0.28 * sin(tau * phase * 3)
            let handOne = sin(tau * phase + 1.3)
            let handTwo = sin(tau * phase - 0.9)
            let brainPulse = 0.5 + 0.5 * sin(tau * phase * 2 + 0.4)
            return ButlerRigPose(
                rootAngle: radians(1.55 * stagger + 0.8 * lurch),
                rootShift: .init(0.002 * stagger, -0.002 * lurch),
                chestAngle: radians(-1.0 * sin(tau * phase + 0.15)),
                chestShift: .init(0.001 * stagger, 0.002 * breath),
                chestScale: .init(0.003 * breath, 0.009 * breath),
                headAngle: radians(-3.5 * sin(tau * phase + 0.9) - 1.5 * lurch),
                headShift: .init(-0.004 * lurch, -0.008 * lurch),
                headScale: .init(0.002 * breath, 0.004 * breath),
                primaryHandAngle: radians(5.0 * handOne),
                primaryHandShift: .init(-0.004 * handOne, 0.006 * handOne),
                secondaryHandAngle: radians(-5.5 * handTwo),
                secondaryHandShift: .init(0.004 * handTwo, 0.006 * handTwo),
                accentScale: .init(0.012 * brainPulse, 0.020 * brainPulse)
            )
        }
    }

    private static func applyRoot(
        _ pose: ButlerRigPose,
        to point: SIMD2<Float>,
        intensity: Float
    ) -> SIMD2<Float> {
        let pivot = SIMD2<Float>(0.5, 0.035)
        let weight = smoothStep(0.03, 0.94, point.y)
        let transformed =
            rotated(point, around: pivot, by: pose.rootAngle * intensity)
            + pose.rootShift * weight * intensity
        return point + (transformed - point) * weight
    }

    private static func apply(
        _ bone: ButlerRigBone,
        angle: Float = 0,
        shift: SIMD2<Float> = .zero,
        scale: SIMD2<Float> = .zero,
        to point: SIMD2<Float>,
        intensity: Float
    ) -> SIMD2<Float> {
        let normalized = SIMD2(
            (point.x - bone.center.x) / max(bone.radius.x, 0.001),
            (point.y - bone.center.y) / max(bone.radius.y, 0.001)
        )
        let distance = sqrt(normalized.x * normalized.x + normalized.y * normalized.y)
        guard distance < 1 else { return point }

        let weight = smoothStep(1, 0, distance)
        var relative = point - bone.pivot
        relative *= SIMD2<Float>(repeating: 1) + scale * intensity
        let cosine = cos(angle * intensity)
        let sine = sin(angle * intensity)
        let rotatedRelative = SIMD2(
            relative.x * cosine - relative.y * sine,
            relative.x * sine + relative.y * cosine
        )
        let transformed = bone.pivot + rotatedRelative + shift * intensity
        return point + (transformed - point) * weight
    }

    private static func rotated(
        _ point: SIMD2<Float>,
        around pivot: SIMD2<Float>,
        by angle: Float
    ) -> SIMD2<Float> {
        let relative = point - pivot
        let cosine = cos(angle)
        let sine = sin(angle)
        return pivot
            + SIMD2(
                relative.x * cosine - relative.y * sine,
                relative.x * sine + relative.y * cosine
            )
    }

    private static func circularPulse(
        _ phase: Float,
        center: Float,
        width: Float
    ) -> Float {
        let directDistance = abs(phase - center)
        let distance = min(directDistance, 1 - directDistance)
        return smoothStep(width, 0, distance)
    }

    private static func smoothStep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        guard edge0 != edge1 else { return value < edge0 ? 0 : 1 }
        let amount = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return amount * amount * (3 - 2 * amount)
    }

    private static func radians(_ degrees: Float) -> Float {
        degrees * .pi / 180
    }
}
