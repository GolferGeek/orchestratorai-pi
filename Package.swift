// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pi",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Pi", targets: ["Pi"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.1.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Pi",
            dependencies: [
                .product(name: "Textual", package: "textual"),
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/Pi",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
