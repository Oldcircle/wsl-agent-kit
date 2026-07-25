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
WIN_DOCS_WSL="${WIN_DOCS_WSL:-}"
WS="$HOME/workspace"

# 探测 Windows 常用目录(含 OneDrive 重定向与中文名)
first_dir() { for d in "$@"; do if [ -d "$d" ]; then printf '%s' "$d"; return 0; fi; done; return 1; }
U="/mnt/c/Users/$WIN_USER"
WIN_DESKTOP="$(first_dir "$U/OneDrive/Desktop" "$U/OneDrive/桌面" "$U/Desktop" || true)"
WIN_DOWNLOADS="$(first_dir "$U/Downloads" || true)"
[ -n "$WIN_DOCS_WSL" ] || WIN_DOCS_WSL="$(first_dir "$U/OneDrive/Documents" "$U/OneDrive/文档" "$U/Documents" || true)"

# ---------- 1. 工作区:建在 Windows 文档目录,WSL 侧软链 ----------
# 好处:资源管理器/Word/播放器/Obsidian 原生直开,无需任何网页或桥接。
step "搭建工作区…"
if [ -n "$WIN_DOCS_WSL" ] && [ -d "$WIN_DOCS_WSL" ]; then
    TARGET="$WIN_DOCS_WSL/AI工作区"
    if [ -e "$WS" ] && [ ! -L "$WS" ]; then
        warn "检测到已有本地工作区 $WS,保持原位不搬家(迁移方法见 docs/TROUBLESHOOTING.md)"
    else
        mkdir -p "$TARGET"
        ln -sfn "$TARGET" "$WS"
        ok "工作区在 Windows「文档\\AI工作区」,WSL 经 ~/workspace 访问"
    fi
else
    warn "未找到 Windows 文档目录(WIN_USER='$WIN_USER'),工作区建在 WSL 内 $WS"
fi
mkdir -p "$WS/"
# --ignore-existing:她已有的笔记/文件绝不覆盖
# 注意必须 -r 而非 -a:工作区在 /mnt/c(NTFS),保留权限/属主会 EPERM
rsync -r --ignore-existing "$KIT_DIR/workspace-template/" "$WS/"
ok "工作区目录就绪(inbox/ projects/ notes/ templates/ archive/)"

# ---------- 2. 把真实 Windows 路径写进 AGENTS.md(只在占位符还在时替换) ----------
if grep -q "__WIN_DESKTOP__" "$WS/AGENTS.md" 2>/dev/null; then
    sed -i \
        -e "s#__WIN_DESKTOP__#${WIN_DESKTOP:-未检测到,按 /mnt/c/Users/用户名/Desktop 推断}#g" \
        -e "s#__WIN_DOCUMENTS__#${WIN_DOCS_WSL:-未检测到}#g" \
        -e "s#__WIN_DOWNLOADS__#${WIN_DOWNLOADS:-未检测到,按 /mnt/c/Users/用户名/Downloads 推断}#g" \
        "$WS/AGENTS.md"
    ok "AGENTS.md 已注入桌面/文档/下载真实路径"
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
