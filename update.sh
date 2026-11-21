#!/bin/bash
# 更新 pstack 與 teamai 兩個 plugin 到最新版。
# 任何一步失敗就停在那一步，以那一步的結束碼結束，不印成功訊息。
set -u

if ! command -v claude >/dev/null 2>&1; then
  echo "找不到 claude 指令。請先安裝 Claude Code 再重跑。" >&2
  exit 1
fi

claude plugin marketplace update pstack-claude || exit $?
claude plugin update pstack@pstack-claude || exit $?
claude plugin marketplace update teamai-pstack || exit $?
claude plugin update teamai@teamai-pstack || exit $?
echo "更新完成。重新開 session 生效。"
