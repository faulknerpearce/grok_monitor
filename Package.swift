// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GrokMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GrokMonitor", targets: ["GrokMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "GrokMonitor",
            path: "GrokMonitor",
            exclude: [
                "Resources/Info.plist",
                "Resources/GrokMonitor.entitlements"
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/PrivacyInfo.xcprivacy"),
                .copy("Fixtures/usage_fixture.json")
            ]
        )
    ]
)
