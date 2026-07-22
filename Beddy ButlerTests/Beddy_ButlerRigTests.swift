import XCTest

@testable import Beddy_Butler

final class Beddy_ButlerRigTests: XCTestCase {
    func testRigProducesAClosedFiniteMeshForEveryPersonality() {
        let expectedVertexCount = (ButlerRigMotion.columns + 1) * (ButlerRigMotion.rows + 1)
        XCTAssertEqual(ButlerRigMotion.sourcePositions.count, expectedVertexCount)

        for personality in ButlerPersonality.allCases {
            let warps = ButlerRigMotion.warps(for: personality)
            XCTAssertEqual(warps.count, ButlerRigMotion.sampleCount + 1)
            XCTAssertTrue(warps.allSatisfy { $0.vertexCount == expectedVertexCount })

            for sample in 0...ButlerRigMotion.sampleCount {
                let phase = Float(sample) / Float(ButlerRigMotion.sampleCount)
                let positions = ButlerRigMotion.destinationPositions(
                    for: personality,
                    phase: phase
                )
                XCTAssertEqual(positions.count, expectedVertexCount)
                XCTAssertTrue(
                    positions.allSatisfy {
                        $0.x.isFinite && $0.y.isFinite
                            && (-0.12...1.12).contains($0.x)
                            && (-0.12...1.12).contains($0.y)
                    },
                    "\(personality.title) produced an invalid mesh at phase \(phase)"
                )
            }

            let start = ButlerRigMotion.destinationPositions(for: personality, phase: 0)
            let end = ButlerRigMotion.destinationPositions(for: personality, phase: 1)
            for (first, last) in zip(start, end) {
                XCTAssertEqual(first.x, last.x, accuracy: 0.000_01)
                XCTAssertEqual(first.y, last.y, accuracy: 0.000_01)
            }
        }
    }

    func testEachPersonalityHasMeaningfulLocalizedDeformation() {
        for personality in ButlerPersonality.allCases {
            let maximumMovement =
                (0...ButlerRigMotion.sampleCount)
                .map { sample -> Float in
                    let phase = Float(sample) / Float(ButlerRigMotion.sampleCount)
                    let positions = ButlerRigMotion.destinationPositions(
                        for: personality,
                        phase: phase
                    )
                    return zip(ButlerRigMotion.sourcePositions, positions)
                        .map { source, destination in
                            let offset = destination - source
                            return sqrt(offset.x * offset.x + offset.y * offset.y)
                        }
                        .max() ?? 0
                }
                .max() ?? 0

            XCTAssertGreaterThan(
                maximumMovement,
                0.012,
                "\(personality.title) should visibly articulate at least one rigged region"
            )
        }
    }

    func testZeroIntensityIsTheReduceMotionIdentityPose() {
        for personality in ButlerPersonality.allCases {
            let positions = ButlerRigMotion.destinationPositions(
                for: personality,
                phase: 0.37,
                intensity: 0
            )
            XCTAssertEqual(positions, ButlerRigMotion.sourcePositions)
        }
    }
}
