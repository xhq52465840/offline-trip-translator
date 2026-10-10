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
