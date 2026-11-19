---
name: cross-review
description: 跨廠牌審核團。重要變更合併前、準備開 PR 前，或使用者說「交叉審查」「找其他 AI 審」「跨廠牌審核」「讓 GPT／Gemini／Grok 看一下」「審核團」時使用。用腳本把同一份改動平行交給本機裝得到的其他廠牌 AI（Codex、Gemini、Grok）做唯讀審查，再由主對話逐條查證後回報。只審查不修改；外部 AI 的結論不直接採用。改動很小、使用者只要 Claude 自己看一眼時不要用。
---

# 跨廠牌審核團

寫的人不驗收自己的成果。Claude 寫的改動，要讓別家廠牌的模型來找漏洞，因為同一家的模型有相同的盲點。這個 skill 用一支腳本把這件事做成固定動作。

腳本在本 skill 資料夾的 `scripts/review-panel.sh`，以下用 `<panel>` 代表它的完整路徑。

## 審核的完整順序

外部審查要花額度與時間，所以放在自己的檢查之後：

1. 先自己驗：測試與實際執行通過（`/teamai:evidence`）。沒過就先修，不要拿壞的東西去審。
2. 動到共用邏輯時跑 `/pstack:blast-radius`。
3. 同廠牌不同模型的交叉審查：`/pstack:interrogate`。
4. 跨廠牌：本 skill。
5. 逐條查證，修正，重新驗證，回報。

小改動可以只做 1 和 4。跳過哪一步要在回報裡寫出來。

## 步驟

### 1. 看有誰可以用

```bash
<panel> --list
```

| 審查者 | 廠牌 | 唯讀的做法 |
|---|---|---|
| `codex` | OpenAI | `codex exec -s read-only` |
| `agy` | Google | `agy --mode plan` |
| `gemini` | Google | `gemini --approval-mode plan`（沒有 agy 時才用，同廠牌只跑一個） |
| `grok` | xAI | `grok --sandbox read-only` |

一個都沒有時，告訴使用者缺什麼、怎麼裝（見最後一節），然後只做 `/pstack:interrogate`，並在回報裡明說少了跨廠牌這一道。

### 2. 第一次用、或工具更新過：先做自我測試

```bash
<panel> --selftest
```

它會實際要求每個審查者建立檔案。合格的條件是檔案沒有出現，而且審查者回報它試過、被擋下來。寫得了檔的判不合格；答非所問、看不出有沒有試的判無法確認。這兩種都不要用，用 `--only` 排除，並告訴使用者。這一步不能用讀說明文件代替：各家工具的旗標常改，唯讀到底有沒有生效只有實測才知道。

### 3. 送審

```bash
<panel> --repo <repo 路徑> --base main
```

- 審未 commit 的改動用 `--uncommitted`（包含還沒 `git add` 的新檔），審分支用 `--base <分支>`，審現成的 diff 用 `--diff <檔案>`。
- 想指定重點加 `--focus "這次改了金額計算，請特別看進位與幣別"`。
- 只用部分審查者加 `--only codex,grok`。
- 每個審查者預設最多跑 20 分鐘，Bash 工具的 timeout 要設得比它長，或用背景執行。
- 結果在 `<repo>/.teamai-review/<時間>/`：每個審查者一個 `.md`，總表是 `summary.tsv`，`.log` 是該工具的原始輸出。這個資料夾會自己忽略自己，不會被 commit。自己用 `--out` 指定時，要給空的或還不存在的資料夾，每一輪用新的。

結束碼：0 至少一個有回覆；2 沒有任何回覆；3 沒有改動；4 改動裡疑似有密鑰，沒有送出。

遇到結束碼 4 不要想辦法繞過。`secrets.txt` 會列出是哪些檔案（不含內容；含原文的 diff 已經刪掉），把那些檔案指給使用者，先把密鑰或 `.env` 從改動裡拿掉。`.env.example`、`.env.sample`、`.env.template` 這類範例檔不會被擋。

### 4. 讀總表，再讀每一份結果

`summary.tsv` 的狀態有 `ok`、`empty`、`failed(碼)`、`timeout`、`missing`。只有 `ok` 的才算審過。`failed` 的去看對應的 `.log` 與 `.md`（有些工具把錯誤訊息印在標準輸出），常見原因是沒登入或額度用完，照實告訴使用者，不要反覆重試。

### 5. 逐條查證

每個發現都要回到程式碼或實際執行去查，分成三類：

- 屬實：寫一個會失敗的測試或實際重現，修正，再驗證。
- 不成立：寫出不成立的理由與依據。
- 無法確認：列給使用者。

兩家以上都提到的問題優先查。只有一家提到不代表是錯的，沒有任何一家提到也不代表沒問題。

### 6. 回報

```
審核團：codex（ok）、gemini（ok）、grok（missing）
跳過的步驟：（例如沒有跑 /pstack:interrogate，原因）

| # | 發現 | 誰提的 | 查證結果 | 處理 |
|---|---|---|---|---|
| 1 | … | codex、gemini | 屬實（重現方式） | 已修，測試名稱 |
| 2 | … | grok | 不成立（依據） | 不處理 |
| 3 | … | gemini | 無法確認 | 請你決定 |

修正後重新驗證的結果：（測試輸出）
審查紀錄：<資料夾路徑>
```

## 規則

- 審查者只能讀。不讓外部 AI 動手修，也不照著它給的修補程式直接貼上；修正由主對話做，做完自己驗。
- 外部 AI 說「沒問題」不等於通過，它只是其中一道檢查。
- 最終數字、資料庫寫入、部署、push 不交給審查者。
- 密鑰、.env、含個資或客戶資料的檔案不送審。腳本會擋常見的密鑰格式，但擋不了個資，送審前自己看一眼改動的內容。
- 審查者會讀到 repo 裡的其他檔案。repo 裡有不能外流的資料時，改用 `--diff` 並把工作目錄指到只放那份 diff 的空資料夾（`--repo <空資料夾>`）。

## 安裝與登入

安裝與登入都要使用者同意，登入由使用者自己在終端機完成，不替他輸入密碼或授權碼。

| 審查者 | 安裝 | 登入 |
|---|---|---|
| codex | 裝 ChatGPT／Codex 桌面版就有（腳本會自己找到 App 內附的 CLI），或 `npm install -g @openai/codex` | `codex login` |
| agy | macOS、Linux：`curl -fsSL https://antigravity.google/cli/install.sh \| bash`；Windows 見 `/teamai:agy-second-opinion` | 在終端機執行 `agy`，依畫面用 Google 帳號登入 |
| gemini | `npm install -g @google/gemini-cli` | 只適用 API key 或企業帳號。個人 Google 帳號登入已被 Google 停用（2026-11 實測，錯誤訊息要求改用 Antigravity），個人帳號請裝 agy |
| grok | `curl -fsSL https://x.ai/cli/install.sh \| bash` | `grok login`（需要 SuperGrok 或 X Premium+） |

工具裝在非標準位置時，用環境變數指定：`TEAMAI_CODEX_BIN`、`TEAMAI_GEMINI_BIN`、`TEAMAI_GROK_BIN`、`TEAMAI_AGY_BIN`。

裝好之後一定跑一次 `<panel> --selftest`。實測紀錄（2026-11，macOS）：Codex 0.169 與 Grok 1.0.89 都擋得住寫檔。Grok 被擋之後會直接結束那一輪、不會回答，自我測試是看它自己的紀錄判定的。
