// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "AsyncMeeting",
    products: [
        .library(
            name: "AsyncMeeting",
            targets: ["AsyncMeeting"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.3.0"),
    ],
    targets: [
        .target(name: "AsyncMeeting"),
        .testTarget(
            name: "AsyncMeetingTests",
            dependencies: [
                "AsyncMeeting",
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ]
        ),
    ]
)
