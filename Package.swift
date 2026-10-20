// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MTPKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MTPShared", targets: ["MTPShared"]),
        .library(name: "MTPKit", targets: ["MTPKit"]),
    ],
    targets: [
        .systemLibrary(
            name: "CMTP",
            pkgConfig: "libmtp",
            providers: [.brew(["libmtp"])]
        ),
        .target(name: "MTPShared"),
        .target(name: "MTPKit", dependencies: ["CMTP", "MTPShared"]),
        .executableTarget(name: "mtpls", dependencies: ["MTPKit"]),
    ]
)
