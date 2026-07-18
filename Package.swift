// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VirtualSMS",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "VirtualSMS",
            targets: ["VirtualSMS"]
        ),
    ],
    targets: [
        .target(
            name: "VirtualSMS",
            path: "Sources/VirtualSMS"
        ),
        .testTarget(
            name: "VirtualSMSTests",
            dependencies: ["VirtualSMS"],
            path: "Tests/VirtualSMSTests"
        ),
    ]
)
