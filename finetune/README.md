# 理解模型 LoRA 微调（Qwen2.5-1.5B-Instruct）

目标：让端侧理解模型（`Understander`）在 17 个旅行场景里把「系统直译」修成对的中文：俚语缩写（udh/gk/brp/otw/share lok）、金额（50rb/1,5jt/Rp 50.000，用 App 换算表）、指代（「刚才那个」「那边」）、价格附加项（++ / nett / 押金 / 小费）。

## 目录
| 路径 | 内容 |
|---|---|
| `data/templates.py` | 人工撰写的场景模板（约 100 个，17 个场景，两个方向），**不含任何模型生成内容，未使用 Hy-MT 输出** |
| `data/gen.py` | 槽位填充生成 → 调 `trip-prompt` 渲染/校验 → 去重 → 剔除与评测集相近样本 → 切分 |
| `out/{train,valid,test}.jsonl` | 生成好的数据（`{"messages": [...]}` 聊天格式，mlx-lm 与 PEFT 通用）；`*.meta.jsonl` 为场景/方向；`stats.json` 为统计 |
| `mlx/lora.yaml`, `mlx/run_mlx.sh` | **Mac 主流程**（Apple Silicon，mlx-lm） |
| `peft/train_peft.py`, `peft/merge_peft.py` | CUDA（或 CPU 冒烟）备选流程 |
| `scripts/to_gguf.sh` | HF 权重 → GGUF f16 → Q4_K_M，输出 sha256/字节数 |
| `scripts/eval_appfmt.py` | 用 App 同一份提示词在 60 条评测用例上打分（与《端侧模型验证报告》同一评分） |
| `results/` | 本机实测结果 |

## 数据怎么来的（保证与 App 一致）
1. 模板 + 槽位：称呼（kak/pak/bu/mas）、地点、物品、颜色、菜名、分钟、钟点、套餐天数/GB、汇率；金额按场景取值范围并随机写成 `50rb / 50 ribu / 50k / Rp 50.000 / 1,5jt / 1.5 juta`。
2. 俚语：模板里 `«sudah»` 这类词随机换成 `udh/sdh/udah`，**字面译文里同步保留缩写**（模拟系统翻译看不懂缩写），目标输出是正确中文。
3. 字面译文模拟常见机翻错误：`ribu`→「千」、`juta`→「百万」、称呼直译成「姐姐/先生」、缩写原样残留。
4. 目标输出里的金额写成 `⟨A1⟩`，由 Swift 工具 `trip-prompt`（`TripCore/Sources/trip-prompt`）用 App 的 `AmountNormalizer` 填入，所以训练目标里的金额与 App 换算器**逐字一致**。
5. `trip-prompt` 同时用 App 的 `PromptBuilder` 渲染 system / few-shot / user（含场景、前情摘要、金额表、词表），并用 `OutputValidator` 校验目标；被拒的样本丢弃。额外检查：金额必须出现在目标里、不得出现原文没有的外语词、「我」方向不得新增/改动数字。
6. 评测隔离：与 60 条评测原文 token Jaccard ≥ 0.6 的样本全部剔除（本次剔除 436 条）。
7. 切分：每个场景留 1 个**整模板**做 test（考察没见过的句式）；其余随机 95/5 分 train/valid。

本次生成（`python data/gen.py --per 50 --seed 7`）：保留 **2767** 条（train 2244 / valid 118 / test 405），他方印尼语→中文 2495 条，我方中文指代澄清 272 条，17 个场景都有覆盖（见 `out/stats.json`）。

> 局限：模板数据句式有限，口语多样性不如真实对话；上线前建议补充母语者撰写/审校的真实样本（每场景 50–100 条），并让母语者抽检 5%。

## Mac 上训练（主流程，Apple Silicon）
以下时间/内存为**估算**，未在 Mac 上实测：
```bash
# 0) 环境
python3 -m venv ~/venv-ft && source ~/venv-ft/bin/activate
pip install -U mlx-lm huggingface_hub
git clone https://github.com/ggml-org/llama.cpp ~/llama.cpp
cmake -S ~/llama.cpp -B ~/llama.cpp/build && cmake --build ~/llama.cpp/build --target llama-quantize -j
pip install -r ~/llama.cpp/requirements/requirements-convert_hf_to_gguf.txt

# 1) 生成数据（需要先在 demo/TripCore 里 swift build 出 trip-prompt）
cd demo/TripCore && swift build && cd ../finetune
python data/gen.py --per 50

# 2) 训练 → 融合 → GGUF Q4_K_M → sha256
LLAMA_CPP=~/llama.cpp bash mlx/run_mlx.sh
#   估算：M1/M2 16GB 约 1–2 小时（1500 iters, batch 4）；M3 Max 约 30–40 分钟；峰值内存约 8–12 GB

# 3) 评测（与基线比较）
pip install llama-cpp-python
python scripts/eval_appfmt.py runs/trip-qwen2.5-1.5b-lora-Q4_K_M.gguf --tag lora
```
CUDA 备选：`python peft/train_peft.py --model Qwen/Qwen2.5-1.5B-Instruct --data out --out runs/lora --steps 600 --bs 8`，再 `python peft/merge_peft.py --base ... --lora runs/lora --out runs/merged`，`bash scripts/to_gguf.sh runs/merged runs/trip-lora`。估算：单张 24GB 显卡约 20–40 分钟。

## 发布新模型（更新 model-manifest）
1. `to_gguf.sh` 输出 `*.gguf.json`（`bytes`、`sha256`）。
2. 按不可变路径上传到各镜像：`models/trip-qwen2.5-1.5b-lora/q4_k_m/{sha256前8位}/model.gguf`（见技术设计 v2 §13.5）。
3. 修改 `TripCore/Sources/TripCore/Resources/model-manifest.json`：新 `id`、`bytes`、`sha256`、`mirrors`（cn → global → hf 占位）。`id` 变化后已装旧模型的用户会重新下载。
4. `swift test`（`testBundledManifest*` 会检查清单格式）。
5. 真机跑一遍首启下载 + 评测用例。

## 本机实测（Linux x86 CPU，非 Mac / 非 iPhone）
见 `results/README.md`。

### 短程 LoRA（2026-10-11，【实测 · 短 CPU 跑】，非最终质量）
- 训练：CPU PEFT，train=2244，约 150 step，`val_loss` 1.40→0.05；融合量化 `runs/short-Q4_K_M.gguf`（约 941MB，不入库）。
- App 60 条：`eval_base` 严格 90/120、金额错 5 → `eval_short` 严格 **105/120**、金额错 **2**（关键词 97→110）。
- 公开集 chrF++：`scripts/eval_public.py` → `results/public_{base,short}.json`（汇总表在 `results/README.md`）。

## Mac run r1 结论与配置调整（2026-10-12）

- 1500 步 / lr 1e-4：验证 loss 第 600 步起为 0，App 格式 60 条 strict 85→88、金额错 5→2，但公开集 chrF++ 47.11→0.28，输出不再是翻译（灾难性遗忘；模板数据多样性不足，验证集与训练集同分布）。
- 已改 `mlx/lora.yaml`：400 步、lr 5e-5、dropout 0.1、每 100 步存检查点、每 50 步验证。
- 选模型规则：App 格式 strict 不低于基座 **且** 公开集 chrF++ 下降不超过 3 分；否则不采用该检查点。
- 后续（待做）：混入通用翻译回放数据（从 Tatoeba 训练侧取，与 public_eval 不相交）以防遗忘。

## r3：通用回放防遗忘（2026-10-12）

r2 的 400 步 s200/s400：App 格式 strict 105/102（基座 85），但公开集三项下降 15–49 分，按规则不采用。原因是只训场景模板数据，通用翻译/口语规范化能力被覆盖。
- `data/build_replay.py`：从 Tatoeba ind↔cmn 与 STIF train 取回放样本（与 public_eval 原文零重叠，脚本内校验），按约 30% 混入 → `out_mix/`（场景 2244 + 回放 961，验证另加 60）。
- `mlx/lora_mix.yaml`：data=out_mix，600 步，适配器 `runs/mlx_adapters_mix`，其余同 lora.yaml。
- 注意：回放用的提示词与 eval_public 相同（同任务不同句子），公开集分数会偏乐观，报告里需注明。

## r3 结果与 r4 调整（2026-10-13）

| 检查点 | App strict（基座 85） | 金额错 | 印→中 chrF | 印→英 chrF++ | 口语规范化 |
|---|---|---|---|---|---|
| mac_base | 85 | 5 | 27.67 | 51.89 | 50.31 |
| mix s300 | 102 | 2 | 16.98 | 18.33 | 67.0* |
| mix s600 | 102 | 1 | 18.71 | 37.9 | 71.86* |

*回放与评测同提示词，偏乐观。按规则（每项降 ≤3）仍不采用；但 s600 抽样输出确实在翻译，遗忘比 r2 明显减轻。
r4：回放提到约 45% 并加入 FLORES dev 的印→中/印→英（r3 无英文回放，印→英掉得最多），800 步。

**待用户决定**：App 内字面翻译由 Apple Translation 完成，LLM 只做上下文修正，通用 MT 能力不是它的主职。若 r4 仍不达标，可考虑放宽规则为「App strict ≥ 基座 +10 且金额错不增加，公开 MT 各项降 ≤ 10」。在用户同意前不改规则。
