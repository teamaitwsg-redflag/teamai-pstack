# teamai-pstack：維護這個 repo 時的規則

這個 repo 是 Claude Code 的 plugin marketplace，沒有應用程式。內容是規則檔、skill、hook 與安裝腳本。

@plugins/teamai/rules/teamai-rules.md

## 這個 repo 專屬的規則
- 這是公開性質的工具包。公司名稱、logo、案件資料、客戶資料、人名、內部主機與個人電腦路徑都不放進來。`scripts/validate.py` 會擋一部分，但不能只靠它。
- 改完一定跑 `bash scripts/check.sh`（結構檢查加全部測試），它以零結束才 commit，而且只認它的結束碼：`bash scripts/check.sh && git commit …`。不要把測試輸出接到 `grep`、`tail` 再串 `&&`，那樣失敗會被吃掉。CI 跑的是同樣的內容。
- 規則檔改了之後，其他 AI 工具要重新同步才拿得到（`/teamai:sync-agents`）。
- 新增或修改 skill：資料夾名稱等於 frontmatter 的 `name`；`description` 寫清楚什麼時候用、什麼時候不用。指令名稱會是 `/teamai:<name>`。
- 規則寫在 `plugins/teamai/rules/teamai-rules.md`。它每個 session 都會被載入，所以要短：只放每次都用得到的規則，流程細節放進 skill。
- 同一種錯出現第二次時，優先在 `scripts/validate.py` 加一條檢查，不是在這裡加一句提醒。
- `plugin.json` 故意不寫 version，讓每個 commit 都算一個新版本，使用者跑 update 就拿得到。
- 用 `bash install.sh --local` 可以把工作中的版本裝到本機測試。
