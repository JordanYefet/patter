// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CCPulse",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CCPulse", targets: ["CCPulse"]),
        .library(name: "PulseCore", targets: ["PulseCore"]),
    ],
    targets: [
        // Foundation-only: event parsing, the session state machine, formatting.
        // No AppKit/SwiftUI, so it builds and tests anywhere Swift runs.
        .target(name: "PulseCore"),

        // The macOS app: menu bar, floating HUD, notch.
        .executableTarget(name: "CCPulse", dependencies: ["PulseCore"]),

        .testTarget(name: "PulseCoreTests", dependencies: ["PulseCore"]),
    ]
)
