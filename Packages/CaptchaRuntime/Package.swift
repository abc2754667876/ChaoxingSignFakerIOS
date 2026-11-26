// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CaptchaRuntime",
    platforms: [.iOS("18.0")],
    products: [.library(name: "CaptchaRuntime", targets: ["CaptchaRuntime"])],
    targets: [
        .binaryTarget(name: "onnxruntime", path: "Artifacts/onnxruntime-1.29.0.xcframework.zip"),
        .target(name: "CaptchaRuntime", dependencies: ["onnxruntime"],
                linkerSettings: [.linkedLibrary("c++"), .linkedFramework("CoreML"), .linkedFramework("Accelerate")])
    ],
    cxxLanguageStandard: .cxx17
)
