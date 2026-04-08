// swift-tools-version: 6.0
import Foundation
import PackageDescription

let environment = ProcessInfo.processInfo.environment
let explicitSearchPath = environment["RHWP_LIB_SEARCH_PATH"]
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let fileManager = FileManager.default
let candidateSearchPaths = [explicitSearchPath, "../target/debug", "../target/release"].compactMap { $0 }
let rustSearchPaths = candidateSearchPaths.filter { path in
    let absolutePath = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: packageDirectory)).path
    return fileManager.fileExists(atPath: absolutePath)
}
let rustLinkerFlags = rustSearchPaths.flatMap { ["-L", $0] }

let package = Package(
    name: "hwp-mac",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "HwpMacApp", targets: ["HwpMacApp"]),
    ],
    targets: [
        .target(
            name: "CRhwpNative",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "HwpMacApp",
            dependencies: ["CRhwpNative"],
            path: "Sources/HwpMacApp",
            linkerSettings: [
                .linkedLibrary("rhwp"),
                .unsafeFlags(rustLinkerFlags),
            ]
        ),
    ]
)
