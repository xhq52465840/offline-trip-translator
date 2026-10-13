# 第三方组件、模型与数据许可（NOTICE）

> 本仓库代码尚未选定开源许可证（待用户决定）。以下为所用第三方内容的许可，发布 App 或数据时需随附相应署名。

| 名称 | 用途 | 许可 | 署名/义务 |
|---|---|---|---|
| Qwen2.5-1.5B-Instruct（Alibaba Qwen） | 端侧理解模型（下载，不进仓库） | Apache-2.0（https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct ） | App 内「关于/致谢」注明模型名称与许可；微调后的衍生模型同样注明 |
| llama.cpp / ggml | 推理运行时 | MIT（https://github.com/ggml-org/llama.cpp ） | 随 App 附 MIT 版权声明 |
| FLORES-200 | 公开评测（`finetune/public_data`） | CC BY-SA 4.0 | 署名 NLLB Team / Meta；衍生评测文件同协议 |
| Tatoeba 句子 | 公开评测 | CC BY 2.0 FR | 署名 Tatoeba 贡献者，保留句子 ID |
| Wikivoyage Indonesian phrasebook | 公开评测 | CC BY-SA 4.0 | 署名 Wikivoyage 贡献者，链接原页面 |
| STIF-Indonesia | 公开评测 | MIT | 署名 Haryo Akbarianto Wibowo 等 |
| Colloquial Indonesian Lexicon（kamus-alay） | 仅本地覆盖统计，不再分发 | 未声明 | 商用前联系作者 |
| 社区语料（`community_cases.jsonl`） | 仅评测，短引用 | 各网站条款；合理使用 | 保留来源网址；不进训练、不进 App |
| 微调训练数据（`finetune/out`） | 模板生成，自有 | 自有 | — |
| Hy-MT1.5（腾讯） | 仅评测过，未采用 | Tencent HY Community License（非 Apache） | 不分发 |

- `finetune/out_mix/`：含通用回放样本，来自 Tatoeba（CC BY 2.0 FR，https://tatoeba.org ）与 STIF-Indonesia train（MIT，https://github.com/haryoa/stif-indonesia ），由 `finetune/data/build_replay.py` 生成，与评测集不相交。
- `finetune/out_mix/` 自 r4 起还含 FLORES-200 dev 句子（CC BY-SA 4.0，https://github.com/facebookresearch/flores ），相应部分按 CC BY-SA 4.0 提供。
