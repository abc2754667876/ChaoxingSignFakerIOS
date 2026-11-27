# ChaoxingSignFakerIOS

基于 Swift / SwiftUI 开发的学习通签到功能研究项目，移植自 [aquamarine5/ChaoxingSignFaker](https://github.com/aquamarine5/ChaoxingSignFaker)。包含账号登录、课程与活动浏览、多账号管理、位置收藏，以及普通、位置、二维码、拍照、手势和签到码等签到流程。

## 声明

本项目仅作为交流学习使用，通过本项目加深前端设计、接口调用、数据库使用、网络通信安全等方面知识的理解。请勿将此项目用作商业用途和任何不正当违规违法行为。任何人或组织使用项目或项目中的代码进行的任何不正当违规和违法行为与作者无关，作者不承担任何因使用本应用而导致的法律或其他任何责任。

## 项目部署

本项目为原生 iOS 客户端，直接调用学习通接口，无需另行部署后端服务或数据库。

### 环境要求

- 可运行 Xcode 的 Mac，建议使用 Xcode 27.0（当前项目验证环境），并安装 iOS SDK 和所需模拟器运行时。
- iOS / iPadOS 18.0 或更高版本的设备或模拟器。
- 真机安装需要 Apple 账号及可用的开发签名；模拟器构建无需开发者账号。

工程使用本地 Swift Package `Packages/CaptchaRuntime`。ONNX Runtime 的 XCFramework 压缩包和验证码模型已包含在仓库中，无需安装 CocoaPods 或单独下载运行库。依赖来源与校验信息见 [CaptchaRuntime 说明](Packages/CaptchaRuntime/README.md)。

### 获取源码并运行

```bash
git clone https://github.com/abc2754667876/ChaoxingSignFakerIOS.git
cd ChaoxingSignFakerIOS
open ChaoxingSignFakerIOS.xcodeproj
```

1. 等待 Xcode 解析本地 Swift Package，确认仓库包含 `Packages/CaptchaRuntime/Artifacts/onnxruntime-1.29.0.xcframework.zip` 和 `ChaoxingSignFakerIOS/Resources/captcha.ort`。
2. 在顶部工具栏选择 `ChaoxingSignFakerIOS` Scheme，选择已安装的 iPhone 或 iPad 模拟器。
3. 按 `⌘R`（Product → Run）编译并启动。相机扫码、拍照和真实定位等能力建议在实机验证。

也可在项目根目录通过命令行检查模拟器构建：

```bash
xcodebuild \
  -project ChaoxingSignFakerIOS.xcodeproj \
  -scheme ChaoxingSignFakerIOS \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

该命令仅生成模拟器构建产物。需要启动应用时，请在 Xcode 中选择具体模拟器运行。

## 实机安装

### 使用 Xcode 安装到 iPhone / iPad

1. 在 Xcode → Settings → Apple Accounts（部分版本显示为 Accounts）中登录自己的 Apple 账号。
2. 使用数据线连接设备，解锁后按提示选择“信任此电脑”，并在 Xcode 中完成设备配对。
3. 在设备的“设置 → 隐私与安全性 → 开发者模式”中开启开发者模式，按提示重启并确认。若该选项未出现，先连接 Xcode 并发起设备配对。详见 [Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。
4. 在 Xcode 左侧选择工程，进入 `TARGETS → ChaoxingSignFakerIOS → Signing & Capabilities`：
   - 勾选 `Automatically manage signing`。
   - 将 `Team` 改为自己的开发团队或 `Personal Team`；仓库中的团队配置需要替换。
   - 将 `Bundle Identifier` 改为自己可用的唯一标识，例如 `com.yourname.ChaoxingSignFakerIOS`。
   - 如需在实机运行测试，也为 `ChaoxingSignFakerIOSTests` 配置自己的团队及唯一标识。
5. 在顶部工具栏选择 `ChaoxingSignFakerIOS` Scheme 和已连接的设备，按 `⌘R`。Xcode 会生成签名、安装并启动应用。
6. 若系统提示开发者未受信任，按提示前往“设置 → 通用 → VPN 与设备管理”信任对应开发者，再次启动应用。
7. 首次使用相关功能时，按需允许相机、照片和定位权限；之后可在系统设置中调整。

完整签名与运行流程可参考 [Apple 真机运行文档](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)。

### 签名有效期与归档

免费 Apple 账号可通过 Personal Team 安装到个人设备。其描述文件有效期为 7 天，到期后需要使用 Xcode 重新构建并安装；相关限制见 [Apple 开发者账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account)。

如需导出真机安装包，在签名配置完成后，将运行目标选为通用 iOS 真机目标，执行 Product → Archive，再通过 Organizer → Distribute App 选择账号支持的分发方式。导出的 IPA 必须具有适用于目标设备的有效签名与描述文件；模拟器构建产物不能直接安装到真机。

### 常见问题

| 问题 | 处理方法 |
| --- | --- |
| 找不到开发团队或签名失败 | 检查 Apple 账号登录状态，选择自己的 Team，并使用唯一的 Bundle Identifier。 |
| 找不到运行设备或 SDK | 检查设备连接、信任和配对状态，按 Xcode 提示安装对应平台组件，确认设备系统不低于 iOS/iPadOS 18。 |
| 找不到 CaptchaRuntime 或二进制依赖 | 确认完整获取仓库，保留本地包与 XCFramework ZIP 的原始路径，再在 Xcode 中重新解析包依赖。 |
| 已安装的应用过期无法打开 | 检查签名及描述文件有效期，使用自己的账号重新构建安装。 |
| 相机、照片或定位不可用 | 检查系统权限，并在真机上验证相关功能。 |

## 开源协议与致谢

本项目采用 [GNU Affero General Public License v3.0（AGPL-3.0）](LICENSE)。代码的使用、修改与分发权利及义务以该协议为准。

感谢原项目 [aquamarine5/ChaoxingSignFaker](https://github.com/aquamarine5/ChaoxingSignFaker) 提供的实现参考。

第三方组件保留各自的许可及版权声明：ONNX Runtime 的许可证见 [Packages/CaptchaRuntime/LICENSE](Packages/CaptchaRuntime/LICENSE)，第三方声明见 [ThirdPartyNotices.txt](Packages/CaptchaRuntime/ThirdPartyNotices.txt)。
