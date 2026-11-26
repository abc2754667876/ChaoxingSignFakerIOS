# 项目各个文件夹作用

## 根目录
```text
App       应用启动、依赖注入、全局路由
Core      可跨业务复用的基础能力
Domain    平台无关的业务模型和接口定义
Data      学习通接口与数据实现
Features  面向用户的具体功能和 SwiftUI 页面
```

## 二级目录

### Core/Networking
网络访问基础设施。这里不写“课程接口”或“签到接口”的业务代码，只提供请求执行和统一错误处理。

### Core/Session
账号登录态和设备身份相关能力。

### Core/Persistence
普通本地数据持久化。

### Core/Location
定位与地图能力封装。

### Core/Media
相机、相册、二维码和图片处理能力。

### Core/UI
全局可复用 UI 组件和设计规范。

### Domain/Models
领域模型目录。

### Domain/Protocols
Repository 抽象接口目录。

### Data/Chaoxing
学习通服务端接口实现目录。

#### DTO/
接口数据传输对象目录。

### Features/Onboarding
首次使用流程。职责：
- 展示隐私协议和使用说明。
- 请求必要权限。
- 保存用户已完成首次引导的状态。
  
### Features/Authentication
登录功能。职责：
- 输入账号密码。
- 调用登录 Use Case。
- 显示登录进度和登录失败原因。
- 登录成功后跳转到主页面。

### Features/Courses
课程和活动浏览功能。职责：
- 展示课程列表。
- 展示课程详情和可用活动。
- 选择活动后进入相应签到流程。

### Features/Sign
所有签到流程的总目录。

`SignVerificationSupport` 为签到页面提供统一的人脸与验证码弹窗，前一个弹窗关闭后才恢复提交。所有签到类型在 `ChaoxingAPI.performSign` 处理验证要求、保留原参数并有限重试；验证码凭证仅用于当前账号的本次提交。

签到通过表单 POST 提交，附带原域名预签到页的 `Referer` 和 `X-Requested-With: XMLHttpRequest`。`ChaoxingSignRoute` 对齐安卓端，将 `mobilelearn.chaoxing.com` 请求路由至 `data-xxt.aichaoxing.com` 并保留原 Host；网络错误或 404 时回退原域名。网络层按原域名维护当前账号 Cookie，验证码地址与来源参数保持原域名。

#### Captcha/
`CaptchaCoordinator` 管理异步等待和取消，`CaptchaView` 展示图片、拖动、校验与刷新。首次加载时通过 `CaptchaPredictor` 在独立 actor 中运行 `Resources/captcha.ort`，将预测偏移送到服务端校验；每次验证只自动尝试一次。模型不可用或无有效检测时保留原图供手动操作，自动校验失败后刷新挑战再转手动。刷新按钮及手动失败后的刷新不触发连续自动识别。

推理使用本地 Swift 包 `Packages/CaptchaRuntime` 中的 ONNX Runtime 1.29.0 CPU 原生库；模型沿用安卓端文件。预处理将图片放在正方形左上角、其余补黑，缩放为 640×640 并转换成 RGB Float32 NCHW；输出选择最高置信度的缺口框，还原为原图坐标并应用安卓端的 4 像素偏移修正。验证码接口位于 `Data/Chaoxing/ChaoxingCaptchaAPI.swift`。离开签到页或退出登录时取消等待；模型执行后校验账号与请求标识，二维码在验证后提交前重新检查有效性。

#### LocationSign/
位置签到功能。职责：
- 展示地图。
- 获取当前位置或选择收藏位置。
- 展示签到范围。
- 调用位置签到执行器。

#### QRCodeSign/
二维码签到功能。职责：
- 打开相机扫码或读取相册二维码。
- 解析学习通二维码。
- 判断二维码是否过期。
- 根据活动要求补充位置、人脸或验证码。

#### PhotoSign/
拍照签到功能。职责：
- 调用相机或相册。
- 压缩和上传图片。
- 使用上传后的 objectId 提交签到。

#### PasswordSign/
签到码签到功能。职责：
- 输入签到码。
- 预校验签到码。
- 如活动要求位置，则允许选择位置后提交。

#### GestureSign/
手势签到功能。职责：
- 提供手势图案输入。
- 将手势顺序转换为接口需要的签到码。
- 执行校验和提交。

### Features/OtherUsers
代签账号管理功能。职责：
- 添加、导入、编辑、删除代签账号。
- 显示代签账号会话状态。
- 为批量签到提供账号选择。
- 管理账号标签和设备标识状态。

### Features/Groups
群聊签到功能。职责：
- 展示群组。
- 加载群消息。
- 从群消息中识别签到活动。
- 跳转到对应签到流程。

### Features/Settings
应用设置功能。职责：
- 管理主题、定位、开发选项、隐私授权等设置。
- 管理更新、日志、外部调用权限等功能。
- 不直接存取 UserDefaults 或 Keychain，应调用 Repository。

### Features/Favorites
收藏位置管理功能。职责：
- 新增、编辑、删除收藏地点。
- 在地图中选择地点。
- 提供给位置签到页面复用。
