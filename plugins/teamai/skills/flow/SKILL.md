---
name: flow
description: teamAI 工作流導覽。使用者不確定現在該用哪個指令、問「接下來要做什麼」「這個任務怎麼開始」「pstack 怎麼用」「要用哪個 skill」，或剛接到一個任務還沒決定做法時使用。依任務所在的階段（規劃、實作、驗收、過夜、修正）指出該用的 pstack 或 teamai 指令。只做導覽，不直接動手實作。
---

# 工作流導覽

先判斷任務在哪個階段，再給一到兩個指令，不要把整張表丟給使用者。判斷不出來就問一個問題：「這是新東西，還是改既有的東西？」

## 階段與指令

| 階段 | 狀況 | 指令 |
|---|---|---|
| 規劃 | 需求模糊、從零開始 | `/teamai:grill-me` |
| 規劃 | 需求明確，要寫成可驗收的任務 | `/pstack:sharpen`、`/pstack:in-your-own-words` |
| 規劃 | 要改既有系統，還不懂它怎麼運作 | `/pstack:how` |
| 規劃 | 看到奇怪的寫法，想知道為什麼 | `/pstack:why` |
| 實作 | 要先定架構與分工 | `/pstack:architect` |
| 實作 | 有幾種做法，想讓不同模型各做一版再比 | `/pstack:arena` |
| 實作 | 行為可以用測試描述 | `/pstack:tdd` |
| 實作 | 跨檔案、原因不明的 bug、效能問題 | `/pstack:poteto-mode` |
| 驗收 | 要證明真的能跑 | `/teamai:evidence`；重複驗的流程做成 `/pstack:create-verification-skill` |
| 驗收 | 想知道這次改動會波及哪裡 | `/pstack:blast-radius` |
| 驗收 | 合併前找漏洞 | `/pstack:interrogate`，再 `/teamai:cross-review`（GPT、Gemini、Grok 交叉審） |
| 驗收 | 準備合併，要多個獨立 AI 實測 | `/pstack:swarm` |
| 過夜 | 要交代無人看管的任務 | `/teamai:overnight`，執行時留 `/pstack:show-me-your-work` |
| 修正 | 同一種錯出現第二次 | `/pstack:correct` |
| 修正 | 回顧這段時間做了什麼、學到什麼 | `/pstack:ketchup`、`/pstack:reflect` |
| 管理 | 想知道專案可以放手到什麼程度 | `/teamai:trust-ladder` |

## 兩種起手式

- 新功能、需求不清楚：重心放在動工前。`/teamai:grill-me` → `/pstack:sharpen` → `/pstack:tdd`。花的 token 少。
- 舊專案、大量修 bug、重構：重心放在驗收與防呆。`/pstack:how` → `/pstack:poteto-mode` → `/pstack:interrogate`。花的 token 多，需要專案已有測試與 CI。

兩種可以接起來用：前段把需求問清楚，後段嚴格驗收。

## 注意

- pstack 沒安裝時（`/pstack:*` 指令不存在），請使用者依 README 安裝，不要假裝有。
- 小任務（單一檔案、改法明顯、有現成測試）直接做，做完驗證，不必走流程。
