#!/bin/bash
# commit 前跑這一支：結構檢查加上所有測試，任何一項沒過就以非零結束。
# 存在的理由：曾經把測試輸出接到 grep 再用 && 串 git commit，測試失敗的結束碼被 grep 吃掉，壞的 commit 就推出去了。
# 所以要 commit 時只認這支腳本的結束碼：bash scripts/check.sh && git commit ...
set -eu
cd "$(dirname "$0")/.."
python3 scripts/validate.py
for t in scripts/test_*.sh; do
  echo "== ${t}"
  /bin/bash "$t" >"/tmp/teamai-check.$$" 2>&1 || { cat "/tmp/teamai-check.$$"; rm -f "/tmp/teamai-check.$$"; echo "沒過：${t}" >&2; exit 1; }
  tail -1 "/tmp/teamai-check.$$"; rm -f "/tmp/teamai-check.$$"
done
echo "全部通過"
