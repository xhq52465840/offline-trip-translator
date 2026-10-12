# Mac 执行手册（给在用户 Mac 上运行的 AI 代理）

> 你只有仓库地址：`https://github.com/xhq52465840/offline-trip-translator`（默认分支 `master`）。
> 本手册自包含：按 T0 → T7 顺序执行。每个任务都有：目标、命令、成功标准、失败处理、记录内容。
> 假设机器为 Apple Silicon Mac。所有时间按用户本地时区记录。

## 总规则（必须遵守）

1. **不要绕过失败**：命令失败时，把完整报错原文（verbatim）写进报告，标记该任务为 ❌/⚠️，然后继续下一个**不依赖它**的任务。不要改系统设置、不要关 SIP、不要 `sudo` 改系统目录、不要禁用签名/校验。
2. **允许的代码修改只有一种**：T3/T4 中 Xcode 编译错误的**最小修复**（每处修复都要在报告里列出：文件、行、原因、diff）。其他任何代码不要改。
3. **绝不提交**：`.gguf`、`.safetensors`、`.bin`、适配器权重、`finetune/runs/` 下任何东西、任何密钥/令牌/证书/个人路径以外的隐私信息。仓库 `.gitignore` 已排除这些，提交前仍需 `git status` 人工核对。
4. **不要上传模型**到任何地方（不传 HF、不传网盘、不传对象存储）。只在报告里写本地路径、字节数、sha256。
5. 不要修改 `TripCore/Sources/TripCore/Resources/model-manifest.json` 里的地址/哈希（托管方案未定）。
6. 所有输出写到仓库内 `reports/mac_run_<日期>.md`（模板见文末），结果 JSON 放 `finetune/results/`。
7. 长任务用 `caffeinate` 防睡眠，并把日志写到文件，不要只看终端。

先设置几个变量（后续命令都用它们）：

```bash
export RUN_DATE=$(date +%Y%m%d)
export WORK=$HOME/trip-work            # 工作目录（模型、llama.cpp、venv 放这里，不在仓库里）
export REPO=$WORK/offline-trip-translator
export LLAMA_CPP=$WORK/llama.cpp
export VENV=$WORK/venv-ft
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
git checkout -b "mac-run-$RUN_DATE"
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

## T4 在模拟器上跑测试

App 工程没有 UI 测试目标；逻辑测试在 Swift 包里，用 xcodebuild 在 iOS 模拟器上跑包测试：

```bash
cd "$REPO/TripCore"
xcodebuild -list                           # 期望看到 TripCore-Package scheme
xcodebuild test -scheme TripCore-Package -destination "id=$SIM" \
  -derivedDataPath "$WORK/DerivedData-pkg" 2>&1 | tee "$WORK/t4_test.log" | tail -30
grep -E "Executed|TEST (SUCCEEDED|FAILED)" "$WORK/t4_test.log"
```

如果 T3 成功，再在模拟器里装起来启动，确认不崩溃（截图存 `reports/`，截图里不要有个人信息）：

```bash
APP=$(find "$WORK/DerivedData/Build/Products/Debug-iphonesimulator" -name "TripUnderstand.app" -maxdepth 1 | head -1)
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" app.tripunderstand.demo
sleep 8
mkdir -p "$REPO/reports"
xcrun simctl io "$SIM" screenshot "$REPO/reports/mac_run_${RUN_DATE}_launch.png"
```

- 模拟器里**不要**真的开始下载 1.1 GB 模型（会占用流量和时间）；看到引导页/阻断页即可。
- **成功标准**：包测试 `TEST SUCCEEDED`；App 能启动到引导页。
- **失败处理**：记录原文；模拟器上的测试失败但 Linux 通过的，标注「平台差异」。
- **记录**：测试数、截图文件名、崩溃日志（如有：`xcrun simctl spawn "$SIM" log show --last 2m --predicate 'process == "TripUnderstand"' | tail -50`）。

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
for t in ["base", "short", "mac_base", "mac_lora"]:
    p = f"eval_{t}.json"
    if os.path.exists(p):
        s = json.load(open(p))["summary"]
        print(f"| {t} | {s['score']}/{s['max']} | {s['strict']} | {s['orig30_strict']} | {s['ext30_strict']} | {s['amount_err']} | {s['app_accepted']} | {s['ttft_med']} |")
print()
print("| tag | n | mt_id_zh chrF | mt_id_en chrF++ | slang_norm chrF++ |")
print("|---|---|---|---|---|")
for t in ["base", "short", "mac_base", "mac_lora"]:
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

## T7（可选，需要用户本人）StoreKit / 真机——只列出，不要执行

以下步骤需要用户的 Apple ID、开发者团队、真机，代理**不要做**，只在报告里原样列出给用户：

1. Xcode 打开 `App/TripUnderstand.xcodeproj` → Signing & Capabilities 选 Team；检查 `com.apple.developer.kernel.increased-memory-limit` 权限是否可用。
2. Scheme → Run → Options → StoreKit Configuration 选 `Products.storekit`；模拟器里测「单次旅行包（30 天）」「终身买断」「恢复购买」；用 Xcode 的 Transaction Manager 退款，确认回到试用状态。
3. 真机（建议 8 GB 内存机型，如 iPhone 15 Pro 及以上）：完整下载 1.1 GB 模型、断网使用、按住说话（含面对面模式对方半屏按钮的上滑取消方向）、复制回 Grab 粘贴。
4. 卸载重装后确认 24 小时试用记录仍在（钥匙串）。
5. 真机测速：模型加载时间、首字延迟、tok/s、内存峰值（Xcode Instruments）。

---

## 提交与反馈

```bash
cd "$REPO"
git status --short
# 检查不该提交的东西：
git status --short | grep -E "\.gguf|\.safetensors|\.bin|finetune/runs/" && echo "STOP: 有模型文件，不要提交"
git add reports/ finetune/results/eval_mac_*.json finetune/results/public_mac_*.json
git add -u App TripCore            # 仅 T3 的编译修复（如有）
git diff --cached --stat
git commit -m "mac run $RUN_DATE: 环境/编译/测试/Metal 冒烟/MLX LoRA 评测报告"
git push -u origin "mac-run-$RUN_DATE"
gh auth status && gh pr create --base master --head "mac-run-$RUN_DATE" \
  --title "Mac run $RUN_DATE" --body-file "reports/mac_run_${RUN_DATE}.md"
```

- `xcodegen generate` 会改写 `App/TripUnderstand.xcodeproj`；如果 T3 编译成功，把重新生成的工程一起提交（它是从 `project.yml` 生成的）。
- `gh` 未登录：不要自己处理令牌；记录「gh 未登录」，并在最终回复里给出手动建 PR 链接：`https://github.com/xhq52465840/offline-trip-translator/compare/master...mac-run-<日期>`。
- push 被拒（无权限）：记录原文，报告留在本机，最终回复里贴报告全文。

---

## 报告模板（复制到 `reports/mac_run_<日期>.md` 并填写）

```markdown
# Mac 运行报告 <日期>

## 环境
| 项 | 值 |
|---|---|
| macOS | |
| 芯片 / RAM / 可用磁盘 | |
| Xcode / iOS SDK / 模拟器 | |
| Swift | |
| python / mlx-lm / llama-cpp-python | |
| llama.cpp 版本 | b11541 |
| 仓库 commit | |

## 任务状态
| 任务 | 状态（✅/⚠️/❌/跳过） | 备注 |
|---|---|---|
| T0 环境 | | |
| T1 代码 | | |
| T2 swift test | | 测试数 / 失败数 |
| T3 Xcode 编译 | | |
| T4 模拟器测试 | | |
| T5 Metal 冒烟 | | |
| T6 LoRA 训练+评测 | | |
| T7 | 未执行（需用户） | |

## 错误原文
（每个错误：任务、命令、完整输出，用代码块）

## 代码修复清单（仅 T3/T4）
| # | 文件:行 | 错误原文 | 修改 | 原因 |
|---|---|---|---|---|

## T5 Metal 冒烟（Mac，非 iPhone）
| 模型 | 来源（HF/hf-mirror） | sha256 校验 | load (ms) | TTFT (ms) | 生成 tok/s | pp512 | tg128 |
|---|---|---|---|---|---|---|---|

## T6 训练
| 项 | 值 |
|---|---|
| 配置 | mlx/lora.yaml（或 lora_mac_small.yaml） |
| 耗时 | |
| 峰值内存 | |
| 最终 Train / Val loss | |

### 60 条 App 格式评测
（粘贴 6.5 的第一张表）

### 公开集 chrF++
（粘贴 6.5 的第二张表）

## 产出文件
| 文件 | 说明 | 是否提交 |
|---|---|---|
| finetune/runs/trip-qwen2.5-1.5b-lora-Q4_K_M.gguf | 微调模型（本机路径：…） | 否 |
| 字节数 / sha256 | | — |
| finetune/results/eval_mac_base.json, eval_mac_lora.json | | 是 |
| finetune/results/public_mac_base.json, public_mac_lora.json | | 是 |

## 需要用户处理
（T7 清单 + 本次发现的问题）
```
