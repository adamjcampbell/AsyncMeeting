// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "AsyncMeeting",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "AsyncMeeting",
            targets: ["AsyncMeeting"]
        ),
    ],
    targets: [
        .target(name: "AsyncMeeting"),
        .testTarget(name: "AsyncMeetingTests", dependencies: ["AsyncMeeting"]),
    ]
)
