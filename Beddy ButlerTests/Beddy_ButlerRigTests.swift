import SpriteKit
import XCTest

@testable import Beddy_Butler

final class Beddy_ButlerRigTests: XCTestCase {
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

            let start = ButlerRigidMotion.pose(for: personality, phase: 0)
            let end = ButlerRigidMotion.pose(for: personality, phase: 1)
            XCTAssertEqual(start.translation.x, end.translation.x, accuracy: 0.000_01)
            XCTAssertEqual(start.translation.y, end.translation.y, accuracy: 0.000_01)
            XCTAssertEqual(start.rotation, end.rotation, accuracy: 0.000_01)
            XCTAssertEqual(start.scale, end.scale, accuracy: 0.000_01)
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
    func testRendererKeepsEveryCharacterAsAnUndeformedSprite() throws {
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
            XCTAssertNil(sprite.warpGeometry)
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
}
