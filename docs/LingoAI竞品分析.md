# LingoAI 竞品分析（离线翻译 + 图片 OCR）

> 调研日期：2026-10-10。标注：**【官方】**＝App Store / 官网 / 隐私政策原文；**【推断】**＝根据公开信息推理，未经证实；**【未知】**＝查不到。没有自己安装测试过。

## 0. 结论先行

- 用户说的「离线 + 支持图片 OCR 的 LingoAI」，基本可以确定是 **LingoAI: Offline AI Translator（又名 LingoAI Translate），开发者 Dajiale / MZSoft Studio（Yongliang Wang）**，App Store id6757940310。
- 它的路线和我们很接近：**把一个端侧翻译专用 LLM 直接打进安装包**（腾讯混元 Hy-MT 1.8B，安装包约 1.2GB），系统 Translation 作为第二引擎，云端可选。差别在于：它是通用翻译工具，**没有「上下文理解 / 数字俗写 / 砍价」这一层**，Relay 对话模式也只是逐条翻译。我们的差异点还在。
- OCR：它说「只在设备上识别文字」，但**没说用的是哪套引擎**；大概率是 Apple Vision / VisionKit【推断】。
- **对我们的建议：把 OCR 定为 P1（第一版发布后的首个迭代）**。用 Vision 离线识别价签、菜单、收据，复用现有的金额解析把「Rp 50.000」「50rb」直接换算成中文金额，这是成本低、和定位贴得很紧的功能。印尼语用 Vision 的拉丁字母识别能读出来，但官方语言列表里没有印尼语，必须真机验证（见 §4）。
- **最值得马上借鉴的一点（P0）**：Hy-MT1.5-1.8B 是专门做翻译的模型，**原生支持印尼语↔中文**，腾讯还发布了 2-bit 574MB / 1.25-bit 440MB 的 GGUF 量化版。这可能改变我们「系统 Translation 出字面意思 + Qwen 做理解」的双模型方案，应该加进模型评测。

## 1. 叫 LingoAI 的产品

| # | 名称 | 形态 | 和用户描述是否吻合 | 链接 |
|---|---|---|---|---|
| **A** | **LingoAI: Offline AI Translator / LingoAI Translate**（Dajiale / MZSoft） | iOS / iPadOS / Apple 芯片 Mac | **吻合**：离线翻译 + 相机 / 照片 OCR + 语音 | https://apps.apple.com/us/app/lingoai-offline-translator/id6757940310 · 官网 https://www.mzjpg.com/products/lingoai |
| B | LingoAI - AI Translator（Oak Premium / BookTok） | iOS，学语言为主 | 不吻合（云端 AI 对话学习，订阅 $29.99/月） | https://apps.apple.com/us/app/lingoai-ai-translator/id6743612570 |
| C | Offline Translator: Lingo AI（CodeBox） | Android | 部分吻合（声称 60+ 语言离线、有相机翻译），但不是 iOS；AppBrain 显示评分 4.14（约 990 条） | https://play.google.com/store/apps/details?id=com.all.language.translator.app.free.voice.translation · https://www.appbrain.com/app/offline-translator-lingo-ai/com.all.language.translator.app.free.voice.translation |
| D | LingoAI LingoPod（lingoai.io） | Web3 / DePIN 翻译耳机 | 不吻合（声称离线 20 个语言对，带代币挖矿） | https://docs.lingoai.io/product/lingopod/lingopod-faq |
| E | 其他同名 / 近似：Lingo（macOS 菜单栏翻译，开源）、LingoPlugs 耳机、Translate Now 里的「Lingo AI」功能 | — | 不吻合 | https://github.com/JasonSung0724/Lingo-ai-translator · https://lingoplugs.com/products/lingobuds-ai-translator-pro |

以下只分析 **A**。

## 2. 产品 A 详情

### 2.1 基本信息【官方，iTunes Lookup 接口 + App Store 页面】
- 版本 3.0（2026-10-09 更新；首发 2026-01-26）。安装包 **1.2GB（1,203,685,376 字节）**。最低 iOS 18。类别：参考。
- 美区评分 4.5，**只有 2 条评分**；中国、新加坡、印尼区的评论 RSS 都没有评论。用户量很小，**评论里的好评差评都没有参考价值**。商店描述里的「What people are saying / Comments from my friends」是开发者自己写的引语，不算用户评论。

### 2.2 翻译怎么做（三个引擎）【官方】
| 引擎 | 实现 | 用途 |
|---|---|---|
| LingoAI Model（默认） | App 里自带的离线翻译模型。商店里的署名：美区写 *Tencent Hy-MT2 (1.8B)*，新加坡区写 *Tencent HY-MT1.5*，商店页自称 Apache 2.0，**但 HY-MT1.5 的实际许可是 Tencent HY Community License**（不授权欧盟、英国、韩国；禁止用输出改进其他模型），见端侧模型验证报告附录 H | 长句、习语，全离线 |
| System | Apple 系统的端侧 Translation | 短语，「接近即时」；语言包由 iOS 下载 |
| Cloud（可选，默认关闭） | 自家服务器 ai.mzjpg.com → Cloudflare AI Gateway → Nebius（DeepSeek）/ 阿里云百炼（Qwen、DeepSeek、GLM）/ Google Gemini | 整篇文档一次翻译，保持术语一致；正式 / 随意语气；多 75 种语言；按点数计费；云端不可用时退回端侧 |

- **是 LLM 吗**：是。Hy-MT1.5-1.8B 是腾讯混元的翻译专用模型（经过 MT 预训练、SFT、在线蒸馏、RL）。支持 33 种语言 + 5 种方言，**其中有印尼语和中文**。官方称超过 Qwen3-32B 和主流商用翻译 API【官方：模型卡，未独立验证】。https://huggingface.co/tencent/HY-MT1.5-1.8B
- 量化版：2-bit 574MB、1.25-bit 440MB，有 GGUF；针对带 Arm SME2 的设备（如 Apple M4）优化【官方】。https://huggingface.co/tencent/Hy-MT1.5-1.8B-2bit-GGUF · https://huggingface.co/tencent/Hy-MT1.5-1.8B-1.25bit
- App 里用的是哪种量化、什么推理框架（llama.cpp、MLX 还是 Core ML）：**【未知】**。安装包 1.2GB，推测是 4-bit 左右或 FP16 的部分权重【推断】。
- **下载流程：没有单独下载**。「完整模型打在 App 里，第一次打开就能离线用，不用再下载任何东西」。代价是 App Store 下载 1.2GB。只有 System 引擎的语言包由 iOS 另行下载。
- 时延：只写了「fast」「near-instant（System）」，**没有任何具体数字**【未知】。
- 上下文 / 语义能力：端侧只有「习语」；**术语一致、语气这些都在 Cloud 里**。端侧没有对话上下文、指代、数字俗写的处理【根据描述推断】。

### 2.3 OCR / 图片翻译
- 【官方】有「Live camera scan」实时相机扫描，也能从已有照片里提取文字；「相机和照片只用来在设备上识别文字，不上传、不保存」。
- 用的哪套 OCR 引擎：**【未知】**。没写自研，也没写第三方 OCR 的许可证（商店里只署名了 Hy-MT）。所以**大概率是 Apple Vision（VNRecognizeTextRequest / RecognizeTextRequest）或 VisionKit 的 Live Text**【推断】。
- 翻译结果是盖在原图上，还是提取文字后放进文本框：**【未知】**。从「lift text out of a photo」这个说法看，更像是先提取文字、再进翻译页【推断】。

### 2.4 其他功能【官方】
- 文本、粘贴（**「一键粘贴提示条，而不是弹窗」**）、听写（自动识别语言）、导入 .txt / Markdown、多目标语言并排对比、朗读（可调速度，可走听筒私下听）、可搜索的历史、常用语言对预设、主题和触感反馈。
- **Relay（面对面对话）**：双方各自用自己的语言说话或打字，所有消息翻译后出现在**同一个共享会话**里，双方都能看、能听。可以清空会话消息但保留会话。免费版只有 1 个文字 Relay + 1 个语音 Relay 会话。**没有提到分屏 / 上下颠倒的面对面布局**【未知】。
- LingoAI 键盘（3.0 新增）：在任意 App 里边打字边翻译。用的是 Apple 端侧翻译引擎，要开「完全访问」，键盘不含任何网络代码。
- 单次翻译上限 2,048 字符（免费版）。

### 2.5 价格【官方】
- 免费（**有 AdMob 广告**）+ 一次性买断：Lifetime Premium **$29.99**（不是订阅，含 500 云点数）。也可以单项购买：无限 Relay $9.99、长文本 $9.99、预设 $9.99、去广告 $4.99。云点数：100 点 $2.99 / 500 点 $9.99 / 1000 点 $14.99，永不过期，短句 1 点。

### 2.6 隐私【官方：隐私政策 https://www.mzjpg.com/policy/lingoai，2026-09-25】
- 不用注册账号；端侧翻译内容不上传；历史和 Relay 录音存在本机。
- 但**免费版的 AdMob 会收集设备标识符、IP、粗略位置**；App Store 隐私标签里有「第三方广告：标识符、使用数据」。语音输入用的是 Apple Speech，**政策承认可能在 Apple 服务器上处理**。Cloud 模式会经过多个模型供应商。

## 3. 和我们（PRD v2 / 技术 v2）对比

| 维度 | LingoAI | 我们 |
|---|---|---|
| 定位 | 通用翻译工具，38 种语言 | 中国游客在印尼，只做「把对话进行下去」 |
| 端侧模型 | Hy-MT 1.8B，**打在安装包里**（1.2GB） | Qwen2.5-1.5B Q4_K_M（约 1.1GB），**首次启动强制下载** |
| 翻译主链 | LLM 直接翻译（默认）/ 系统 Translation | 系统 Translation 出字面意思 → LLM 结合上下文给「理解」 + 代码校验金额 |
| 上下文 / 俗写数字 / 砍价 | 无 | 核心卖点 |
| 对话 | Relay 共享会话 | 对话页 + 出示页（大字给对方看） |
| 语音 | Apple Speech，可能走服务器 | 强制本机识别（SpeechAnalyzer / SFSpeech 要求本机识别） |
| OCR | 有（引擎未知） | **没有** |
| 云端 | 可选，按点数 | 完全不联网 |
| 价格 | 买断 $29.99 + 广告 + 云点数 | 30 条试用 + 买断（见 PRD v2 §15） |
| 隐私 | 免费版有广告追踪 | 不追踪；匿名计数可关 |

## 4. 候选功能：离线 OCR（价签 / 菜单 / 招牌 / 收据）

### 4.1 iOS 上离线能不能做
- **Vision 文字识别**（VNRecognizeTextRequest，iOS 13+；Swift 版 RecognizeTextRequest，iOS 18+）：完全在本机运行，不用另外下载模型，打在系统里。
- **语言**：网上实测的 iOS 18 支持列表是 en-US、fr-FR、it-IT、de-DE、es-ES、pt-BR、zh-Hans、zh-Hant、yue、ko-KR、ja-JP、ru-RU、uk-UA、th-TH、vi-VT、ar-SA、ars-SA。**没有 id-ID**。来源：https://en.zhgchg.li/posts/kkday-tech-blog/ios-vision-framework-explore-swift-api-enhancements-from-wwdc-24-session-755509180ca8/ 。iOS 26 有没有加：**【未知】**，要在真机上调用 `supportedRecognitionLanguages` 查。
- **对策**：印尼语是纯拉丁字母、基本没有变音符号，用 `["en-US"]`（或 en-US + zh-Hans）配合 `.accurate` 就能识别字符。把 `usesLanguageCorrection` 关掉，避免把「rb / jt / brp」这类缩写「纠正」成英文单词。价格数字（「Rp 25.000」「25rb」「@15k」）不依赖语言模型。**结论：技术上可行，准确率要真机验证**【推断】。
- **VisionKit Live Text**（ImageAnalyzer / ImageAnalysisInteraction，iOS 16+）：能免费拿到系统原生的「长按选字 / 复制」交互；Live Text 系统自带翻译。但支持的语言同样受限，而且很难插入我们自己的金额换算和「理解」层。建议只作为选字交互的辅助。
- **把翻译盖在原图上**：用 Vision 返回的 `boundingBox` 在原文位置画中文标签。可行，大约 2 人周【推断】。
- 翻译走现有的 Translation 框架（离线语言包已经在强制下载里了）→ 金额走 `AmountNormalizer` → 菜单 / 招牌这类短文本可选走 LLM 理解（例如「nasi goreng ayam」→「鸡肉炒饭」）。

### 4.2 场景和价值
| 场景 | 价值 | 复用 |
|---|---|---|
| 市场 / 超市价签「Rp 25.000」「25rb」「3 for 50k」 | **高**：直接显示「2万5千印尼盾」，和砍价对话打通（「把这个价格带进对话」） | AmountNormalizer、出示页 |
| 菜单 | 高：菜名 + 价格；端侧 LLM 解释菜名 | Translation + LLM |
| 招牌 / 告示（Dilarang…, Keluar） | 中 | Translation |
| 收据 / 账单核对 | 中：逐项金额求和、核对是否多收 | AmountNormalizer |

### 4.3 优先级建议：**P1**
- 第一版不加。理由：PRD v2 §20 已经压了范围，核心链路（强制下载 + 对话 + 理解）的真机验证还没做；OCR 会多一个相机 / 照片权限、多一套审核材料。
- 第一版之后的首个迭代做「拍价签 / 菜单」：先只做静态拍照（不做实时 AR），走提取文字 → 列表展示原文 / 中文 / 金额，加一个「放进对话」按钮。
- 为第一版预留：`AmountNormalizer` 已经是纯函数可以直接复用；在 Readiness 里不需要新增下载项（Vision 是系统自带的）。

## 5. 可借鉴点（按优先级）

**P0（建议立刻做）**
1. **把 Hy-MT1.5-1.8B 加进模型评测**（GGUF 2-bit 574MB / 1.25-bit 440MB / Q4）。用 docs/model_eval 的 30 条用例对比 Qwen2.5-1.5B。如果它的印尼语↔中文直译质量明显好于系统 Translation，可以考虑「Hy-MT 直译 + Qwen 理解」，或者干脆用 Hy-MT 单模型同时做直译和理解（要测它能不能按指令输出结构化结果、带上下文）。**更正：许可证是 Tencent HY Community License，不是 Apache 2.0**。**已测完，结论见端侧模型验证报告附录 H：不替换现方案。**注意：它的 SME2 优化针对 M4，**A17 / A18 iPhone 上的速度未知**。
2. **粘贴用「一键提示条，不用系统弹窗」**：和我们 PRD v2 的 PasteButton 方案一致，确认方向是对的。
3. **用文案强调「完全离线、不注册账号、不追踪」**：LingoAI 免费版带 AdMob、语音可能走服务器、Cloud 会出设备，这些都是它的隐私短板。我们是「强制本机语音识别 + 零网络」，应该在商店页和隐私页明确对比式表述（不点名竞品）。

**P1**
4. **离线 OCR 拍价签 / 菜单**（§4）。
5. **朗读译文，可调速度、可走听筒私下听**：用 AVSpeechSynthesizer 离线就能做，出示页加「读给对方听」，成本很低。
6. **会话里「清空消息但保留会话」**：和我们「新对话 / 清除本机对话」的区分可以参考，放进设置的说明文案里。
7. **一次性买断 + 单项购买**：它用 $29.99 买断，说明这个品类的用户接受买断。我们的买断价可以参考这个价位，**不做订阅**。

**P2**
8. 双引擎提示：短句走系统 Translation「接近即时」、长句走模型。我们本来就是「字面意思先出、理解后替换」，可以在 UI 上更明确地标出「字面」和「理解」。
9. 「常用语言对预设」对我们意义不大（固定是中文↔印尼语 / 英语）。

## 6. 要避免的
- **把模型打进安装包**：1.2GB 的 App Store 下载，在蜂窝网络下会被系统限制或提示，转化率低。另外每次修复 bug 都要用户重新下载 1.2GB，除非模型放在按需资源里。我们的「薄壳 + 首次强制下载」更利于快速迭代，但要做好 App Store 审核说明（见评审报告）。或者折中：评估用 **Background Assets** 托管到 Apple 服务器【建议另做调研】。
- **Cloud 退路和广告 SDK**：违背我们「完全离线」的承诺和隐私标签，不要加。
- **在商店描述里写自编「用户评价」**：可能被审核认定为误导（Guideline 2.3），不要这样做。
- **单次 2,048 字符这类限制和多种单项内购**：对一个人用的旅行场景太复杂，保持「试用 30 条 → 一次买断」。
- **语音可能走 Apple 服务器**：我们必须坚持 `requiresOnDeviceRecognition = true`，SpeechAnalyzer 只在语言资源已经装好时才用（demo 已经这样实现）。

## 7. 未知 / 待验证
- LingoAI 的推理框架、量化方式、真机时延和内存；OCR 引擎；Relay 有没有分屏 UI。
- 美区写「Hy-MT2」、新加坡区写「HY-MT1.5」，署名不一致（可能是版本升级后各区描述没同步）。Hy-MT2 公开模型卡没查到【未知】。
- iOS 26 的 Vision 有没有加印尼语。
- Hy-MT1.5 在 iPhone（非 SME2）上的 tokens/s。
