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
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.1.0")
    ],
    targets: [
        .executableTarget(
            name: "Pi",
            dependencies: [
                .product(name: "Textual", package: "textual")
            ],
            path: "Sources/Pi"
        )
    ]
)
