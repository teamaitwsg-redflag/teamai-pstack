#!/bin/bash
# teamAI 工具包安裝（macOS、Linux、Windows 的 Git Bash、雲端 session）。
# 安裝 pstack 與 teamai 兩個 plugin。可以重複執行。
# 用法：bash install.sh            從 GitHub 安裝
#       bash install.sh --local    用這個資料夾的內容安裝（開發這個工具包時用）
set -u
REPO="teamaitwsg-redflag/teamai-pstack"
here="$(cd "$(dirname "$0")" && pwd)"

if ! command -v claude >/dev/null 2>&1; then
  echo "找不到 claude 指令。請先安裝 Claude Code 再重跑。" >&2
  exit 1
fi

src="$REPO"
[ "${1:-}" = "--local" ] && src="$here"

fail=0
claude plugin marketplace add michael-denyer/pstack-claude || fail=1
claude plugin install pstack@pstack-claude || fail=1
claude plugin marketplace add "$src" || fail=1
claude plugin install teamai@teamai-pstack || fail=1

if [ "$fail" -ne 0 ]; then
  echo "有步驟失敗，請看上面的訊息。已安裝的部分不受影響，修正後可以重跑。" >&2
  exit 1
fi
echo "完成。重新開一個 Claude Code session 生效，然後輸入 /teamai:flow 開始。"
