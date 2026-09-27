// swift-tools-version: 6.4
// Modified by Chaehyeon Lee (2026): BarNook package branding.
import PackageDescription

let package = Package(
    name: "BarNook",
    platforms: [.macOS(.v27)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(
            name: "BarNookCore",
            path: "Sources/BarNookCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "BarNook",
            dependencies: ["BarNookCore", "Sparkle"],
            path: "Sources/BarNook",
            swiftSettings: [.swiftLanguageMode(.v6)],
            // bundle.sh puts Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(
            name: "Probe",
            dependencies: ["BarNookCore"],
            path: "Sources/Probe",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Fixture",
            path: "Sources/Fixture",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BarNookTests",
            dependencies: ["BarNook", "BarNookCore"],
            path: "Tests/BarNookTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Drives the app in a Tart guest. Skipped unless BARNOOK_VM is set.
        // scripts/vm-test.sh runs it.
        .testTarget(
            name: "BarNookVMTests",
            dependencies: ["BarNookCore"],
            path: "Tests/BarNookVMTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
