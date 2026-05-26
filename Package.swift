// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PromptShelf",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "PromptShelf",
            path: "Sources/PromptShelf",
            resources: [
                .process("Resources/Sounds"),
                .process("Resources/HowTo")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)   // Swift 5 동작 유지 (strict concurrency 비활성)
            ],
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/PromptShelf/Resources/Info.plist"
                ])
            ]
        )
    ]
)
