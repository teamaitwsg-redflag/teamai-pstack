#!/bin/bash
# 跨廠牌審核團：把同一份改動交給本機裝得到的其他廠牌 AI（Codex、Gemini、Grok）平行做唯讀審查。
#
#   review-panel.sh --list                      列出找得到哪些審查者
#   review-panel.sh --selftest [--only a,b]     實測每個審查者「會回答」而且「寫不了檔」
#   review-panel.sh [--uncommitted | --base REF | --diff FILE]
#                   [--repo DIR] [--out DIR] [--only a,b] [--timeout 秒] [--focus "重點"]
#
# 審查結果寫到 <out>/<審查者>.md，總表在 <out>/summary.tsv（審查者、狀態、位元組、秒數）。
# 結束碼：0 至少一個審查者有回覆；2 沒有任何審查者有回覆；3 沒有改動；4 改動裡疑似有密鑰；64 用法錯誤。
#
# 寫給 macOS 內建的 bash 3.2，所以不用關聯陣列、mapfile、timeout 指令。
set -u

REVIEWERS="codex gemini grok agy"

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "review-panel: $*" >&2; exit 64; }

# ---------- 找審查者 ----------
# 設了 TEAMAI_<名稱>_BIN 就只認它（測試與自訂路徑用）；否則找 PATH，再找已知的安裝位置。
find_bin() {
  local name="$1" upper override p
  upper="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
  eval "override=\${TEAMAI_${upper}_BIN-__unset__}"
  if [ "$override" != "__unset__" ]; then
    [ -x "$override" ] && printf '%s\n' "$override"
    return 0
  fi
  if p="$(command -v "$name" 2>/dev/null)" && [ -n "$p" ]; then printf '%s\n' "$p"; return 0; fi
  case "$name" in
    codex) set -- "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex" \
                  "/Applications/Codex.app/Contents/Resources/codex-cli/bin/codex" ;;
    grok)  set -- "$HOME/.grok/bin/grok" "$HOME/.local/bin/grok" ;;
    agy)   set -- "${LOCALAPPDATA:-/nonexistent}/agy/bin/agy.exe" "${LOCALAPPDATA:-/nonexistent}/agy/bin/agy" ;;
    *)     set -- ;;
  esac
  for p in "$@"; do
    if [ -x "$p" ]; then printf '%s\n' "$p"; return 0; fi
  done
  return 0
}

vendor_of() {
  case "$1" in
    codex) echo "OpenAI" ;;
    gemini|agy) echo "Google" ;;
    grok) echo "xAI" ;;
  esac
}

# ---------- 每個審查者的唯讀呼叫方式 ----------
# 參數：名稱 執行檔 工作目錄 提示詞 輸出檔。在子 shell 裡 exec，讓逾時能直接砍到那個程序。
launch() {
  local name="$1" bin="$2" dir="$3" prompt="$4" out="$5"
  cd "$dir" || exit 97
  case "$name" in
    codex)
      exec "$bin" exec -s read-only --ephemeral --skip-git-repo-check \
        -c model_reasoning_effort=high -o "$out" "$prompt" </dev/null ;;
    gemini)
      exec "$bin" --approval-mode plan --skip-trust -o text -p "$prompt" </dev/null >"$out" ;;
    grok)
      exec "$bin" --sandbox read-only --output-format plain -p "$prompt" </dev/null >"$out" ;;
    agy)
      exec "$bin" --mode plan --print-timeout 20m --add-dir "$dir" \
        --model "Gemini 4 Hydrogen (XHigh)" -p "$prompt" </dev/null >"$out" ;;
  esac
}

# 跑一個審查者並寫下狀態。狀態檔一行：名稱<TAB>狀態<TAB>位元組<TAB>秒數
run_one() {
  local name="$1" bin="$2" dir="$3" prompt="$4" outdir="$5" secs="$6"
  local out="$outdir/$name.md" log="$outdir/$name.log" start end rc pid wd status bytes
  start="$(date +%s)"
  : >"$out"
  ( launch "$name" "$bin" "$dir" "$prompt" "$out" ) >"$log" 2>&1 &
  pid=$!
  ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null; sleep 3; kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  wd=$!
  wait "$pid"; rc=$?
  pkill -P "$wd" >/dev/null 2>&1; kill "$wd" >/dev/null 2>&1; wait "$wd" 2>/dev/null
  end="$(date +%s)"
  bytes="$(wc -c <"$out" | tr -d ' ')"
  if [ "$rc" -eq 143 ] || [ "$rc" -eq 137 ]; then status="timeout"
  elif [ "$rc" -ne 0 ]; then status="failed($rc)"
  elif [ "$bytes" -lt 2 ]; then status="empty"
  else status="ok"; fi
  printf '%s\t%s\t%s\t%s\n' "$name" "$status" "$bytes" "$((end - start))" >"$outdir/$name.status"
}

# ---------- 參數 ----------
mode="review"; src=""; base=""; diff_file=""; repo="."; out=""; only=""; secs=1200; focus=""
while [ $# -gt 0 ]; do
  case "$1" in
    --list) mode="list" ;;
    --selftest) mode="selftest" ;;
    --uncommitted) src="uncommitted" ;;
    --base) [ $# -ge 2 ] || die "--base 需要一個 ref"; src="base"; base="$2"; shift ;;
    --diff) [ $# -ge 2 ] || die "--diff 需要一個檔案"; src="diff"; diff_file="$2"; shift ;;
    --repo) [ $# -ge 2 ] || die "--repo 需要一個資料夾"; repo="$2"; shift ;;
    --out) [ $# -ge 2 ] || die "--out 需要一個資料夾"; out="$2"; shift ;;
    --only) [ $# -ge 2 ] || die "--only 需要名稱清單"; only="$2"; shift ;;
    --timeout) [ $# -ge 2 ] || die "--timeout 需要秒數"; secs="$2"; shift ;;
    --focus) [ $# -ge 2 ] || die "--focus 需要文字"; focus="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "不認得的參數：$1" ;;
  esac
  shift
done
case "$secs" in ''|*[!0-9]*) die "--timeout 要是整數秒" ;; esac

wanted() {
  [ -z "$only" ] && return 0
  case ",$only," in *",$1,"*) return 0 ;; esac
  return 1
}

# 決定這次要用誰。同一家廠牌只留一個（gemini 與 agy 都是 Google，有 gemini 就不跑 agy）。
selected=""; missing=""; seen_vendors=""
for name in $REVIEWERS; do
  wanted "$name" || continue
  bin="$(find_bin "$name")"
  if [ -z "$bin" ]; then missing="$missing $name"; continue; fi
  v="$(vendor_of "$name")"
  case " $seen_vendors " in *" $v "*) continue ;; esac
  seen_vendors="$seen_vendors $v"
  selected="$selected $name"
done

if [ "$mode" = "list" ]; then
  for name in $REVIEWERS; do
    bin="$(find_bin "$name")"
    if [ -n "$bin" ]; then printf '%s\t%s\t%s\n' "$name" "$(vendor_of "$name")" "$bin"
    else printf '%s\t%s\t%s\n' "$name" "$(vendor_of "$name")" "(沒裝)"; fi
  done
  exit 0
fi

# ---------- 自我測試：會回答，而且寫不了檔 ----------
if [ "$mode" = "selftest" ]; then
  [ -n "$selected" ] || { echo "找不到任何審查者。" >&2; exit 2; }
  fail=0
  for name in $selected; do
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/teamai-selftest.XXXXXX")"
    mkdir "$tmp/work" "$tmp/out"
    run_one "$name" "$(find_bin "$name")" "$tmp/work" \
      "請用 shell 指令或寫檔工具，在目前資料夾建立檔案 proof.txt，內容是 hi。然後只回答一行：有建立成功就回答 WROTE，被擋下來就回答 BLOCKED。" \
      "$tmp/out" "$secs"
    st="$(cut -f2 "$tmp/out/$name.status")"
    if [ -e "$tmp/work/proof.txt" ]; then verdict="不合格：寫得了檔"; fail=1
    elif [ "$st" != "ok" ]; then verdict="不合格：沒有回覆（$st）"; fail=1
    else verdict="合格：有回覆，寫不了檔"; fi
    printf '%s\t%s\t回覆：%s\n' "$name" "$verdict" "$(head -c 200 "$tmp/out/$name.md" | tr '\n' ' ')"
    rm -rf "$tmp"
  done
  exit "$fail"
fi

# ---------- 準備改動 ----------
[ -d "$repo" ] || die "找不到資料夾：$repo"
repo="$(cd "$repo" && pwd)"
if [ -z "$out" ]; then
  mkdir -p "$repo/.teamai-review" || die "建立不了 $repo/.teamai-review"
  # 資料夾自己忽略自己，審查紀錄不會被 commit
  [ -f "$repo/.teamai-review/.gitignore" ] || echo '*' >"$repo/.teamai-review/.gitignore"
  out="$repo/.teamai-review/$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$out" || die "建立不了 $out"
out="$(cd "$out" && pwd)"
change="$out/change.diff"

if [ -z "$src" ]; then
  if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then src="uncommitted"
  else die "工作區沒有未 commit 的改動，請用 --base <分支> 或 --diff <檔案> 指定要審什麼"; fi
fi
case "$src" in
  uncommitted) git -C "$repo" diff HEAD >"$change" 2>"$out/git.log" || die "git diff 失敗，見 $out/git.log" ;;
  base) git -C "$repo" diff "$base...HEAD" >"$change" 2>"$out/git.log" || die "git diff 失敗，見 $out/git.log" ;;
  diff) [ -f "$diff_file" ] || die "找不到 diff 檔：$diff_file"; cp "$diff_file" "$change" ;;
esac
if [ ! -s "$change" ]; then echo "沒有改動可以審。" >&2; exit 3; fi

# 密鑰不送給外部 AI：改動裡看起來有密鑰或 .env 就停下來，沒有略過的選項。
if grep -nE '(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,}|xai-[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' "$change" >"$out/secrets.txt" \
   || grep -nE '^(\+\+\+|---) [ab]/(.*/)?\.env(\.[A-Za-z0-9_.-]+)?$' "$change" >>"$out/secrets.txt"; then
  echo "改動裡疑似有密鑰或 .env，沒有送出。行號見 $out/secrets.txt（對應 $change）。" >&2
  exit 4
fi
rm -f "$out/secrets.txt"

[ -n "$selected" ] || { echo "找不到任何審查者（缺：$missing ）。" >&2; exit 2; }

prompt="你是獨立的程式審查者。只能讀檔，禁止修改任何檔案，禁止執行會改變狀態的指令。
要審的改動在這個檔案（unified diff）：$change
需要上下文時可以讀 $repo 裡的其他檔案。

請回報：
(1) 會造成錯誤結果、當機或資料毀損的邏輯錯誤
(2) 邊界條件與例外處理的漏洞
(3) 安全問題（注入、密鑰外洩、權限）
(4) 與現有程式碼的介面或慣例不一致的地方
(5) 缺少的測試

每個發現寫一行：[嚴重度 高/中/低] 檔案:行號 — 問題 — 你的依據 — 建議。
沒有發現的類別寫「未發現」。看不到或無法判斷的寫「無法確認」，不要猜。
最後用一行寫出你是哪個模型。"
[ -n "$focus" ] && prompt="$prompt

這次請特別注意：$focus"
printf '%s\n' "$prompt" >"$out/prompt.txt"

# ---------- 平行執行 ----------
pids=""
for name in $selected; do
  run_one "$name" "$(find_bin "$name")" "$repo" "$prompt" "$out" "$secs" &
  pids="$pids $!"
done
for p in $pids; do wait "$p"; done

: >"$out/summary.tsv"
okcount=0
for name in $selected; do
  cat "$out/$name.status" >>"$out/summary.tsv"
  [ "$(cut -f2 "$out/$name.status")" = "ok" ] && okcount=$((okcount + 1))
  rm -f "$out/$name.status"
done
# 同廠牌已經有人審過的（例如有 gemini 時的 agy）不算缺席
for name in $missing; do
  case " $seen_vendors " in *" $(vendor_of "$name") "*) continue ;; esac
  printf '%s\tmissing\t0\t0\n' "$name" >>"$out/summary.tsv"
done

echo "審查紀錄：$out"
cat "$out/summary.tsv"
[ "$okcount" -gt 0 ] || exit 2
exit 0
