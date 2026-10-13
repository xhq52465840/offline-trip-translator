# Mac 执行手册（给在用户 Mac 上运行的 AI 代理）

> 你只有仓库地址：`https://github.com/xhq52465840/offline-trip-translator`（默认分支 `master`）。
> 本手册自包含：按 T0 → T7 顺序执行，并按文末「§迭代循环」一轮一轮重复（每轮编号 r1、r2…）。每个任务都有：目标、命令、成功标准、失败处理、记录内容。
> 假设机器为 Apple Silicon Mac。所有时间按用户本地时区记录。

## 总规则（必须遵守）

1. **不要绕过失败**：命令失败时，把完整报错原文（verbatim）写进报告，标记该任务为 ❌/⚠️，然后继续下一个**不依赖它**的任务。不要改系统设置、不要关 SIP、不要 `sudo` 改系统目录、不要禁用签名/校验。
2. **允许的代码修改只有一种**：T3/T4 中 Xcode 编译错误的**最小修复**（每处修复都要在报告里列出：文件、行、原因、diff）。其他任何代码不要改。
3. **绝不提交**：`.gguf`、`.safetensors`、`.bin`、适配器权重、`finetune/runs/` 下任何东西、任何密钥/令牌/证书/个人路径以外的隐私信息。仓库 `.gitignore` 已排除这些，提交前仍需 `git status` 人工核对。
4. **不要上传模型**到任何地方（不传 HF、不传网盘、不传对象存储）。只在报告里写本地路径、字节数、sha256。
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

App 侧（r2、r3 已连续两轮全绿）：本轮 T3/T4 只需编译 + UI 测试 + 06_home 截图确认底行副标题不被遮挡。

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
