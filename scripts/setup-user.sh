#!/usr/bin/env bash
# ============================================================
#  用户级初始化(以 WSL 默认用户运行,由 setup.sh 调用)
#  职责: 工作区脚手架 → Windows 目录桥接 → shell/npm 配置 → agent 基础配置
#  可重复运行(幂等),不覆盖用户已有内容。
# ============================================================
set -euo pipefail

KIT_DIR="/opt/agent-kit"
# shellcheck source=lib.sh
. "$KIT_DIR/scripts/lib.sh"

WIN_USER="${WIN_USER:-}"
WS="$HOME/workspace"

# ---------- 1. 工作区脚手架 ----------
step "搭建工作区 $WS …"
mkdir -p "$WS"
# --ignore-existing:她已有的笔记/文件绝不覆盖
rsync -a --ignore-existing "$KIT_DIR/workspace-template/" "$WS/"
ok "工作区目录就绪(inbox/ projects/ notes/ templates/ archive/)"

# ---------- 2. 桥接 Windows 常用目录 ----------
step "桥接 Windows 桌面/文档/下载…"
link_win() {
    local label="$1"; shift
    local target=""
    for cand in "$@"; do
        if [ -d "$cand" ]; then target="$cand"; break; fi
    done
    if [ -n "$target" ]; then
        ln -sfn "$target" "$WS/$label"
        ok "$label → $target"
    fi
}
if [ -n "$WIN_USER" ] && [ -d "/mnt/c/Users/$WIN_USER" ]; then
    U="/mnt/c/Users/$WIN_USER"
    link_win "win-桌面"  "$U/OneDrive/Desktop" "$U/OneDrive/桌面" "$U/Desktop"
    link_win "win-文档"  "$U/OneDrive/Documents" "$U/OneDrive/文档" "$U/Documents"
    link_win "win-下载"  "$U/Downloads"
else
    warn "未找到 Windows 用户目录(WIN_USER='$WIN_USER'),跳过桥接。之后可手动: ln -s /mnt/c/Users/<你>/Desktop \$HOME/workspace/win-桌面"
fi

# ---------- 3. shell 与 npm 配置 ----------
step "写入 shell 配置…"
append_once "$HOME/.bashrc" "# --- agent-kit ---" \
'export BROWSER=wslview                      # OAuth 登录时自动打开 Windows 浏览器
export HF_ENDPOINT=https://hf-mirror.com     # HuggingFace 国内镜像(本地转写模型用)
export PATH="$HOME/.local/bin:$PATH"
[ -f "$HOME/.config/agent-kit/env" ] && . "$HOME/.config/agent-kit/env"
# 开终端若正处在家目录,自动站到工作区(这样直接敲 opencode/claude 也带上工作区规范)
case $- in *i*) [ "$PWD" = "$HOME" ] && [ -d "$HOME/workspace" ] && cd "$HOME/workspace";; esac'

if ! grep -q npmmirror "$HOME/.npmrc" 2>/dev/null; then
    echo 'registry=https://registry.npmmirror.com' >> "$HOME/.npmrc"
fi
mkdir -p "$HOME/.config/agent-kit"
ok "shell 配置完成"

# ---------- 4. Agent 用户配置(不覆盖已有) ----------
if [ ! -f "$HOME/.config/opencode/opencode.json" ]; then
    mkdir -p "$HOME/.config/opencode"
    cp "$KIT_DIR/config-template/opencode-base.json" "$HOME/.config/opencode/opencode.json"
    ok "已写入 OpenCode 基础配置(.config/opencode/opencode.json)"
else
    ok "OpenCode 配置已存在,不动"
fi
if [ ! -f "$HOME/.qwen/settings.json" ]; then
    mkdir -p "$HOME/.qwen"
    cp "$KIT_DIR/config-template/qwen-settings.json" "$HOME/.qwen/settings.json"
    ok "已写入 Qwen Code 基础配置(.qwen/settings.json,仅装了 qwen 时生效)"
else
    ok "Qwen Code 配置已存在,不动"
fi

ok "用户级初始化完成"
