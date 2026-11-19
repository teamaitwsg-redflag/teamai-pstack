#!/bin/bash
# 測 session-start hook：會輸出規則與模型分工表；放了 teamai-off 就不輸出。
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/plugins/teamai/hooks/session-start.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

out="$(CLAUDE_CONFIG_DIR="$tmp" CLAUDE_PLUGIN_ROOT="$root/plugins/teamai" bash "$hook" </dev/null)"
echo "$out" | grep -q "teamAI 共用工作規則" || { echo "失敗：沒有輸出規則"; exit 1; }
echo "$out" | grep -q "interrogate reviewers" || { echo "失敗：沒有輸出內附的模型分工表"; exit 1; }

echo "strongest judgment: custom-model" > "$tmp/pstack-models.md"
out="$(CLAUDE_CONFIG_DIR="$tmp" CLAUDE_PLUGIN_ROOT="$root/plugins/teamai" bash "$hook" </dev/null)"
echo "$out" | grep -q "custom-model" || { echo "失敗：使用者自己的模型分工表沒有優先"; exit 1; }
echo "$out" | grep -q "interrogate reviewers" && { echo "失敗：內附的分工表不該同時出現"; exit 1; }

touch "$tmp/teamai-off"
out="$(CLAUDE_CONFIG_DIR="$tmp" CLAUDE_PLUGIN_ROOT="$root/plugins/teamai" bash "$hook" </dev/null)"
[ -z "$out" ] || { echo "失敗：放了 teamai-off 還是有輸出"; exit 1; }
echo "hook 測試通過（3 項）"
