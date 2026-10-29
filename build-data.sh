#!/bin/bash
# 方方詞卡: builds the app's word data (FangfangCards/dict.json and cards.json) from the
# Ministry of Education's 臺灣台語常用詞辭典 file (kautian.ods). The data isn't stored in this
# repository: the dictionary's license (CC BY-ND 3.0 TW) doesn't allow sharing changed versions,
# so everyone builds their own copy from the original file.
#   bash build-data.sh                 (downloads kautian.ods from the MOE website)
#   bash build-data.sh ~/Downloads/kautian.ods
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ODS="$1"
if [ -z "$ODS" ]; then
  ODS="$TMP/kautian.ods"
  echo "下載教育部《臺灣台語常用詞辭典》資料（kautian.ods）…"
  curl -fL --progress-bar -o "$ODS" "https://sutian.moe.edu.tw/media/senn/ods/kautian.ods"
fi
[ -f "$ODS" ] || { echo "✗ 找不到 $ODS"; exit 1; }
echo "下載 rime-essay 字頻表…"
curl -fsSL -o "$TMP/essay.txt" "https://raw.githubusercontent.com/rime/rime-essay/master/essay.txt"
cd "$HERE/tools"
echo "整理資料中…（大概 1 分鐘）"
/usr/bin/env python3 ods2csv.py "$ODS" "$TMP/sheets.json" > /dev/null
/usr/bin/env python3 build_moe.py "$TMP/sheets.json" own.json "$TMP/data2.json" > /dev/null
/usr/bin/env python3 to_app_data.py "$TMP/data2.json" "$TMP/essay.txt" "$HERE/FangfangCards/dict.json" > /dev/null
/usr/bin/env python3 build_cards.py "$HERE/FangfangCards/dict.json" "$TMP/essay.txt" "$HERE/FangfangCards/cards.json" > /dev/null
/usr/bin/env python3 build_grammar.py "$HERE/FangfangCards/dict.json" "$HERE/FangfangCards/grammar.json" > /dev/null
echo "✓ 完成：FangfangCards/dict.json、FangfangCards/cards.json、FangfangCards/grammar.json"
