// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Patter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Patter", targets: ["Patter"]),
        .library(name: "PatterCore", targets: ["PatterCore"]),
    ],
    targets: [
        // Foundation-only: event parsing, the session state machine, formatting.
        // No AppKit/SwiftUI, so it builds and tests anywhere Swift runs.
        .target(name: "PatterCore"),

        // The macOS app: menu bar, floating HUD, notch.
        .executableTarget(name: "Patter", dependencies: ["PatterCore"]),

        .testTarget(name: "PatterCoreTests", dependencies: ["PatterCore"]),
    ]
)
