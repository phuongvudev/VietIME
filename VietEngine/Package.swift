// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VietEngine",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "VietEngine", targets: ["VietEngine"]),
    ],
    targets: [
        // Lõi C: biên dịch & test được trên mọi nền tảng (xem ctests/, Makefile).
        .target(name: "CVietEngine"),
        // Lớp Swift mỏng cho app.
        .target(name: "VietEngine", dependencies: ["CVietEngine"]),
        .testTarget(name: "VietEngineTests", dependencies: ["VietEngine"]),
    ]
)
