// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UniPDF",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "UniPDF", targets: ["UniPDF"])],
    targets: [
        .target(name: "UniPDFCore"),
        .executableTarget(name: "UniPDF", dependencies: ["UniPDFCore"],
                          swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "UniPDFCoreTests", dependencies: ["UniPDFCore"]),
        .testTarget(name: "UniPDFTests", dependencies: ["UniPDF", "UniPDFCore"])
    ]
)
