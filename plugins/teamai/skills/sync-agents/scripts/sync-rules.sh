#!/bin/bash
# 把 teamAI 共用規則寫進其他 AI 工具的全域規則檔，讓它們也照同一套規則做事。
#
#   sync-rules.sh            寫入（只處理這台電腦上有裝的工具）
#   sync-rules.sh --check    只檢查，不寫入；有任何一個不是最新就回傳 1
#   sync-rules.sh --remove   把寫進去的區塊拿掉，其他內容不動
#
# 目標檔案：
#   Grok CLI    ~/.grok/AGENTS.md
#   Codex       ~/.codex/AGENTS.md
#   Gemini CLI  ~/.gemini/GEMINI.md
# 只改兩個標記之間的區塊；檔案裡原本的內容不動。可以重複執行。
set -u

here="$(cd "$(dirname "$0")" && pwd)"
rules="$here/../../../rules/teamai-rules.md"
[ -f "$rules" ] || { echo "sync-rules: 找不到規則檔 ${rules}" >&2; exit 64; }

START="<!-- teamai-rules:start（由 teamai plugin 的 sync-rules.sh 寫入，請勿手改這個區塊） -->"
END="<!-- teamai-rules:end -->"

mode="write"
case "${1:-}" in
  "") ;;
  --check) mode="check" ;;
  --remove) mode="remove" ;;
  *) echo "sync-rules: 不認得的參數：$1" >&2; exit 64 ;;
esac

block() {
  printf '%s\n' "$START"
  cat <<'HEAD'
# 給這個 AI 工具的說明

你和 Claude Code 在同一個團隊裡工作，下面是團隊共用的規則，你也要遵守。

- 規則裡的 `/pstack:…` 與 `/teamai:…` 是 Claude Code 的指令。你的工具裡有同名的 skill 就用它；沒有的話，照那條規則的意思做。
- 你被請來審查別人的成果時：只讀不改。每個發現寫出檔案與行號、你的依據、建議。沒有發現就明說「未發現」，看不到或無法判斷就寫「無法確認」，不要猜。
- 你自己寫的成果，不由你自己驗收，也不由你自己合併。

HEAD
  cat "$rules"
  printf '%s\n' "$END"
}

# 把檔案裡兩個標記之間（含標記）的內容拿掉，印出剩下的
strip_block() {
  awk -v s="$START" -v e="$END" '
    $0 == s { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip { print }' "$1"
}

# 名稱<TAB>判斷有沒有裝的資料夾<TAB>規則檔
targets="grok	$HOME/.grok	$HOME/.grok/AGENTS.md
codex	$HOME/.codex	$HOME/.codex/AGENTS.md
gemini	$HOME/.gemini	$HOME/.gemini/GEMINI.md"

stale=0
tmp="$(mktemp)"; trap 'rm -f "$tmp" "$tmp.new"' EXIT
printf '%s\n' "$targets" | while IFS="	" read -r name dir file; do
  if [ ! -d "$dir" ]; then printf '%s\t沒裝，略過\n' "$name"; continue; fi
  block >"$tmp"
  if [ -f "$file" ]; then strip_block "$file" >"$tmp.new"; else : >"$tmp.new"; fi
  case "$mode" in
    remove)
      if [ -f "$file" ] && ! cmp -s "$file" "$tmp.new"; then cp "$tmp.new" "$file"; printf '%s\t已移除\t%s\n' "$name" "$file"
      else printf '%s\t原本就沒有\n' "$name"; fi
      continue ;;
  esac
  # 新內容 = 原本其他內容（去掉尾端空行）+ 空一行 + 區塊
  { awk '{ lines[NR] = $0 } END { n = NR; while (n > 0 && lines[n] == "") n--; for (i = 1; i <= n; i++) print lines[i]; if (n > 0) print "" }' "$tmp.new"
    cat "$tmp"; } >"$tmp.out"
  if [ -f "$file" ] && cmp -s "$file" "$tmp.out"; then printf '%s\t已是最新\t%s\n' "$name" "$file"
  elif [ "$mode" = "check" ]; then printf '%s\t需要更新\t%s\n' "$name" "$file"; echo 1 >"$tmp.stale"
  else cp "$tmp.out" "$file" && printf '%s\t已寫入\t%s\n' "$name" "$file"; fi
  rm -f "$tmp.out"
done
if [ -f "$tmp.stale" ]; then rm -f "$tmp.stale"; exit 1; fi
exit 0
