// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TrackMyMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TrackMyMac", targets: ["TrackMyMac"])
    ],
    targets: [
        .executableTarget(
            name: "TrackMyMac",
            path: "Sources/TrackMyMac",
            exclude: [],
            resources: [],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
