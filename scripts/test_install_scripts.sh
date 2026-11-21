#!/bin/bash
# 用假的 claude 測 install.sh 與 update.sh：失敗不可以被報成成功。不會呼叫真的 claude。
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; failn=0
check() { if eval "$2"; then pass=$((pass + 1)); echo "  通過：$1"; else failn=$((failn + 1)); echo "  失敗：$1"; fi; }

mkdir "$tmp/bin"
cat >"$tmp/bin/claude" <<'FAKE'
#!/bin/bash
# 第 FAIL_AT 次呼叫回傳 FAIL_CODE（FAIL_AT=all 每次都失敗），其餘回傳 0。每次呼叫記一行。
n=$(( $(wc -l < "$CALLS") + 1 ))
echo "claude $*" >>"$CALLS"
if [ "${FAIL_AT:-0}" = "$n" ] || [ "${FAIL_AT:-0}" = all ]; then echo "fake claude: failure on call $n" >&2; exit "${FAIL_CODE:-7}"; fi
exit 0
FAKE
chmod +x "$tmp/bin/claude"

# run 腳本 FAIL_AT [有沒有 claude]
run() {
  : >"$tmp/calls"
  local path="$tmp/bin:/usr/bin:/bin"; [ "${3:-yes}" = no ] && path="/usr/bin:/bin"
  out="$(cd "$tmp" && CALLS="$tmp/calls" FAIL_AT="$2" FAIL_CODE=7 PATH="$path" /bin/bash "$root/$1" 2>&1)"; rc=$?
  calls=$(wc -l < "$tmp/calls" | tr -d ' ')
}
said_ok() { printf '%s' "$out" | grep -q -E "$1"; }

for spec in "update.sh|更新完成" "install.sh|完成。重新開"; do
  s="${spec%%|*}"; okmsg="${spec#*|}"
  echo "== ${s}"
  run "$s" 0
  check "全部成功：結束碼 0、呼叫 4 次、印出成功" '[ "$rc" -eq 0 ] && [ "$calls" -eq 4 ] && said_ok "$okmsg"'
  run "$s" all
  check "每一步都失敗：結束碼不是 0，不印成功" '[ "$rc" -ne 0 ] && ! said_ok "$okmsg"'
  run "$s" 0 no
  check "找不到 claude：結束碼 1，不印成功" '[ "$rc" -eq 1 ] && ! said_ok "$okmsg"'
done

echo "== update.sh：停在失敗的那一步，保留它的結束碼"
for k in 1 2 3 4; do
  run update.sh "$k"
  check "第 ${k} 步失敗：結束碼 7、只呼叫到第 ${k} 次、不印成功" '[ "$rc" -eq 7 ] && [ "$calls" -eq "$k" ] && ! said_ok 更新完成'
done
echo "== install.sh：任何一步失敗都不印成功"
for k in 1 4; do
  run install.sh "$k"
  check "第 ${k} 步失敗：結束碼不是 0、不印成功" '[ "$rc" -ne 0 ] && ! said_ok "完成。重新開"'
done

echo; echo "install／update 腳本測試：通過 ${pass}，失敗 ${failn}"
[ "$failn" -eq 0 ]
