// swift-tools-version: 6.4
// Modified by Chaehyeon Lee (2026): BarNook package branding; inherited target names remain internal.
import PackageDescription

let package = Package(
    name: "BarNook",
    platforms: [.macOS(.v27)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(
            name: "EllipsisCore",
            path: "Sources/EllipsisCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Ellipsis",
            dependencies: ["EllipsisCore", "Sparkle"],
            path: "Sources/Ellipsis",
            swiftSettings: [.swiftLanguageMode(.v6)],
            // bundle.sh puts Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(
            name: "Probe",
            dependencies: ["EllipsisCore"],
            path: "Sources/Probe",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Fixture",
            path: "Sources/Fixture",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "EllipsisTests",
            dependencies: ["Ellipsis", "EllipsisCore"],
            path: "Tests/EllipsisTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Drives the app in a Tart guest. Skipped unless ELLIPSIS_VM is set.
        // scripts/vm-test.sh runs it.
        .testTarget(
            name: "EllipsisVMTests",
            dependencies: ["EllipsisCore"],
            path: "Tests/EllipsisVMTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
