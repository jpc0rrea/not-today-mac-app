// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotToday",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NotToday", targets: ["NotToday"])
    ],
    targets: [
        .executableTarget(
            name: "NotToday",
            path: "NotToday/Sources/NotToday",
            resources: [
                .copy("../../Resources/config.json"),
                .copy("Resources/menubar_icon_18x18.png"),
                .copy("Resources/menubar_icon_18x18@2x.png"),
                .copy("Resources/menubar_icon_22x22.png"),
                .copy("Resources/menubar_icon_22x22@2x.png")
            ]
        )
    ]
)
