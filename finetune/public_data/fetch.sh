#!/usr/bin/env bash
# 下载公开数据原始文件到 raw/（不进仓库），再运行 build_public_eval.py
set -euo pipefail; cd "$(dirname "$0")"; mkdir -p raw; cd raw
B=https://downloads.tatoeba.org/exports/per_language
for f in ind/ind-cmn_links ind/ind_sentences cmn/cmn_sentences; do curl -sfL "$B/$f.tsv.bz2" | python3 -c "import bz2,sys;sys.stdout.buffer.write(bz2.decompress(sys.stdin.buffer.read()))" > "$(basename $f).tsv"; done
curl -sfL https://dl.fbaipublicfiles.com/nllb/flores200_dataset.tar.gz | tar xz --wildcards "*ind_Latn*" "*zho_Hans*" "*eng_Latn*"
for s in test dev train; do for e in inf for; do curl -sfL -o stif_$s.$e https://raw.githubusercontent.com/haryoa/stif-indonesia/main/data/labelled/$s.$e; done; done
curl -sfL -o colloquial-indonesian-lexicon.csv https://raw.githubusercontent.com/nasalsabila/kamus-alay/master/colloquial-indonesian-lexicon.csv
curl -sfL -o wikivoyage_indonesian_phrasebook.wiki "https://en.wikivoyage.org/w/index.php?title=Indonesian_phrasebook&action=raw"
echo ok
