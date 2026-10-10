# 离线行程理解 · 技术设计文档

状态：可按此开发  
版本：1.1  
日期：2026-10-10  
对应产品文档：同目录《产品需求文档》1.1

产品文档规定用户看见什么。本文规定模块、数据、接口、降级和验收测量。不写排期，只写实现顺序。

---

## 1. 目标与硬约束

第一版是一个 iPhone 应用。游客的中文和对方的印尼语或英语在本机互译，一场对话的上下文可以修正中文意思。断网与有网走同一条代码，没有在线推理分支。

硬约束：

| 项 | 值 |
| --- | --- |
| 最低系统 | iOS 26 |
| 设备 | iPhone。必须在 4GB 的 iPhone 13 / 13 mini 上可交互 |
| 方向 | 只竖屏 |
| 界面语言 | zh-Hans |
| 对方语言 | 由语言清单驱动。第一版只启用 `id`、`en`。其他语言放缓，不从模型里删掉扩展位 |
| 游客语言 | 固定 `zh-Hans` |
| 安装包 | 不内置大模型。系统语言包由系统下载 |
| 自有模型上限 | 修正模型若存在，文件 ≤ 150MB。印尼语听写包若存在，用完即卸载驻留 |
| 进程内存目标 | 稳态 < 700MB。收到内存警告后 < 450MB |
| 网络 | 推理路径零请求。只有准备页的资源下载可以有网 |

iOS 26 作为最低系统，是为了只维护一套系统翻译和一套系统听写。iPhone 13 能升级到这个系统。不在第一版做 iOS 18 的双实现。

## 2. 总体结构

```
对话界面
   │
   ▼
TurnCoordinator          一场里产生一条消息的唯一入口
   │
   ├── SessionStore       当前这场的读写
   ├── Glossary           印尼语数字俗写和词条，纯本地规则
   ├── Translator         系统离线翻译
   ├── Speaker            系统离线听写，印尼语可替换实现
   ├── Corrector          可选。超时或缺失则跳过
   ├── Entitlement        买断与试用计数
   └── PrepareStatus      四种离线能力的就绪状态
```

界面不调用翻译、听写或模型。界面只把「听对方松手」「发送中文」「点了剪贴板」交给 `TurnCoordinator`，并渲染 `Turn`。

依赖方向只允许自上而下。`Translator`、`Speaker`、`Corrector` 互相不引用。

## 3. 工程划分

建议单 target，目录如下。名称可以改，边界不能并掉。

```
App/
  TripUnderstandApp.swift
  Features/
    Conversation/        对话页、气泡、底部栏、剪贴板条
    Present/             出示页
    Prepare/             离线准备
    Paywall/
    Privacy/
  Domain/
    Turn.swift
    Session.swift
    LanguageCatalog.swift
    TrialPolicy.swift
  Services/
    TurnCoordinator.swift
    SessionStore.swift
    Glossary.swift
    Translator.swift
    Speaker.swift
    Corrector.swift
    Entitlement.swift
    PrepareStatus.swift
    ClipboardHint.swift
  Resources/
    languages.json
    glossary-id.json
```

SwiftUI。导航用 `NavigationStack`。不引入 UIKit 业务页面。听写缓冲、出示页的全屏覆盖可以用 `UIViewRepresentable` 只包音频或用纯 SwiftUI 均可，但业务状态放在 `TurnCoordinator`。

并发：`TurnCoordinator` 是 `@MainActor`。翻译、听写、修正在自己的 actor 里执行，回到主 actor 只提交 `Turn` 的字段更新。同一时刻只允许一个 `Task` 处于「正在产生消息」。新的发送在这个 `Task` 完成前被界面禁用。

## 4. 领域模型

对方语言不做成只含印尼语和英语的枚举。用语言标识字符串，合法值只来自 `languages.json` 里 `enabled == true` 的项。第一版该文件只有两项为启用。以后加语言是加一条记录并提供词表，不改对话页分支。

```swift
struct LanguageDefinition: Codable, Identifiable {
    var id: String              // BCP-47，如 id、en、ms
    var displayName: String     // 印尼语
    var enabled: Bool           // 第一版仅 id、en 为 true
    var glossary: String?       // glossary-id.json，没有则为 nil
    var numericRules: String?   // 数字俗写规则名，没有则跳过
}

enum TurnRole: String, Codable {
    case them, me
}

enum InputKind: String, Codable {
    case paste, voice, type
}

struct Turn: Codable, Identifiable {
    var id: UUID
    var role: TurnRole
    var createdAt: Date
    var inputKind: InputKind
    var sourceText: String          // 对方原文，或游客中文
    var sourceLocale: String        // "id" / "en" / "zh-Hans"
    var zhLiteral: String?          // 字面中文。我的消息等于 sourceText
    var zhDisplay: String?          // 主行。缺省时界面用 zhLiteral
    var zhDidCorrect: Bool          // true 且与 literal 不同才显示「字面」
    var foreignText: String?        // 给对方的话。对方消息等于 sourceText
    var foreignLocale: String?
    var backTranslation: String?
    var showBackTranslation: Bool
    var offerRetranslateAs: String?  // 另一种已启用语言的 id，没有则为 nil
    var status: TurnStatus
}

enum TurnStatus: String, Codable {
    case translating
    case ready
    case failedPackMissing
    case failed
}
```

我的消息：`sourceLocale` 永远是 `zh-Hans`，`zhLiteral` 与 `zhDisplay` 初始都等于原文。`foreignText` 后填。

对方消息：`foreignText` 等于原文，`foreignLocale` 是实际采用的语言。`zhLiteral` 后填，`zhDisplay` 先等于 `zhLiteral`。

会话：

```swift
struct Session: Codable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var theirLanguage: String       // languages.json 里的 id
    var turns: [Turn]
}
```

文件：`Application Support/session-current.json`，原子写入（先写临时文件再 `replaceItemAt`）。编码 UTF-8，日期 ISO 8601。

损坏：解析失败时把原文件改名为 `session-corrupt-{时间戳}.json`，开一场空会话。不崩溃。损坏文件保留 7 天后删除。

`theirLanguage` 同时写在 `UserDefaults` 键 `theirLanguage`，空会话也要记住开关。会话文件里的值用于恢复这场；若两者不一致，以会话文件为准，并回写 UserDefaults。

4 小时规则：进入对话页时，若 `now - updatedAt >= 4 * 3600` 且 `turns` 非空，弹产品文档里的那句。选继续则把 `updatedAt` 更新为现在，避免每次启动都问。选新开则走新对话流程。

30 天清理：启动时删除 `updatedAt` 早于 30 天且不是当前文件的会话残留。当前文件不删。

## 5. 词表与数字俗写

文件 `glossary-id.json`：

```json
{
  "version": 1,
  "locale": "id",
  "entries": [
    {"source": "ongkos", "zh": "车费"},
    {"source": "bisa", "zh": "可以"},
    {"source": "tidak", "zh": "不"},
    {"source": "belum", "zh": "还没有"},
    {"source": "termasuk", "zh": "包含"},
    {"source": "mahal", "zh": "贵"},
    {"source": "tunggu", "zh": "等"},
    {"source": "habis", "zh": "没有了"}
  ]
}
```

上表是结构示例。上架前换成真实聊天里的词，开发期测试至少覆盖第 5.1 节的数字规则。英文不建词表。

### 5.1 数字，在翻译之前用代码处理

对印尼语原文做下面的替换，长匹配优先。大小写不敏感。

| 形式 | 含义 | 中文替换 |
| --- | --- | --- |
| `(\d+(?:[.,]\d+)?)\s*rb` | × 1000 | 见下 |
| `(\d+(?:[.,]\d+)?)\s*ribu` | × 1000 | 见下 |
| `(\d+(?:[.,]\d+)?)\s*jt` | × 1_000_000 | 见下 |
| `(\d+(?:[.,]\d+)?)\s*juta` | × 1_000_000 | 见下 |

逗号小数按印尼习惯先当作点。`50rb` → 50000。

中文金额：

- 能整除 10000：写成「{n}万」，50rb → 「5万」。
- 否则写成带千分位的阿拉伯数字加「印尼盾」不自动加，只写数字。币种不猜。

替换结果放进给翻译器的文本，同时保留未替换的 `sourceText` 作为副行原文。主行中文里应能看见「5万」，而不是「50rb」。

若系统翻译已经把 50rb 译对，也不要再译一遍数字。做法：先把数字俗写换成中文数字占位，再翻译，避免模型或系统把 `rb` 译丢。占位用全角括号包住的已计算中文，例如把 `50rb` 换成 `5万`，整句变成 `5万 belum termasuk ongkos`，然后翻译。词表再处理 `ongkos`。

### 5.2 词条匹配

- 在数字替换之后。
- 按 `source` 长度降序。
- 只替换完整词，Unicode 词边界。
- 命中的 `{source, zh}` 列表最多 8 条，顺序即出现顺序，交给修正模型。
- 词条不直接改写整句中文。数字规则才会改写原文再送翻译。词条是修正模型的输入，以及测试断言用。

英语消息不跑印尼词表。

## 6. 翻译

### 6.1 实现

使用系统 `Translation` 框架，`TranslationSession`，语言对只在本机。

语言标识：

| 用途 | 标识 |
| --- | --- |
| 简体中文 | `zh-Hans` |
| 英语 | `en` |
| 印尼语 | `id` |

需要的方向：

- `id` → `zh-Hans`
- `en` → `zh-Hans`
- `zh-Hans` → `id`
- `zh-Hans` → `en`

不调用 `zh-Hans` → 其他，也不调用网络翻译 API。系统若因未下载语言包而无法离线完成，视为失败，错误码 `packMissing`，不许去掉 on-device 限制重试。

就绪检查：`LanguageAvailability.status(from:to:)` 为已安装才算准备页那一行完成。印尼语翻译一行要求 `id ↔ zh-Hans` 两个方向都已安装。英文一行要求 `en ↔ zh-Hans` 都已安装，并且英文听写就绪（第 7 节）。

超时：单次翻译 2.0 秒。超时错误码 `timeout`，界面留下产品文档里的失败句。用户再粘贴同一句可以重试，不自动重试第二次。

### 6.2 回译

仅「我的消息」在 `foreignText` 写入之后做一次反向翻译，得到 `backTranslation`。

一致判定，全部命中才算一致，隐藏灰行：

1. 两边都去掉空白和标点（含中英文标点）。
2. 若游客原文含阿拉伯数字，回译里必须含同一组数字，顺序一致。缺数字则不一致。
3. 其余字符计算重合率：`|交集| / max(|原文|, |回译|)`，按字符多重集。重合率 ≥ 0.72 视为一致。

不一致：`showBackTranslation = true`。界面用「对方会理解成：」加回译，不替换副行。副行仍是实际复制和出示的字符串。

回译超时或失败：当作一致，不展示灰行，不阻塞复制。

纯数字消息跳过翻译和回译。

## 7. 听写

### 7.1 接口

```swift
protocol Speaker: Sendable {
    func availability(for locale: Locale) async -> SpeechAvailability
    func transcribe(locale: Locale, audio: AudioStream) -> AsyncThrowingStream<SpeechEvent, Error>
}

enum SpeechAvailability {
    case ready
    case needsDownload
    case unsupported
}

enum SpeechEvent {
    case partial(String)
    case final(String)
}
```

界面录音：16 kHz、单声道、PCM 16 bit。按下 0.3 秒后才把缓冲送给 `Speaker`。上滑取消则结束流并丢弃结果。30 秒到时结束流，取 final；没有 final 就用最后一条 partial。结果去掉首尾空白后为空，则不创建 `Turn`。

录音期间配置 `AVAudioSession` 为 `.record`，结束立即 `setActive(false)`。进入后台取消流。

强制本机。任何实现不得在 `unsupported` 或飞行模式时改走服务器。`SFSpeechRecognitionRequest.requiresOnDeviceRecognition = true`。若该属性不被满足，调用直接失败，错误码 `notOnDevice`。

### 7.2 系统实现

语言：

| 按钮 | Locale |
| --- | --- |
| 听对方，开关英语 | `en-US` |
| 听对方，开关印尼语 | `id-ID` |
| 说中文 | `zh-CN` |

选择顺序，每个 locale 单独判断：

1. iOS 26 的 `SpeechTranscriber`：`supportedLocales` 含该 locale，且资源已安装。用 `SpeechAnalyzer` 做短句转写。它在应用进程外运行，不计入我们的模型内存。
2. 否则 `SFSpeechRecognizer`：`supportsOnDeviceRecognition == true` 才使用。
3. 否则 `availability` 返回 `unsupported` 或 `needsDownload`。能下载的系统资源走准备页。不能下载的印尼语进入第 7.3 节。英文和中文没有自带包，准备页保持未就绪并引导系统设置或系统资源下载。

英文、中文预期走第 1 或第 2 步。印尼语预期 `supportsOnDeviceRecognition == false`，以真机为准。

### 7.3 印尼语实验与备用包

上架前在一台 iPhone 13、iOS 26 或 27、飞行模式下执行：

1. 准备页触发 `id-ID` 的系统听写资源。
2. 朗读三句印尼语：「lima puluh ribu belum termasuk ongkos」「bisa lebih murah」「tunggu sebentar」。
3. 每句在 4 秒内得到非空、意思相关的文字，记为通过。

三句都通过：`IndonesianSystemSpeaker` 为印尼语实现，不引入备用包。准备页印尼语听写为「已就绪」。

任一失败：实现 `IndonesianLocalSpeaker`。

备用包要求：

- 只识别印尼语，不用于英语和中文。
- 模型文件随准备页下载，Wi-Fi 默认，校验 SHA-256，支持断点。
- 体积目标 ≤ 200MB。优先 int8 的较小多语种听写模型，语言参数固定 `id`。
- 推理用独立的 hearing actor。开始识别前若修正模型已加载，先卸载修正模型。识别结束释放听写权重，再允许修正模型下次加载。
- 未下载时 `availability` 为 `needsDownload`。
- 实验结论写进仓库 `docs/印尼语听写实验.md`，三个句子的识别文本和耗时。没有这份记录，不合并备用包，也不把印尼语听写标成已就绪。

第一版允许印尼语听写不可用。粘贴印尼语、英语听写、中文听写仍必须可用。这时准备页该行固定「听印尼语暂不可用」。

### 7.4 权限

麦克风与语音识别分开请求，都在第一次按住时。拒绝后按钮仍可点，点了走产品文档的设置对话框。`UIApplication.openSettingsURLString`。

## 8. 修正模型

修正是增强。`Corrector` 不存在、模型文件缺失、加载失败、超时，都不影响 `zhLiteral` 和 `foreignText`。

### 8.1 什么时候调用

对方消息，同时满足才调用：

- 已买断，或试用未用尽。
- `zhLiteral` 已写入。
- 这场在本句之前至少有一条 `ready` 消息，或词表命中至少 1 条。

两条都不满足：不加载模型，`zhDisplay = zhLiteral`，`zhDidCorrect = false`。

我的消息不把修正结果展示成另一句中文。若之前有上下文，且原文含指代（正则见下），先让修正模型输出「要翻译的中文」，再用这句去翻译。模型失败则用游客原文翻译。

指代正则，命中任一即可：`这个|那个|刚才|之前|同上|还是|便宜点|40|太贵`。数字「40」只有在本场已有对方消息时才算指代。

### 8.2 输入与输出

输入是一段固定提示词加 JSON，不用用户可编辑的提示词。

```text
你只修改中文译文，让它符合这场对话。不要写印尼语或英语。不要解释。
只输出一行中文。没法判断就原样输出「字面」。

这场对话（时间顺序）：
{每条一行：对方：原文 ／ 中文：展示句}
{或：我：中文}

词：
{source = zh，没有则写无}

字面：
{zhLiteral 或游客原文}
```

输出取第一行，去掉引号和空白。空输出、超过 80 个汉字、含有拉丁字母单词（长度 ≥ 4 的连续拉丁字母，数字除外）都视为失败，保持字面。

与字面的比较用第 6.2 节的同一套规范化。规范化后相同：`zhDidCorrect = false`，界面不替换、不闪。不同：`zhDisplay` 改为这一行，`zhDidCorrect = true`。

超时 1.2 秒，从提示词开始计算，不含模型冷加载。冷加载另计，见第 8.4 节。超时放弃，保持字面。

### 8.3 模型选择

优先级：

1. 已有的指令小模型，量化后文件 ≤ 150MB，中文一问一答稳定。体量目标远小于 0.6B。0.6B 4-bit 约 400MB，超过上限，不能当默认。
2. 若没有合格的现成模型：第一版不带修正模型出货。词表数字规则和系统翻译仍然出货。
3. 只有当第 1 项在第 19 节的对话样本上明显忽略上下文，才训练 1 亿到 3 亿参数的改写模型。训练不是第一版开工条件。样本由离线的大模型标注，输入里要包含听写错字。训练产物仍受 150MB 限制。

运行时：llama.cpp 的 iOS 构建，Metal，GGUF。放在 `Corrector` actor。禁止在主线程 `llama_decode`。

上下文窗口配置 2048 token 足够。一场超过这个窗口时，保留最早 1 条和最近的消息，从最近开始往前塞，直到放不下。屏幕上的消息不删。

### 8.4 内存

- 第一次需要修正时才加载。
- `UIApplication.didReceiveMemoryWarningNotification`：立刻卸载权重。
- 进入后台不主动卸载。从 WhatsApp 回来要还能用字面翻译；修正能留住就留，留不住就等下次再加载。
- 与印尼语备用听写包互斥，见第 7.3 节。
- 冷加载目标 ≤ 1.5 秒。加载期间界面已经显示字面，不增加「正在看这句」的时间。
- 加载失败记一次本地日志，不含原文，本次会话不再自动重试加载。下次进程启动可以再试。

## 9. 一条消息的时序

### 9.1 对方，粘贴或听写结束

`TurnCoordinator.submitThem(text:localeHint:)`

1. 试用已用尽：仍创建对方消息，只做翻译，不做修正。这种字面消息不再计数。`Entitlement.allowsFull == false` 时跳过修正。
2. 决定 locale：默认等于开关。若第 10 节猜测为另一种语言，`offerRetranslateAs` 设为那种语言，但本轮仍用开关。
3. 写入 `Turn`，`status = translating`，`sourceText` 立即可见。
4. 印尼语则跑第 5 节数字替换，得到 `textForMT`。
5. `Translator.translate(textForMT, to: zh-Hans)`。
6. 成功：写 `zhLiteral` 与 `zhDisplay`，`status = ready`，试用未用尽则计数 +1。
7. 按第 8.1 节决定是否修正。修正任务单独 `Task`，不挡住第 6 步的界面刷新。4 秒内（从 `Turn.createdAt`）才允许写 `zhDisplay`。
8. 失败：`status` 为 `failedPackMissing` 或 `failed`。不计数。

### 9.2 我，发送中文或中文听写结束

1. 校验汉字或纯数字。不通过则不创建 `Turn`。
2. 试用用尽：不创建带译文的消息。界面用输入框下的句子拦截，文本留在输入框里。
3. 创建 `Turn`，主行立刻是中文，`status = translating`。
4. 纯数字：`foreignText` 等于原文，`status = ready`，计数 +1，结束。
5. 若命中指代正则且修正可用：最多等修正 1.2 秒得到「要翻译的中文」。失败用原文。
6. 翻译到 `theirLanguage`。2 秒超时。
7. 成功：写 `foreignText`，计数 +1，再跑回译。回译不挡住复制按钮。`foreignText` 一写入，复制和出示就可点。
8. 失败：中文气泡保留，`status = failed` 或 `failedPackMissing`。不计数。

### 9.3 重译一句话

`TurnCoordinator.retranslate(turnID:as:)`

只适用于对方消息。用新 locale 再跑第 9.1 节的第 4 到第 7 步，替换中文字段，不新增气泡，不重复计数。用户确认「之后都按{语言}」时才改 `Session.theirLanguage`。

## 10. 粘贴语言猜测

只用于是否显示「按英语重译 / 按印尼语重译」，不改变本轮翻译方向。

```text
function guess(text) -> id | en | unknown:
    if hanCount > 0: return unknown
    idHits = 印尼功能词命中数
    enHits = 英语功能词命中数
    if idHits >= 2 and idHits > enHits: return id
    if enHits >= 2 and enHits > idHits: return en
    return unknown
```

印尼功能词：`yang, tidak, nggak, gak, sudah, belum, bisa, mau, ini, itu, saja, dong, ya, di, ke, dari, untuk, dengan, ada, harga, ongkos, ribu`。

英语功能词：`the, and, you, this, that, with, for, not, can, please, price, wait, how, much, where`。

词按大小写不敏感的完整词计数。

猜测与开关相同，或为 `unknown`：不显示按钮。

## 11. 剪贴板

`scenePhase` 变为 `.active` 时读 `UIPasteboard.general`。

出现提示的条件全部满足：

- `hasStrings`。
- 去掉空白后非空，长度 ≤ 1000。超过 1000 仍提示，但收进对话时截断到 500，并走产品文档的超长提示。听写和输入框上限是 500，剪贴板检测放宽到 1000 只为能看见「太长」。
- 规范化后不等于当前会话最后一条的 `sourceText`，也不等于最后一条的 `zhDisplay`。
- 规范化后不等于本进程内上次被关闭的那段文字。

不使用 `UIPasteboard.detectedPatterns` 去联网。不把内容写入日志。提示关闭或被使用后，记录规范化字符串在内存里，不进磁盘。进程被杀后同一段剪贴板可以再提示一次，这是可以接受的。

点提示调用 `submitThem`。

## 12. 试用与购买

StoreKit 2，非消耗型，产品 ID：`unlock.full`。不上家庭共享。

```swift
enum EntitlementState {
    case trial(remaining: Int)
    case unlocked
}

enum TrialPolicy {
    static let freeCompleteTurns = 30
    static let bannerThreshold = 5
}
```

本地文件 `Application Support/trial.json`：`{ "used": 0 }`。只在完整消息成功时 +1。买断后忽略 `used`。

解锁判定：`Transaction.currentEntitlements` 含 `unlock.full` 且未撤销。启动时和购买后刷新。退款导致交易撤销后回到试用，`used` 保留，不重置。

恢复购买：`AppStore.sync()`，再刷新 entitlements。

价格按钮用 `Product.displayPrice`。产品文档里的 30 到 68 元只给商店标价，不写进客户端。

购买页与准备页的「一次买断」都加载同一个 `Product`。加载失败显示「价格暂时取不到」，按钮不可点，恢复购买仍可点。

## 13. 准备页状态

准备页的对方语言行从清单里 `enabled == true` 的项生成，每项两行：翻译、听写。中文听写是游客侧固定行，不放进对方语言清单。第一版因此仍是四行：中文听写、英语翻译与听写、印尼语翻译、印尼语听写。启用第三门对方语言时，准备页自己多出两行，不用改页面结构。

```swift
struct PrepareStatus: Equatable {
    var touristSpeech: Readiness
    var theirLanguages: [TheirLanguageReadiness]
}

struct TheirLanguageReadiness: Equatable, Identifiable {
    var id: String
    var translation: Readiness
    var speech: Readiness
}

enum Readiness: Equatable {
    case ready
    case needsDownload
    case checking
    case unavailable(String)
    case notEnoughSpace
}
```

`unavailable` 的文案只用产品文档允许的句子。

检查时机：进入准备页，以及对话页 `onAppear`。对话页只为了红点，不阻塞首屏。红点条件：任一可见行是 `needsDownload`。行数随启用语言变化。`unavailable` 不显示红点，避免无法完成的项永远红。

系统语言包下载用对应框架自己的下载 API，包在系统管理的空间。我们只展示就绪与否。

自有文件下载（仅印尼语备用听写或修正模型）：

- 清单：`prepare-manifest.json`，可先打进安装包。字段 `url, sha256, bytes, kind`。
- `URLSession` 下载，允许蜂窝的开关由确认框决定。
- 完成后校验。失败删除半成品。
- 断点：使用 `URLSession` 的 resume data。

修正模型若第一版不带，准备页不出现第五行。不要为了「以后可能有模型」加一行空的。

## 14. 出示与复制

复制：`UIPasteboard.general.string = foreignText`。只在 `foreignText` 非空且 `status == ready` 时可用。

出示：`fullScreenCover`，内容绑定该 `Turn.id`。封面出现期间不重新翻译。若这条消息被删除（新对话），出示页立即关闭。

出示页布局：`ZStack` 黑底。文本 `ViewThatFits` 或二分查找字号，从 96 pt 降到 34 pt，宽度为屏幕宽度减 40 pt。34 pt 仍超出则 `ScrollView` 只允许垂直。关闭按钮在安全区内，字号 15 pt，白色 80% 不透明度。点按空白调用 dismiss。`simultaneousGesture` 的下拉超过 60 pt 也 dismiss。

不修改 `UIUserInterfaceStyle`。背景写死 `Color.black`，文字 `Color.white`。

## 15. 界面状态机

对话页底部发送按钮：

| 条件 | 发送 |
| --- | --- |
| 输入规范化后为空 | 不可点 |
| 有消息正在 translating | 不可点 |
| 试用用尽 | 可点，但只触发用尽提示，不创建译文 |
| 其余 | 可点 |

听写按钮：

| 条件 | 结果 |
| --- | --- |
| 试用用尽 | 不可点 |
| 正在翻译或正在录音 | 不可点 |
| 该语言 availability 不是 ready | 可点，点了提示去准备，不录音 |
| 其余 | 按住录音 |

这些禁用用透明度 0.4 表示，仍占位，布局不跳动。

## 16. 错误码

`TurnCoordinator` 内部错误，不展示给用户原文，只映射成产品文案。

| 码 | 含义 | 用户可见 |
| --- | --- | --- |
| `packMissing` | 翻译或听写资源未安装 | 去准备 |
| `notOnDevice` | 系统试图走网络被我们拒绝 | 与没听清或翻译失败相同，不提示「开网」 |
| `timeout` | 超过第 6、7、8 节时限 | 失败句或保持字面 |
| `deniedMic` | 麦克风拒绝 | 去设置 |
| `deniedSpeech` | 语音识别拒绝 | 去设置 |
| `emptyASR` | 识别为空 | 没听清 |
| `cancelled` | 上滑或进后台 | 无气泡 |
| `notChinese` | 没有汉字且不是纯数字 | 输入框提示 |
| `trial` | 用尽后仍要发送完整消息 | 用尽句子 |
| `corruptSession` | 会话文件损坏 | 静默新开一场空对话 |

日志：`os.Logger`，子系统 `app.tripunderstand`。允许记录错误码、耗时、语言、字数。禁止记录文本、音频路径、剪贴板。Release 配置同样禁止。

## 17. 性能测量

在真机飞行模式、准备完成、修正模型若存在则已经冷启动过一次之后，用 `OSSignposter` 打点：

| 名字 | 起点 | 终点 | 目标 |
| --- | --- | --- | --- |
| `mt` | 调用翻译 | 返回 | 字面中文或对方语言 2 秒内可见。翻译本身目标 1 秒 |
| `asr` | 松手 | final 文本 | 8 秒以内的话，合计 4 秒内出现气泡 |
| `correct` | 字面已显示 | 放弃或替换 | ≤ 1.2 秒，且不晚于气泡创建后 4 秒 |
| `present` | 点出示 | 首帧黑底 | 一帧内，不出现进度指示 |

第 19 节的样本要在 iPhone 13 上留一份 Instruments 截图或 signpost 导出，放在 `docs/perf/`，不进安装包。

内存：Xcode Memory Report。听英语、粘贴印尼语、连续 20 句。峰值超过 700MB 就要卸载修正模型并复测。出现 jetsam 即视为失败。

## 18. 隐私实现

- 不集成统计 SDK，不接崩溃 SDK，除非其配置能保证不上传正文。第一版默认都不接。
- 不使用 `NWPathMonitor` 切换实现。可以在准备页用它决定要不要弹非 Wi-Fi 确认，不能用它打开在线翻译。
- 翻译 session 与听写 request 的 on-device 标志在代码审查清单里各有一条，缺了不能合并。
- 备份：会话文件设 `isExcludedFromBackup = true`，避免进 iCloud 备份。试用计数同样排除。买断不依赖这个文件。
- 截图允许。不出示页水印。

Info.plist 只有产品文档第 12 节的两则用途说明，外加加密出口声明使用系统 HTTPS 的豁免（若备用包下载使用 HTTPS）。

## 19. 测试

### 19.1 单元测试，不依赖真机

- 数字：`50rb` → 送译文本含「5万」；原文副行仍含 `50rb`。`1,5jt` 按 1.5 juta 处理并有明确期望值，测试里写死期望。
- 词边界：`bisa` 不误伤更长词。
- 回译重合率：完全一致、只差标点、丢掉数字、完全不同，四例。
- 语言猜测：纯英语、纯印尼语、`ok`、含汉字，四例。
- 试用：第 30 条成功后 `allowsFull == false`；失败消息不计数；买断后忽略 used。
- 会话：写入后杀掉内存中的对象再读出；损坏 JSON 会备份并得到空会话。
- 4 秒修正窗口：把时钟注入成创建后 5 秒，修正结果被丢弃。
- 指代正则与「纯数字不翻译」。

`Translator` 和 `Speaker` 用协议假对象。测试不调用系统翻译。

### 19.2 真机验收

执行产品需求文档第 19 节的 14 条。设备矩阵：iPhone 13 或 13 mini（4GB）、iPhone 14（6GB）、iPhone 16 或更新（8GB）。系统为最低支持版本和当时最新版本各一套即可，至少 iPhone 13 跑最低系统。

额外技术项：

- 飞行模式下抓包或 Charles 无此应用的连接。没有代理时用网络调试仪表确认无请求。准备页下载除外，该项在飞行模式下应失败并保持未就绪，而不是崩溃。
- 连续从微信或备忘录复制 10 次再回来，当前会话条数正确，进程不被 jetsam。
- 内存警告模拟后，字面翻译仍成功。

### 19.3 样本对话

开发自测固定用这三句，写进测试或样例资源：

1. 对方：`50rb belum termasuk ongkos`
2. 我：`太贵了，能不能便宜一点`
3. 对方：`yang tadi 40 saja`

期望：第 1 句中文含 5 万和车费的意思；第 2 句能复制出印尼文；第 3 句在修正可用时，中文能看出是刚才的价格而不是孤立的「刚才」。修正不可用时第 3 句只要有字面中文和原文。

## 20. 实现顺序

按这个顺序做，前一步没在飞行模式下走通，不开始下一步。

1. 会话文件、对话页、对方气泡和我的气泡的静态数据。
2. 系统翻译：粘贴印尼语、发送中文、复制、出示。
3. 数字俗写和词表结构。
4. 英语开关，旧消息不重译。
5. 中文与英语的系统听写，按住、取消、30 秒。
6. 剪贴板提示。
7. 试用与 StoreKit。沙盒购买和恢复。
8. 准备页四行状态。
9. iPhone 13 飞行模式听写实验。通过则接上印尼语系统听写；失败则按第 7.3 节做备用包，或把该行标成不可用。
10. 修正模型。最后做。没有合格的 150MB 以内模型就跳过，不挡住出货。

第 10 步跳过时，产品文档里「字面」行不会出现，这是符合产品文档的：只有意思和字面不同才出现。

## 21. 风险与对应实现

| 风险 | 实现上怎么接 |
| --- | --- |
| 印尼语系统听写不能离线 | 第 7.3 节实验。失败则备用包或明确不可用。粘贴路径不依赖它 |
| 4GB 上自有模型把进程杀掉 | 150MB 上限、与听写互斥、内存警告卸载。字面翻译不加载模型 |
| 系统翻译把口语译平 | 数字用代码，词表进修正。修正缺失时至少数字是对的 |
| 从聊天软件回来要重新加载大模型 | 不把大模型当主路径。字面翻译用系统框架，不占我们的权重 |
| 回译小题大做挡住复制 | 回译异步。`foreignText` 一到就能复制 |
| 游客把英文打进输入框 | 没有汉字就不创建消息 |
| 试用计数被卸载清掉 | 接受。买断靠 StoreKit，不靠本地计数 |

## 22. 语言清单，坑位留在第一版

其他语言放缓，不是明确不做。最终要能装很多地方的语言。第一版代码就按清单写，不把印尼语和英语写成仅有的两个 `case`。

`Resources/languages.json`：

```json
{
  "version": 1,
  "touristLanguage": "zh-Hans",
  "defaultTheirLanguage": "id",
  "languages": [
    {"id": "id", "displayName": "印尼语", "enabled": true, "glossary": "glossary-id.json", "numericRules": "id-rupiah"},
    {"id": "en", "displayName": "英语", "enabled": true, "glossary": null, "numericRules": null}
  ]
}
```

启用一门放缓的语言时，只允许做这些事：

- 在 `languages` 里把对应项 `enabled` 设为 true，或追加一项。
- 需要词表就加 `glossary-{id}.json`。有数字俗写就加一条规则，没有就 `numericRules` 为空。
- 确认系统翻译和听写的 locale。听写不了就沿用印尼语那条备用包接口，按 locale 参数化，不复制一套界面。

禁止：为新语言复制对话页、出示页或购买页。禁止在界面层 `switch` 穷尽印尼语和英语而不留默认分支。未知或未启用的 id 不得进入开关；会话里若读到已禁用的 id，回退到 `defaultTheirLanguage`。

`Translator` 与 `Speaker` 的参数已经是 locale。语言清单只决定哪些 locale 对用户可见。

Android 以后复用这份 JSON、`session-current.json` 的字段含义、词表 JSON、错误码名字，以及「字面先上屏、修正失败保持字面」。不复用 Swift 调用。
