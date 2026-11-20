// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TPHaptics",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TPHaptics",
            path: "Sources/TPHaptics"
        )
    ],
    swiftLanguageVersions: [.v5]
)
