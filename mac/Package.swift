// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nabiz",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NabizCore", targets: ["NabizCore"]),
        .executable(name: "Nabiz", targets: ["Nabiz"]),
    ],
    targets: [
        .target(name: "NabizCore"),
        .executableTarget(
            name: "Nabiz",
            dependencies: ["NabizCore"],
            exclude: ["Info.plist"],
            // SPM calistirilabilir paketi .app degildir: Info.plist ikiliye gomulur (LSUIElement vb.).
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist", "-Xlinker", "Sources/Nabiz/Info.plist",
            ])]
        ),
        .testTarget(name: "NabizCoreTests", dependencies: ["NabizCore"]),
    ]
)
