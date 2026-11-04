// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Translator",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Translator", path: "Sources/Translator")
    ]
)
