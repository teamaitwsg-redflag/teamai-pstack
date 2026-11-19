# teamai-pstack

teamAI 寫程式與工作用的 Claude Code 工作流。它是一個 Claude Code plugin，搭配 [pstack](https://github.com/michael-denyer/pstack-claude) 使用：pstack 提供工作流指令，這個工具包補上團隊的共用規則、信任曲線，以及幾個 pstack 沒有的 skill。

裝好之後，任何專案、任何電腦、雲端或本機的 Claude Code session 都會有同一套規則與指令。

## 安裝

需要 Claude Code 與 Git。

macOS、Linux、Windows 的 Git Bash：

```bash
git clone https://github.com/teamaitwsg-redflag/teamai-pstack.git
```

```bash
bash teamai-pstack/install.sh
```

Windows PowerShell：

```powershell
git clone https://github.com/teamaitwsg-redflag/teamai-pstack.git
powershell -ExecutionPolicy Bypass -File .\teamai-pstack\install.ps1
```

也可以不 clone，直接在終端機執行這四行：

```bash
claude plugin marketplace add michael-denyer/pstack-claude
claude plugin install pstack@pstack-claude
claude plugin marketplace add teamaitwsg-redflag/teamai-pstack
claude plugin install teamai@teamai-pstack
```

裝完重新開一個 session，輸入 `/teamai:flow`。

雲端 session（claude.ai/code）：把上面四行放進雲端環境的 setup script，之後每個新 session 都會自動安裝。repo 必須是公開的，setup script 才抓得到。

更新：`bash update.sh`，或 Windows 的 `update.ps1`。

## 裡面有什麼

| 指令 | 用途 |
|---|---|
| `/teamai:flow` | 工作流導覽：現在這個任務該用哪個指令 |
| `/teamai:grill-me` | 動工前的需求釐清，一次問一個問題 |
| `/teamai:evidence` | 交件附證據：實際執行並逐條對照驗收條件 |
| `/teamai:trust-ladder` | 信任曲線檢核：專案可以自動化到什麼程度 |
| `/teamai:overnight` | 過夜任務單：完成條件、停損條件、權限範圍 |
| `/teamai:cross-review` | 跨廠牌審核團：把改動平行交給本機的 Codex（GPT）、Gemini、Grok 唯讀審查，再逐條查證 |
| `/teamai:sync-agents` | 把共用規則同步給本機的 Grok CLI、Codex、Gemini CLI，讓它們照同一套規則做事 |
| `/teamai:agy-second-opinion` | 用 agy（Gemini）審文件、PDF、圖片，或只有 agy 可用時的第二意見 |

另外，plugin 會在每個 session 開始時載入兩份內容：

- `plugins/teamai/rules/teamai-rules.md`：共用工作規則。
- pstack 模型分工表：pstack 各角色用哪個模型。你在 `~/.claude/pstack-models.md` 放自己的版本時以你的為準，沒有才用內附的。

不想自動載入時，在 `~/.claude/` 放一個名為 `teamai-off` 的空檔。

## 四條鐵律

1. 球員不兼裁判：寫的 AI 不核准、不合併自己的 PR。
2. 交件附證據：沒有實際執行並看過輸出，就不說完成。
3. 錯誤變成硬規則：同一種錯出現第二次，就寫成 linter、測試或 CI 閘門。
4. 信任一階一階給：沒走到對應的階段，不開自動合併、不過夜放行。

完整的階段說明與指令對照見 [docs/workflow.md](docs/workflow.md)。

## repo 結構

| 路徑 | 用途 |
|---|---|
| `.claude-plugin/marketplace.json` | 讓這個 repo 可以用 `claude plugin marketplace add` 加入 |
| `plugins/teamai/skills/` | 八個 skill，每個資料夾一個 `SKILL.md` |
| `plugins/teamai/rules/` | 共用規則與模型分工表 |
| `plugins/teamai/hooks/` | session 開始時載入規則的 hook |
| `scripts/validate.py`、`scripts/test_*.sh` | 結構檢查，以及 hook、審核團、規則同步三支腳本的測試，CI 在 Linux 與 macOS 都跑 |
| `install.sh`、`install.ps1`、`update.sh`、`update.ps1` | 安裝與更新 |
| `docs/workflow.md` | 工作流說明 |

## 修改與新增 skill

1. 在 `plugins/teamai/skills/<名稱>/SKILL.md` 新增或修改。frontmatter 要有 `name`（等於資料夾名稱）與 `description`（寫清楚什麼時候用、什麼時候不用）。
2. 跑檢查：

```bash
bash scripts/check.sh
```

3. 用 `bash install.sh --local` 裝到本機，開新 session 試用。
4. commit、push。其他人跑更新腳本就拿得到。

這個 repo 不放公司名稱、logo、案件或客戶資料、人名、內部主機與個人電腦路徑。

## 來源

- pstack 由 Lauren Tan 設計，Claude Code 版由 Michael Denyer 移植。這個工具包沒有複製 pstack 的內容，只在安裝時一併安裝它。
- 階段劃分與信任曲線整理自一支拆解 pstack 工作流的影片分析筆記。
