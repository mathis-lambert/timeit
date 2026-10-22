// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Timeit",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Timeit", targets: ["TimeitApp"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "3.1.0"),
        .package(url: "https://github.com/openid/AppAuth-iOS.git", exact: "3.0.0"),
        .package(url: "https://github.com/square/Valet.git", exact: "5.1.1"),
    ],
    targets: [
        .target(name: "TimeitCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(
            name: "TimeitApp",
            dependencies: [
                "TimeitCore", "KeyboardShortcuts", "Valet",
                .product(name: "AppAuth", package: "AppAuth-iOS"),
            ],
            resources: [.process("Resources")]),
        .testTarget(name: "TimeitCoreTests", dependencies: ["TimeitCore"]),
        .testTarget(name: "TimeitAppTests", dependencies: ["TimeitApp"]),
    ]
)
