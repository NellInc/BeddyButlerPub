import AppKit
import SpriteKit
import SwiftUI

enum ButlerRigContentMode {
    case fit
    case upperBody
}

/// Renders each original character as one intact sprite and gives it
/// personality-specific choreography using only translation, rotation, and
/// uniform scale. Keeping the artwork rigid avoids distortions around the face,
/// hands, and clothing.
struct ButlerRiggedView: NSViewRepresentable {
    let personality: ButlerPersonality
    let motionEnabled: Bool
    let isVisible: Bool
    let contentMode: ButlerRigContentMode
    let intensity: Float

    func makeNSView(context: Context) -> ButlerMotionSKView {
        let view = ButlerMotionSKView()
        view.configure(
            personality: personality,
            motionEnabled: motionEnabled,
            isVisible: isVisible,
            contentMode: contentMode,
            intensity: intensity
        )
        return view
    }

    func updateNSView(_ nsView: ButlerMotionSKView, context: Context) {
        nsView.configure(
            personality: personality,
            motionEnabled: motionEnabled,
            isVisible: isVisible,
            contentMode: contentMode,
            intensity: intensity
        )
    }

    static func dismantleNSView(_ nsView: ButlerMotionSKView, coordinator: ()) {
        nsView.stopRendering()
    }
}

final class ButlerMotionSKView: SKView {
    private let motionScene = ButlerMotionScene()
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
        presentScene(motionScene)
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
        motionScene.configure(
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
            presentScene(motionScene)
        }

        guard
            permitsOccludedRendering
                || window?.occlusionState.contains(.visible) == true
        else {
            isPaused = true
            return
        }
        isPaused = false
        guard !motionEnabled else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.renderGeneration == generation, !self.motionEnabled else { return }
            self.isPaused = true
        }
    }
}

final class ButlerMotionScene: SKScene {
    static let maximumTextureHeight = 384

    private var characterNode: SKSpriteNode?
    private var personality: ButlerPersonality?
    private var motionEnabled = true
    private var intensity: Float = 1
    private var contentMode: ButlerRigContentMode = .fit
    private var artworkAspect: CGFloat = 0.75
    private var neutralPosition = CGPoint.zero
    private var elapsedTime: TimeInterval = 0
    private var lastUpdateTime: TimeInterval?

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

    override func update(_ currentTime: TimeInterval) {
        guard motionEnabled else { return }
        if let lastUpdateTime {
            let elapsedFrame = min(max(currentTime - lastUpdateTime, 0), 0.1)
            elapsedTime += elapsedFrame
        }
        lastUpdateTime = currentTime
        applyCurrentPose()
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

        if personalityChanged {
            elapsedTime = 0
            lastUpdateTime = nil
            replaceCharacter(with: requestedPersonality)
        }
        if contentModeChanged {
            layoutCharacter()
        }
        if motionChanged {
            lastUpdateTime = nil
        }
        if personalityChanged || motionChanged || intensityChanged || contentModeChanged {
            applyCurrentPose()
        }
    }

    func applyPose(at elapsedTime: TimeInterval) {
        self.elapsedTime = max(elapsedTime, 0)
        applyCurrentPose()
    }

    private func replaceCharacter(with personality: ButlerPersonality) {
        guard let image = NSImage(named: personality.rigAssetName) else { return }

        let (texture, aspect) = makeDisplayTexture(from: image)
        texture.filteringMode = .linear
        let newNode = SKSpriteNode(texture: texture)
        newNode.name = "animated-\(personality.rawValue)-butler"
        newNode.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        newNode.blendMode = .alpha

        artworkAspect = aspect

        let oldNode = characterNode
        characterNode = newNode
        addChild(newNode)
        layoutCharacter()

        guard let oldNode else { return }
        if motionEnabled {
            newNode.alpha = 0
            newNode.run(.fadeIn(withDuration: 0.22))
            oldNode.run(
                .sequence([
                    .fadeOut(withDuration: 0.18),
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
        // SpriteKit's linear texture filter still aliases when it minifies the
        // 1K character exports into an 80 to 112 point SwiftUI view. Prefilter
        // the source with AppKit's high-quality scaler so SpriteKit only has a
        // modest final resize to perform on Retina displays.
        if pixelSize.height <= CGFloat(Self.maximumTextureHeight) {
            return (SKTexture(image: image), aspect)
        }
        let targetHeight = min(
            max(Int(pixelSize.height.rounded()), 1),
            Self.maximumTextureHeight
        )
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
        let margin = max(1, min(size.width, size.height) * 0.04)
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
            neutralPosition = CGPoint(x: size.width / 2, y: size.height / 2)
        case .upperBody:
            let artworkWidth = available.width * 1.38
            let artworkHeight = artworkWidth / max(artworkAspect, 0.01)
            characterNode.size = CGSize(width: artworkWidth, height: artworkHeight)
            neutralPosition = CGPoint(
                x: size.width / 2,
                y: size.height - margin - artworkHeight / 2
            )
        }
        applyCurrentPose()
    }

    private func applyCurrentPose() {
        guard let characterNode, let personality else { return }
        let duration = ButlerRigidMotion.cycleDuration(for: personality)
        let phase = Float((elapsedTime / duration).truncatingRemainder(dividingBy: 1))
        let pose =
            motionEnabled
            ? ButlerRigidMotion.pose(for: personality, phase: phase, intensity: intensity)
            : .identity

        characterNode.position = CGPoint(
            x: neutralPosition.x + CGFloat(pose.translation.x) * size.width,
            y: neutralPosition.y + CGFloat(pose.translation.y) * size.height
        )
        characterNode.zRotation = CGFloat(pose.rotation)
        characterNode.setScale(CGFloat(pose.scale))
    }
}

struct ButlerRigidPose: Equatable {
    var translation: SIMD2<Float> = .zero
    var rotation: Float = 0
    var scale: Float = 1

    static let identity = ButlerRigidPose()
}

enum ButlerRigidMotion {
    static func cycleDuration(for personality: ButlerPersonality) -> TimeInterval {
        switch personality {
        case .shy: 5.2
        case .insistent: 4.1
        case .zombie: 5.8
        }
    }

    static func pose(
        for personality: ButlerPersonality,
        phase: Float,
        intensity: Float = 1
    ) -> ButlerRigidPose {
        let normalizedPhase = phase - floor(phase)
        let rawPose = rawPose(for: personality, phase: normalizedPhase)
        let clampedIntensity = min(max(intensity, 0), 1.25)
        return ButlerRigidPose(
            translation: rawPose.translation * clampedIntensity,
            rotation: rawPose.rotation * clampedIntensity,
            scale: 1 + (rawPose.scale - 1) * clampedIntensity
        )
    }

    private static func rawPose(
        for personality: ButlerPersonality,
        phase: Float
    ) -> ButlerRigidPose {
        let tau = Float.pi * 2
        let wave = sin(tau * phase)
        let breath = sin(tau * phase - .pi / 2)

        switch personality {
        case .shy:
            let yawn = circularPulse(phase, center: 0.58, width: 0.20)
            return ButlerRigidPose(
                translation: .init(
                    0.009 * wave,
                    0.010 * breath - 0.024 * yawn
                ),
                rotation: radians(1.7 * wave - 2.8 * yawn),
                scale: 1 + 0.010 * breath - 0.007 * yawn
            )
        case .insistent:
            let flourish = circularPulse(phase, center: 0.43, width: 0.19)
            let emphasis = sin(tau * phase * 2 + 0.35)
            return ButlerRigidPose(
                translation: .init(
                    0.016 * wave + 0.010 * flourish,
                    0.011 * emphasis + 0.020 * flourish
                ),
                rotation: radians(-2.8 * wave + 3.8 * flourish),
                scale: 1 + 0.009 * emphasis + 0.012 * flourish
            )
        case .zombie:
            let lurch = circularPulse(phase, center: 0.68, width: 0.18)
            let stagger = sin(tau * phase + 0.7) + 0.32 * sin(tau * phase * 3)
            return ButlerRigidPose(
                translation: .init(
                    0.024 * stagger,
                    0.012 * breath - 0.024 * lurch
                ),
                rotation: radians(4.3 * stagger + 3.0 * lurch),
                scale: 1 + 0.010 * breath + 0.014 * lurch
            )
        }
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
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func radians(_ degrees: Float) -> Float {
        degrees * .pi / 180
    }
}
