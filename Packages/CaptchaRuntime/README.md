# CaptchaRuntime

本地 Swift 包，通过 ONNX Runtime C++ API 为 Swift 提供 CPU 推理接口。Xcode 可直接解析仓库内的 XCFramework ZIP，无需 CocoaPods 或联网下载依赖。

原生库来自微软 NuGet 发布包 `Microsoft.ML.OnnxRuntime 1.29.0`，与安卓项目的运行时版本一致：

- 发布页：https://www.nuget.org/packages/Microsoft.ML.OnnxRuntime/1.29.0
- 下载地址：https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/1.29.0/microsoft.ml.onnxruntime.1.29.0.nupkg
- NuGet 包 SHA-256：`4557021fec4da3924e2e12ff44b1cc50b176de0d2c5c7daa89ab11c208b3a454`
- 提取文件：`runtimes/ios/native/onnxruntime.xcframework.zip`
- 仓库内 ZIP SHA-256：`38147c96d960d6e7f0fdad89391e4f6c23786f424fe1dc781481bca7a955e413`

XCFramework 原样保留真机、模拟器和 Catalyst 切片，压缩文件约 57 MiB。`LICENSE` 和 `ThirdPartyNotices.txt` 同样提取自该发布包。微软 SPM 仓库及原下载域名在本次接入时无法使用，因此采用本地依赖。

升级时应从微软发布包重新提取 XCFramework，同步更新版本、校验值和许可文件，运行 `CaptchaPredictorTests` 验证现有 ORT 模型与运行时兼容。
