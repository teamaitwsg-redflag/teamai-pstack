#!/bin/bash
# 測 sync-rules.sh：用假的家目錄，不碰真的設定。
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
sync="$root/plugins/teamai/skills/sync-agents/scripts/sync-rules.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; failn=0
check() { if eval "$2"; then pass=$((pass + 1)); echo "  通過：$1"; else failn=$((failn + 1)); echo "  失敗：$1"; fi; }
export HOME="$tmp/home"; mkdir -p "$HOME/.grok" "$HOME/.codex"
mkdir -p "$tmp/home2/.gemini/config"; printf '# agy 原本的規則\n' >"$tmp/home2/.gemini/config/AGENTS.md"
printf '# 我自己的規則\n\n不要動這一行。\n' >"$HOME/.codex/AGENTS.md"

"$sync" --check >"$tmp/c1.txt" 2>&1; rc=$?
check "還沒寫入時 --check 回傳 1，而且沒有建立檔案" '[ "$rc" -eq 1 ] && [ ! -e "$HOME/.grok/AGENTS.md" ]'
"$sync" >"$tmp/w1.txt" 2>&1; rc=$?
check "寫入成功" '[ "$rc" -eq 0 ] && grep -q "球員不兼裁判" "$HOME/.grok/AGENTS.md" && grep -q "球員不兼裁判" "$HOME/.codex/AGENTS.md"'
check "沒裝的工具略過，不建立它的資料夾" 'grep -q "^google	沒裝" "$tmp/w1.txt" && [ ! -e "$HOME/.gemini" ]'
check "使用者原本的內容還在，而且在前面" '[ "$(head -1 "$HOME/.codex/AGENTS.md")" = "# 我自己的規則" ] && grep -q "不要動這一行" "$HOME/.codex/AGENTS.md"'
cp "$HOME/.codex/AGENTS.md" "$tmp/after1"
"$sync" >"$tmp/w2.txt" 2>&1
check "重複執行結果相同" 'cmp -s "$tmp/after1" "$HOME/.codex/AGENTS.md" && grep -q "^codex	已是最新" "$tmp/w2.txt"'
check "區塊只有一份" '[ "$(grep -c "teamai-rules:start" "$HOME/.codex/AGENTS.md")" -eq 1 ]'
"$sync" --check >/dev/null 2>&1; rc=$?
check "寫入後 --check 回傳 0" '[ "$rc" -eq 0 ]'
sed -i.bak 's/球員不兼裁判/被改掉了/' "$HOME/.grok/AGENTS.md"
"$sync" --check >/dev/null 2>&1; rc=$?
check "區塊被改過：--check 回傳 1" '[ "$rc" -eq 1 ]'
"$sync" >/dev/null 2>&1
check "再寫一次會修回來" 'grep -q "球員不兼裁判" "$HOME/.grok/AGENTS.md" && ! grep -q "被改掉了" "$HOME/.grok/AGENTS.md"'
"$sync" --remove >"$tmp/r.txt" 2>&1
check "--remove 拿掉區塊，使用者的內容留著" '! grep -q "teamai-rules" "$HOME/.codex/AGENTS.md" && grep -q "不要動這一行" "$HOME/.codex/AGENTS.md"'
"$sync" --bogus >/dev/null 2>&1; rc=$?
check "不認得的參數：結束碼 64" '[ "$rc" -eq 64 ]'
( export HOME="$tmp/home2"
  # 模擬舊版留下的狀態：agy 的 config/AGENTS.md 裡有使用者自己的內容，加上舊版寫進去的區塊
  "$sync" >/dev/null 2>&1
  { cat "$HOME/.gemini/config/AGENTS.md"; sed -n '/teamai-rules:start/,/teamai-rules:end/p' "$HOME/.gemini/GEMINI.md"; } >"$tmp/old-agents"
  cp "$tmp/old-agents" "$HOME/.gemini/config/AGENTS.md"
  "$sync" --check >"$tmp/a0.txt" 2>&1; echo $? >"$tmp/a0.rc"
  "$sync" >"$tmp/a1.txt" 2>&1
  "$sync" --check >/dev/null 2>&1; echo $? >"$tmp/a1.rc" )
check "Google 的規則只寫進 GEMINI.md" 'grep -q "^google	" "$tmp/a1.txt" && grep -q "球員不兼裁判" "$tmp/home2/.gemini/GEMINI.md"'
check "舊位置還有區塊時 --check 回傳 1" '[ "$(cat "$tmp/a0.rc")" -eq 1 ] && grep -q "^舊位置	需要清除" "$tmp/a0.txt"'
check "舊位置的區塊被清掉，使用者自己的內容留著" 'grep -q "^舊位置	已清除" "$tmp/a1.txt" && ! grep -q "teamai-rules" "$tmp/home2/.gemini/config/AGENTS.md" && grep -q "agy 原本的規則" "$tmp/home2/.gemini/config/AGENTS.md"'
check "清完之後 --check 回傳 0" '[ "$(cat "$tmp/a1.rc")" -eq 0 ]'
echo; echo "sync-rules 測試：通過 ${pass}，失敗 ${failn}"
[ "$failn" -eq 0 ]
