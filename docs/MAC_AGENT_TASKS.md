# Mac 执行手册（给在用户 Mac 上运行的 AI 代理）

> 你只有仓库地址：`https://github.com/xhq52465840/offline-trip-translator`（默认分支 `master`）。
> 本手册自包含：按 T0 → T7 顺序执行，并按文末「§迭代循环」一轮一轮重复（每轮编号 r1、r2…）。每个任务都有：目标、命令、成功标准、失败处理、记录内容。
> 假设机器为 Apple Silicon Mac。所有时间按用户本地时区记录。

## 总规则（必须遵守）

1. **不要绕过失败**：命令失败时，把完整报错原文（verbatim）写进报告，标记该任务为 ❌/⚠️，然后继续下一个**不依赖它**的任务。不要改系统设置、不要关 SIP、不要 `sudo` 改系统目录、不要禁用签名/校验。
2. **允许的代码修改只有一种**：T3/T4 中 Xcode 编译错误的**最小修复**（每处修复都要在报告里列出：文件、行、原因、diff）。其他任何代码不要改。
3. **绝不提交**：`.gguf`、`.safetensors`、`.bin`、适配器权重、`finetune/runs/` 下任何东西、任何密钥/令牌/证书/个人路径以外的隐私信息。仓库 `.gitignore` 已排除这些，提交前仍需 `git status` 人工核对。
4. **不要上传模型**到任何地方（不传 HF、不传网盘、不传对象存储）。只在报告里写本地路径、字节数、sha256。**唯一例外（用户 2026-10-14 批准）**：r8 把 s400 一个文件上传到本仓库 GitHub Release `model-s400-v1`，见 r8 清单；其他模型文件仍不上传。
5. 不要修改 `TripCore/Sources/TripCore/Resources/model-manifest.json` 里的地址/哈希（托管方案未定）。
6. 所有输出写到仓库内 `reports/mac_run_<日期>_r<轮次>.md`（模板见文末），结果 JSON 放 `finetune/results/`。
7. 长任务用 `caffeinate` 防睡眠，并把日志写到文件，不要只看终端。

先设置几个变量（后续命令都用它们）：

```bash
export RUN_DATE=$(date +%Y%m%d)
export WORK=$HOME/trip-work            # 工作目录（模型、llama.cpp、venv 放这里，不在仓库里）
export REPO=$WORK/offline-trip-translator
export LLAMA_CPP=$WORK/llama.cpp
export VENV=$WORK/venv-ft
export ROUND=${ROUND:-1}                # 当前轮次，见 §迭代循环
export BR=mac-run-$RUN_DATE-r$ROUND
export SCREENS=reports/screens/$RUN_DATE-r$ROUND
mkdir -p "$WORK"
```

---

## ▶️ 当前轮次：r10 —— v4 交互改版验收（2026-10-15 重新开启 Mac 循环）

**用户说「pull master and continue」就做这一节。** 方案：`docs/交互改版方案_v4.md`；线框：`docs/wireframes/01–04*.png`。
盒子已实现 V1–V7（每阶段一个提交），`swift test` 200 项全绿、`i18n check` OK、`swiftc -parse` 通过。**盒子不能编译 SwiftUI**，所以你的首要任务是：编译、跑 UI 测试、截图对照线框。

规则不变：只允许 Xcode 编译错误的最小修复（列出文件/行/diff）；不改业务逻辑；不提交权重；不合并 PR。

### r10 清单

1. **准备**：`git pull origin master`；`ROUND=10`；分支 `mac-run-<日期>-r10`；`cd TripCore && swift test`（期望 200，全绿）；`python3 scripts/i18n.py check` = OK；`cd App && xcodegen generate`；编译 TripUnderstand（模拟器 + Generic iOS Device）。编译错误按规则 2 最小修复（盒子只做了 `-parse`，可能有类型错误，重点看 `ConversationView.swift`、`OnboardingView.swift`、`AppState.swift`）。
2. **UI 测试中英两遍**（`TripUITests` 中文 19 项 + `TripUITestsEnglish` 英文 17 项），`TEST_RUNNER_SCREEN_DIR=$SCREENS`。全绿；失败的贴原文和截图。新增/改动用例：
   - `testFirstLaunchTwoSteps`、`testStatusBarInsteadOfBlockingSheet`、`testPhraseBookFromSettingsAndPresent`、`testPurchasePageOpens`（改从设置进入）
   - `testMoneyCardPresentsFullScreen`、`testAmountConversionShown(English)`（改查金额卡 label）
   - `testContextualRepliesAfterPrice`、`testSingleHoldToTalkAndSwitch`、`testFaceToFaceShowsAmounts`、`testEmptyConversationStarters`、`testAccessibilityXXXLMoneyCard`
   - 回归：`testHomeAndChatWithMockEngine`（zh→id）、`testChineseMeEnglishPartner`、`testEnglishMeChinesePartnerAndFaceToFace`、`testSwapLanguages`、`testEnglishUIHasNoChinese`
3. **截图对照线框**（报告里每张线框放一张对应截图，逐条写 ✅/❌）：
   - 线框 01 对话首页 ↔ `06_home`、`17_empty_starters`、`15_single_talk_button`：冷启动直接是对话页；没有场景网格；「按住说话」是全屏最大元素且高度 ≥ 96pt；下面有「给对方看（面对面）」；左上角设置菜单里有 离线准备/汇率/常用句/隐私/界面语言/购买/使用统计。
   - 线框 02 金额卡 + 情境回复 ↔ `13_money_card`、`14_context_replies`、`08_amount_conversion(_en)`：卡片在气泡最上方、原币字号最大、≈¥/$ 第二行强调色；英文界面没有「万印尼盾」；快捷回复区标题「根据对方的话推荐」，含「太贵了，便宜点」和程序算出的「8万印尼盾行吗？」（100.000×80%）；点一下直接发出印尼语。
   - 线框 03 面对面 ↔ `11_face_to_face_lang`、`16_face_to_face_amount`：上半屏倒置，显示最新一句（对方语言）+ `Rp 100.000` 大字 + 对方按住说话；下半屏我的语言 + 金额卡 + 按住说话 + 退出/大字出示。
   - 线框 04 首次打开 ↔ `01_onboarding`、`01b_first_launch_pick`、`01c_first_launch_done`：只有「我说/对方说」两组 + 下载大小一行 + 「开始用」；没有购买/隐私/准备列表；点开始后直接进对话页（mock 下顶部出现状态条）。
4. **状态条三种状态**（截图 + 结论）：
   - `mock-not-ready` → `02_status_bar_not_ready`：顶部状态条、**没有**阻断弹窗、输入框可用、快捷句可点。
   - 模拟器里把 Mac 断网（或飞行模式模拟）后用 `mock-not-ready` 启动：状态条应变成「连上网后自动继续下载」。只记录结果，不需要改代码。
   - 真实构建（非 mock）首次启动走一遍：选语言 → 开始用 → 状态条显示「理解能力准备中 xx%」（模拟器后台 URLSession 4097 是已知限制，记录即可）。
5. **无障碍**：Accessibility Inspector 跑对话页、金额卡、面对面、首次打开，贴告警；`18_ax5_money_card` 人工看是否截断；打开旁白：金额卡读成一整句「对方报价 10万印尼盾，约 ¥37…」，按住说话按钮旁白下「点一下开始、再点一下结束」能录一句（模拟器无麦克风可只确认没崩溃）。
6. **回归**：照 r9 的三条样例（zh→id、id→zh 含金额、英文 fallback）在模拟器真模型下各跑一次，输出贴原文；确认低质量标签、金额只由程序生成没有变化。
7. **交付**：报告 `reports/mac_run_<日期>_r10.md`；截图 `reports/screens/<日期>-r10/`；开 PR「Mac run r10」，不要合并。

---

## （历史）⛔ Mac 循环曾在 r9 后结束（2026-10-14）—— 已被上面的 r10 取代

（以下为 r9 结束时的说明，仅存档；现在请执行 r10。）

最终状态：
- 模型：s400（`trip-mix2-s400-Q4_K_M.gguf`，986048640 字节，sha256 `691a1b2b…f05b0a`），已在 GitHub Release `model-s400-v1`，盒子独立下载核对一致；清单 v5 只指向它。
- App：中英 UI 24 项连续多轮全绿；`swift test` 170 项（盒子，r9 审阅后）。
- r9 真实模型（模拟器 CPU）：不再输出「!!!!」，整句 7–11 秒，内存峰值约 2.3 GB。r9 暴露的三个兜底问题已在盒子修复并有单元测试（见下），**没有再上 Mac 复测**，改由真机清单 C 节覆盖：
  1. 中→印本机模型照抄中文原句 → 现在判为失败，显示「这句还没翻译出来」；
  2. 本机模型丢了金额占位符、把 50rb 写成「50元人民币」→ 不再显示它的整句直译，改为「原文（5万）」；
  3. 理解结果把印尼盾说成「人民币」→ 校验器拒绝（原文提到人民币 / ¥ 时除外）。

---

## 当前轮次：r9 = 最后一轮：模拟器真实模型复测（r8 已审阅合并；拉取 master 后按此清单执行）

> 用户只会说「pull master and continue」。开 PR `Mac run r9`，**不要 merge**。**r9 全绿后 Mac 循环结束**：之后再收到「continue」，只回复「Mac 循环已结束，剩下的是真机步骤（docs/真机验证清单.md）」，不要再开新轮次。
> r8 结论：Release `model-s400-v1` 已上线，盒子独立下载核对：986048640 字节、sha256 `691a1b2b…f05b0a`、GGUF 头、支持 Range ✓；清单地址一致 ✓；隐私清单进工程 ✓；中英 UI 24 项 ✓；只检查两种语言 ✓；兜底标注中英 ✓。
> 问题与盒子修复（本轮要验证）：
> - 模拟器上真实模型输出整串「!!!!」→ 模拟器的 Metal 跑 llama.cpp 不可靠，`LlamaCppEngine` 在模拟器里改成纯 CPU（`gpuLayers = 0`）；另加「坏输出」检测，整串重复 / 几乎没有文字的输出当失败，绝不显示。
> - 我方改英语后被「听英语暂不可用」阻断且关不掉 → 我方听写**不可用**时不再阻断（可打字）；可下载时仍提示下载。
> - App 后台下载在模拟器连不上 nsurlsessiond（4097）：模拟器限制，真机验证（真机清单 A 节），不改代码。

1. `git pull`；`ROUND=9`；`swift test`（167）全绿；`i18n check` OK；`xcodegen generate`；编译；中英 UI 测试 24 项全绿。
2. 和 r8 一样把 curl 核对过的 s400 放进 App 容器（`models/trip-mix2-s400-q4_k_m/model.gguf` + `installed.json`），DEBUG 构建、不加 `-UITestMode`。
3. 同样 3 句（我方中文 ← `50rb belum termasuk ongkos`；我方中文 → `太贵了，能便宜一点吗`；我方英文 ← `harganya 100rb kak`），记录：显示内容、秒表耗时、RSS 峰值、截图 `r9_s1/s2/s3.png`。
   - **预期**：正文是正常的中文 / 印尼语 / 英文（不再是「!!!!」）；若模型仍输出坏结果，气泡应显示「这句还没翻译出来」而不是乱码。两种情况都如实记录。
   - 第 3 句前在对话里把**我方**改成英语：不应再被「听英语暂不可用」阻断（截图 `r9_my_en.png`）。
4. 报告 `reports/mac_run_<日期>_r9.md`，PR `Mac run r9`，**不要 merge**。最后一行写「Mac 循环结束」。

---

## 当前轮次：r8 = 上传 s400 到 GitHub Release + 用真实模型回归（r7 已审阅合并；拉取 master 后按此清单执行）

> 用户只会说「pull master and continue」。开 PR `Mac run r8`，**不要 merge**。
> **用户已批准：本轮由 Mac 直接把 s400 GGUF 上传到公开仓库的 GitHub Release `model-s400-v1`。** 只上传 s400 这一个模型文件和下面列出的附件；不要上传 s600/s1000、适配器、训练日志。权重**仍然不提交到 git**。
> 最终模型 = s400：`finetune/runs/trip-mix2-s400-Q4_K_M.gguf`，986048640 字节，sha256 `691a1b2b1e0b73e3e2156583505300697753184477176301924877f73bf05b0a`。
> 盒子新增（r8 之前）：印→英走 Apple 直译；Apple 翻译不支持 / 没装好的方向改用本地模型直译（`FallbackTranslator`），这类方向不再阻断启动；隐私清单 `PrivacyInfo.xcprivacy`；
> 本机模型兜底的气泡下方标注「本机模型翻译，质量较低，重要信息请再确认」（英文 “Translated by the on-device model (lower quality) …”）；准备检查只看**我方 + 当前对方**两种语言；清单删掉占位 CDN，只剩 GitHub（清单版本 5）。

1. **代码**：`git pull origin master`；`ROUND=8`；分支 `mac-run-<日期>-r8`。`swift test`（164）全绿；`python3 scripts/i18n.py check` OK；`cd App && xcodegen generate`（会把 `PrivacyInfo.xcprivacy` 加进资源，确认 Build Phases 里有）；编译。中英 UI 测试一次跑完（`TripUITests` + `TripUITestsEnglish`），全绿。看 `08_amount_conversion_en`：直译 + `≈ $5.6`；`08_amount_conversion`：理解后的「约 ¥37」。
2. **核对 sha256**：`shasum -a 256 finetune/runs/trip-mix2-s400-Q4_K_M.gguf` 和 `stat -f %z`，必须等于上面的两个值，否则**停止**并报告。
3. **准备附件**（放 `~/trip-work/release/model-s400-v1/`，不进 git）：
   - `SHA256SUMS`：`691a1b2b1e0b73e3e2156583505300697753184477176301924877f73bf05b0a  trip-mix2-s400-Q4_K_M.gguf`
   - `LICENSE-Qwen2.5.txt`：Apache-2.0 全文（Qwen2.5-1.5B-Instruct 的许可证）
   - `NOTICE.txt`：复制仓库 `NOTICE.md`，开头加一段「本文件为 Qwen2.5-1.5B-Instruct 的 LoRA 微调 + Q4_K_M 量化，训练数据来源与许可证见下」
   - `RELEASE_NOTES.md`：用途（离线旅行 App 的印尼语→中文理解）、基座与量化、r4 评测（印→中 strict 105/120、金额错 0；公开集降幅）、已知局限（印→英不用于 App 理解；仅供参考，金额由程序换算）、sha256、对应 App 清单版本 4。
4. **上传**（`gh auth status` 必须已登录；没登录就停下请用户 `gh auth login`）：
   ```bash
   cd "$REPO"; R=~/trip-work/release/model-s400-v1
   gh release create model-s400-v1 finetune/runs/trip-mix2-s400-Q4_K_M.gguf "$R/SHA256SUMS" "$R/LICENSE-Qwen2.5.txt" "$R/NOTICE.txt" \
     --repo xhq52465840/offline-trip-translator --title "Model s400 v1 (offline understanding, Q4_K_M)" --notes-file "$R/RELEASE_NOTES.md" --latest=false
   ```
   如果 tag 已存在，用 `gh release upload model-s400-v1 … --clobber`，不要删 tag。
5. **按清单地址验证下载**（清单：`TripCore/Sources/TripCore/Resources/model-manifest.json` 的 `url`）：
   ```bash
   URL=$(python3 -c "import json;print(json.load(open('TripCore/Sources/TripCore/Resources/model-manifest.json'))['models'][0]['url'])")
   curl -sIL "$URL" | grep -iE "^(HTTP|content-length|accept-ranges)"      # 最终 200、长度 986048640、支持 Range（断点续传要用）
   curl -L -r 0-1023 -o /tmp/head.bin "$URL" && xxd /tmp/head.bin | head -1  # 以 GGUF 开头
   curl -L -o /tmp/s400_dl.gguf "$URL" && shasum -a 256 /tmp/s400_dl.gguf   # 必须等于清单 sha256；记录耗时
   ```
6. **模拟器真实模型回归**（DEBUG 构建，不加 `-UITestMode`；先删掉 App 重新装，确保从清单地址下载）：
   - 走一遍引导 → 「全部准备」：记录模型下载耗时、进度显示、sha256 校验通过（日志 / 界面变「已就绪」）。模拟器装不了 Apple 印尼语/英语包时，这些方向应显示「系统没有这门语言的离线翻译，将用本机模型翻译（质量较低）」并且**不再阻断**进入对话（这是本轮新行为，截图 `r8_prepare.png`）。
   - 发 3 句，每句记录首字延迟（TTFT，从日志 `GenerationStats` 或秒表）、整句耗时、显示结果，截图：
     1. 我方中文 ← 对方印尼语 `50rb belum termasuk ongkos`：应出现理解结果，金额「5万」（`r8_s1.png`）；
     2. 我方英文 ← 对方印尼语 `harganya 100rb kak`：应只有直译（Apple 或本地模型兜底）+ `≈ $`，金额 Rp 100,000 不变（`r8_s2.png`）；
     3. 我方中文 → 对方印尼语 `太贵了，能便宜一点吗`：应出现印尼语译文（`r8_s3.png`）。
   - 内存：每句之后 `ps -o rss= -p <App pid>`，记录峰值。
7. **复核盒子的三项新改动**（每项 ✓/✗ + 截图）：
   - **只检查两种语言**：模拟器全新安装、我方中文、对方印尼语，准备页只列中文听写、印尼语翻译 / 听写、理解能力，**不出现英语**（`r8_prepare_two_langs.png`）；进对话后把对方改成英语 → 这时才提示英语相关准备（`r8_switch_to_en.png`）。
   - **兜底标注**：第 6 步里凡是走了本地模型直译的气泡（模拟器没有 Apple 印尼语包时，第 1、3 句都会走兜底），下方应有「本机模型翻译，质量较低，重要信息请再确认」；英文界面是英文提示（`r8_fallback_note.png`、`r8_fallback_note_en.png`）。走了 Apple 翻译的气泡不应有这行。
   - **镜像**：下载日志里只尝试 GitHub 地址一次，没有对 `example.com` 的请求。
8. 报告 `reports/mac_run_<日期>_r8.md`：Release 链接、资产列表与大小、下载验证结果、3 句的 TTFT / 内存 / 截图、新的兜底行为截图。PR `Mac run r8`，**不要 merge**。全绿时写「r8 全绿：可以进入真机 / TestFlight（见 docs/真机验证清单.md）」。

---

## 当前轮次：r7 = P9 三语 LoRA 训练（r6 已审阅合并；拉取 master 后按此清单执行）

> 用户只会说「pull master and continue」。开 PR `Mac run r7`，**不要 merge**。权重只在本机，**不上传、不提交**。
> r6 结论：App 中英 UI 一次跑完 24 项全绿（r5、r6 连续两轮无代码缺陷，App 循环本身已完成）；s400 sha256 一致；
> 基座印→英 strict **100**/120、金额错 0；s400 印→英 **97**、金额错 0 → 按计划 §5「≥ 基座 + 10」不达标 → **做 P9**。
> 盒子已准备好数据：`finetune/out_en/`（英文目标场景 1250 条训练，`data/gen_en.py` + `templates_en.py`，已剔除与 cases_en/cases/cases_ext 相近的句子）、
> `finetune/out_mix3/`（= r4 的 out_mix 4080 条 + 英文场景 1250 条，英文约 23.5%）、配置 `finetune/mlx/lora_mix3.yaml`（1000 步，适配器 `runs/mlx_adapters_mix3`）。

1. `git pull origin master`；`ROUND=7`；分支 `mac-run-<日期>-r7`。T2 `swift test` 全绿；`swift build --product trip-prompt`（eval 脚本要用）。
   App UI 测试**本轮可跳过**（App 代码自 r6 未改）；只跑 `python3 scripts/i18n.py check`。
2. **训练**（同 6.3c/6.3d 的命令，换配置）：`python -m mlx_lm lora --config mlx/lora_mix3.yaml 2>&1 | tee runs/mlx_mix3_train.log`。约 2.5–3 小时。记录 train/val loss 曲线（每 100 步）。
3. 对 **s600 与 s1000** 各自 fuse → GGUF Q4_K_M → sha256（目录 `runs/mlx_adapters_mix3_s$S`，GGUF 前缀 `runs/trip-mix3-s$S`）。
4. 每个检查点跑三项评测（tag `mac_mix3_s$S`）：
   - `eval_appfmt.py <gguf> --tag mac_mix3_s$S --limit 60`（印→中）
   - `eval_appfmt.py <gguf> --tag mac_mix3_s${S}_en --target en --limit 60`（印→英）
   - `eval_public.py <gguf> --tag mac_mix3_s$S`（公开集 mt_id_zh / mt_id_en / slang_norm）
5. **采用规则（每个方向单独判定，基准都是同机基座）**：
   - 印→中：strict ≥ 95（基座 85 + 10）且金额错 ≤ 5，且不低于 s400 的 105 − 3；
   - 印→英：strict ≥ **110**（基座 100 + 10）且金额错 = 0；
   - 公开集 mt_id_zh chrF、mt_id_en chrF++ 相对基座各自下降 ≤ 10。
   报告每个检查点 × 每条规则 ✓/✗，并给出建议：
   - 两个方向都达标 → 建议采用该检查点替换 s400；
   - 只有印→中达标 → 保留 s400，印→英按计划 §5 在 App 里不启用本地理解（改走 Apple 翻译直译），由盒子改代码；
   - 都不达标 → 保留 s400，报告数字即可。
6. 被采用候选的 GGUF 留在本机，只报告路径、字节数、sha256。**s400 不要删。**
7. 报告 `reports/mac_run_<日期>_r7.md`（训练日志摘要、评测表、每个方向的失败样例各 5 条），PR `Mac run r7`，**不要 merge**。

---

## 当前轮次：r6（r5 已审阅合并；拉取 master 后按此清单执行）

> 用户只会说「pull master and continue」。开 PR `Mac run r6`，**不要 merge**。不训练、不上传权重。
> r5 结论：编译 / swift test 156 / 中文 UI 12 项全绿；英文截图无汉字（常用句分段除外，已修）；s400 中文复跑 strict 105、金额错 0（无回归）；sha256 一致；s400 印→英 strict 97/120、金额错 0。
> **P9 是否重训取决于本轮第 5 步**（计划 §5 规则：id→en strict ≥ 同机基座 + 10 且金额错 ≤ 基座）。

1. `git pull origin master`；`ROUND=6`；分支 `mac-run-<日期>-r6`；`python3 scripts/i18n.py check` = OK；`cd App && xcodegen generate`；`cd TripCore && swift test` 全绿。
2. **UI 测试一次跑完中英两遍**（不再用 `TEST_RUNNER_UI_LANG`，r5 实测无效）：照 T4.4 的命令跑整个 `TripUITests` 目标，会同时执行 `TripUITests`（中文，12 项）和 `TripUITestsEnglish`（英文，继承用例，截图自动加 `_en`）。两个类都要全绿；英文类里依赖中文界面的断言如有失败，只记录。
3. **复核 r5 的 UX 修复**（逐张看截图，写 ✓/✗ + 文件名）：
   - 对话顶栏只显示「English ⇄ Indonesian」这类语言名（我方加粗），不被返回按钮裁切，不和右侧图标重叠（`07_chat_sent_en`、`08_amount_conversion_en`、`11_face_to_face_lang`）；
   - 英文首页大标题为 `Trip Translator`，不截断（`06_home_en`）；
   - 英文阻断页缺包说明完整显示（可滚动 / 可上拉）（`02_blocking_sheet_en`）；
   - 英文常用句分段无汉字（`03_phrasebook_en`、`12_no_han_phrasebook_en`）；
   - 离线准备、常用句列表最后一行不被 Home 指示条挡住（`01_onboarding`、`03_phrasebook`）。
   - 金额：`08_amount_conversion` 有 `约 ¥37`，`08_amount_conversion_en` 有 `≈ $5.6`。
4. s400 sha256 仍为 `691a1b2b…f05b0a`、986048640 字节（不删、不传）。
5. **P9 判定：基座印→英 60 条（必做）**，同机、同脚本：
   ```bash
   cd "$REPO/finetune/mlx"
   python ../scripts/eval_appfmt.py "$BASE" --tag mac_base_en --target en --limit 60 2>&1 | tee "$WORK/t6_eval_base_en.log" | tail -5
   ```
   报告表：基座 vs s400（r5：strict 97、金额错 0、App 接受 46）。判定：s400 strict ≥ 基座 + 10 且金额错 ≤ 基座 → **不做 P9**；否则写「P9 需要」，下一轮由盒子准备数据。
6. 报告 `reports/mac_run_<日期>_r6.md`，PR `Mac run r6`，**不要 merge**。

---

## 当前轮次：r5（r5 原清单 + 三语/国际化 P1–P8 验证，合并为一张清单）

> 用户只会说「pull master and continue」。按本节从上到下执行，开 PR `Mac run r5`，**不要 merge**。
> 背景：r4 结论 `mac_mix2_s400` **采用**（strict 105、金额错 0）。盒子已按 `docs/三语与国际化改造计划.md` 完成 P1–P4、P6–P8 代码（P5 真机部分、P9 未做）。权重只在 Mac 本机，**不上传、不提交**。

**A. 准备**
1. `git fetch && git checkout master && git pull origin master`；`ROUND=5`；分支 `mac-run-<日期>-r5`；截图目录 `reports/screens/<日期>-r5/`。
2. `python3 scripts/i18n.py check` 必须输出 `i18n check: OK`（字符串完整性；失败原文写进报告，不要手改生成文件——改 `i18n/strings.json` 后 `python3 scripts/i18n.py gen`）。
3. `cd App && xcodegen generate`（project.yml 新增 `developmentLanguage`、`CFBundleLocalizations: [zh-Hans, en]`、`Localizable.xcstrings`、`en.lproj/InfoPlist.strings`）。

**B. 单元测试 + 编译（T2/T3）**
4. `cd TripCore && swift test`：盒子 Linux 上 156 项全绿，Mac 上也应全绿（新增 TrilingualTests、FXEnglishTests、PromptEnglishTests、PhraseTrilingualTests、L10nTests）。
5. T3 编译 App 无 error；警告里如有 `Localizable.xcstrings` 相关（未用键/缺翻译）抄进报告。

**C. UI 测试两遍（T4.4）**
6. 中文界面（默认）：照 T4.4 跑一遍，共 12 项，全绿。
7. 英文界面：同一命令加 `TEST_RUNNER_UI_LANG=en`，`-resultBundlePath "$WORK/ui_r${ROUND}_en.xcresult"`，日志 `t4_ui_en.log`。这一遍截图自动加 `_en` 后缀。
   - `testEnglishUIHasNoChinese` 必须通过（引导页、阻断页、首页、对话页可见文字里没有汉字）。失败时把它列出的汉字字符串逐条写进报告（这是缺键，属于盒子要修的缺陷，不要改 App 掩盖）。
   - 中文专用断言（比如 `约 ¥37`、`太贵了`）在英文遍里失败的，只记录不修，并注明是否属于测试本身假设了中文界面。
8. 截图复核（两遍合并，逐张看）：
   - `08_amount_conversion`：`Rp 100.000（约 ¥37）`，汇率行含 `2026-10-12`。`08_amount_conversion_en`：出现 `≈ $5.6`；
   - `04_present_fullscreen`：“Indonesia” 不拆行；
   - `06_home`：滚到底再截一张 `06_home_scrolled`，最后一行（紧急求助/问路/闲聊）完整可点；
   - **P4** `10_lang_picker`：顶部有「我说 / ⇄ / 对方说」三个控件，发「太贵了」后出现英文 `Too expensive`；
   - **P4** `11_face_to_face_lang`：英文界面，我方英文、对方中文，面对面模式下对方一侧有语言选择器；
   - **P4** `testSwapLanguages` 通过（交换后我方显示印尼语）；
   - **P6** `03_phrasebook` / `03_phrasebook_en`：场景标题按界面语言显示；短语出示语言跟随对方语言；
   - **P7** 英文全套 `01…12_*_en`：无中文、无截断/重叠；设置里有「界面语言 / App language」入口（截 `13_ui_language`，手动导航即可）；
   - **P2**：英文遍的金额芯片为 `Rp 50,000`（逗号分组）这种形式，中文遍为 `5万`。
9. 指标照 T4.4 / 4.5 记录。

**D. 模型（T6 不训练）**
10. s400 GGUF 重算 sha256，确认和 r4 一致：`691a1b2b…f05b0a`，986048640 字节。文件留在原路径，不删、不传。
11. **P3 基线（必做）**：用 s400 跑 id→en 理解 60 条评测（`docs/model_eval/cases_en.py`），同时复跑中文目标确认没有回归：
    ```bash
    cd "$REPO/finetune/mlx"   # 和 6.2 / 6.5 相同的 venv、trip-prompt 路径
    python ../scripts/eval_appfmt.py "$S400" --tag mac_mix2_s400_en --target en --limit 60 2>&1 | tee "$WORK/t6_eval_s400_en.log" | tail -5
    python ../scripts/eval_appfmt.py "$S400" --tag mac_mix2_s400_zh_r5 --limit 60 2>&1 | tee "$WORK/t6_eval_s400_zh.log" | tail -5
    ```
    报告：strict / valid / 金额错 / 平均延迟，并把每条失败的 id 和模型原文贴出来。**参考门槛**（只报告，本轮不决定是否训练）：en strict ≥ 45/60，金额错 = 0。中文复跑应和 r4 的 105 / 0 基本一致（±3）。
    - 如果 `eval_appfmt.py --target en` 报错（盒子只用桩模块测过），允许修脚本里的明显 bug，必须写进报告并随 PR 提交。
12. （可选，时间充裕时）T6b：s400 真实模型在模拟器里跑 T4.6 一次，中文→英文、英文→印尼语各发一句，报告 TTFT 和内存。不上传、不提交。

**E. 只记录、不执行**
13. 真机部分（P5：Apple Translation zh↔en、en↔id 语言包下载，各语言的语音识别）和 StoreKit 沙盒购买（T7）需要用户本人操作，只列在报告的「待真机」一节。
14. 英文和印尼语短语的母语者校对见 `docs/印尼语短语核对.md`，Mac 不做。

**F. 提交**
15. 报告 `reports/mac_run_<日期>_r5.md`：每一步 ✓/✗；UI 测试中文遍、英文遍各自的 pass/fail 表；P3 评测数字；截图清单和亲眼看到的 UX 问题（写明文件名）。
16. 开 PR `Mac run r5`，**不要 merge**。全绿且截图无新问题时，在报告里写「r5 全绿」，等审阅方回复。

---

## 当前轮次：r4（拉取 master 后按此清单执行）

> 用户不转述消息。Mac 代理只需 `git pull origin master`，读本节 + 下文 T0–T7 / T3b / 6.3d，开 PR 标题 `Mac run r4`。**不要合并 PR。**

### r4 必做清单

1. **拉最新** `git fetch && git checkout master && git pull`，设 `ROUND=4`，分支 `mac-run-<日期>-r4`。
2. **T0–T4**：编译、UI 测试全绿；截图目录 `reports/screens/<日期>-r4/`。
3. **T3b 金额换算截图（本轮新增，必做）**
   - 跑 `testAmountConversionShown`（`-UITestMode mock-ready -UITestSeedAmount`）→ `08_amount_conversion`：气泡须有 `Rp 100.000（约 ¥37）` + 汇率行含 `2026-10-12`。
   - `07_chat_sent`：芯片为「约 ¥…」，无「示例汇率」。
   - 设置 → 汇率 → `09_rate_settings`（1 CNY/1 USD→IDR、日期、来源）。
   - 英文环境 `-AppleLanguages (en) -AppleLocale en_US` → `08_amount_conversion_en`，应见 `≈ $5.6`。
4. **T6 混合训练（6.3d，优先于 6.3c）**：`out_mix/`（约 45% 回放，含 FLORES **dev**），`mlx/lora_mix.yaml` **800 步**，适配器 `runs/mlx_adapters_mix2`。对 **s400 与 s800** 分别 fuse→GGUF→评测（tag `mac_mix2_s400` / `mac_mix2_s800`）。
5. **采用规则（正式，放宽版）**，相对同机 `mac_base`（strict 85、金额错 5），三条同时满足才采用：
   - App 60 条 strict ≥ 基座 + 10（≥ 95）；
   - 金额错 ≤ 基座（≤ 5）；
   - 公开集 `mt_id_zh` chrF、`mt_id_en` chrF++ 相对基座各自下降 ≤ 10（`slang_norm` 只报告）。
   报告对每个检查点写 ✓/✗。
6. **不上传模型**：只报告本机 GGUF 路径、字节数、sha256；不提交权重、不传 HF/网盘。
7. **盒子 CPU 旁路已中止**：Linux 盒子曾试跑 CPU PEFT 混合短训（`scripts/box_mix_r4.sh`），约 step 55 被终止（`MIX_R4_FAILED`），**无可用评测数字**。r4 **以 Mac MLX 800 步为准**，不要等盒子结果。
8. 开 PR：标题 `Mac run r4`，报告 `reports/mac_run_<日期>_r4.md`，**不要 merge**。等审阅方评论 `next round`。

---

## T0 环境检查

**目标**：确认 macOS、芯片、内存、磁盘、Xcode、python3、git、brew，缺的用 brew / venv 内 pip 安装。

```bash
sw_vers
uname -m                                   # 期望 arm64
sysctl -n machdep.cpu.brand_string
sysctl -n hw.memsize | awk '{printf "RAM %.1f GB\n", $1/1073741824}'
df -h "$HOME" | tail -1                    # 需要 ≥ 30 GB 空闲（基座 HF 权重 ~3 GB、融合 ~3 GB、f16 GGUF ~3 GB、Q4 ~1.1 GB、缓存）
xcode-select -p
xcodebuild -version                        # 期望 Xcode 16 或更高（iOS 17+ 部署目标；SpeechAnalyzer 代码需 Xcode 26 SDK，见 T3）
xcrun simctl list runtimes | grep -i ios
python3 --version                          # 期望 ≥ 3.10
git --version
brew --version || echo "NO_BREW"
which cmake xcodegen gh || true
```

缺失项安装（只用 brew 和 venv，不要系统级 pip）：

```bash
# 没有 brew：记录 NO_BREW，停下来让用户安装（https://brew.sh），不要自己用 sudo 装
brew install cmake xcodegen gh git-lfs 2>&1 | tail -5
python3 -m venv "$VENV" && source "$VENV/bin/activate"
python -m pip install -U pip
```

- **成功标准**：arm64；RAM、磁盘已记录；`xcodebuild -version` 有输出；venv 可激活；cmake、xcodegen 可用。
- **失败处理**：没有 Xcode（只有 CommandLineTools）→ T3/T4 标 ❌「需用户安装 Xcode」，继续 T1/T2/T5/T6。RAM < 16 GB → T6 照做但在报告里标注，可能需把 `batch_size` 降到 2（只改运行参数，见 T6）。
- **记录**：上面每条命令的输出（原样）。

---

## T1 获取代码

```bash
cd "$WORK"
if [ -d "$REPO/.git" ]; then
  git -C "$REPO" fetch origin && git -C "$REPO" checkout master && git -C "$REPO" pull --ff-only
else
  git clone https://github.com/xhq52465840/offline-trip-translator.git "$REPO"
fi
cd "$REPO"
git log --oneline -1
git checkout -B "$BR"
ls App TripCore finetune docs
```

- **成功标准**：存在 `App/project.yml`、`TripCore/Package.swift`、`finetune/mlx/run_mlx.sh`、`finetune/scripts/eval_appfmt.py`、`finetune/scripts/eval_public.py`。
- **失败处理**：克隆失败（网络）→ 记录报错，重试一次；仍失败则整份报告无法推送，所有结果保存在本机，并在最终回复里说明。
- **记录**：commit hash。

---

## T2 Swift 单元测试（TripCore 包）

```bash
cd "$REPO/TripCore"
swift --version
swift build 2>&1 | tee "$WORK/t2_build.log" | tail -20
swift test 2>&1 | tee "$WORK/t2_test.log" | tail -30
grep -E "Executed [0-9]+ tests" "$WORK/t2_test.log"
```

- 首次会通过 SPM 下载 llama.cpp XCFramework（`b11541`，`Package.swift` 里有 checksum），需要联网。
- **成功标准**：两个测试包都 `0 failures`。参考（Linux 上的结果）：TripCoreTests 59、TripAppModelTests 42，共 101 个全过。
- **失败处理**：不要改测试或源码让它通过。记录失败测试名与断言原文，继续 T3。checksum 不符 → 原样记录，不要改 checksum。
- **记录**：测试数、失败数、失败原文。

---

## T3 Xcode 编译 App（iOS 模拟器）

```bash
cd "$REPO/App"
xcodegen generate 2>&1 | tail -5          # 用 project.yml 重新生成（含 StoreKit 本地配置的 scheme）
xcodebuild -list -project TripUnderstand.xcodeproj
SIM=$(xcrun simctl list devices available | grep -Eo 'iPhone [0-9]+( Pro)?( Max)? \([0-9A-F-]+\)' | head -1 | sed -E 's/.*\(([0-9A-F-]+)\)/\1/')
echo "SIM=$SIM"
xcodebuild -project TripUnderstand.xcodeproj -scheme TripUnderstand \
  -destination "id=$SIM" -configuration Debug \
  -derivedDataPath "$WORK/DerivedData" CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$WORK/t3_build.log" | tail -40
grep -E "error:|warning: .*deprecated" "$WORK/t3_build.log" | sort -u > "$WORK/t3_errors.txt"; wc -l "$WORK/t3_errors.txt"
```

- 这个 App 之前**从未在真实 Xcode 里编译过**（只在 Linux 上做过 `swiftc -parse` 语法检查），出现编译错误是预期的。
- 已知风险点：`Speech.swift` 用 `#if canImport` / `#available(iOS 26, *)` 包着 `SpeechAnalyzer`/`SpeechTranscriber`；若 Xcode 版本的 SDK 没有这些 API，会报错——这时用 `#if compiler(>=6.2)` 之类的条件编译包起来是可接受的最小修复。Translation 框架 API（`TranslationSession`、`LanguageAvailability`、`.translationTask`）同理。
- **允许的修复**：只改到能编译为止的最小改动（类型名、可用性标注、缺少的 import、`@MainActor` 标注等）。不要删功能、不要注释掉整段逻辑；实在修不了的，记录并停在这里。每修一处，重新编译，并记录：
  - 文件:行、错误原文、修改原因、`git diff` 片段。
- 每修完一轮，确认单元测试仍然绿：`cd "$REPO/TripCore" && swift test 2>&1 | grep -E "Executed|error"`。
- **成功标准**：`** BUILD SUCCEEDED **`。
- **失败处理**：记录所有错误原文（`t3_errors.txt` 全文贴进报告），列出已修与未修。
- **记录**：Xcode 版本、模拟器型号、错误全文、修复清单、最终结果。

---

## T4 在模拟器上运行并测试 App（必须真的跑起来）

### 4.1 选最新 iPhone 模拟器并启动

```bash
RUNTIME=$(xcrun simctl list runtimes available -j | python3 -c "import json,sys;r=[x for x in json.load(sys.stdin)['runtimes'] if x['platform']=='iOS'];r.sort(key=lambda x:[int(p) for p in x['version'].split('.')]);print(r[-1]['identifier'])")
DEVTYPE=$(xcrun simctl list devicetypes -j | python3 -c "
import json,sys,re
d=[x for x in json.load(sys.stdin)['devicetypes'] if re.fullmatch(r'iPhone \d+ Pro', x['name'])]
d.sort(key=lambda x:int(re.search(r'\d+',x['name']).group()))
print(d[-1]['identifier'])")   # 取编号最大的「iPhone N Pro」（r1 误选了 iPhone 11 Pro）
SIM=$(xcrun simctl create "Trip-r$ROUND" "$DEVTYPE" "$RUNTIME")
xcrun simctl boot "$SIM"; xcrun simctl bootstatus "$SIM" -b
echo "RUNTIME=$RUNTIME DEVTYPE=$DEVTYPE SIM=$SIM"
```

（T3 里如已设 `SIM`，这里用新的 `SIM` 覆盖；T3 编译若失败，T4 全部标 ❌。）

### 4.1b llama.xcframework 模拟器切片（r1 发现：官方 b11541 zip 只有 ios-arm64 与 macOS）

模拟器链接需要本机补 `ios-arm64-simulator` 切片。**这是允许的仓库改动**：把 r1 的补片步骤写成脚本 `TripCore/scripts/patch_llama_xcframework_sim.sh`（参数：DerivedData 路径；从 `$LLAMA_CPP` b11541 编模拟器库、ad-hoc 签名、放入 `SourcePackages/artifacts/tripcore/llama/llama.xcframework/ios-arm64-simulator`、更新 Info.plist），提交到仓库并在每次新 DerivedData 解压后运行。不要改 `Package.swift` 的 checksum，不要提交二进制。

```bash
[ -x "$REPO/TripCore/scripts/patch_llama_xcframework_sim.sh" ] && \
  bash "$REPO/TripCore/scripts/patch_llama_xcframework_sim.sh" "$WORK/DerivedData" && \
  bash "$REPO/TripCore/scripts/patch_llama_xcframework_sim.sh" "$WORK/DerivedData-pkg"
```

### 4.2 包内逻辑测试（模拟器）

```bash
cd "$REPO/TripCore"
xcodebuild test -scheme TripCore-Package -destination "id=$SIM" \
  -derivedDataPath "$WORK/DerivedData-pkg" 2>&1 | tee "$WORK/t4_pkg.log" | tail -20
grep -E "Executed|TEST (SUCCEEDED|FAILED)" "$WORK/t4_pkg.log"
```

### 4.3 安装、以测试模式启动、截图

App 在 **DEBUG** 构建里支持启动参数 `-UITestMode <模式>`（实现：`TripCore/Sources/TripAppModel/UITestMode.swift` + `App/TripApp/AppState.swift` 的 `uiTest(_:)`；Release 构建不含）：

| 模式 | 效果 |
|---|---|
| `mock-onboarding` | 首次启动引导页 |
| `mock-not-ready` | 已引导过但模型缺失 → 每次启动出现阻断弹窗（可进「常用句」） |
| `mock-ready` | 全部就绪 → 首页 / 对话；MockEngine 固定理解输出、假翻译表 |

模拟器里**不需要**下载 1.1 GB 模型，也不需要 Apple Translation 语言包。测试模式用独立 UserDefaults 域与内存试用记录，每次启动清空。

```bash
cd "$REPO"; mkdir -p "$SCREENS"
APP=$(find "$WORK/DerivedData/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name "TripUnderstand.app" | head -1)
xcrun simctl install "$SIM" "$APP"
for MODE in mock-onboarding mock-not-ready mock-ready; do
  xcrun simctl terminate "$SIM" app.tripunderstand.demo 2>/dev/null
  xcrun simctl launch "$SIM" app.tripunderstand.demo -UITestMode $MODE
  sleep 6
  xcrun simctl io "$SIM" screenshot "$SCREENS/simctl_$MODE.png"
done
xcrun simctl launch "$SIM" app.tripunderstand.demo -UITestMode mock-ready; sleep 5
xcrun simctl ui "$SIM" appearance dark; sleep 2; xcrun simctl io "$SIM" screenshot "$SCREENS/simctl_mock-ready_dark.png"
xcrun simctl ui "$SIM" appearance light
```

### 4.4 XCUITest（目标 `TripUITests`，在 `App/project.yml` 中；先 `xcodegen generate`）

覆盖：引导页出现；未就绪启动出现阻断弹窗；从阻断弹窗进入常用句并全屏出示；购买页打开；`mock-ready` 下首页 → 对话 → 输入「太贵了」发送 → 出现假译文「Terlalu mahal」；启动内存 / 启动时间指标（`XCTMemoryMetric`、`XCTApplicationLaunchMetric`）。

```bash
cd "$REPO/App"
xcodegen generate
xcodebuild test -project TripUnderstand.xcodeproj -scheme TripUnderstand -destination "id=$SIM" \
  -derivedDataPath "$WORK/DerivedData" CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath "$WORK/ui_r$ROUND.xcresult" \
  TEST_RUNNER_SCREEN_DIR="$REPO/$SCREENS" 2>&1 | tee "$WORK/t4_ui.log" | tail -40
grep -E "Test Case .*(passed|failed)|error:|TEST (SUCCEEDED|FAILED)" "$WORK/t4_ui.log"
ls -la "$REPO/$SCREENS"
```

- 截图以 xcresult 导出为准（r1/r2 实测 `TEST_RUNNER_SCREEN_DIR` 直写为空，可忽略）：
  ```bash
  xcrun xcresulttool export attachments --path "$WORK/ui_r$ROUND.xcresult" --output-path "$REPO/$SCREENS/xcresult" 2>&1 | tail -3 \
    || echo "xcresulttool 版本不支持 export attachments：记录并跳过"
  ```
- 压缩截图（保持仓库小，每张目标 < 300 KB）：
  ```bash
  for f in "$REPO/$SCREENS"/*.png "$REPO/$SCREENS"/xcresult/*.png; do [ -f "$f" ] && sips -Z 1200 "$f" >/dev/null; done
  du -sh "$REPO/$SCREENS"
  ```
- 指标：从日志里取 `XCTMemoryMetric` 的 `Memory Physical` 与 `XCTApplicationLaunchMetric` 的 `Duration`：
  ```bash
  grep -E "measured \[(Memory|Duration|Clock)" "$WORK/t4_ui.log" | head -10
  ```
- UI 测试失败时：允许修**测试代码本身**的定位问题（如等待时间、`textFields` vs `textViews`），必须记录；App 行为与预期不符（例如阻断弹窗没出现）**不要改 App 掩盖**，记为缺陷。
- **成功标准**：包测试与 UI 测试 `TEST SUCCEEDED`；`$SCREENS` 下至少 01–07 共 7 张截图 + simctl 截图。
- **记录**：每个 UI 测试 pass/fail、失败原文、截图清单、内存与启动时间、你**亲眼看截图发现的 UX 问题**（文字截断、重叠、深色模式对比度、按钮太小、中文显示不全等，每条写截图文件名）。

### 4.5 基本内存检查（无需 Instruments）

```bash
xcrun simctl launch "$SIM" app.tripunderstand.demo -UITestMode mock-ready; sleep 8
PID=$(xcrun simctl spawn "$SIM" launchctl list | awk '/app.tripunderstand.demo/{print $1}' | head -1)
echo "PID=$PID"; ps -o pid,rss,vsz,command -p "$PID" 2>/dev/null | tail -1     # 模拟器 App 是主机进程，rss 单位 KB
xcrun simctl spawn "$SIM" log show --last 2m --style compact --predicate 'process == "TripUnderstand" AND (messageType == error OR messageType == fault)' | tail -30
```

记录 RSS（注意：模拟器内存 ≠ 真机内存，只作趋势参考）和错误/故障日志。

### 4.6（可选）模拟器里的真实模型端到端

模拟器里正常（非测试模式）启动需要 Apple Translation 语言包与语音资源，模拟器上可能装不了，所以**不保证可行**：

```bash
xcrun simctl terminate "$SIM" app.tripunderstand.demo; xcrun simctl launch "$SIM" app.tripunderstand.demo
sleep 8; xcrun simctl io "$SIM" screenshot "$REPO/$SCREENS/live_onboarding.png"
```

在引导页点「全部准备」（可用 UI 测试或手动，若代理无法点击就只记录截图）。若能下载模型并进入对话：粘贴 `udh sampe blm?` 并记录从发送到理解行出现的时间（秒表或日志时间戳）。若卡在系统语言包：记录卡住的项与截图，标「模拟器不支持，需真机（T7）」，不要绕过。真实模型的 Mac 速度以 T5 为准。

---

## T5 llama.cpp Metal 冒烟（基座模型）

**目标**：在 Mac GPU（Metal）上加载基座 GGUF，测加载时间、首字延迟（TTFT）、生成速度。注意：这是 Mac 数字，**不是 iPhone 数字**。

```bash
cd "$WORK"
[ -d "$LLAMA_CPP" ] || git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_CPP"
git -C "$LLAMA_CPP" fetch --tags && git -C "$LLAMA_CPP" checkout b11541   # 与 App 的 XCFramework 同版本
cmake -S "$LLAMA_CPP" -B "$LLAMA_CPP/build" -DGGML_METAL=ON -DCMAKE_BUILD_TYPE=Release
cmake --build "$LLAMA_CPP/build" -j --target llama-completion llama-bench llama-quantize 2>&1 | tail -5
ls "$LLAMA_CPP/build/bin/"
```

下载基座 GGUF（地址与 sha256 取自仓库里的清单，不要手抄）：

```bash
mkdir -p "$WORK/models"
MAN="$REPO/TripCore/Sources/TripCore/Resources/model-manifest.json"
URL=$(python3 -c "import json;print(json.load(open('$MAN'))['models'][0]['url'])")
SHA=$(python3 -c "import json;print(json.load(open('$MAN'))['models'][0]['sha256'])")
BASE="$WORK/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
curl -L -C - --retry 5 -o "$BASE" "$URL" || curl -L -C - --retry 5 -o "$BASE" "${URL/huggingface.co/hf-mirror.com}"
echo "$SHA  $BASE" | shasum -a 256 -c -
```

- 清单里 `cn` / `global` 镜像是**占位域名**（example.com），不能下载；只用 `url`（Hugging Face）。国内网络访问不了 HF 时，上面会退到 `hf-mirror.com`（第三方镜像），并必须通过 sha256 校验；在报告里注明用了哪个来源。
- sha256 不一致 → 删掉文件重下一次；仍不一致则 T5/T6 标 ❌，**不要**使用该文件。

测速：

```bash
"$LLAMA_CPP/build/bin/llama-bench" -m "$BASE" -ngl 99 -p 512 -n 128 -r 3 2>&1 | tee "$WORK/t5_bench.log"
/usr/bin/time -p "$LLAMA_CPP/build/bin/llama-completion" -m "$BASE" -ngl 99 -no-cnv -n 64 --temp 0 \
  -p "把下面的印尼语翻译成中文：Pak, saya sudah di lobi, share lok ya" 2>&1 | tee "$WORK/t5_cli.log" | tail -25
grep -E "load time|prompt eval time|eval time" "$WORK/t5_cli.log"
```

- 加载时间 = `load time`；TTFT ≈ `load` 之后的 `prompt eval time`（总毫秒）；生成速度 = `eval time` 行的 tokens per second；`llama-bench` 的 `pp512`/`tg128` 也记录。
- b11541 中 `-no-cnv` 只属于 `llama-completion`（`llama-cli` 不支持），所以这里用 `llama-completion`。若参数被拒，记录原文并改用 `llama-bench` 的数字。
- **成功标准**：sha256 通过；有 load/TTFT/tok/s 数字；输出中文合理。
- **记录**：表格（见模板）、实际命令、输出文本。

---

## T6 MLX LoRA 完整训练 → 融合 → GGUF → 评测

**训练数据已在仓库里**（`finetune/out/train.jsonl` 等，2244/118/405 条），**不要重新生成**，保证与已有结果可比。配置见 `finetune/mlx/lora.yaml`（1500 iters，batch 4，rank 16，全部层）。

### 6.1 安装

```bash
source "$VENV/bin/activate"
pip install -U mlx-lm huggingface_hub sacrebleu
pip install -r "$LLAMA_CPP/requirements/requirements-convert_hf_to_gguf.txt"
CMAKE_ARGS="-DGGML_METAL=on" pip install -U llama-cpp-python
python -c "import mlx_lm, llama_cpp, sacrebleu; print(mlx_lm.__version__, llama_cpp.__version__, sacrebleu.__version__)"
```

`eval_appfmt.py` 需要仓库里的 `trip-prompt` 工具（T2 已 `swift build`，路径 `TripCore/.build/debug/trip-prompt`）：

```bash
ls -l "$REPO/TripCore/.build/debug/trip-prompt" || (cd "$REPO/TripCore" && swift build --product trip-prompt)
```

### 6.2 基座重测（同一台 Mac、同一脚本，作为对照）

```bash
cd "$REPO/finetune/results"
python ../scripts/eval_appfmt.py "$BASE" --tag mac_base --limit 60 2>&1 | tee "$WORK/t6_eval_base.log" | tail -3
cd "$REPO/finetune"
python scripts/test_eval_public.py
python scripts/eval_public.py "$BASE" --tag mac_base 2>&1 | tee "$WORK/t6_public_base.log" | tail -25
```

产物：`finetune/results/eval_mac_base.json`、`finetune/results/public_mac_base.json`。

### 6.3 训练（长任务）

估算【估算，未实测】：M1/M2 16 GB 约 2–4 小时；M3/M4 Pro/Max 约 1–2 小时。基座 HF 权重（约 3 GB）首次会从 Hugging Face 下载；访问不了时 `export HF_ENDPOINT=https://hf-mirror.com` 并记录。

```bash
cd "$REPO/finetune"
mkdir -p runs
nohup caffeinate -dimsu python -m mlx_lm lora -c mlx/lora.yaml > runs/mlx_train.log 2>&1 &
echo $! > runs/mlx_train.pid
sleep 60; tail -5 runs/mlx_train.log
```

- 如果 `python -m mlx_lm lora` 不存在（版本差异），改用 `mlx_lm.lora -c mlx/lora.yaml`，记录。
- 内存不足（OOM / `[METAL] Command buffer execution failed`）：在 lora.yaml 同目录**新建**一份 `mlx/lora_mac_small.yaml`（复制后只把 `batch_size: 2`），用它重跑并记录；不要改原文件。
- 监控（每 10–20 分钟看一次即可）：`tail -3 runs/mlx_train.log`；`Train loss`、`Val loss` 行记录到报告。完成标志：进程退出且 `runs/mlx_adapters/adapters.safetensors` 存在。

```bash
while kill -0 $(cat runs/mlx_train.pid) 2>/dev/null; do sleep 300; tail -1 runs/mlx_train.log; done
ls -l runs/mlx_adapters/
grep -E "Val loss|Train loss" runs/mlx_train.log | tail -10
```

### 6.3b 检查点挑选（r2 起）

`lora.yaml` 已改为 400 步、每 100 步存检查点（r1：1500 步导致公开集 chrF 47→0.3）。对 200 步与 400 步两个检查点都做 6.4–6.5（用 tag `mac_lora_s200`、`mac_lora_s400`）：

```bash
cd "$REPO/finetune"
for S in 200 400; do
  D=runs/mlx_adapters_s$S; mkdir -p $D
  cp runs/mlx_adapters/adapter_config.json $D/
  cp runs/mlx_adapters/$(printf "%07d" $S)_adapters.safetensors $D/adapters.safetensors
done
ls runs/mlx_adapters_s*/
```

6.4 中把 `--adapter-path runs/mlx_adapters` 换成 `runs/mlx_adapters_s$S`、输出前缀换成 `runs/trip-lora-s$S`，6.5 的 tag 换成 `mac_lora_s$S`。采用规则：见 6.5 末尾「采用规则（正式）」。

### 6.3c 回放混合训练（r3 起，优先于 6.3b）

r2 结论：只训场景数据会遗忘通用能力。r3 起用 `mlx/lora_mix.yaml`（数据 `out_mix/` = 场景 + Tatoeba/STIF 回放，600 步，适配器 `runs/mlx_adapters_mix`）。先确认数据存在（已提交；如需重建：`bash public_data/fetch.sh && python3 data/build_replay.py`）：

```bash
cd "$REPO/finetune" && cat out_mix/stats.json
nohup caffeinate -dimsu python -m mlx_lm lora -c mlx/lora_mix.yaml > runs/mlx_mix_train.log 2>&1 &
echo $! > runs/mlx_mix_train.pid
```

检查点挑选同 6.3b，但用 300 与 600 步：`runs/mlx_adapters_mix/0000300_adapters.safetensors`、`0000600_…`，目录 `runs/mlx_adapters_mix_s$S`，GGUF 前缀 `runs/trip-mix-s$S`，tag `mac_mix_s$S`。报告里注明：回放与 eval_public 同提示词（不同句子），公开集分数偏乐观。

### 6.3d 回放 v2（r4 起，优先于 6.3c）

`out_mix/` 已重建：回放约 45%，新增 FLORES-200 **dev** 的 印→中、印→英（评测只用 devtest，零重叠已校验）。`mlx/lora_mix.yaml` 改为 800 步，适配器 `runs/mlx_adapters_mix2`。命令同 6.3c，日志 `runs/mlx_mix2_train.log`；评测 s400 与 s800（目录 `runs/mlx_adapters_mix2_s$S`，GGUF 前缀 `runs/trip-mix2-s$S`，tag `mac_mix2_s$S`）。公开集照旧注明「同提示词偏乐观」，并对最好的检查点各任务抽 2 条输出。

App 侧：r2、r3 已连续两轮全绿；**r4 仍须完整 T3/T4 + T3b 金额换算截图**（见文首「当前轮次：r4」）。

**盒子 CPU**：曾尝试 `scripts/box_mix_r4.sh`（CPU PEFT，~100 步），约 step 55 被终止，`MIX_R4_FAILED`，无评测结论。**以本机 MLX 800 步为准，勿等待盒子。**

### 采用规则（正式）

**采用规则（正式，2026-10-13 用户批准，取代旧的「每项降 ≤ 3」）**：以同机基座 `mac_base`（strict 85、金额错 5）为准，三条同时满足才采用：
1. App 格式 60 条 strict ≥ 基座 + 10（即 ≥ 95）；
2. 金额错 ≤ 基座（≤ 5）；
3. 公开集翻译指标 `mt_id_zh`（chrF）与 `mt_id_en`（chrF++）相对基座各自下降 ≤ 10 分（`slang_norm` 只报告，不作门槛；回放同提示词偏乐观）。

报告里对每个检查点逐条写 ✓/✗。达标也**只报告**本机 GGUF 路径、字节数、sha256，不上传、不提交。

### 6.4 融合 → GGUF Q4_K_M → sha256

```bash
cd "$REPO/finetune"
python -m mlx_lm fuse --model Qwen/Qwen2.5-1.5B-Instruct --adapter-path runs/mlx_adapters --save-path runs/merged 2>&1 | tail -5
LLAMA_CPP="$LLAMA_CPP" bash scripts/to_gguf.sh runs/merged runs/trip-qwen2.5-1.5b-lora 2>&1 | tail -8
cat runs/trip-qwen2.5-1.5b-lora-Q4_K_M.gguf.json      # 文件名、字节数、sha256
TUNED="$REPO/finetune/runs/trip-qwen2.5-1.5b-lora-Q4_K_M.gguf"
rm -rf runs/merged                                     # 省空间
```

（`run_mlx.sh` 做的是同样三步，可作参考，但这里分步执行以便定位失败。）

### 6.5 评测微调模型

```bash
cd "$REPO/finetune/results"
python ../scripts/eval_appfmt.py "$TUNED" --tag mac_lora --limit 60 2>&1 | tee "$WORK/t6_eval_lora.log" | tail -3
cd "$REPO/finetune"
python scripts/eval_public.py "$TUNED" --tag mac_lora 2>&1 | tee "$WORK/t6_public_lora.log" | tail -25
"$LLAMA_CPP/build/bin/llama-bench" -m "$TUNED" -ngl 99 -p 512 -n 128 -r 3 2>&1 | tail -4
```

对比汇总（打印到报告里）：

```bash
cd "$REPO/finetune/results"
python3 - <<'PY'
import json, os
print("| tag | score | strict | 原30 strict | 扩30 strict | 金额错 | App 接受 | TTFT 中位 |")
print("|---|---|---|---|---|---|---|---|")
for t in ["base", "short", "mac_base", "mac_lora", "mac_lora_s200", "mac_lora_s400", "mac_mix_s300", "mac_mix_s600", "mac_mix2_s400", "mac_mix2_s800"]:
    p = f"eval_{t}.json"
    if os.path.exists(p):
        s = json.load(open(p))["summary"]
        print(f"| {t} | {s['score']}/{s['max']} | {s['strict']} | {s['orig30_strict']} | {s['ext30_strict']} | {s['amount_err']} | {s['app_accepted']} | {s['ttft_med']} |")
print()
print("| tag | n | mt_id_zh chrF | mt_id_en chrF++ | slang_norm chrF++ |")
print("|---|---|---|---|---|")
for t in ["base", "short", "mac_base", "mac_lora", "mac_lora_s200", "mac_lora_s400", "mac_mix_s300", "mac_mix_s600", "mac_mix2_s400", "mac_mix2_s800"]:
    p = f"public_{t}.json"
    if os.path.exists(p):
        d = json.load(open(p)); s = d["summary"]
        g = lambda k: s.get(f"task:{k}", {}).get("chrf", "-")
        print(f"| {t} | {d['n']} | {g('mt_id_zh')} | {g('mt_id_en')} | {g('slang_norm')} |")
PY
```

参考（Linux CPU 上已有结果）：`eval_base` strict 90/120、金额错 5、App 接受 40；`eval_short`（CPU 短训）strict 105、金额错 2、App 接受 49。`public_base/short` 是在旧的 528 条公开集上跑的，现集合为 513 条，**只和 mac_base 对比**。

- **成功标准**：得到 `eval_mac_lora.json` 与 `public_mac_lora.json`；表格完整；GGUF 的 sha256/字节数已记录。
- **失败处理**：任何一步失败，记录原文，保留已有产物，不要改训练数据或评分脚本。
- **记录**：训练耗时、峰值内存（活动监视器或 `/usr/bin/time -l` 不便时写「未测」）、最终 Train/Val loss、两张对比表、GGUF 路径 + 字节数 + sha256。

---

## T3b（r4/r5 必做）金额换算截图验证

1. 跑 `testAmountConversionShown`（启动参数 `-UITestMode mock-ready -UITestSeedAmount`），截图 `08_amount_conversion`：气泡必须出现 `Rp 100.000（约 ¥37）` 和汇率说明行（含 `2026-10-12`）。
2. 在 `07_chat_sent` 截图中确认金额芯片显示「约 ¥…」，不再出现「示例汇率」。
3. 打开 设置 → 汇率，截图 `09_rate_settings`（1 CNY / 1 USD 对应 IDR、日期、来源）。
4. 英文环境再跑一次：追加 `-AppleLanguages (en) -AppleLocale en_US`，截图 `08_amount_conversion_en`，应显示 `≈ $5.6`（UI 测试里中文断言失败属预期，只要截图正确即可，报告里注明）。
5. 报告里写明：数量级是否正确（100.000 → ¥37 而非 ¥3.7/¥370）、日期是否显示、有无截断。

## T7（可选，需要用户本人）StoreKit / 真机——只列出，不要执行

以下步骤需要用户的 Apple ID、开发者团队、真机，代理**不要做**，只在报告里原样列出给用户：

1. Xcode 打开 `App/TripUnderstand.xcodeproj` → Signing & Capabilities 选 Team；检查 `com.apple.developer.kernel.increased-memory-limit` 权限是否可用。
2. Scheme → Run → Options → StoreKit Configuration 选 `Products.storekit`；模拟器里测「单次旅行包（30 天）」「终身买断」「恢复购买」；用 Xcode 的 Transaction Manager 退款，确认回到试用状态。
3. 真机（建议 8 GB 内存机型，如 iPhone 15 Pro 及以上）：完整下载 1.1 GB 模型、断网使用、按住说话（含面对面模式对方半屏按钮的上滑取消方向）、复制回 Grab 粘贴。
4. 卸载重装后确认 24 小时试用记录仍在（钥匙串）。
5. 真机测速：模型加载时间、首字延迟、tok/s、内存峰值（Xcode Instruments）。

---

## 提交与反馈（每轮）

```bash
cd "$REPO"
REPORT=reports/mac_run_${RUN_DATE}_r${ROUND}.md
git status --short
git status --short | grep -E "\.gguf|\.safetensors|\.bin|finetune/runs/|\.xcresult" && echo "STOP: 有模型/大文件，不要提交"
du -sh "$SCREENS"                                         # 截图总量应 < 5 MB
git add "$REPORT" "$SCREENS" finetune/results/eval_mac_*.json finetune/results/public_mac_*.json 2>/dev/null
git add -u App TripCore                                   # 仅 T3/T4 允许的最小修复 + xcodegen 重新生成的工程
git diff --cached --stat
git commit -m "Mac run r$ROUND ($RUN_DATE): 报告、截图、评测结果"
git push -u origin "$BR"
gh auth status && gh pr create --base master --head "$BR" --title "Mac run r$ROUND" --body-file "$REPORT"
```

- **不要合并 PR**（不要 `gh pr merge`，也不要推 master）。
- `xcodegen generate` 会改写 `App/TripUnderstand.xcodeproj`；编译成功时把重新生成的工程一起提交。
- `gh` 未登录：不要自己处理令牌；记录「gh 未登录」，并在最终回复里给出手动建 PR 链接：`https://github.com/xhq52465840/offline-trip-translator/compare/master...<分支名>`。
- push 被拒（无权限）：记录原文，报告留在本机，最终回复里贴报告全文。

---

## 迭代循环（两个代理）

角色：
- **Mac 代理（你）**：每轮拉最新 master，执行 T0–T6（T0/T5/T6 见下方「每轮跑哪些」），写报告、推分支、开 PR。不合并。
- **盒子代理（Linux，审阅方）**：看 PR 报告与截图，修复问题推到 master（保证 Linux 上 `swift test` 全绿、UI 文件 `swiftc -parse` 通过），然后在 PR 上评论 `next round`（可能附带说明，如「r3 只跑 T2–T4」）。

### 每轮跑哪些

| 任务 | r1 | 之后每轮 |
|---|---|---|
| T0 环境 | 全做 | 只记录 `xcodebuild -version`、磁盘 |
| T1–T4 | 全做 | 全做 |
| T5 Metal 冒烟 | 做 | 模型文件已在则跳过下载；llama.cpp 版本未变则跳过 |
| T6 LoRA 训练 | 做（长任务） | 仅当 PR 评论或 master 改动了 `finetune/`（`git diff --stat <上轮commit>..origin/master -- finetune/`）时重做 |
| T7 | 只列出 | 只列出 |

### 等待下一轮

开完 PR 后，每 10 分钟检查一次（最多等 24 小时）：

```bash
PR=$(gh pr list --head "$BR" --json number -q '.[0].number'); echo "PR=$PR"
LAST=$(git rev-parse origin/master)
while true; do
  git fetch -q origin
  gh pr view "$PR" --comments --json comments -q '.comments[].body' | tail -5 > "$WORK/pr_comments.txt"
  STATE=$(gh pr view "$PR" --json state -q .state)
  if grep -qiE "^\s*stop\b" "$WORK/pr_comments.txt"; then echo STOP; break; fi   # 合并不代表停止（$STATE 仅记录）
  if grep -qi "next round" "$WORK/pr_comments.txt" && [ "$(git rev-parse origin/master)" != "$LAST" ]; then echo NEXT; break; fi
  sleep 600
done
```

- 看到 `next round` **且** master 有新提交：读完整评论（`gh pr view "$PR" --comments`），把评论里的要求写进下一轮报告开头「本轮输入」，然后：
  ```bash
  export ROUND=$((ROUND+1)); export BR=mac-run-$RUN_DATE-r$ROUND; export SCREENS=reports/screens/$RUN_DATE-r$ROUND
  cd "$REPO" && git checkout master && git pull --ff-only && git checkout -B "$BR"
  ```
  从 T1 重新开始（日期变了就用新日期，轮次继续累加）。
- 只有 `next round` 但 master 没新提交：继续等（审阅方可能还在推）。
- 上一轮 PR 不用关闭；审阅方负责关闭/合并（可能 squash 进 master 后关闭 PR，评论仍有效）。
- 新一轮开分支前先 `git checkout master && git pull --ff-only`，因为上一轮的提交可能已被 squash 进 master，旧分支不要再用。

### 停止条件（满足任一即停，在最后的 PR 上评论总结）

1. PR 评论出现 `stop`（独占一行）。**PR 被合并（或审阅方 squash 后关闭）不是停止信号**：审阅方仍会在该 PR（含已合并/已关闭的 PR）上评论 `next round`，照常进入下一轮；
2. 连续两轮：T2/T4 全部通过、无新编译错误、无新 UX 问题（报告里写明「连续两轮全绿」）；
3. 达到 8 轮；
4. 等待超过 24 小时没有新评论；
5. 出现需要用户本人的阻塞（Apple ID、签名、付费、真机）：评论说明并停止。

停止时的最终评论：
```bash
gh pr comment "$PR" --body "Mac 代理停止：<原因>。最后一轮 r$ROUND，报告 reports/mac_run_${RUN_DATE}_r${ROUND}.md。"
```

---

## 报告模板（复制到 `reports/mac_run_<日期>_r<轮次>.md` 并填写）

```markdown
# Mac run r<N>（<日期>）

## 本轮输入
- 基于 master commit：
- 上一轮 PR 评论要求：（r1 写「无」）

## 环境
| 项 | 值 |
|---|---|
| macOS | |
| 芯片 / RAM / 可用磁盘 | |
| Xcode / iOS SDK / 模拟器（机型 + runtime） | |
| Swift | |
| python / mlx-lm / llama-cpp-python | |
| llama.cpp 版本 | b11541 |

## 任务状态
| 任务 | 状态（✅/⚠️/❌/跳过） | 备注 |
|---|---|---|
| T0 环境 | | |
| T1 代码 | | |
| T2 swift test | | 测试数 / 失败数 |
| T3 Xcode 编译 | | |
| T4.2 包测试（模拟器） | | |
| T4.4 UI 测试 | | |
| T4.5 内存检查 | | |
| T4.6 模拟器真实模型 | | |
| T5 Metal 冒烟 | | |
| T6 LoRA 训练+评测 | | |
| T7 | 未执行（需用户） | |

## UI 测试结果
| 测试 | 结果 | 耗时 | 失败原文 |
|---|---|---|---|
| testOnboardingShows | | | |
| testBlockingSheetOnLaunchWhenNotReady | | | |
| testPhraseBookFromBlockingSheetAndPresent | | | |
| testPurchasePageOpens | | | |
| testHomeAndChatWithMockEngine | | | |
| testLaunchMemoryMetric | | | |

## 截图
| 文件（reports/screens/<日期>-r<N>/） | 画面 | 观察到的问题 |
|---|---|---|

## UX 问题（亲眼看截图）
| # | 截图 | 问题 | 严重度（高/中/低） | 建议 |
|---|---|---|---|---|

## 指标
| 项 | 值 | 说明 |
|---|---|---|
| 启动内存（XCTMemoryMetric） | | 模拟器，非真机 |
| 启动时间（XCTApplicationLaunchMetric） | | |
| RSS（ps） | | |
| T5 load / TTFT / tok/s | | Mac Metal，非 iPhone |

## 错误原文
（每个错误：任务、命令、完整输出，用代码块）

## 代码修复清单（仅 T3/T4 允许的最小修复）
| # | 文件:行 | 错误原文 | 修改 | 原因 |
|---|---|---|---|---|

## T6 训练与评测（本轮做了才填）
| 项 | 值 |
|---|---|
| 配置 / 耗时 / 峰值内存 / 最终 Train·Val loss | |

（粘贴 6.5 的两张对比表）

## 产出文件
| 文件 | 说明 | 是否提交 |
|---|---|---|
| finetune/runs/trip-qwen2.5-1.5b-lora-Q4_K_M.gguf | 本机路径：… ；字节数：… ；sha256：… | 否 |
| finetune/results/*_mac_*.json | | 是 |
| reports/screens/<日期>-r<N>/*.png | | 是 |

## 需要用户处理 / 给审阅方的问题
```
