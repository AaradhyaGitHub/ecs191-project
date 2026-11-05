// swift-tools-version: 6.0
// The app's logic, one module per area. Views stay in the app target (ios/MuscleMap).
// Builds for macOS too, so `swift test` runs these tests in seconds without the simulator:
//   swift test --package-path ios/MuscleMapKit --filter <Module>Tests
import PackageDescription

let package = Package(
    name: "MuscleMapKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Models", targets: ["Models"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "LiftCore", targets: ["LiftCore"]),
        .library(name: "BodyCore", targets: ["BodyCore"]),
        .library(name: "GoalsCore", targets: ["GoalsCore"]),
    ],
    targets: [
        .target(name: "Models"),
        .target(name: "Networking", dependencies: ["Models"]),
        // Resources/exercise_library.json: the bundled exercise library (server/seed/export_library.py).
        .target(name: "LiftCore", dependencies: ["Models", "Networking"], resources: [.process("Resources")]),
        // Body tab (MuscleLab page): muscle IDs, SVG figure art, sample sessions, workout analysis.
        .target(name: "BodyCore", resources: [.process("Resources")]),
        // Goals tab: goal form rules, card texts, screen state (specs/goals.llm.md).
        .target(name: "GoalsCore", dependencies: ["Models", "Networking"]),
        .testTarget(name: "ModelsTests", dependencies: ["Models"]),
        .testTarget(name: "NetworkingTests", dependencies: ["Networking"]),
        .testTarget(name: "LiftCoreTests", dependencies: ["LiftCore"]),
        .testTarget(name: "BodyCoreTests", dependencies: ["BodyCore"]),
        .testTarget(name: "GoalsCoreTests", dependencies: ["GoalsCore"]),
    ]
)
