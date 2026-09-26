#!/usr/bin/env bash
# ============================================================
#  用户级初始化(以 WSL 默认用户运行,由 setup.sh 调用)
#  职责: 工作区(建在 Windows 文档目录,含旧版目录迁移)→ AI 规范文件
#        → shell/npm/pip 配置 → 各 agent 基础配置
#  可重复运行(幂等),不覆盖用户内容。
# ============================================================
set -euo pipefail

KIT_DIR="/opt/agent-kit"
# shellcheck source=lib.sh
. "$KIT_DIR/scripts/lib.sh"
# shellcheck source=/dev/null
[ -f /etc/agent-kit/net.env ] && . /etc/agent-kit/net.env

WS="$HOME/workspace"
CONF_DIR="$HOME/.config/agent-kit"
mkdir -p "$CONF_DIR"

# Windows 目录:优先用 install.ps1 精确传来的(已处理 OneDrive/改过位置的情况),
# 缺了再按用户名猜(兼容旧参数 --win-user)
first_dir() { for d in "$@"; do if [ -n "$d" ] && [ -d "$d" ]; then printf '%s' "$d"; return 0; fi; done; return 1; }
U="/mnt/c/Users/${WIN_USER:-}"
WIN_DESKTOP="$(first_dir "${WIN_DESKTOP_WSL:-}" "$U/OneDrive/Desktop" "$U/OneDrive/桌面" "$U/Desktop" || true)"
WIN_DOWNLOADS="$(first_dir "${WIN_DOWNLOADS_WSL:-}" "$U/Downloads" || true)"
WIN_DOCS="$(first_dir "${WIN_DOCS_WSL:-}" "$U/OneDrive/Documents" "$U/OneDrive/文档" "$U/Documents" || true)"

# 在 /mnt 上时,调 Windows 的 attrib 去掉隐藏属性(NTFS 上被隐藏的文件,从 Linux 侧覆盖写会被拒)
win_unhide() {
    case "$1" in /mnt/[a-z]/*) ;; *) return 0 ;; esac
    [ -e "$1" ] && [ -x /mnt/c/Windows/System32/attrib.exe ] || return 0
    /mnt/c/Windows/System32/attrib.exe -h "$(wslpath -w "$1")" >/dev/null 2>&1 || true
}

# ---------- 1. 工作区位置:Windows「文档\AI工作区」,WSL 侧软链 ~/workspace ----------
step "搭建工作区…"
if [ -n "$WIN_DOCS" ]; then
    TARGET="$WIN_DOCS/AI工作区"
    if [ -e "$WS" ] && [ ! -L "$WS" ]; then
        warn "检测到已有本地工作区 $WS,保持原位不搬家(迁移方法见 docs/TROUBLESHOOTING.md)"
    else
        mkdir -p "$TARGET"
        ln -sfn "$TARGET" "$WS"
        ok "工作区 = Windows「文档\\AI工作区」(WSL 里是 ~/workspace)"
    fi
else
    warn "没找到 Windows 文档目录,工作区只能建在 WSL 内部 $WS(资源管理器里看不到,见 docs/TROUBLESHOOTING.md)"
fi
mkdir -p "$WS"

# ---------- 2. 旧版目录结构迁移(v1:inbox/projects/notes/templates/archive) ----------
migrate() { # <旧相对路径> <新相对路径>
    if [ -d "$WS/$1" ] && [ ! -e "$WS/$2" ]; then
        mv "$WS/$1" "$WS/$2" && note "$1 → $2"
    elif [ -d "$WS/$1" ]; then
        warn "新旧文件夹都在:$1 和 $2,旧的保持原样,请手动合并"
    fi
}
if [ -d "$WS/inbox" ] || [ -d "$WS/projects" ] || [ -d "$WS/notes" ] || [ -d "$WS/templates" ]; then
    step "把旧版英文文件夹改成新的中文结构(文件原样保留)…"
    migrate inbox 1-收件箱
    migrate projects/文案 2-文案
    migrate projects/调研 3-调研
    migrate projects/短视频分析 4-短视频
    migrate notes 6-笔记
    migrate templates 7-模板
    migrate archive 8-归档
    [ -f "$WS/6-笔记/_index.md" ] && [ ! -e "$WS/6-笔记/笔记索引.md" ] && mv "$WS/6-笔记/_index.md" "$WS/6-笔记/笔记索引.md"
    if [ -f "$WS/8-归档/初次导览已完成.txt" ]; then
        mkdir -p "$WS/.agent-kit"
        mv "$WS/8-归档/初次导览已完成.txt" "$WS/.agent-kit/" 2>/dev/null || true
    fi
    rm -f "$WS/1-收件箱/说明.md"                        # 旧版说明,新版是 说明.txt
    rm -f "$WS/使用说明.md"                              # 旧版 .md 双击打不开,换成 .txt
    rmdir "$WS/projects" 2>/dev/null || note "projects/ 里还有你自己建的东西,原样保留"
    ok "迁移完成"
fi

# ---------- 3. 模板与脚手架(已有文件一律不覆盖) ----------
# 必须 -r 而非 -a:工作区在 /mnt/c(NTFS),保留权限/属主会 EPERM
rsync -r --ignore-existing --exclude AGENTS.md "$KIT_DIR/workspace-template/" "$WS/"
mkdir -p "$WS/.agent-kit"
ok "工作区文件夹就绪(1-收件箱 … 8-归档)"

# ---------- 4. AGENTS.md:安装包维护的「AI 工作规范」 ----------
# 每次安装都更新到最新版(并注入真实桌面/下载路径)。若发现被改动过,旧版先备份到 8-归档。
# 路径里可能有 & # \(Windows 用户名如 Tom&Jerry),进 sed 替换串前要转义
sed_repl() { printf '%s' "$1" | sed -e 's/[\\&#]/\\&/g'; }
render_agents() {
    local desk docs dl
    desk="$(sed_repl "${WIN_DESKTOP:-未检测到,按 /mnt/c/Users/用户名/Desktop 推断}")"
    docs="$(sed_repl "${WIN_DOCS:-未检测到}")"
    dl="$(sed_repl "${WIN_DOWNLOADS:-未检测到,按 /mnt/c/Users/用户名/Downloads 推断}")"
    sed -e "s#__WIN_DESKTOP__#${desk}#g" \
        -e "s#__WIN_DOCUMENTS__#${docs}#g" \
        -e "s#__WIN_DOWNLOADS__#${dl}#g" \
        "$KIT_DIR/workspace-template/AGENTS.md"
}
NEW_AGENTS="$(mktemp)"
render_agents > "$NEW_AGENTS"
HASH_FILE="$CONF_DIR/AGENTS.md.sha256"
DEST="$WS/AGENTS.md"
if [ -f "$DEST" ] && ! cmp -s "$NEW_AGENTS" "$DEST"; then
    cur="$(sha256sum "$DEST" | cut -d' ' -f1)"
    if [ "$cur" != "$(cat "$HASH_FILE" 2>/dev/null)" ]; then
        mkdir -p "$WS/8-归档"
        bak="$WS/8-归档/旧版AI规范-$(date +%Y%m%d-%H%M%S).md"
        cp "$DEST" "$bak"
        note "AGENTS.md 有过改动,旧版已备份到 8-归档/$(basename "$bak")"
    fi
fi
if ! cmp -s "$NEW_AGENTS" "$DEST" 2>/dev/null; then
    win_unhide "$DEST"
    cat "$NEW_AGENTS" > "$DEST"
    ok "AI 工作规范(AGENTS.md)已更新,桌面/文档/下载路径已写入"
fi
sha256sum "$DEST" | cut -d' ' -f1 > "$HASH_FILE"
rm -f "$NEW_AGENTS"

# ---------- 5. shell / npm / pip ----------
step "写入 shell 与软件源配置…"
write_block "$HOME/.bashrc" "# --- agent-kit ---" "# --- agent-kit end ---" \
'# 由 AI 办公助手安装包维护(重装会更新这一段;要加自己的配置请写在这段外面)
[ -r /etc/profile.d/agent-kit.sh ] && . /etc/profile.d/agent-kit.sh
# 开终端若正处在家目录,自动站到工作区(直接敲 opencode/claude 也带上工作区规范)
case $- in *i*) [ "$PWD" = "$HOME" ] && [ -d "$HOME/workspace" ] && cd "$HOME/workspace";; esac'

# npm:只替换我们写过的 registry 行
REG="${npm_config_registry:-https://registry.npmmirror.com}"
touch "$HOME/.npmrc"
if grep -qE '^registry=' "$HOME/.npmrc" && ! grep -qE '^registry=https://registry\.(npmmirror\.com|npmjs\.org)/?$' "$HOME/.npmrc"; then
    note ".npmrc 里有你自己设的 registry,保持不动"
else
    sed -i '/^registry=/d' "$HOME/.npmrc"
    echo "registry=$REG" >> "$HOME/.npmrc"
fi

# pip:这个 Ubuntu 专供 AI 干活,允许 pip install --user(免得 agent 撞上 externally-managed 报错)
PIP_CONF="$HOME/.config/pip/pip.conf"
if [ ! -f "$PIP_CONF" ]; then
    mkdir -p "$(dirname "$PIP_CONF")"
    printf '[global]\nindex-url = %s\nbreak-system-packages = true\n' \
        "${PIP_INDEX_URL:-https://pypi.org/simple}" > "$PIP_CONF"
fi
ok "shell / npm / pip 配置完成"

# ---------- 6. 各 agent 的基础配置(已有不动) ----------
copy_if_absent() { # <模板> <目标>
    if [ ! -f "$2" ]; then mkdir -p "$(dirname "$2")"; cp "$1" "$2"; fi
}
copy_if_absent "$KIT_DIR/config-template/opencode-base.json" "$HOME/.config/opencode/opencode.json"
copy_if_absent "$KIT_DIR/config-template/qwen-settings.json" "$HOME/.qwen/settings.json"
copy_if_absent "$KIT_DIR/config-template/gemini-settings.json" "$HOME/.gemini/settings.json"
ok "OpenCode / Qwen / Gemini 基础配置就绪(都读工作区的 AGENTS.md)"

ok "用户级初始化完成"
