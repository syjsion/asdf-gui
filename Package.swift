// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "asdf-gui",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "asdf-gui", targets: ["AsdfGUI"])],
    targets: [
        .executableTarget(name: "AsdfGUI"),
        .testTarget(name: "AsdfGUITests", dependencies: ["AsdfGUI"])
    ]
)
