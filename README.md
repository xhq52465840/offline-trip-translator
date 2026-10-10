# 离线行程理解 · iOS Demo

阶段 A：`TripCore` 本地 Swift Package（纯 Swift + Foundation，Linux 可测）。

- `Amount.swift`：印尼语金额俗写解析（rb/ribu/rbu/jt/juta/k、`1,5jt`、`50.000`）、中文「万」格式、占位 ⟦Nk⟧ 与回填（技术设计 v2 §5）
- `Readiness.swift`：必备项、阻断判定 `ReadinessGate`、设备档位（4GB 默认关闭）、下载状态机（Wi‑Fi 策略、断点续传、空间预检、SHA‑256 校验重试 1 次）（§2、§13）
- `SHA256.swift`：纯 Swift 流式 SHA‑256（不依赖 CryptoKit）
- `Understanding.swift`：提示词构建、输出校验（格式、外语词、金额交叉校验）（§8.2、§5.3）
- `Trial.swift`：试用计数协议、内存实现、钥匙串实现（`#if canImport(Security)`）、匿名计数开关（默认开、可关）

在 Xcode 中：File > Add Package Dependencies > Add Local… 选 `TripCore`（阶段 B 会加 App 工程）。

```
cd TripCore && swift build && swift test
```

## 阶段 B：推理引擎与下载

- `TripCore/LLMEngine.swift`：`LLMEngine` 协议（load / warmUp 前缀缓存 / 流式 generate / complete / 取消）+ `MockEngine`
- `TripCore/Understander.swift`：提示词 + 生成 + 超时 + 校验
- `TripLLM/LlamaCppEngine.swift`：llama.cpp 实现。Apple 平台用官方 XCFramework（release **b11541**，`import llama`，checksum 已核对）；Linux 用 `CLlama` system library（仅当设置 `LLAMA_CPP_DIR`）。C API 已按 b11541 的 `include/llama.h` 核对（XCFramework 内的 llama.h 与源码逐字节相同）。
- `TripCore/ModelDownloader.swift`：状态机 + 传输协议 + SHA-256 + 原子安装；`URLSessionTransport`（后台会话、resume data、蜂窝策略）只在 Apple 平台编译。
- `Resources/model-manifest.json`：Qwen2.5-1.5B-Instruct Q4_K_M（HF 固定 commit，bytes 与 sha256 已核对）。

Linux 冒烟（真实模型）：

```
cd /workspace/llama.cpp && cmake -B build -DBUILD_SHARED_LIBS=ON -DLLAMA_CURL=OFF && cmake --build build --target llama
cd TripCore && LLAMA_CPP_DIR=/workspace/llama.cpp swift run llm-smoke /path/to/qwen2.5-1.5b-instruct-q4_k_m.gguf
```
输出见 `docs/llm-smoke-linux.txt`（Linux x86 CPU，非 iPhone 速度）。

## 阶段 C：SwiftUI App

- `TripCore/Sources/TripAppModel`（非 UI，Linux 可测）：`AppGate`（启动/前台阻断判定）、`ConversationModel`（金额占位翻译、理解替换 3 秒预算、我的消息改写+回译、试用）、`ClipboardHint`（hasStrings + PasteButton）、`PrepareRows`、`DemoScript`、回译一致判定、语言猜测。
- `App/TripApp`（SwiftUI，iOS 17+）：强制准备引导、准备页、不可关闭的阻断 sheet（每次冷启动与 scenePhase .active 检查）、对话页、出示页、示例演示、隐私（匿名计数开关）、购买（StoreKit 2）。系统翻译：iOS 18+ `LanguageAvailability` / `prepareTranslation()`（经 `.translationTask`），iOS 26+ `TranslationSession(installedSource:target:)`；听写资源：iOS 26 `AssetInventory`。
- 生成 Xcode 工程：`cd App && xcodegen generate`（`project.yml`）。
