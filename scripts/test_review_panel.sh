#!/bin/bash
# 用假的 CLI 測 review-panel.sh 的行為。不呼叫任何真的 AI。
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
panel="$root/plugins/teamai/skills/cross-review/scripts/review-panel.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pass=0; failn=0
ok() { pass=$((pass + 1)); echo "  通過：$1"; }
bad() { failn=$((failn + 1)); echo "  失敗：$1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# 假的審查者。行為由 FAKE_MODE 決定：reply（預設）、fail、hang、write、silent。
# 會把收到的參數記到 $FAKE_LOG，測試用它確認唯讀旗標真的有帶。
mkdir -p "$tmp/bin"
for name in codex gemini grok agy; do
cat >"$tmp/bin/$name" <<FAKE
#!/bin/bash
echo "$name \$*" >>"\${FAKE_LOG:-/dev/null}"
out=""
prev=""
for a in "\$@"; do [ "\$prev" = "-o" ] && [ "$name" = "codex" ] && out="\$a"; prev="\$a"; done
mode="\${FAKE_MODE_$name:-\${FAKE_MODE:-reply}}"
case "\$mode" in
  fail) echo "boom" >&2; exit 7 ;;
  hang) sleep 30 ;;
  write) echo hi > proof.txt ;;
  silent) exit 0 ;;
esac
if [ -n "\$out" ]; then echo "[低] a.txt:1 — $name 的發現" >"\$out"; else echo "[低] a.txt:1 — $name 的發現"; fi
FAKE
chmod +x "$tmp/bin/$name"
done
use_fakes() { export TEAMAI_CODEX_BIN="$tmp/bin/codex" TEAMAI_GEMINI_BIN="$tmp/bin/gemini" TEAMAI_GROK_BIN="$tmp/bin/grok" TEAMAI_AGY_BIN="$tmp/bin/agy"; }
unset FAKE_MODE FAKE_MODE_codex FAKE_MODE_gemini FAKE_MODE_grok FAKE_MODE_agy

# 測試用的 repo：一個已 commit 的檔案加一個未 commit 的修改
repo="$tmp/repo"; mkdir "$repo"
git -C "$repo" init -q -b main
git -C "$repo" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
echo one >"$repo/a.txt"; git -C "$repo" add a.txt
git -C "$repo" -c user.email=t@example.com -c user.name=t commit -q -m a
echo two >>"$repo/a.txt"
export FAKE_LOG="$tmp/calls.log"

echo "1. 三家都在：平行執行，各自有結果"
use_fakes; : >"$FAKE_LOG"
"$panel" --repo "$repo" --out "$tmp/o1" >"$tmp/o1.txt" 2>&1; rc=$?
check "結束碼 0" '[ "$rc" -eq 0 ]'
check "codex、gemini、grok 都是 ok" '[ "$(grep -c "	ok	" "$tmp/o1/summary.tsv")" -eq 3 ]'
check "同廠牌只跑一個：有 gemini 就不跑 agy" '! grep -q "^agy" "$tmp/o1/summary.tsv" && ! grep -q "^agy " "$FAKE_LOG"'
check "各自的審查結果有內容" 'grep -q "codex 的發現" "$tmp/o1/codex.md" && grep -q "grok 的發現" "$tmp/o1/grok.md"'
check "改動有存成 change.diff" 'grep -q "^+two" "$tmp/o1/change.diff"'
check "codex 帶了唯讀旗標" 'grep -q "^codex exec -s read-only" "$FAKE_LOG"'
check "gemini 帶了 plan 模式" 'grep -q "^gemini --approval-mode plan" "$FAKE_LOG"'
check "grok 帶了唯讀沙箱" 'grep -q "^grok --sandbox read-only" "$FAKE_LOG"'

echo "2. 有人沒裝、有人失敗：照實記錄，其他人不受影響"
use_fakes; export TEAMAI_GROK_BIN="$tmp/none" TEAMAI_AGY_BIN="$tmp/none" FAKE_MODE_gemini=fail
"$panel" --repo "$repo" --out "$tmp/o2" >"$tmp/o2.txt" 2>&1; rc=$?
check "還有一家成功所以結束碼 0" '[ "$rc" -eq 0 ]'
check "grok 記為 missing" 'grep -q "^grok	missing" "$tmp/o2/summary.tsv"'
check "gemini 記為 failed(7)" 'grep -q "^gemini	failed(7)" "$tmp/o2/summary.tsv"'
check "codex 仍然 ok" 'grep -q "^codex	ok" "$tmp/o2/summary.tsv"'
unset FAKE_MODE_gemini

echo "3. 沒有任何回覆：結束碼 2，不假裝審過"
use_fakes; export FAKE_MODE=silent
"$panel" --repo "$repo" --out "$tmp/o3" --only codex >"$tmp/o3.txt" 2>&1; rc=$?
check "結束碼 2" '[ "$rc" -eq 2 ]'
check "codex 記為 empty" 'grep -q "^codex	empty" "$tmp/o3/summary.tsv"'
unset FAKE_MODE

echo "4. 逾時：砍掉並記為 timeout"
use_fakes; export FAKE_MODE=hang
start=$(date +%s)
"$panel" --repo "$repo" --out "$tmp/o4" --only grok --timeout 2 >"$tmp/o4.txt" 2>&1; rc=$?
took=$(( $(date +%s) - start ))
check "grok 記為 timeout" 'grep -q "^grok	timeout" "$tmp/o4/summary.tsv"'
check "沒有等到假程式自己結束（${took} 秒）" '[ "$took" -lt 15 ]'
unset FAKE_MODE

echo "5. 改動裡有密鑰：不送出"
use_fakes; : >"$FAKE_LOG"
printf 'token = "ghp_%s"\n' "abcdefghijklmnopqrstuvwxyz0123" >>"$repo/a.txt"
"$panel" --repo "$repo" --out "$tmp/o5" >"$tmp/o5.txt" 2>&1; rc=$?
check "結束碼 4" '[ "$rc" -eq 4 ]'
check "沒有呼叫任何審查者" '[ ! -s "$FAKE_LOG" ]'
git -C "$repo" checkout -q a.txt; echo two >>"$repo/a.txt"

echo "6. 改動裡有 .env：不送出"
echo "X=1" >"$repo/.env"; git -C "$repo" add -N .env
"$panel" --repo "$repo" --out "$tmp/o6" >"$tmp/o6.txt" 2>&1; rc=$?
check "結束碼 4" '[ "$rc" -eq 4 ]'
git -C "$repo" reset -q .env; rm "$repo/.env"

echo "7. 沒有改動：結束碼 3"
git -C "$repo" checkout -q a.txt
"$panel" --repo "$repo" --out "$tmp/o7" --uncommitted >"$tmp/o7.txt" 2>&1; rc=$?
check "結束碼 3" '[ "$rc" -eq 3 ]'
echo two >>"$repo/a.txt"

echo "8. 預設輸出資料夾在 repo 裡，而且不會被 git 看到"
use_fakes
"$panel" --repo "$repo" --only codex >"$tmp/o8.txt" 2>&1; rc=$?
check "結束碼 0" '[ "$rc" -eq 0 ]'
check "git status 看不到 .teamai-review" '! git -C "$repo" status --porcelain | grep -q teamai-review'

echo "9. 自我測試：寫得了檔的審查者要判不合格"
use_fakes
"$panel" --selftest --only codex,grok >"$tmp/s1.txt" 2>&1; rc=$?
check "乖的審查者：結束碼 0、兩個都合格" '[ "$rc" -eq 0 ] && [ "$(grep -c "合格：有回覆" "$tmp/s1.txt")" -eq 2 ]'
export FAKE_MODE_grok=write
"$panel" --selftest --only codex,grok >"$tmp/s2.txt" 2>&1; rc=$?
check "會寫檔的審查者：結束碼非 0" '[ "$rc" -ne 0 ]'
check "點名 grok 寫得了檔" 'grep -q "^grok	不合格：寫得了檔" "$tmp/s2.txt"'
unset FAKE_MODE_grok

echo "10. --list 與用法錯誤"
use_fakes; export TEAMAI_GROK_BIN="$tmp/none"
"$panel" --list >"$tmp/l.txt" 2>&1
check "--list 標出沒裝的" 'grep -q "^grok	xAI	(沒裝)" "$tmp/l.txt" && grep -q "^codex	OpenAI	$tmp/bin/codex" "$tmp/l.txt"'
"$panel" --bogus >/dev/null 2>&1; rc=$?
check "不認得的參數：結束碼 64" '[ "$rc" -eq 64 ]'

echo
echo "review-panel 測試：通過 $pass，失敗 $failn"
[ "$failn" -eq 0 ]
