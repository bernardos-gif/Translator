// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VPN",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "VPN", path: "Sources/VPN")
    ]
)
