# 离线行程理解 · iOS Demo

中国游客在印尼，手机断网也能把一场对话进行下去：系统离线翻译给出字面意思，端侧小模型（Qwen2.5-1.5B Q4_K_M，llama.cpp + Metal）结合上下文给出「理解」（俗写数字、砍价、指代），金额由代码交叉校验。模型与离线语言包首次启动强制下载，缺失时每次启动/回前台弹出不可关闭的提示。

## 目录

```
App/                      SwiftUI 应用（iOS 17+）
  project.yml             XcodeGen 定义（权威来源）
  TripUnderstand.xcodeproj 已生成好的工程（Linux 上用 XcodeGen 2.44.1 生成）
  TripApp/                视图、AppState、系统服务（Translation / Speech / 网络）、Info.plist、entitlements、图标占位
TripCore/                 本地 Swift Package
  Sources/TripCore        纯 Foundation 逻辑：金额解析、就绪/下载状态机、SHA-256、提示词与校验、试用计数、下载器、LLMEngine 协议 + MockEngine
  Sources/TripLLM         LlamaCppEngine（llama.cpp C API；Apple 用官方 XCFramework b11541）
  Sources/TripAppModel    与 UI 无关的视图模型：对话、门禁、剪贴板、按住说话、会话持久化
  Sources/llm-smoke       仅 Linux：用真实 GGUF 跑引擎冒烟
  Tests/                  59 个 XCTest
docs/                     原始需求、prd/tech、评审报告、端侧模型验证报告、PRD/技术 v2、model_eval 脚本与结果（不含模型）
```

## Mac 上跑起来

1. 环境：macOS 15+，**Xcode 26**（需要 iOS 26 SDK 才能编译 SpeechAnalyzer 代码；运行最低 iOS 17）。真机建议 iPhone 15 Pro 及以上（8GB），6GB 机型为 B 档，4GB 机型被门禁拦截。
2. 打开工程（二选一）：
   - 直接打开 `App/TripUnderstand.xcodeproj`；
   - 或重新生成：`brew install xcodegen && cd App && xcodegen generate && open TripUnderstand.xcodeproj`
3. 等待 Xcode 解析 Swift Package：会从 GitHub 下载 `llama-b11541-xcframework.zip`（校验和已写在 `TripCore/Package.swift`）。失败时 File ▸ Packages ▸ Reset Package Caches。
4. Target `TripUnderstand` ▸ Signing & Capabilities：选择你的 Team，必要时改 Bundle ID（默认 `app.tripunderstand.demo`）。工程带 `Increased Memory Limit` entitlement；若签名报错，可先在 Capabilities 里移除再试。
5. 选择真机运行（模拟器没有 Metal 性能参考，Translation/Speech 离线资源也不完整）。
6. 命令行测纯逻辑：`cd TripCore && swift test`

## 真机测试清单

- 首次启动：引导页 → 下载语言包（系统 Translation 弹窗）+ 模型约 1.1GB（建议 Wi-Fi；蜂窝会二次确认）。下载中可看示例、隐私、购买页。
- 杀掉 App / 关掉 Wi-Fi 后再打开：未完成时应出现不可关闭的阻断弹窗。
- 开飞行模式：粘贴/输入印尼语（如 `50rb aja`、`yang tadi brp?`），看字面翻译后是否在时间预算内被「理解」替换，金额是否正确。
- 按住「听对方」/「说中文」：0.3 秒后开始，上滑取消，松手出结果；首次会请求麦克风与语音识别权限。
- 杀掉 App 后重开：对话恢复；超过 4 小时询问是否继续；「新对话 ▸ 清除本机对话」后全部删除。
- 记录：模型冷启动、首 token 时延、tokens/s、内存峰值（Instruments），对照 docs/端侧模型验证报告.md 的预算。

## 未验证项（Linux 上无法编译 SwiftUI / Apple 框架）

- App 目录下所有代码只做了 `swiftc -parse` 语法检查，API 名称对照了 Apple 文档，但**没有类型检查与真机运行**；首次在 Xcode 编译可能有少量类型错误需修。
- SpeechAnalyzer 路径（iOS 26）的音频格式转换、结果最终化时机；SFSpeechRecognizer 本机识别对印尼语的支持需真机确认。
- Translation 框架 iOS 18–25 的 `prepareTranslation` 桥接、语言包状态探测。
- llama.cpp XCFramework 在 iOS 上的加载、Metal 卸载层数、内存峰值；Linux 上已用同一 C API 跑通 Qwen2.5-1.5B。
- 后台 URLSession 下载、续传、Keychain 试用计数、StoreKit 购买（购买页为占位）。
- `increased-memory-limit` entitlement 与个人开发者账号的签名兼容性。

## 下一步

1. 真机基准：A/B 档机型冷/热启动、时延、内存，决定是否换 Qwen3-1.7B。
2. LoRA 微调：用 docs/model_eval 的用例扩充到数千条（俗写数字、砍价、指代、印尼口语缩写），合并后再量化为 Q4_K_M，更新 `model-manifest.json` 的 URL/sha256/大小。
3. 模型托管到自有 CDN（当前指向 Hugging Face 公共地址），补 StoreKit 2 真实商品。
4. 按 docs/评审报告.md 的优先级处理审核风险（强制下载的文案与示例页）。
