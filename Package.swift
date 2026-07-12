// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrokUsage",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GrokUsage", targets: ["GrokUsage"])
    ],
    targets: [
        .executableTarget(
            name: "GrokUsage",
            path: "GrokUsage",
            exclude: [
                "Resources/Info.plist",
                "Resources/GrokUsage.entitlements"
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Fixtures/usage_fixture.json")
            ]
        )
    ]
)
