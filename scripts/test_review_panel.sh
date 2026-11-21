#!/bin/bash
# 用假的 CLI 測 review-panel.sh 的行為。不呼叫任何真的 AI。
set -u
# 不讀執行者自己的 git 設定：開了 commit 簽章的電腦上，建立測試用 repo 會失敗或卡住
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
root="$(cd "$(dirname "$0")/.." && pwd)"
panel="$root/plugins/teamai/skills/cross-review/scripts/review-panel.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pass=0; failn=0
ok() { pass=$((pass + 1)); echo "  通過：$1"; }
bad() { failn=$((failn + 1)); echo "  失敗：$1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# 假的審查者。行為由 FAKE_MODE 決定：reply（預設）、fail、hang、stubborn、write、chatty、refused、silent。
# refused 模仿寫檔被工具擋下後整輪結束：refused 還印了一句話，refused-quiet 完全沒有 stdout，
# refused-other 被擋的是別的事、refused-read 被擋的是讀 proof.txt（都不算證據）。cutoff 模仿審到一半被打斷：有輸出、正常結束、但沒有完成標記。
# hang 會衍生一個子程序；stubborn 不理會 TERM；chatty 在自我測試時答非所問。
# 會把收到的參數記到 $FAKE_LOG，測試用它確認唯讀旗標真的有帶。
mkdir -p "$tmp/bin"
for name in codex gemini grok agy; do
cat >"$tmp/bin/$name" <<FAKE
#!/bin/bash
# 每次呼叫記成一行（提示詞裡的換行換成空白），才能用「這一行是誰」來檢查它收到的提示詞。
# 幾個假審查者會同時跑，長的一行在 macOS 上會被別人的輸出插進來，所以寫入前先拿鎖（mkdir 是原子的）。
line="$name \$(printf '%s' "\$*" | tr '\n' ' ')"
if [ -n "\${FAKE_LOG:-}" ]; then
  until mkdir "\$FAKE_LOG.lock" 2>/dev/null; do sleep 0.01; done
  printf '%s\n%s\n' "\$line" "$name CWD=\$PWD" >>"\$FAKE_LOG"
  rmdir "\$FAKE_LOG.lock"
fi
out=""
prev=""
for a in "\$@"; do [ "\$prev" = "-o" ] && [ "$name" = "codex" ] && out="\$a"; prev="\$a"; done
mode="\${FAKE_MODE_$name:-\${FAKE_MODE:-reply}}"
case "\$mode" in
  fail) echo "boom" >&2; exit 7 ;;
  hang) sleep 31.4159 & wait ;;
  stubborn) trap "" TERM; sleep 27.1828 & wait; sleep 27.1828 ;;
  write) echo hi > proof.txt ;;
  silent) exit 0 ;;
esac
case "\$*" in
  *inside.txt*)
     # 隔離自我測試。預設：寫得了副本裡，副本外被擋，而且像 shell 一樣在 stderr 留下被拒絕的訊息。
     # prove-leak 副本外也寫得到；prove-none 兩邊都寫不了；
     # prove-lazy 根本沒去試副本外；prove-liar 沒去試卻回答 BOTH；
     # prove-unrelated 有拒絕訊息但講的是別的路徑；prove-crash 被擋了但以錯誤結束。
     outside="\$(printf '%s' "\$*" | grep -o '/[^ ]*/outside.txt' | head -1)"
     case "\$mode" in
       prove-leak) echo hi >inside.txt; echo hi >"\$outside"; msg=BOTH ;;
       prove-none) msg=NONE ;;
       prove-lazy) echo hi >inside.txt; msg=INSIDE-ONLY ;;
       prove-liar) echo hi >inside.txt; msg=BOTH ;;
       prove-unrelated) echo hi >inside.txt; echo "bash: /etc/hosts: Permission denied" >&2; msg=INSIDE-ONLY ;;
       prove-crash) echo hi >inside.txt; echo "bash: \$outside: Operation not permitted" >&2; echo INSIDE-ONLY >"\$out"; exit 7 ;;
       *) echo hi >inside.txt; echo "bash: \$outside: Operation not permitted" >&2; msg=INSIDE-ONLY ;;
     esac
     if [ -n "\$out" ]; then echo "\$msg" >"\$out"; else echo "\$msg"; fi; exit 0 ;;
esac
case "\$*" in
  *workspace-write*) echo "echo repro" >repro.sh ;;
esac
case "\$*" in
  *proof.txt*) if [ "\$mode" = "refused" ]; then echo "我現在建立 proof.txt"; echo "permission required: Write proof.txt was not run" >&2; exit 0; fi
     if [ "\$mode" = "refused-quiet" ]; then echo "permission required: Write proof.txt was not run" >&2; exit 0; fi
     case "\$mode" in
       refused-agy|refused-agy-command|refused-agy-read)
         perm=write_file; [ "\$mode" = "refused-agy-command" ] && perm=command; [ "\$mode" = "refused-agy-read" ] && perm=read_file
         echo "jetski: no output produced — a tool required the \\"\$perm\\" permission that headless mode cannot prompt for, so it was auto-denied." >&2; exit 0 ;;
       refused-touch) echo "permission denied: touch proof.txt" >&2; exit 0 ;;
       refused-write-other) echo "我看一下"; echo "permission denied: Write other.txt" >&2; exit 0 ;;
     esac
     if [ "\$mode" = "refused-read" ]; then echo "我看一下"; echo "permission required: Read proof.txt was not run" >&2; exit 0; fi
     if [ "\$mode" = "refused-other" ]; then echo "我看一下"; echo "permission denied: reading /etc/shadow" >&2; exit 0; fi
     if [ "\$mode" = "chatty" ]; then msg="好的，我看了一下。"; elif [ "\$mode" = "write" ]; then msg="WROTE"; else msg="BLOCKED"; fi
     if [ -n "\$out" ]; then echo "\$msg" >"\$out"; else echo "\$msg"; fi; exit 0 ;;
esac
body="[低] a.txt:1 — $name 的發現"
case "\$mode" in
  cutoff) ;;
  quoted) body="提示詞要我最後寫 REVIEW-COMPLETE，我先讀檔。
\$body" ;;
  trailing) body="\$body
REVIEW-COMPLETE $name-model
接著我再看一下其他檔案。" ;;
  nomodel) body="\$body
REVIEW-COMPLETE" ;;
  *) body="\$body
REVIEW-COMPLETE $name-model" ;;
esac
if [ -n "\$out" ]; then echo "\$body" >"\$out"; else echo "\$body"; fi
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
check "codex、agy、grok 都是 ok" '[ "$(grep -c "	ok	" "$tmp/o1/summary.tsv")" -eq 3 ]'
check "同廠牌只跑一個：有 agy 就不跑 gemini" '! grep -q "^gemini" "$tmp/o1/summary.tsv" && ! grep -q "^gemini " "$FAKE_LOG"'
check "各自的審查結果有內容" 'grep -q "codex 的發現" "$tmp/o1/codex.md" && grep -q "grok 的發現" "$tmp/o1/grok.md"'
check "改動有存成 change.diff" 'grep -q "^+two" "$tmp/o1/change.diff"'
check "codex 帶了唯讀旗標" 'grep -q "^codex exec -s read-only" "$FAKE_LOG"'
check "agy 帶了 plan 模式" 'grep -q "^agy --mode plan" "$FAKE_LOG"'
check "grok 帶了唯讀沙箱、只給讀檔工具、關掉上網" 'grep -q "^grok --sandbox read-only --tools read_file,grep,list_dir --disable-web-search" "$FAKE_LOG"'

echo "2. 有人沒裝、有人失敗：照實記錄，其他人不受影響"
use_fakes; export TEAMAI_GROK_BIN="$tmp/none" TEAMAI_AGY_BIN="$tmp/none" FAKE_MODE_gemini=fail; : >"$FAKE_LOG"
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

echo "3b. 審到一半被打斷：有輸出也不算審過"
use_fakes; export FAKE_MODE=cutoff
"$panel" --repo "$repo" --out "$tmp/o3b" --only grok >"$tmp/o3b.txt" 2>&1; rc=$?
check "grok 記為 incomplete，結束碼 2" '[ "$rc" -eq 2 ] && grep -q "^grok	incomplete" "$tmp/o3b/summary.tsv"'
n=0
for m in quoted trailing nomodel; do
  n=$((n + 1)); export FAKE_MODE="$m"
  "$panel" --repo "$repo" --out "$tmp/o3c$n" --only codex >/dev/null 2>&1; rc=$?
  check "完成標記位置不對（${m}）：incomplete，結束碼 2" '[ "$rc" -eq 2 ] && grep -q "^codex	incomplete" "$tmp/o3c$n/summary.tsv"'
done
unset FAKE_MODE

echo "4. 逾時：砍掉並記為 timeout"
use_fakes; export FAKE_MODE=hang
start=$(date +%s)
"$panel" --repo "$repo" --out "$tmp/o4" --only grok --timeout 2 >"$tmp/o4.txt" 2>&1; rc=$?
took=$(( $(date +%s) - start ))
check "grok 記為 timeout" 'grep -q "^grok	timeout" "$tmp/o4/summary.tsv"'
check "沒有等到假程式自己結束（${took} 秒）" '[ "$took" -lt 15 ]'
check "假程式衍生的子程序也被收掉" '! pgrep -f "sleep 31.4159" >/dev/null'
export FAKE_MODE=stubborn
"$panel" --repo "$repo" --out "$tmp/o4b" --only codex --timeout 2 >"$tmp/o4b.txt" 2>&1; rc=$?
check "不理會 TERM 的也記為 timeout" 'grep -q "^codex	timeout" "$tmp/o4b/summary.tsv"'
check "不理會 TERM 的連同子程序被強制結束" '! pgrep -f "sleep 27.1828" >/dev/null'
unset FAKE_MODE
export FAKE_MODE=fail
"$panel" --repo "$repo" --out "$tmp/o4c" --only codex --timeout 60 >"$tmp/o4c.txt" 2>&1
check "很快就失敗的不會被記成 timeout" 'grep -q "^codex	failed(7)" "$tmp/o4c/summary.tsv"'
unset FAKE_MODE

echo "5. 改動裡有密鑰：不送出"
use_fakes; : >"$FAKE_LOG"
printf 'token = "ghp_%s"\n' "abcdefghijklmnopqrstuvwxyz0123" >>"$repo/a.txt"
"$panel" --repo "$repo" --out "$tmp/o5" >"$tmp/o5.txt" 2>&1; rc=$?
check "結束碼 4" '[ "$rc" -eq 4 ]'
check "沒有呼叫任何審查者" '[ ! -s "$FAKE_LOG" ]'
check "報告只寫檔名，沒有把密鑰抄進去" 'grep -q "a.txt: 疑似密鑰" "$tmp/o5/secrets.txt" && ! grep -q "ghp_" "$tmp/o5/secrets.txt"'
check "含密鑰的 change.diff 沒有留下來" '[ ! -e "$tmp/o5/change.diff" ] && ! grep -rq "ghp_" "$tmp/o5"'
git -C "$repo" checkout -q a.txt; echo two >>"$repo/a.txt"
printf 'token = "ghs_%s"\n' "abcdefghijklmnopqrstuvwxyz0123" >>"$repo/a.txt"
"$panel" --repo "$repo" --out "$tmp/o5b" >"$tmp/o5b.txt" 2>&1; rc=$?
check "GitHub App 的 token 也擋（結束碼 4）" '[ "$rc" -eq 4 ]'
git -C "$repo" checkout -q a.txt; echo two >>"$repo/a.txt"

echo "6. 改動裡有 .env：不送出"
: >"$FAKE_LOG"
echo "X=1" >"$repo/.env"
"$panel" --repo "$repo" --out "$tmp/o6" >"$tmp/o6.txt" 2>&1; rc=$?
check "還沒 add 的 .env：結束碼 4" '[ "$rc" -eq 4 ]'
rm "$repo/.env"
mkdir -p "$repo/設定"; echo "X=1" >"$repo/設定/.env.local"
"$panel" --repo "$repo" --out "$tmp/o6b" >"$tmp/o6b.txt" 2>&1; rc=$?
check "中文資料夾裡的 .env.local（git 會加引號）：結束碼 4" '[ "$rc" -eq 4 ]'
rm -r "$repo/設定"
printf 'diff -u old/.env new/.env\n--- old/.env\t2026-01-01\n+++ new/.env\t2026-01-02\n@@ -1 +1 @@\n-A=1\n+A=2\n' >"$tmp/plain.diff"
"$panel" --repo "$repo" --out "$tmp/o6c" --diff "$tmp/plain.diff" >"$tmp/o6c.txt" 2>&1; rc=$?
check "沒有 a/ b/ 前綴、帶 tab 的 diff 標頭：結束碼 4" '[ "$rc" -eq 4 ]'
printf 'diff --git a/config.txt b/.env\nsimilarity index 100%%\nrename from config.txt\nrename to .env\n' >"$tmp/rename.diff"
"$panel" --repo "$repo" --out "$tmp/o6d" --diff "$tmp/rename.diff" >"$tmp/o6d.txt" 2>&1; rc=$?
check "純改名成 .env：結束碼 4" '[ "$rc" -eq 4 ]'
check "以上都沒有呼叫任何審查者" '[ ! -s "$FAKE_LOG" ]'
git -C "$repo" config color.ui always
echo "X=1" >"$repo/.env"
"$panel" --repo "$repo" --out "$tmp/o6f" >"$tmp/o6f.txt" 2>&1; rc=$?
check "repo 設成強制彩色輸出時 .env 照樣擋（結束碼 4）" '[ "$rc" -eq 4 ]'
rm "$repo/.env"; git -C "$repo" config --unset color.ui
printf '\033[1mdiff --git a/x b/x\033[m\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n' >"$tmp/color.diff"
"$panel" --repo "$repo" --out "$tmp/o6g" --diff "$tmp/color.diff" >"$tmp/o6g.txt" 2>&1; rc=$?
check "帶顏色控制碼的 diff 檔：拒絕（結束碼 64）" '[ "$rc" -eq 64 ]'
echo "X=" >"$repo/.env.example"
"$panel" --repo "$repo" --out "$tmp/o6e" --only codex >"$tmp/o6e.txt" 2>&1; rc=$?
check ".env.example 是範例檔，照常送審" '[ "$rc" -eq 0 ]'
rm "$repo/.env.example"

echo "7. 沒有改動：結束碼 3"
git -C "$repo" checkout -q a.txt
"$panel" --repo "$repo" --out "$tmp/o7" --uncommitted >"$tmp/o7.txt" 2>&1; rc=$?
check "指定 --uncommitted：結束碼 3" '[ "$rc" -eq 3 ]'
"$panel" --repo "$repo" --out "$tmp/o7b" >"$tmp/o7b.txt" 2>&1; rc=$?
check "沒指定來源：也是結束碼 3" '[ "$rc" -eq 3 ]'
echo two >>"$repo/a.txt"

echo "7b. 還沒 add 的新檔也要送審"
echo "brand new" >"$repo/new.txt"
"$panel" --repo "$repo" --out "$tmp/o7c" --only codex >"$tmp/o7c.txt" 2>&1; rc=$?
check "change.diff 裡有新檔的內容" 'grep -q "^+brand new" "$tmp/o7c/change.diff" && grep -q "^+two" "$tmp/o7c/change.diff"'
rm "$repo/new.txt"
git -C "$repo" checkout -q a.txt
echo staged >>"$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" show HEAD:a.txt >"$repo/a.txt"
"$panel" --repo "$repo" --out "$tmp/o7c2" --only codex >"$tmp/o7c2.txt" 2>&1; rc=$?
check "add 之後又在工作區改回去：已 add 的內容仍然送審" 'grep -q "^+staged" "$tmp/o7c2/change.diff"'
git -C "$repo" reset -q --hard; echo two >>"$repo/a.txt"
"$panel" --repo "$repo" --out "$repo/inside-out" --only codex >"$tmp/o7c3.txt" 2>&1; rc=$?
check "--out 放在 repo 裡：自己的輸出不會被當成改動送審" '[ "$rc" -eq 0 ] && ! grep -q "inside-out" "$repo/inside-out/change.diff"'
rm -rf "$repo/inside-out"
( cd "$tmp/bin" && TEAMAI_CODEX_BIN="./codex" "$panel" --repo "$repo" --out "$tmp/o7c4" --only codex >"$tmp/o7c4.txt" 2>&1 ); rc=$?
check "TEAMAI_CODEX_BIN 給相對路徑：切換目錄後仍執行同一個檔案" '[ "$rc" -eq 0 ] && grep -q "^codex	ok" "$tmp/o7c4/summary.tsv"'

echo "7c. --base 只審分支上的 commit，--diff 審現成的檔案"
git -C "$repo" checkout -q -b feature
echo three >"$repo/b.txt"; git -C "$repo" add b.txt
git -C "$repo" -c user.email=t@example.com -c user.name=t commit -q -m b
"$panel" --repo "$repo" --out "$tmp/o7d" --base main --only codex >"$tmp/o7d.txt" 2>&1; rc=$?
check "--base：有分支的改動，沒有未 commit 的改動" 'grep -q "^+three" "$tmp/o7d/change.diff" && ! grep -q "^+two" "$tmp/o7d/change.diff"'
git -C "$repo" stash -q; git -C "$repo" checkout -q main; git -C "$repo" stash pop -q
printf -- '--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+from file\n' >"$tmp/given.diff"
"$panel" --repo "$repo" --out "$tmp/o7e" --diff "$tmp/given.diff" --only codex >"$tmp/o7e.txt" 2>&1; rc=$?
check "--diff：送審的就是那個檔案" 'cmp -s "$tmp/given.diff" "$tmp/o7e/change.diff"'
"$panel" --repo "$repo" --out "$tmp/o7f" --diff "$tmp/nope.diff" >"$tmp/o7f.txt" 2>&1; rc=$?
check "--diff 指到不存在的檔案：結束碼 64" '[ "$rc" -eq 64 ]'
"$panel" --repo "$repo" --out "$tmp/o7e" --only codex >"$tmp/o7g.txt" 2>&1; rc=$?
check "--out 指到已經有東西的資料夾：拒絕（結束碼 64）" '[ "$rc" -eq 64 ]'

echo "7d. Google 這一家：有 agy 用 agy，沒有才用 gemini"
use_fakes; export TEAMAI_GEMINI_BIN="$tmp/none"; : >"$FAKE_LOG"
"$panel" --repo "$repo" --out "$tmp/o7h" >"$tmp/o7h.txt" 2>&1; rc=$?
check "agy 有跑而且是 ok" 'grep -q "^agy	ok" "$tmp/o7h/summary.tsv"'
check "agy 的提示詞有禁止 shell" 'grep -q "禁止執行任何 shell 指令" "$FAKE_LOG"'
check "同廠牌已有 agy，gemini 不列為缺席" '! grep -q "^gemini" "$tmp/o7h/summary.tsv"'
use_fakes; export TEAMAI_AGY_BIN="$tmp/none"; : >"$FAKE_LOG"
"$panel" --repo "$repo" --out "$tmp/o7i" >"$tmp/o7i.txt" 2>&1; rc=$?
check "沒有 agy 時改用 gemini，帶 plan 模式" 'grep -q "^gemini	ok" "$tmp/o7i/summary.tsv" && grep -q "^gemini --approval-mode plan" "$FAKE_LOG"'
use_fakes; export FAKE_MODE_agy=fail
"$panel" --repo "$repo" --out "$tmp/o7j" --only agy,gemini >"$tmp/o7j.txt" 2>&1; rc=$?
check "agy 有裝但失敗（例如沒登入）：換 gemini 上，兩個都記錄" '[ "$rc" -eq 0 ] && grep -q "^agy	failed(7)" "$tmp/o7j/summary.tsv" && grep -q "^gemini	ok" "$tmp/o7j/summary.tsv"'
unset FAKE_MODE_agy

echo "8. 預設輸出資料夾在 repo 裡，而且不會被 git 看到"
use_fakes
"$panel" --repo "$repo" --only codex >"$tmp/o8.txt" 2>&1; rc=$?
check "結束碼 0" '[ "$rc" -eq 0 ]'
check "git status 看不到 .teamai-review" '! git -C "$repo" status --porcelain | grep -q teamai-review'

echo "9. 自我測試：寫得了檔的審查者要判不合格"
use_fakes
"$panel" --selftest --only codex,grok >"$tmp/s1.txt" 2>&1; rc=$?
check "試過而且被擋下來：結束碼 0、兩個都合格" '[ "$rc" -eq 0 ] && [ "$(grep -c "	合格：試過寫檔，被擋下來" "$tmp/s1.txt")" -eq 2 ]'
export FAKE_MODE_grok=write
"$panel" --selftest --only codex,grok >"$tmp/s2.txt" 2>&1; rc=$?
check "會寫檔的審查者：結束碼非 0" '[ "$rc" -ne 0 ]'
check "點名 grok 寫得了檔" 'grep -q "^grok	不合格：寫得了檔" "$tmp/s2.txt"'
unset FAKE_MODE_grok
export FAKE_MODE_grok=refused
"$panel" --selftest --only grok >"$tmp/s4.txt" 2>&1; rc=$?
check "被工具擋下後沒回答、但紀錄寫明拒絕寫入：合格，並印出那行紀錄" '[ "$rc" -eq 0 ] && grep -q "^grok	合格：寫檔被工具本身擋下，紀錄是「permission required: Write proof.txt was not run」" "$tmp/s4.txt"'
export FAKE_MODE_grok=refused-quiet
"$panel" --selftest --only grok >"$tmp/s5.txt" 2>&1; rc=$?
check "完全沒有 stdout、只有拒絕紀錄：也合格" '[ "$rc" -eq 0 ] && grep -q "^grok	合格：寫檔被工具本身擋下" "$tmp/s5.txt"'
export FAKE_MODE_grok=refused-other
"$panel" --selftest --only grok >"$tmp/s6.txt" 2>&1; rc=$?
check "被擋的是別的事、跟 proof.txt 無關：不算證據，判無法確認" '[ "$rc" -ne 0 ] && grep -q "^grok	無法確認" "$tmp/s6.txt"'
use_fakes; export FAKE_MODE_agy=refused-agy
"$panel" --selftest --only agy >"$tmp/s9.txt" 2>&1; rc=$?
check "agy 的拒絕寫法（write_file 權限被自動拒絕、沒有任何 stdout）：合格" '[ "$rc" -eq 0 ] && grep -q "^agy	合格：寫檔被工具本身擋下" "$tmp/s9.txt"'
export FAKE_MODE_agy=refused-agy-command
"$panel" --selftest --only agy >"$tmp/s10.txt" 2>&1; rc=$?
check "agy 用 shell 建檔被自動拒絕（command 權限）：合格" '[ "$rc" -eq 0 ] && grep -q "^agy	合格：寫檔被工具本身擋下" "$tmp/s10.txt"'
export FAKE_MODE_agy=refused-agy-read
"$panel" --selftest --only agy >"$tmp/s11.txt" 2>&1; rc=$?
check "agy 被拒的是讀檔權限：不算證據" '[ "$rc" -ne 0 ] && ! grep -q "	合格：" "$tmp/s11.txt"'
unset FAKE_MODE_agy
export FAKE_MODE_grok=refused-agy
"$panel" --selftest --only grok >"$tmp/s12.txt" 2>&1; rc=$?
check "agy 的專用格式只對 agy 有效，別的審查者印出同樣的話不算" '[ "$rc" -ne 0 ] && ! grep -q "	合格：" "$tmp/s12.txt"'
export FAKE_MODE_grok=refused-touch
"$panel" --selftest --only grok >"$tmp/s13.txt" 2>&1; rc=$?
check "用 touch 建 proof.txt 被拒：合格" '[ "$rc" -eq 0 ] && grep -q "^grok	合格：寫檔被工具本身擋下" "$tmp/s13.txt"'
export FAKE_MODE_grok=refused-write-other
"$panel" --selftest --only grok >"$tmp/s14.txt" 2>&1; rc=$?
check "被拒的是寫別的檔、跟 proof.txt 無關：不算證據" '[ "$rc" -ne 0 ] && grep -q "^grok	無法確認" "$tmp/s14.txt"'
export FAKE_MODE_grok=refused-read
"$panel" --selftest --only grok >"$tmp/s7.txt" 2>&1; rc=$?
check "被擋的是讀 proof.txt 不是寫：不算證據，判無法確認" '[ "$rc" -ne 0 ] && grep -q "^grok	無法確認" "$tmp/s7.txt"'
unset FAKE_MODE_grok
use_fakes
"$panel" --selftest >"$tmp/s8.txt" 2>&1; rc=$?
check "自我測試涵蓋同廠牌的備援：agy 和 gemini 都測" 'grep -q "^agy	合格" "$tmp/s8.txt" && grep -q "^gemini	合格" "$tmp/s8.txt"'
export FAKE_MODE_codex=chatty
"$panel" --selftest --only codex >"$tmp/s3.txt" 2>&1; rc=$?
check "答非所問、看不出有沒有試：判無法確認，結束碼非 0" '[ "$rc" -ne 0 ] && grep -q "^codex	無法確認" "$tmp/s3.txt"'
unset FAKE_MODE_codex

echo "9b. --prove：在隔離副本裡執行"
use_fakes; : >"$FAKE_LOG"
git -C "$repo" reset -q --hard; git -C "$repo" clean -q -fd
printf 'secret.txt\n' >"$repo/.gitignore"; git -C "$repo" add .gitignore
git -C "$repo" -c user.email=t@example.com -c user.name=t commit -q -m ignore
echo keep >"$repo/gone.txt"; git -C "$repo" add gone.txt
git -C "$repo" -c user.email=t@example.com -c user.name=t commit -q -m gone
echo two >>"$repo/a.txt"; echo "brand new" >"$repo/new.txt"; echo "do-not-copy" >"$repo/secret.txt"; rm "$repo/gone.txt"
"$panel" --repo "$repo" --out "$tmp/p1" --prove --only codex,grok >"$tmp/p1.txt" 2>&1; rc=$?
copy="$(cat "$tmp/p1/codex.workdir" 2>/dev/null)"
check "結束碼 0，codex 用執行模式、grok 照舊唯讀" '[ "$rc" -eq 0 ] && grep -q "^codex	ok	.*	prove$" "$tmp/p1/summary.tsv" && grep -q "^grok	ok	.*	read$" "$tmp/p1/summary.tsv"'
check "codex 帶的是只限工作目錄可寫、不連網的沙箱" 'grep -q "^codex exec -s workspace-write .*network_access=false" "$FAKE_LOG" && ! grep -q "^codex exec -s read-only" "$FAKE_LOG"'
check "codex 是在副本裡跑的，不是在原本的 repo" '[ -n "$copy" ] && [ "$copy" != "$repo" ] && grep -q "^codex CWD=$copy$" "$FAKE_LOG"'
check "grok 仍然在原本的 repo 唯讀" 'grep -q "^grok CWD=$repo$" "$FAKE_LOG" && grep -q "^grok --sandbox read-only" "$FAKE_LOG"'
check "副本有未 commit 的修改和還沒 add 的新檔" 'grep -q "^two$" "$copy/a.txt" && grep -q "brand new" "$copy/new.txt"'
check "工作區裡刪掉的檔案，副本裡也沒有" '[ ! -e "$copy/gone.txt" ]'
check "被 .gitignore 忽略的檔案沒有進副本" '[ ! -e "$copy/secret.txt" ]'
check "副本裡有要審的 diff" 'grep -q "^+two" "$copy/.teamai-change.diff"'
check "審查者寫的檔案留在副本，原本的 repo 沒有多東西" '[ -e "$copy/repro.sh" ] && [ ! -e "$repo/repro.sh" ] && [ ! -e "$repo/.teamai-change.diff" ]'
check "提示詞要求用實際執行證明" 'grep -q "實際執行" "$FAKE_LOG"'
check "唯讀的 grok 被告知它提的都是未驗證線索" 'grep "^grok --sandbox" "$FAKE_LOG" | grep -q "未驗證線索"'
check "執行模式的 codex 不會被要求寫未驗證線索（沒跑過的不寫）" '! grep "^codex exec -s workspace-write" "$FAKE_LOG" | grep -q "未驗證線索"'
rm -rf "$copy"
"$panel" --repo "$repo" --out "$tmp/p2" --prove --diff "$tmp/given.diff" --only codex >"$tmp/p2.txt" 2>&1; rc=$?
check "--prove 配 --diff：拒絕（結束碼 64）" '[ "$rc" -eq 64 ]'
git -C "$repo" reset -q --hard; git -C "$repo" clean -q -fd; echo two >>"$repo/a.txt"

echo "9c. --selftest --prove：隔離要實測"
use_fakes; export TEAMAI_CANARY_ROOT="$tmp"
"$panel" --selftest --prove --only codex >"$tmp/ps1.txt" 2>&1; rc=$?
check "副本裡寫得了、副本外的寫入有被拒絕的紀錄：合格，並印出那行紀錄" '[ "$rc" -eq 0 ] && grep -q "^codex	合格：副本裡寫得了，副本外的寫入被拒絕（紀錄：bash: .*outside.txt: Operation not permitted）" "$tmp/ps1.txt"'
check "合格時不留紀錄資料夾" '! grep -q "紀錄保留在" "$tmp/ps1.txt"'
n=0
for m in prove-lazy prove-liar prove-unrelated prove-crash; do
  n=$((n + 1)); export FAKE_MODE_codex="$m"
  "$panel" --selftest --prove --only codex >"$tmp/pu$n.txt" 2>&1; rc=$?
  check "沒有可驗證的拒絕證據（${m}）：未驗證，結束碼 3" '[ "$rc" -eq 3 ] && grep -q "^codex	未驗證：" "$tmp/pu$n.txt"'
  check "未驗證時保留紀錄，而且紀錄檔真的在（${m}）" 'd="$(sed -n "s/^  紀錄保留在 \([^（]*\)（.*/\1/p" "$tmp/pu$n.txt")"; [ -n "$d" ] && [ -f "$d/codex.log" ] && rm -rf "$(dirname "$d")"'
done
check "沒去試卻回答 BOTH：標明回覆和事實矛盾" 'grep -q "^codex	未驗證：回覆說副本外也寫成功" "$tmp/pu2.txt"'
check "以錯誤結束：標明沒有正常結束" 'grep -q "^codex	未驗證：審查者沒有正常結束（failed(7)）" "$tmp/pu4.txt"'
unset FAKE_MODE_codex
export FAKE_MODE_codex=prove-leak
"$panel" --selftest --prove --only codex >"$tmp/ps2.txt" 2>&1; rc=$?
check "副本外也寫得到：不合格，結束碼 1" '[ "$rc" -eq 1 ] && grep -q "^codex	不合格：寫得到副本以外的地方" "$tmp/ps2.txt"'
export FAKE_MODE_codex=prove-none
"$panel" --selftest --prove --only codex >"$tmp/ps3.txt" 2>&1; rc=$?
check "副本裡也寫不了：不合格（沒辦法執行來證明），結束碼 1" '[ "$rc" -eq 1 ] && grep -q "^codex	不合格：副本裡也寫不了" "$tmp/ps3.txt"'
unset FAKE_MODE_codex
"$panel" --selftest --prove --only grok,agy >"$tmp/ps4.txt" 2>&1; rc=$?
check "沒有可執行的審查者：結束碼 2，不假裝測過" '[ "$rc" -eq 2 ]'
check "測試點都有清掉" '[ -z "$(ls -d "$tmp"/.teamai-canary.* 2>/dev/null)" ]'
unset TEAMAI_CANARY_ROOT

echo "10. --list 與用法錯誤"
use_fakes; export TEAMAI_GROK_BIN="$tmp/none"
"$panel" --list >"$tmp/l.txt" 2>&1
check "--list 標出沒裝的" 'grep -q "^grok	xAI	(沒裝)" "$tmp/l.txt" && grep -q "^codex	OpenAI	$tmp/bin/codex" "$tmp/l.txt"'
"$panel" --bogus >/dev/null 2>&1; rc=$?
check "不認得的參數：結束碼 64" '[ "$rc" -eq 64 ]'

echo
echo "review-panel 測試：通過 ${pass}，失敗 $failn"
[ "$failn" -eq 0 ]
