// swift-tools-version:5.9
import PackageDescription
import Foundation

// llama.cpp 集成：
// - Apple 平台：官方 XCFramework（ggml-org/llama.cpp release b11541），模块名 `llama`。
//   checksum 与 GitHub release 资产 digest 一致（已在 Linux 上下载核对）。
// - Linux：只有设置了 LLAMA_CPP_DIR（llama.cpp 源码根目录，已编译 build/bin/libllama.so）时，
//   才加入 system library 目标 `CLlama` 和冒烟可执行 `llm-smoke`；否则 TripLLM 编成空壳，保证 swift build 永远可过。
let llamaDir = ProcessInfo.processInfo.environment["LLAMA_CPP_DIR"]

var targets: [Target] = [
    .target(name: "TripCore", resources: [.process("Resources")]),
    .testTarget(name: "TripCoreTests", dependencies: ["TripCore"]),
    .target(name: "TripAppModel", dependencies: ["TripCore"]),
    .testTarget(name: "TripAppModelTests", dependencies: ["TripAppModel", "TripCore"]),
]
var tripLLMDeps: [Target.Dependency] = ["TripCore"]
var products: [Product] = [
    .library(name: "TripCore", targets: ["TripCore"]),
    .library(name: "TripLLM", targets: ["TripLLM"]),
    .library(name: "TripAppModel", targets: ["TripAppModel"]),
]

#if os(Linux)
if let dir = llamaDir {
    targets.append(.systemLibrary(name: "CLlama", path: "Sources/CLlama"))
    tripLLMDeps.append("CLlama")
    targets.append(.executableTarget(
        name: "llm-smoke",
        dependencies: ["TripCore", "TripLLM"],
        linkerSettings: [.unsafeFlags(["-L\(dir)/build/bin", "-Xlinker", "-rpath", "-Xlinker", "\(dir)/build/bin"])]
    ))
    products.append(.executable(name: "llm-smoke", targets: ["llm-smoke"]))
}
#else
targets.append(.binaryTarget(
    name: "llama",
    url: "https://github.com/ggml-org/llama.cpp/releases/download/b11541/llama-b11541-xcframework.zip",
    checksum: "c6635419d2527e2a2fd052b6756f14c3e0e84c346e3638a43b305434e6753dc4"
))
tripLLMDeps.append(.target(name: "llama", condition: .when(platforms: [.iOS, .macOS])))
#endif

var tripLLMSettings: [SwiftSetting] = []
var tripLLMCSettings: [CSetting] = []
#if os(Linux)
if let dir = llamaDir {
    tripLLMSettings = [.unsafeFlags(["-Xcc", "-I\(dir)/include", "-Xcc", "-I\(dir)/ggml/include"])]
}
#endif
targets.append(.target(name: "TripLLM", dependencies: tripLLMDeps, exclude: [], swiftSettings: tripLLMSettings))
if let i = targets.firstIndex(where: { $0.name == "llm-smoke" }) {
    targets[i].swiftSettings = tripLLMSettings
}

let package = Package(
    name: "TripCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: products,
    targets: targets
)
