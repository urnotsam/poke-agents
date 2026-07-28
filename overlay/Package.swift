// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PokeAgents",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic, no AppKit, so it runs without a window server.
        .target(name: "PokeAgentsCore"),
        .executableTarget(name: "PokeAgents", dependencies: ["PokeAgentsCore"]),
        // XCTest ships with Xcode, not the Command Line Tools, so tests run as
        // a plain executable against a small assertion harness.
        .executableTarget(name: "PokeAgentsTests", dependencies: ["PokeAgentsCore"]),
    ]
)
