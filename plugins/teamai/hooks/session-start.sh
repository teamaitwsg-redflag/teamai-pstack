#!/bin/bash
# 每個 session 開始時，把 teamAI 共用規則與 pstack 模型分工表放進對話。
# SessionStart hook 的 stdout 會成為 Claude 的背景資訊，所以這裡只輸出這兩個檔案的內容。
# 要關掉：在 ~/.claude/teamai-off 放一個空檔。
set -u
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[ -e "$cfg/teamai-off" ] && exit 0

cat "$root/rules/teamai-rules.md" 2>/dev/null || exit 0

# 模型分工表：使用者自己放在 ~/.claude 的版本優先，沒有才用 plugin 內附的
sheet="$cfg/pstack-models.md"
[ -f "$sheet" ] || sheet="$root/rules/pstack-models.md"
if [ -f "$sheet" ]; then
  printf '\n\n'
  cat "$sheet"
fi
exit 0
