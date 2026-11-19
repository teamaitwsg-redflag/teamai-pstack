#!/usr/bin/env python3
"""檢查這個工具包的結構。CI 與 commit 前都跑這支，沒過就不能合併。

每一條檢查都對應一種曾經發生或很容易發生的錯：
- manifest 不是合法 JSON，plugin 會整個裝不起來
- SKILL.md 沒有 name 或 description，skill 不會被載入
- name 和資料夾名稱不同，指令名稱會對不上文件
- 密鑰或本機路徑被 commit 進公開的 repo
- 文件裡提到的 /teamai:xxx 其實不存在
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLUGIN = ROOT / "plugins" / "teamai"
errors = []


def err(path, msg):
    errors.append(f"{Path(path).relative_to(ROOT)}: {msg}")


def load_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        err(path, f"不是合法的 JSON：{e}")
        return None


# 1. manifest
market = load_json(ROOT / ".claude-plugin" / "marketplace.json")
plugin = load_json(PLUGIN / ".claude-plugin" / "plugin.json")
load_json(PLUGIN / "hooks" / "hooks.json")
if market is not None:
    names = [p.get("name") for p in market.get("plugins", [])]
    if names != ["teamai"]:
        err(ROOT / ".claude-plugin" / "marketplace.json", f"plugins 應該只有 teamai，實際是 {names}")
if plugin is not None and plugin.get("name") != "teamai":
    err(PLUGIN / ".claude-plugin" / "plugin.json", "name 必須是 teamai")

# 2. skills
skills = set()
for d in sorted((PLUGIN / "skills").iterdir()):
    if not d.is_dir():
        continue
    f = d / "SKILL.md"
    if not f.exists():
        err(d, "缺少 SKILL.md")
        continue
    text = f.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        err(f, "開頭要有 --- 包住的 frontmatter")
        continue
    fm = dict(
        (k.strip(), v.strip())
        for k, v in (line.split(":", 1) for line in m.group(1).splitlines() if ":" in line)
    )
    if fm.get("name") != d.name:
        err(f, f"name（{fm.get('name')!r}）要和資料夾名稱（{d.name!r}）相同")
    desc = fm.get("description", "")
    if len(desc) < 30:
        err(f, "description 太短，要寫清楚什麼時候用、什麼時候不用")
    if len(desc) > 1024:
        err(f, f"description 有 {len(desc)} 字，上限 1024")
    if "使用" not in desc:
        err(f, "description 要寫出觸發情境（什麼時候使用）")
    skills.add(d.name)

# 3. hook 腳本與規則檔
hook = PLUGIN / "hooks" / "session-start.sh"
if not hook.exists():
    err(PLUGIN / "hooks", "缺少 session-start.sh")
for name in ("teamai-rules.md", "pstack-models.md"):
    if not (PLUGIN / "rules" / name).exists():
        err(PLUGIN / "rules", f"缺少 {name}")

# 4. 文件裡提到的 /teamai:xxx 必須存在
text_files = [p for p in ROOT.rglob("*") if p.is_file() and ".git" not in p.parts
              and p.suffix in {".md", ".sh", ".ps1", ".py", ".json", ".yml"}]
for p in text_files:
    body = p.read_text(encoding="utf-8", errors="replace")
    if p.name == "validate.py":
        continue
    for ref in set(re.findall(r"/teamai:([a-z0-9-]+)", body)):
        if ref not in skills:
            err(p, f"提到 /teamai:{ref}，但沒有這個 skill")

# 5. 不該進公開 repo 的東西
SECRET = re.compile(r"(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,}"
                    r"|-----BEGIN [A-Z ]*PRIVATE KEY-----)")
LOCAL = re.compile(r"(C:\\Users\\[A-Za-z0-9_.-]+\\|/Users/[A-Za-z0-9_.-]+/|\\\\[A-Za-z0-9_-]+\\share)")
for p in text_files:
    if p.name == "validate.py":
        continue
    body = p.read_text(encoding="utf-8", errors="replace")
    if SECRET.search(body):
        err(p, "疑似含有密鑰或 token")
    m = LOCAL.search(body)
    if m:
        err(p, f"含有個人電腦或內部主機的路徑：{m.group(0)}")
for p in ROOT.rglob("*"):
    if p.is_file() and ".git" not in p.parts and (p.name == ".env" or p.suffix in {".pem", ".key", ".pfx"}):
        err(p, "憑證或 .env 不可以進 repo")

# 6. shell 腳本裡，變數名後面不可以直接接中文或全形標點
# macOS 內建的 bash 3.2 在非 UTF-8 語系下會把那些位元組當成變數名的一部分（CI 上發生過），要寫成 ${name}
BARE_VAR = re.compile(r"\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]")
for p in text_files:
    if p.suffix != ".sh":
        continue
    for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue
        m = BARE_VAR.search(line)
        if m:
            err(p, f"第 {n} 行的 {m.group(0)[:-1]} 後面直接接了非 ASCII 字元，請寫成 ${{...}}")

if errors:
    print(f"檢查沒過，共 {len(errors)} 項：")
    for e in errors:
        print(" -", e)
    sys.exit(1)
print(f"檢查通過：{len(skills)} 個 skill（{', '.join(sorted(skills))}）")
