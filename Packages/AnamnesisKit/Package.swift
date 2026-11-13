// swift-tools-version: 6.4
import PackageDescription

// Pure logic shared by the app and its extensions. No UIKit/SwiftUI/Speech/ScreenCaptureKit here; SwiftData is
// allowed for the library schema (spec 009, D-028), which only the host app opens.
// macOS is declared only so `swift test` runs on the Mac; every source must stay platform-neutral.
let swiftSettings: [SwiftSetting] = [
    // Capture callbacks arrive on arbitrary queues, so nothing here may default to MainActor (D-012).
    .defaultIsolation(nil)
]

let package = Package(
    name: "AnamnesisKit",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "AnamnesisKit", targets: ["AnamnesisKit"])
    ],
    targets: [
        .target(name: "AnamnesisKit", swiftSettings: swiftSettings),
        .testTarget(name: "AnamnesisKitTests", dependencies: ["AnamnesisKit"], swiftSettings: swiftSettings)
    ],
    swiftLanguageModes: [.v6]
)
