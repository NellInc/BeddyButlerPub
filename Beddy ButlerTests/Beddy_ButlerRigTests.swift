import SpriteKit
import UniformTypeIdentifiers
import XCTest

@testable import Beddy_Butler

@MainActor
private final class LiveFrameProbe: NSObject, @preconcurrency SKSceneDelegate {
    var timestamps: [Double] = []
    func didFinishUpdate(for scene: SKScene) { timestamps.append(CACurrentMediaTime()) }
}

final class Beddy_ButlerRigTests: XCTestCase {
    @MainActor
    func testLiveAnimationTimingCapture() async throws {
        guard let directory = ProcessInfo.processInfo.environment["BEDDY_MOTION_PROOF_DIR"] else {
            throw XCTSkip("Opt-in live window timing capture requires BEDDY_MOTION_PROOF_DIR")
        }
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let window = NSWindow(
            contentRect: NSRect(x: 180, y: 180, width: 720, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Beddy Butler animation timing review"
        window.isReleasedWhenClosed = false
        var views: [ButlerMotionSKView] = []
        var probes: [LiveFrameProbe] = []
        for (i, personality) in ButlerPersonality.allCases.enumerated() {
            let view = ButlerMotionSKView(frame: NSRect(x: i * 240, y: 0, width: 240, height: 400))
            window.contentView!.addSubview(view)
            views.append(view)
            let probe = LiveFrameProbe()
            probes.append(probe)
            view.configure(
                personality: personality, motionEnabled: true, isVisible: true,
                contentMode: .fit, intensity: 1)
        }
        window.makeKeyAndOrderFront(nil)
        defer {
            for view in views { view.stopRendering() }
            window.close()
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        for (view, probe) in zip(views, probes) {
            try XCTUnwrap(view.scene).delegate = probe
            probe.timestamps = []
        }
        for sample in 0..<4 {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            for (i, view) in views.enumerated() {
                let texture = try XCTUnwrap(view.texture(from: try XCTUnwrap(view.scene)))
                let bitmap = NSBitmapImageRep(cgImage: texture.cgImage())
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(
                        to: output.appendingPathComponent(
                            "native-\(ButlerPersonality.allCases[i].rawValue)-\(sample).png"))
            }
        }
        // Measure separately: texture readback and PNG encoding deliberately stall the render thread.
        for probe in probes { probe.timestamps = [] }
        try await Task.sleep(nanoseconds: 12_000_000_000)
        var results: [[String: Any]] = []
        for (i, probe) in probes.enumerated() {
            let intervals = zip(probe.timestamps.dropFirst(), probe.timestamps).map { ($0 - $1) * 1000 }.sorted()
            XCTAssertGreaterThan(intervals.count, 100, "Live renderer must actually update")
            guard !intervals.isEmpty else { continue }
            results.append([
                "avatar": ButlerPersonality.allCases[i].rawValue, "frames": intervals.count,
                "medianMs": intervals[intervals.count / 2], "p95Ms": intervals[Int(Double(intervals.count) * 0.95)],
                "maxMs": intervals.last!, "gapsOver50Ms": intervals.filter { $0 > 50 }.count,
            ])
        }
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("native-timing.json"))
        var singleResults: [[String: Any]] = []
        for (i, view) in views.enumerated() {
            for other in views { other.stopRendering() }
            view.configure(
                personality: ButlerPersonality.allCases[i], motionEnabled: true,
                isVisible: true, contentMode: .fit, intensity: 1)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try XCTUnwrap(view.scene).delegate = probes[i]
            probes[i].timestamps = []
            try await Task.sleep(nanoseconds: 12_000_000_000)
            let t = probes[i].timestamps
            let intervals = zip(t.dropFirst(), t).map { ($0 - $1) * 1000 }.sorted()
            XCTAssertGreaterThan(intervals.count, 100)
            guard !intervals.isEmpty else { continue }
            singleResults.append([
                "avatar": ButlerPersonality.allCases[i].rawValue, "frames": intervals.count,
                "medianMs": intervals[intervals.count / 2], "p95Ms": intervals[Int(Double(intervals.count) * 0.95)],
                "maxMs": intervals.last!, "gapsOver50Ms": intervals.filter { $0 > 50 }.count,
            ])
        }
        try JSONSerialization.data(withJSONObject: singleResults, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("native-single-timing.json"))
    }

    @MainActor
    func testArticulatedAssetsLoopAndRespectReducedMotion() throws {
        for personality in ButlerPersonality.allCases {
            let motion = try XCTUnwrap(ButlerArticulatedMotion.load(personality))
            // geometry(at:) interpolates the last frame back into frame 0, so the wrap step
            // must be no larger than an ordinary step or the loop visibly jumps.
            func frameDelta(_ a: Int, _ b: Int) -> Float {
                (0..<motion.vertexCount).map { i in
                    simd_length(
                        motion.positions[a * motion.vertexCount + i] - motion.positions[b * motion.vertexCount + i])
                }.max() ?? 0
            }
            let largestStep = (0..<(motion.frames - 1)).map { frameDelta($0, $0 + 1) }.max() ?? 0
            XCTAssertGreaterThan(largestStep, 0, "\(personality.title) motion must move")
            XCTAssertLessThanOrEqual(
                frameDelta(motion.frames - 1, 0), largestStep * 1.5, "\(personality.title) loop seam")
            let rest = motion.geometry(at: 2, intensity: 0)
            for i in 0..<rest.vertexCount {
                XCTAssertEqual(rest.destPosition(at: i), rest.sourcePosition(at: i))
            }
            let scene = ButlerMotionScene()
            scene.configure(personality: personality, motionEnabled: true, contentMode: .fit, intensity: 1)
            let sprite = try XCTUnwrap(scene.children.compactMap { $0 as? SKSpriteNode }.last)
            XCTAssertNotNil(sprite.warpGeometry)
            scene.configure(personality: personality, motionEnabled: false, contentMode: .fit, intensity: 1)
            XCTAssertNil(sprite.warpGeometry)
            scene.configure(personality: personality, motionEnabled: true, contentMode: .fit, intensity: 1)
            XCTAssertEqual(sprite.subdivisionLevels, 0)
            // Validate the live scene's interpolated mesh and native GPU output.
            scene.applyPose(at: 0)
            let first = try XCTUnwrap(sprite.warpGeometry as? SKWarpGeometryGrid)
            scene.applyPose(at: motion.duration * 0.43)
            let second = try XCTUnwrap(sprite.warpGeometry as? SKWarpGeometryGrid)
            XCTAssertTrue(
                (0..<first.vertexCount).contains {
                    first.destPosition(at: $0) != second.destPosition(at: $0)
                }, "Native poses must change")
            for sample in 0...120 {
                let pose = motion.geometry(at: motion.duration * Double(sample) / 120, intensity: 1)
                for i in 0..<pose.vertexCount {
                    let p = pose.destPosition(at: i)
                    XCTAssertTrue(p.x.isFinite && p.y.isFinite)
                }
            }
            let view = SKView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
            view.presentScene(scene)
            var renderedFrames: [Data] = []
            for (index, time) in [0.0, motion.duration * 0.43].enumerated() {
                scene.applyPose(at: time)
                let texture = try XCTUnwrap(view.texture(from: sprite))
                let bitmap = NSBitmapImageRep(cgImage: texture.cgImage())
                let pixels = try XCTUnwrap(bitmap.bitmapData)
                XCTAssertTrue(
                    (0..<(bitmap.bytesPerRow * bitmap.pixelsHigh)).contains { pixels[$0] != 0 }, "Blank native render")
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                renderedFrames.append(png)
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: UTType.png.identifier)
                attachment.name = "beddy-native-\(personality.rawValue)-\(index).png"
                attachment.lifetime = .deleteOnSuccess
                add(attachment)
            }
            XCTAssertNotEqual(renderedFrames[0], renderedFrames[1], "Native poses must visibly change")
            view.presentScene(nil)
        }
        XCTAssertNil(ButlerArticulatedMotion(data: Data()))
        XCTAssertNil(ButlerArticulatedMotion(data: Data(repeating: 0, count: 32)))
    }

    func testRigidChoreographyIsClosedFiniteAndVisuallySafe() {
        for personality in ButlerPersonality.allCases {
            for sample in 0...120 {
                let phase = Float(sample) / 120
                let pose = ButlerRigidMotion.pose(for: personality, phase: phase)

                XCTAssertTrue(pose.translation.x.isFinite)
                XCTAssertTrue(pose.translation.y.isFinite)
                XCTAssertTrue(pose.rotation.isFinite)
                XCTAssertTrue(pose.scale.isFinite)
                XCTAssertTrue((-0.06...0.06).contains(pose.translation.x))
                XCTAssertTrue((-0.06...0.06).contains(pose.translation.y))
                XCTAssertLessThan(abs(pose.rotation), Float.pi / 18)
                XCTAssertTrue((0.94...1.06).contains(pose.scale))
            }

            // pose(phase:) wraps phase 1 back to 0, so compare against the end of the cycle.
            let start = ButlerRigidMotion.pose(for: personality, phase: 0)
            let end = ButlerRigidMotion.pose(for: personality, phase: 0.9999)
            XCTAssertEqual(start.translation.x, end.translation.x, accuracy: 0.001)
            XCTAssertEqual(start.translation.y, end.translation.y, accuracy: 0.001)
            XCTAssertEqual(start.rotation, end.rotation, accuracy: 0.001)
            XCTAssertEqual(start.scale, end.scale, accuracy: 0.001)
        }
    }

    func testEveryPersonalityNowHasClearlyVisibleMovement() {
        for personality in ButlerPersonality.allCases {
            let poses = (0...120).map { sample in
                ButlerRigidMotion.pose(
                    for: personality,
                    phase: Float(sample) / 120
                )
            }
            let maximumTranslation =
                poses.map { pose in
                    sqrt(
                        pose.translation.x * pose.translation.x
                            + pose.translation.y * pose.translation.y
                    )
                }.max() ?? 0
            let maximumRotation = poses.map { abs($0.rotation) }.max() ?? 0
            let maximumScaleChange = poses.map { abs($0.scale - 1) }.max() ?? 0

            XCTAssertGreaterThan(maximumTranslation, 0.014, personality.title)
            XCTAssertGreaterThan(maximumRotation, 0.03, personality.title)
            XCTAssertGreaterThan(maximumScaleChange, 0.006, personality.title)
        }
    }

    func testPersonalitiesHaveDistinctChoreography() {
        let phases: [Float] = [0.17, 0.43, 0.68, 0.89]
        let shy = phases.map { ButlerRigidMotion.pose(for: .shy, phase: $0) }
        let insistent = phases.map { ButlerRigidMotion.pose(for: .insistent, phase: $0) }
        let zombie = phases.map { ButlerRigidMotion.pose(for: .zombie, phase: $0) }

        XCTAssertNotEqual(shy, insistent)
        XCTAssertNotEqual(insistent, zombie)
        XCTAssertNotEqual(shy, zombie)
    }

    func testZeroIntensityIsTheReduceMotionIdentityPose() {
        for personality in ButlerPersonality.allCases {
            let pose = ButlerRigidMotion.pose(
                for: personality,
                phase: 0.37,
                intensity: 0
            )
            XCTAssertEqual(pose, .identity)
        }
    }

    @MainActor
    func testRendererUsesArticulatedMeshAndOriginalTexture() throws {
        let scene = ButlerMotionScene()
        scene.size = CGSize(width: 300, height: 400)

        for personality in ButlerPersonality.allCases {
            scene.configure(
                personality: personality,
                motionEnabled: true,
                contentMode: .fit,
                intensity: 1
            )
            scene.applyPose(at: ButlerRigidMotion.cycleDuration(for: personality) * 0.43)

            let sprite = try XCTUnwrap(
                scene.children.compactMap { $0 as? SKSpriteNode }.last,
                "Missing sprite for \(personality.title)"
            )
            XCTAssertNotNil(sprite.warpGeometry)
            XCTAssertEqual(sprite.xScale, sprite.yScale, accuracy: 0.000_01)
            let texture = try XCTUnwrap(sprite.texture)
            XCTAssertEqual(texture.filteringMode, .linear)
            XCTAssertLessThanOrEqual(
                texture.cgImage().height,
                ButlerMotionScene.maximumTextureHeight,
                "\(personality.title) should be prefiltered before SpriteKit minifies it"
            )
        }
    }

    @MainActor
    func testVisibilityPollingStopsWhenWindowClosesAndResumesOnReopen() async throws {
        let (window, view) = makeRigWindow(motionEnabled: true)
        defer {
            view.stopRendering()
            window.close()
        }
        try await waitForOnScreen(window)
        let pollingStarted = await waitUntil { view.isVisibilityPollingActive }
        XCTAssertTrue(pollingStarted)
        XCTAssertFalse(view.isPaused)

        window.close()
        XCTAssertFalse(view.isVisibilityPollingActive, "Closing must stop polling immediately")
        XCTAssertTrue(view.isPaused)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertFalse(view.isVisibilityPollingActive, "Polling must stay stopped while closed")
        XCTAssertTrue(view.isPaused, "Rendering must stay paused while closed")

        window.orderFrontRegardless()
        let pollingResumed = await waitUntil { view.isVisibilityPollingActive }
        XCTAssertTrue(pollingResumed, "Reopening must resume polling")
        let renderingResumed = await waitUntil { !view.isPaused }
        XCTAssertTrue(renderingResumed, "Reopening must resume the animated preview")
    }

    @MainActor
    func testReducedMotionPreviewRendersOnlyWhenItsInputsChange() async throws {
        let (window, view) = makeRigWindow(motionEnabled: false)
        defer {
            view.stopRendering()
            window.close()
        }
        try await waitForOnScreen(window)
        let pollingStarted = await waitUntil { view.isVisibilityPollingActive }
        XCTAssertTrue(pollingStarted)
        try await Task.sleep(nanoseconds: 600_000_000)
        let probe = LiveFrameProbe()
        try XCTUnwrap(view.scene).delegate = probe

        try await Task.sleep(nanoseconds: 1_600_000_000)
        XCTAssertLessThanOrEqual(probe.timestamps.count, 1, "An unchanged static preview must stay paused")
        XCTAssertTrue(view.isPaused)

        probe.timestamps = []
        view.configure(personality: .shy, motionEnabled: false, isVisible: true, contentMode: .fit, intensity: 1)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(probe.timestamps.count, 0, "Reapplying the same inputs must not redraw")

        view.setFrameSize(NSSize(width: 200, height: 260))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertGreaterThan(probe.timestamps.count, 0, "Resizing must redraw the static preview")
        XCTAssertTrue(view.isPaused)

        probe.timestamps = []
        view.configure(
            personality: .zombie, motionEnabled: false, isVisible: true, contentMode: .fit, intensity: 1)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertGreaterThan(probe.timestamps.count, 0, "Changing personality must redraw the static preview")
        XCTAssertTrue(view.isPaused)
    }

    @MainActor
    private func makeRigWindow(motionEnabled: Bool) -> (NSWindow, ButlerMotionSKView) {
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 320, height: 420),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        let view = ButlerMotionSKView(frame: NSRect(x: 0, y: 0, width: 240, height: 320))
        window.contentView!.addSubview(view)
        view.configure(
            personality: .shy, motionEnabled: motionEnabled, isVisible: true, contentMode: .fit, intensity: 1)
        window.orderFrontRegardless()
        return (window, view)
    }

    @MainActor
    private func waitForOnScreen(_ window: NSWindow) async throws {
        guard await waitUntil({ window.occlusionState.contains(.visible) }) else {
            throw XCTSkip("Requires a visible window on a live display")
        }
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return true
    }
}
