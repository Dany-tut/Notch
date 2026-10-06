// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Notch",
            path: "Sources/Notch",
            // AppIcon.icns кладёт в бандл сам build-app.sh, а не SwiftPM:
            // .icns нужен прямо в Contents/Resources, а не внутри вложенного
            // ресурсного бандла пакета.
            exclude: ["Resources/Icon"],
            resources: [.copy("Resources/Sounds")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
