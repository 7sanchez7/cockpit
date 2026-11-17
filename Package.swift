// swift-tools-version: 6.2
// Sert seulement aux tests : `make test` compile le cœur sans interface (Store, Collecte, Sources).
// L'app se construit avec project.yml (XcodeGen).
import PackageDescription

let reglages: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Cockpit",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "CockpitNoyau", path: "Cockpit", exclude: ["App", "Design", "Ecrans", "Composants"],
                swiftSettings: reglages, linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "CockpitTests", dependencies: ["CockpitNoyau"], path: "CockpitTests", swiftSettings: reglages),
    ]
)
