#!/bin/bash
# 更新 pstack 與 teamai 兩個 plugin 到最新版。
set -u
claude plugin marketplace update pstack-claude
claude plugin update pstack@pstack-claude
claude plugin marketplace update teamai-pstack
claude plugin update teamai@teamai-pstack
echo "更新完成。重新開 session 生效。"
