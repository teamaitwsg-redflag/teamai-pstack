#!/bin/bash
# 跨廠牌審核團：把同一份改動交給本機裝得到的其他廠牌 AI（Codex、Gemini、Grok）平行做唯讀審查。
#
#   review-panel.sh --list                      列出找得到哪些審查者
#   review-panel.sh --selftest [--only a,b]     實測每個審查者「會回答」而且「寫不了檔」
#   review-panel.sh [--uncommitted | --base REF | --diff FILE]
#                   [--repo DIR] [--out DIR] [--only a,b] [--timeout 秒] [--focus "重點"]
#
# 審查結果寫到 <out>/<審查者>.md，總表在 <out>/summary.tsv（審查者、狀態、位元組、秒數）。
# 結束碼：0 至少一個審查者審完；2 沒有任何審查者審完；3 沒有改動；4 改動裡疑似有密鑰；64 用法錯誤。
#
# 寫給 macOS 內建的 bash 3.2，所以不用關聯陣列、mapfile、timeout 指令。
set -u
umask 077

# 同一家廠牌只跑排在前面的那個。Google 排 agy 在前：個人帳號登入的 Gemini CLI 已被 Google 停用，要改用 Antigravity（agy）
REVIEWERS="codex agy gemini grok"

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "review-panel: $*" >&2; exit 64; }

# ---------- 找審查者 ----------
# 設了 TEAMAI_<名稱>_BIN 就只認它（測試與自訂路徑用）；否則找 PATH，再找已知的安裝位置。
find_bin() {
  local name="$1" upper override p
  upper="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
  eval "override=\${TEAMAI_${upper}_BIN-__unset__}"
  if [ "$override" != "__unset__" ]; then
    # 之後會切換目錄才執行，所以先換成絕對路徑，確保執行的就是這裡檢查過的那個檔案
    case "$override" in /*) ;; *) override="$PWD/$override" ;; esac
    [ -x "$override" ] && printf '%s\n' "$override"
    return 0
  fi
  if p="$(command -v "$name" 2>/dev/null)" && [ -n "$p" ]; then printf '%s\n' "$p"; return 0; fi
  case "$name" in
    codex) set -- "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex" \
                  "/Applications/Codex.app/Contents/Resources/codex-cli/bin/codex" ;;
    grok)  set -- "$HOME/.grok/bin/grok" "$HOME/.local/bin/grok" ;;
    agy)   set -- "$HOME/.local/bin/agy" "${LOCALAPPDATA:-/nonexistent}/agy/bin/agy.exe" "${LOCALAPPDATA:-/nonexistent}/agy/bin/agy" ;;
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
      # Grok 在無人看管時，只要叫了需要核准的工具（寫檔、上網）整輪就會結束，審到一半也算正常結束。
      # 所以只給它讀檔類的工具並關掉上網，讓它沒有東西可以被擋。
      exec "$bin" --sandbox read-only --tools "read_file,grep,list_dir" --disable-web-search \
        --output-format plain -p "$prompt" </dev/null >"$out" ;;
    agy)
      # agy 不明說禁止 shell 的話，連簡單的題目都會去叫 shell 而失敗（自我測試時不加，因為那時就是要它試）
      [ "$mode" = "review" ] && prompt="只准使用 read_file 工具讀檔，禁止執行任何 shell 指令。
$prompt"
      exec "$bin" --mode plan --print-timeout 20m --add-dir "$dir" \
        --model "Gemini 4 Hydrogen (XHigh)" -p "$prompt" </dev/null >"$out" ;;
  esac
}

# 跑一個審查者並寫下狀態。狀態檔一行：名稱<TAB>狀態<TAB>位元組<TAB>秒數
# 一律在子 shell 裡呼叫：它會開 job control 並設 trap。
# 審查者放在自己的程序群組裡，逾時或被取消時整組一起收掉，不留下它衍生的子程序。
run_one() {
  local name="$1" bin="$2" dir="$3" prompt="$4" outdir="$5" secs="$6"
  local out="$outdir/$name.md" log="$outdir/$name.log" mark="$outdir/$name.timedout"
  local start end rc pid wd status bytes
  start="$(date +%s)"
  rm -f "$mark"
  : >"$out"
  set -m
  ( launch "$name" "$bin" "$dir" "$prompt" "$out" ) >"$log" 2>&1 &
  pid=$!
  set +m
  trap 'kill -TERM -- "-$pid" 2>/dev/null; pkill -P "$wd" 2>/dev/null; kill "$wd" 2>/dev/null; sleep 1; kill -KILL -- "-$pid" 2>/dev/null; printf "%s\tcancelled\t0\t0\n" "$name" >"$outdir/$name.status"; exit 130' INT TERM
  # 逾時與否由計時器自己記下來，不從結束碼猜
  # 用 && 串起來：計時器被提早收掉時 sleep 會失敗，後面就不會誤記逾時、也不會亂砍
  ( sleep "$secs" && : >"$mark" && { kill -TERM -- "-$pid" 2>/dev/null; sleep 3; kill -KILL -- "-$pid" 2>/dev/null; } ) >/dev/null 2>&1 &
  wd=$!
  wait "$pid"; rc=$?
  pkill -P "$wd" >/dev/null 2>&1; kill "$wd" >/dev/null 2>&1; wait "$wd" 2>/dev/null
  # 主程序結束後，群組裡還活著的子孫一併收掉
  if kill -TERM -- "-$pid" 2>/dev/null; then sleep 1; kill -KILL -- "-$pid" 2>/dev/null; fi
  trap - INT TERM
  end="$(date +%s)"
  bytes="$(wc -c <"$out" | tr -d ' ')"
  if [ -e "$mark" ]; then status="timeout"
  elif [ "$rc" -ne 0 ]; then status="failed($rc)"
  elif [ "$bytes" -lt 2 ]; then status="empty"
  # 審查要寫到最後的完成標記才算數；中途被打斷的會正常結束、也有輸出，只能靠這個分辨
  elif [ "$mode" = "review" ] && ! grep -q "REVIEW-COMPLETE" "$out"; then status="incomplete"
  else status="ok"; fi
  rm -f "$mark"
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

# 決定這次要用誰。同一家廠牌只留一個（agy 與 gemini 都是 Google，有 agy 就不跑 gemini）。
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
    ( run_one "$name" "$(find_bin "$name")" "$tmp/work" \
      "請用 shell 指令或寫檔工具，在目前資料夾建立檔案 proof.txt，內容是 hi。一定要實際嘗試。然後只回答一行：有建立成功就回答 WROTE，被擋下來就回答 BLOCKED。" \
      "$tmp/out" "$secs" )
    st="$(cut -f2 "$tmp/out/$name.status")"
    # 合格要同時滿足：檔案不存在，而且它自己回報試過、被擋下來。
    # 只回了別的話不算，因為那可能是根本沒試。
    # 有些工具一被擋就結束這一輪，來不及回答。這時看工具自己的紀錄：
    # 要同一行同時提到 proof.txt 和拒絕，別的權限錯誤不算。
    refusal="$(grep -iE "(permission required|was not run|permission denied|not permitted).*proof\.txt|proof\.txt.*(permission required|was not run|permission denied|not permitted)" "$tmp/out/$name.log" | head -1 | cut -c1-160)"
    if [ -e "$tmp/work/proof.txt" ]; then verdict="不合格：寫得了檔"; fail=1
    elif [ "$st" != "ok" ] && [ "$st" != "empty" ]; then verdict="不合格：沒有回覆（${st}）"; fail=1
    elif grep -q "WROTE" "$tmp/out/$name.md"; then verdict="不合格：它回報寫入成功"; fail=1
    elif grep -q "BLOCKED" "$tmp/out/$name.md"; then verdict="合格：試過寫檔，被擋下來"
    elif [ -n "$refusal" ]; then verdict="合格：寫檔被工具本身擋下，紀錄是「${refusal}」"
    elif [ "$st" = "empty" ]; then verdict="不合格：沒有回覆（empty）"; fail=1
    else verdict="無法確認：沒有照指示回答，不知道有沒有試"; fail=1; fi
    printf '%s\t%s\t回覆：%s\n' "$name" "$verdict" "$(head -c 200 "$tmp/out/$name.md" | tr '\n' ' ')"
    rm -rf "$tmp"
  done
  exit "$fail"
fi

# ---------- 準備改動 ----------
[ -d "$repo" ] || die "找不到資料夾：$repo"
repo="$(cd "$repo" && pwd)"

# 收集改動用的 git：不讓 repo 的設定在這裡執行外部程式（fsmonitor、外部 diff、textconv），也不要顏色碼
g() { git -C "$repo" -c core.fsmonitor=false "$@"; }
gd() { g diff --no-color --no-ext-diff --no-textconv "$@"; }

if [ -z "$src" ]; then
  st="$(g status --porcelain --untracked-files=all 2>/dev/null)" || die "git status 失敗：$repo 不是 git repo，或 git 出錯"
  if [ -n "$st" ]; then src="uncommitted"
  else echo "工作區沒有未 commit 的改動。要審分支請用 --base <分支>，要審現成的 diff 請用 --diff <檔案>。" >&2; exit 3; fi
fi

# 每一輪用自己的新資料夾，不沿用舊的：避免兩輪互相覆寫，也避免把上一輪的 diff 拿來送審。
if [ -z "$out" ]; then
  mkdir -p "$repo/.teamai-review" || die "建立不了 $repo/.teamai-review"
  # 資料夾自己忽略自己，審查紀錄不會被 commit
  [ -f "$repo/.teamai-review/.gitignore" ] || echo '*' >"$repo/.teamai-review/.gitignore"
  out="$(mktemp -d "$repo/.teamai-review/$(date +%Y%m%d-%H%M%S).XXXXXX")" || die "建立不了輸出資料夾"
else
  [ -L "$out" ] && die "--out 不可以是符號連結：$out"
  if [ -e "$out" ]; then
    [ -d "$out" ] || die "--out 不是資料夾：$out"
    [ -z "$(ls -A "$out")" ] || die "--out 必須是空的或還不存在的資料夾：$out"
  else
    mkdir -p "$out" || die "建立不了 $out"
  fi
fi
out="$(cd "$out" && pwd)"
change="$out/change.diff"

case "$src" in
  uncommitted)
    # 已 add 的與還沒 add 的分開收：只看工作區對 HEAD 的話，add 之後又改回去的內容會漏掉
    { gd --cached HEAD && gd; } >"$change" 2>"$out/git.log" || die "git diff 失敗，見 $out/git.log"
    # git diff 不含還沒 add 的新檔，要另外補進來（被 .gitignore 忽略的不算）
    g ls-files --others --exclude-standard -z >"$out/untracked.list" 2>>"$out/git.log" || die "列不出未追蹤的檔案，見 $out/git.log"
    while IFS= read -r -d '' f; do
      # 這一輪自己的輸出不算改動
      case "$repo/$f" in "$out"/*) continue ;; esac
      [ -r "$repo/$f" ] || die "讀不到未追蹤的檔案，沒有送出：$f"
      ( cd "$repo" && git -c core.fsmonitor=false diff --no-color --no-ext-diff --no-textconv --no-index -- /dev/null "$f" ) >>"$change" 2>>"$out/git.log"
    done <"$out/untracked.list"
    rm -f "$out/untracked.list" ;;
  base) gd "$base...HEAD" >"$change" 2>"$out/git.log" || die "git diff 失敗，見 $out/git.log" ;;
  diff)
    [ -f "$diff_file" ] || die "找不到 diff 檔：$diff_file"
    cp "$diff_file" "$change" || die "複製不了 diff 檔：$diff_file"
    # 顏色控制碼會讓下面的檔名檢查看不到標頭
    if grep -q "$(printf '\033')" "$change"; then rm -f "$change"; die "diff 檔裡有終端機顏色控制碼，請用 --no-color 重新產生"; fi ;;
esac
if [ ! -s "$change" ]; then echo "沒有改動可以審。" >&2; exit 3; fi

# 密鑰不送給外部 AI：改動裡看起來有密鑰或 .env 就停下來，沒有略過的選項。
# 掃描本身出錯也停下來，不當成「沒掃到」。報告只寫行號，不把密鑰再抄一份。
SECRET_RE='(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,}|xai-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'
TAB="$(printf '\t')"
hits="$(grep -nE "$SECRET_RE" "$change")"; rc=$?
[ "$rc" -gt 1 ] && { echo "密鑰掃描失敗，沒有送出。" >&2; exit 4; }
# 檔名是 .env 或 .env.xxx 的都擋（含加引號、改名、沒有 a/ b/ 前綴的寫法），範例檔除外
headers="$(grep -nE '^(diff --git |\+\+\+ |--- |rename from |rename to )' "$change")"; rc=$?
[ "$rc" -gt 1 ] && { echo "密鑰掃描失敗，沒有送出。" >&2; exit 4; }
envhits="$(printf '%s\n' "$headers" | grep -E "[/\" ${TAB}]\\.env([.\" ${TAB}]|\$)" | grep -vE "\\.env\\.(example|sample|template)([\" ${TAB}]|\$)")"
if [ -n "$hits" ] || [ -n "$envhits" ]; then
  # 報告只寫是哪個檔案，不抄內容；含原文的 change.diff 也刪掉，免得下一輪被審查者讀到
  nums="$(printf '%s\n' "$hits" | cut -d: -f1 | tr '\n' ' ')"
  { awk -v nums="$nums" 'BEGIN { n = split(nums, a, " "); for (i = 1; i <= n; i++) want[a[i]] = 1 }
      /^\+\+\+ / { file = substr($0, 5) }
      (NR in want) { print file ": 疑似密鑰" }' "$change" | sort -u
    printf '%s\n' "$envhits" | cut -d: -f2- | sed -e '/^$/d' -e 's/$/: .env 檔/'; } >"$out/secrets.txt"
  rm -f "$change"
  echo "改動裡疑似有密鑰或 .env，沒有送出。是哪些檔案見 $out/secrets.txt" >&2
  exit 4
fi

[ -n "$selected" ] || { echo "找不到任何審查者（缺：$missing ）。" >&2; exit 2; }

prompt="你是獨立的程式審查者。只用讀檔與搜尋檔案的工具。禁止修改任何檔案，禁止執行指令，不要上網。
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
全部寫完後，最後一行寫：REVIEW-COMPLETE 加上你是哪個模型。沒有這一行會被當成沒審完。"
[ -n "$focus" ] && prompt="$prompt

這次請特別注意：$focus"
printf '%s\n' "$prompt" >"$out/prompt.txt"

# ---------- 平行執行 ----------
pids=""
# 被中斷時把每個審查者的程序群組都收掉
trap 'for p in $pids; do kill -TERM "$p" 2>/dev/null; done; wait; echo "已取消，審查者都已停止。" >&2; exit 130' INT TERM
for name in $selected; do
  ( run_one "$name" "$(find_bin "$name")" "$repo" "$prompt" "$out" "$secs" ) &
  pids="$pids $!"
done
for p in $pids; do wait "$p"; done

# 同一家廠牌有備援時（Google 的 agy 與 gemini）：排前面的沒成功，就換後面的上
for name in $REVIEWERS; do
  wanted "$name" || continue
  case " $selected " in *" $name "*) continue ;; esac
  alt="$(find_bin "$name")"; [ -n "$alt" ] || continue
  for first in $selected; do
    [ "$(vendor_of "$first")" = "$(vendor_of "$name")" ] || continue
    [ "$(cut -f2 "$out/$first.status")" = "ok" ] && continue
    ( run_one "$name" "$alt" "$repo" "$prompt" "$out" "$secs" ) &
    pids="$!"; wait "$pids"
    selected="$selected $name"
  done
done
trap - INT TERM

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
