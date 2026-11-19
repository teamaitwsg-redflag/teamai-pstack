---
name: sync-agents
description: 把 teamAI 共用規則同步給這台電腦上的其他 AI 工具（Grok CLI、Codex、Gemini CLI），讓它們和 Claude Code 照同一套規則做事。使用者說「讓 Grok／Codex／Gemini 也知道這些規則」「同步規則給其他 agent」「其他 AI 也要用這套工作流」，或剛裝好其中一個工具、剛更新過 teamai plugin 時使用。只寫各工具自己的全域規則檔，不動專案檔案。只想讓其他 AI 審查某份改動時不要用，那是 /teamai:cross-review。
---

# 把規則同步給其他 AI 工具

Claude Code 的規則是靠 plugin 在 session 開始時載入的，其他工具讀不到。這個 skill 把同一份規則寫進它們各自的全域規則檔。

腳本在本 skill 資料夾的 `scripts/sync-rules.sh`，以下用 `<sync>` 代表它的完整路徑。

| 工具 | 規則檔 | 備註 |
|---|---|---|
| Grok CLI | `~/.grok/AGENTS.md` | Grok CLI 也會自動讀到 Claude Code 裝的 plugin skill |
| Codex（ChatGPT 桌面版內附） | `~/.codex/AGENTS.md` | |
| Gemini CLI 與 Antigravity（agy） | `~/.gemini/GEMINI.md` | 兩個工具都讀這個檔。agy 另外也讀 `~/.gemini/config/AGENTS.md`，兩邊都寫會載入兩次，所以只寫這一個 |

## 步驟

1. 先看現況，不寫入：

```bash
<sync> --check
```

2. 這是在改使用者家目錄裡、專案以外的檔案。第一次在這台電腦寫入前，先告訴使用者會改哪幾個檔案，得到同意再做：

```bash
<sync>
```

3. 逐一確認真的生效。規則檔寫進去不等於工具有讀到：
   - Grok：`grok inspect` 的輸出裡要看得到 `~/.grok/AGENTS.md`。
   - Codex、agy、Gemini：用唯讀模式問它一句「你的規則裡有沒有『球員不兼裁判』？原文是什麼？」，看它答不答得出來。
   - 沒登入的工具無法驗證，照實回報「已寫入，未驗證」。

4. 回報每個工具的狀態：已寫入並驗證、已寫入未驗證、沒裝。

## 注意

- 腳本只改兩個標記之間的區塊，檔案裡使用者原本寫的內容不動。重複執行結果相同。
- teamai plugin 更新後規則可能變了，再跑一次就會更新。
- 要拿掉：`<sync> --remove`。
- 桌面版 App 讀不讀這些檔案，各家不同（2026-11 在 macOS 上查證）：

| App | 讀不讀命令列的規則檔 | 依據 |
|---|---|---|
| ChatGPT 的本機 Codex 模式 | 讀，和命令列同一份 | 對話紀錄檔裡注入的規則區塊，指紋和 `~/.codex/AGENTS.md` 的相同 |
| ChatGPT 的一般聊天 | 沒有驗證過 | |
| Gemini 桌面版 | 不讀 | 程式裡沒有 `GEMINI.md` 或全域規則檔的讀取；它的 skill 存在帳號那一端，不在這台電腦上 |
| Grok Bot 桌面版 | 不讀 | 程式裡沒有 `AGENTS.md`、`CLAUDE.md`；它用的是 App 內每個 bot 自己的自訂指示，資料夾是 `~/.grokbot`，和 Grok CLI 的 `~/.grok` 無關 |

  不讀檔的 App 只能由使用者在 App 自己的自訂指示裡貼上規則，而且之後規則更新不會自動同步。規則全文在 plugin 的 `rules/teamai-rules.md`。
- 驗證 ChatGPT 本機 Codex 模式時，不必操作畫面，也不必問模型：每個對話都存成 `~/.codex/sessions/年/月/日/rollout-…-<對話編號>.jsonl`，裡面有實際注入的指示。取出兩個標記之間的區塊算指紋，和規則檔的比對即可。這是機器留下的紀錄，比模型自己回答可靠。
- 要用問答測一個 App 時，問它「照你的規則該下哪個指令」這類要它照做的題目，再加一題規則裡沒有答案的對照題；不要叫它背出指示。兩次新對話答案不一致，或對照題編出答案，就不能採信。
- 專案層級的規則（repo 裡的 `AGENTS.md`、`CLAUDE.md`）不歸這個 skill 管。
