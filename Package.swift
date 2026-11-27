// swift-tools-version: 6.0
//
// Test harness for Klayboard's keyboard logic. The app itself is built from
// Klayboard.xcodeproj; this package only exists so the logic files (shared
// with the keyboard extension) can be unit tested on the iOS simulator:
//
//   xcodebuild test -scheme KlayboardCore \
//     -destination 'platform=iOS Simulator,name=iPhone 17'
//
// The library target compiles the same source files the extension does, so a
// test failure here is a failure in the shipped keyboard code.

import PackageDescription

let package = Package(
    name: "KlayboardCore",
    platforms: [.iOS(.v17)],
    targets: [
        .target(
            name: "KlayboardCore",
            path: ".",
            exclude: ["Tests"],
            sources: [
                "Shared/KeyboardDataStructures.swift",
                "Shared/BaseLayouts.swift",
                "KlayboardExtension/AccentVariants.swift",
                "KlayboardExtension/BigramModel.swift",
                "KlayboardExtension/ClipboardHistory.swift",
                "KlayboardExtension/CursorEngine.swift",
                "KlayboardExtension/MacroEngine.swift",
                "KlayboardExtension/SplitLayout.swift",
                "KlayboardExtension/TouchModel.swift",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KlayboardCoreTests",
            dependencies: ["KlayboardCore"],
            path: "Tests/KlayboardCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
