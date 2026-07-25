#!/usr/bin/env bash
# ============================================================
#  WSL 内安装脚本(root 运行)——合成版:可选装多个 agent
#  用法: bash setup.sh --win-user <名> [--agents opencode,kimi,claude]
#                      [--agents-only] [--with-asr] [--with-qwen] [--no-mirror]
#  可装: opencode kimi claude qwen codex gemini hermes openclaw goose
#  职责: apt 依赖 → Node 22 → 所选 agents → 命令入口 → 用户级初始化
#  可重复运行(幂等)。
# ============================================================
set -euo pipefail

KIT_DIR="/opt/agent-kit"
# shellcheck source=lib.sh
. "$KIT_DIR/scripts/lib.sh"

trap 'die "安装在第 $LINENO 行中断。把上面的红字/报错发给安装人即可定位。重新运行 install.bat 可从头再来(安全)。"' ERR

[ "$(id -u)" -eq 0 ] || die "setup.sh 需要 root 运行(由 install.ps1 自动调用)"

WIN_USER=""
WIN_DOCS=""
WITH_ASR=0
USE_MIRROR=1
AGENTS_CSV="opencode,kimi,claude"   # 默认推荐组合
AGENTS_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --win-user) WIN_USER="${2:-}"; shift 2 ;;
        --win-docs) WIN_DOCS="${2:-}"; shift 2 ;;
        --agents) AGENTS_CSV="${2:-$AGENTS_CSV}"; shift 2 ;;
        --agents-only) AGENTS_ONLY=1; shift ;;
        --with-asr) WITH_ASR=1; shift ;;
        --with-qwen) AGENTS_CSV="$AGENTS_CSV,qwen"; shift ;;
        --no-mirror) USE_MIRROR=0; shift ;;
        *) shift ;;
    esac
done

KIT_USER="$(default_user)"
[ -n "$KIT_USER" ] || die "找不到 uid=1000 的默认用户(install.ps1 应已创建)"
ok "目标用户:$KIT_USER  Windows 用户:${WIN_USER:-未知}"

if [ "$AGENTS_ONLY" -eq 0 ]; then
# ---------- 1. apt 源(国内镜像,默认开) ----------
if [ "$USE_MIRROR" -eq 1 ] && [ -f /etc/apt/sources.list.d/ubuntu.sources ] \
   && ! grep -q 'tuna.tsinghua' /etc/apt/sources.list.d/ubuntu.sources; then
    step "切换 apt 到清华镜像(国内提速;--no-mirror 可跳过)"
    cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak
    sed -i -E 's#https?://(archive|security)\.ubuntu\.com#https://mirrors.tuna.tsinghua.edu.cn#g' \
        /etc/apt/sources.list.d/ubuntu.sources
    ok "apt 源已切换(原文件备份为 ubuntu.sources.bak)"
fi

# ---------- 2. 基础依赖 ----------
step "安装基础工具(git/curl/ripgrep/jq/ffmpeg/python3 等)…"
export DEBIAN_FRONTEND=noninteractive
retry 3 apt-get update -qq
retry 3 apt-get install -y -qq \
    ca-certificates curl wget git unzip zip xz-utils \
    ripgrep jq rsync \
    ffmpeg \
    python3 python3-venv python3-pip \
    python3-pandas python3-openpyxl python3-docx \
    wslu >/dev/null
ok "基础工具就绪"
fi  # AGENTS_ONLY

# ---------- 3. Node.js 22(npmmirror 直装,免 nvm) ----------
step "检查 Node.js…"
need_node=1
if command -v node >/dev/null 2>&1; then
    major="$(node -e 'console.log(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)"
    if [ "${major:-0}" -ge 20 ]; then
        need_node=0
        ok "已有 Node $(node -v),跳过"
    fi
fi
if [ "$need_node" -eq 1 ] && [ "$AGENTS_ONLY" -eq 1 ]; then
    die "尚未完成基础安装(缺 Node),请先运行完整安装(install.bat 或不带 --agents-only 的 setup.sh)"
fi
if [ "$need_node" -eq 1 ]; then
    case "$(uname -m)" in
        x86_64)  narch="linux-x64" ;;
        aarch64) narch="linux-arm64" ;;
        *) die "不支持的 CPU 架构:$(uname -m)" ;;
    esac
    fetch_node() {
        local base=$1
        local fname
        fname="$(curl -fsSL --connect-timeout 15 "$base/latest-v22.x/SHASUMS256.txt" \
                 | grep -o "node-v22[0-9.]*-$narch.tar.xz" | head -1)" || return 1
        [ -n "$fname" ] || return 1
        retry 2 curl -fL --connect-timeout 15 -o /tmp/node.tar.xz "$base/latest-v22.x/$fname"
    }
    step "下载 Node.js 22($narch)…"
    fetch_node "https://npmmirror.com/mirrors/node" || fetch_node "https://nodejs.org/dist" \
        || die "Node.js 下载失败,请检查网络"
    rm -rf /usr/local/lib/nodejs-v22
    mkdir -p /usr/local/lib/nodejs-v22
    tar -xJf /tmp/node.tar.xz -C /usr/local/lib/nodejs-v22 --strip-components=1
    rm -f /tmp/node.tar.xz
    for b in node npm npx; do
        ln -sfn /usr/local/lib/nodejs-v22/bin/$b /usr/local/bin/$b
    done
    ok "Node $(node -v) 安装完成"
fi

# ---------- 4. 安装所选 agents ----------
# npm 系:install_npm_agent <npm包> <命令名> <显示名>
install_npm_agent() {
    local pkg="$1" bin="$2" name="$3"
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$name 已安装,跳过(升级:npm update -g $pkg)"
        return 0
    fi
    if ! retry 3 npm install -g "$pkg@latest" \
        --registry=https://registry.npmmirror.com --no-fund --no-audit >/dev/null; then
        warn "$name 安装失败(可稍后 ai-install 重试)"
        return 1
    fi
    if [ -x "/usr/local/lib/nodejs-v22/bin/$bin" ]; then
        ln -sfn "/usr/local/lib/nodejs-v22/bin/$bin" "/usr/local/bin/$bin"
    fi
    command -v "$bin" >/dev/null 2>&1 && ok "$name 安装完成" || warn "$name 装完找不到命令 $bin"
}

# 用户级官方脚本系:install_user_agent <显示名> <检测命令...> -- <安装命令字符串>
install_user_script_agent() {
    local name="$1" check="$2" script="$3"
    if runuser -u "$KIT_USER" -- bash -lc "command -v $check" >/dev/null 2>&1; then
        ok "$name 已安装,跳过"
        return 0
    fi
    if runuser -u "$KIT_USER" -- bash -lc "$script"; then
        ok "$name 安装完成"
    else
        warn "$name 安装失败(常见原因:该官方源需要顺畅的 GitHub 访问;可稍后 ai-install 重试)"
    fi
}

install_one_agent() {
    case "$1" in
        opencode) step "安装 OpenCode(主推)…"
                  install_npm_agent "opencode-ai" "opencode" "OpenCode" \
                      || die "主推 agent OpenCode 安装失败,请检查网络后重跑" ;;
        claude)   step "安装 Claude Code…"
                  install_npm_agent "@anthropic-ai/claude-code" "claude" "Claude Code" || true ;;
        qwen)     step "安装 Qwen Code…"
                  install_npm_agent "@qwen-code/qwen-code" "qwen" "Qwen Code" || true ;;
        codex)    step "安装 Codex CLI…"
                  install_npm_agent "@openai/codex" "codex" "Codex CLI" || true ;;
        gemini)   step "安装 Gemini CLI…"
                  install_npm_agent "@google/gemini-cli" "gemini" "Gemini CLI" || true ;;
        openclaw) step "安装 OpenClaw(小龙虾 🦞)…"
                  install_npm_agent "openclaw" "openclaw" "OpenClaw" || true
                  command -v openclaw >/dev/null 2>&1 \
                      && warn "OpenClaw 首次使用需以普通用户运行 openclaw onboard 完成引导(见 docs/USAGE.md)" ;;
        kimi)     step "安装 Kimi Code CLI(官方脚本)…"
                  install_user_script_agent "Kimi Code" "kimi" \
                      'curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash' ;;
        hermes)   step "安装 Hermes Agent(爱马仕)…"
                  install_user_script_agent "Hermes Agent" "hermes" \
                      'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash' ;;
        goose)    step "安装 Goose…"
                  install_user_script_agent "Goose" "goose" \
                      'curl -fsSL https://github.com/block/goose/releases/latest/download/download_cli.sh | bash' ;;
        *)        warn "未知 agent:$1(可选:opencode kimi claude qwen codex gemini hermes openclaw goose)" ;;
    esac
}

for a in $(echo "$AGENTS_CSV" | tr ',' ' '); do
    install_one_agent "$a"
done

# ---------- 5. 命令入口:ai / ai-config / ai-video ----------
step "安装 ai / ai-config / ai-video 命令…"
cat > /usr/local/bin/ai <<'LAUNCHER'
#!/usr/bin/env bash
# AI 助手统一入口
#   ai              启动默认 agent(首次自动进配置向导)
#   ai <名字>       本次临时用指定 agent,如 ai claude / ai kimi
#   ai use <名字>   把默认换成指定 agent(下次双击图标就是它)
#   ai list         看看装了哪些、当前默认是谁
set -u
CONF_DIR="$HOME/.config/agent-kit"
KNOWN="opencode kimi claude qwen codex gemini hermes openclaw goose"
[ -f "$CONF_DIR/env" ] && . "$CONF_DIR/env"

is_known() { case " $KNOWN " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
has_agent() {
    if [ "$1" = "kimi" ]; then
        command -v kimi >/dev/null 2>&1 || command -v kimi-code >/dev/null 2>&1
    else
        command -v "$1" >/dev/null 2>&1
    fi
}
run_agent() { # <名字> [参数...]
    local a="$1"; shift
    mkdir -p "$HOME/workspace"; cd "$HOME/workspace"
    if [ "$a" = "kimi" ]; then
        for c in kimi kimi-code; do
            command -v "$c" >/dev/null 2>&1 && exec "$c" "$@"
        done
    elif command -v "$a" >/dev/null 2>&1; then
        exec "$a" "$@"
    fi
    echo "[!] 「$a」未安装,改用 OpenCode 启动(追加安装:ai-install $a)"
    exec opencode "$@"
}

case "${1:-}" in
    list)
        DEF="$(cat "$CONF_DIR/default-agent" 2>/dev/null || echo '')"
        if [ "${2:-}" = "--plain" ]; then
            # 机器可读:名字|已装(1/0)|默认(1/0),供「AI 控制台」解析
            for a in $KNOWN; do
                inst=0; has_agent "$a" && inst=1
                d=0; [ "$a" = "$DEF" ] && d=1
                printf '%s|%d|%d\n' "$a" "$inst" "$d"
            done
            exit 0
        fi
        echo "已安装的 agent(* 为默认):"
        for a in $KNOWN; do
            if has_agent "$a"; then
                if [ "$a" = "$DEF" ]; then echo "  * $a"; else echo "    $a"; fi
            fi
        done
        echo "临时用某个:ai <名字>;换默认:ai use <名字>;加装:ai-install <名字>;选着启动:ai menu"
        exit 0 ;;
    menu)
        # 终端里的启动菜单:↑↓ 选已装 agent,回车启动(TTY 专用)
        if [ ! -t 0 ]; then echo "ai menu 需要交互终端"; exit 1; fi
        AVAIL=""
        for a in $KNOWN; do has_agent "$a" && AVAIL="$AVAIL $a"; done
        # shellcheck disable=SC2086
        set -- $AVAIL
        [ $# -gt 0 ] || { echo "还没有装任何 agent?运行 ai-install <名字>"; exit 1; }
        cur=0; n=$#
        printf '\n选择要启动的 AI( ↑↓ + 回车 ):\n\n'
        i=0; while [ $i -lt $n ]; do printf '\n'; i=$((i+1)); done
        while :; do
            printf '\033[%dA' "$n"
            i=1
            for a in "$@"; do
                if [ $((i-1)) -eq $cur ]; then printf '\033[2K \033[7m %s \033[0m\n' "$a"
                else printf '\033[2K  %s\n' "$a"; fi
                i=$((i+1))
            done
            IFS= read -rsn1 k || exit 1
            case "$k" in
                $'\033') read -rsn2 -t 1 r || r=""
                         case "$r" in
                             '[A') cur=$(( (cur-1+n)%n )) ;;
                             '[B') cur=$(( (cur+1)%n )) ;;
                         esac ;;
                '') shift "$cur"; exec /usr/local/bin/ai "$1" ;;
            esac
        done ;;
    use)
        NEW="${2:-}"
        if [ -z "$NEW" ] || ! is_known "$NEW"; then
            echo "用法:ai use <名字>(可选:$KNOWN)"; exit 1
        fi
        has_agent "$NEW" || { echo "「$NEW」还没安装,先跑:ai-install $NEW"; exit 1; }
        mkdir -p "$CONF_DIR"; echo "$NEW" > "$CONF_DIR/default-agent"
        echo "默认 agent 已换成:$NEW(现在起双击「AI 助手」就是它)"
        exit 0 ;;
esac

if [ -n "${1:-}" ] && is_known "$1"; then
    A="$1"; shift
    run_agent "$A" "$@"
fi

if [ ! -f "$CONF_DIR/default-agent" ]; then
    echo "首次使用,先做一次配置(1 分钟)…"
    bash /opt/agent-kit/scripts/configure.sh || exit 1
fi
run_agent "$(cat "$CONF_DIR/default-agent" 2>/dev/null || echo opencode)" "$@"
LAUNCHER
chmod +x /usr/local/bin/ai

cat > /usr/local/bin/ai-install <<'EOF'
#!/usr/bin/env bash
# 追加安装一个 agent:ai-install <opencode|kimi|claude|qwen|codex|gemini|hermes|openclaw|goose>
set -u
if [ -z "${1:-}" ]; then
    echo "用法:ai-install <名字>"
    echo "可选:opencode kimi claude qwen codex gemini hermes openclaw goose"
    exit 1
fi
exec sudo bash /opt/agent-kit/scripts/setup.sh --agents "$1" --agents-only
EOF
chmod +x /usr/local/bin/ai-install

cat > /usr/local/bin/ai-config <<'EOF'
#!/usr/bin/env bash
exec bash /opt/agent-kit/scripts/configure.sh "$@"
EOF
chmod +x /usr/local/bin/ai-config

cat > /usr/local/bin/ai-video <<'EOF'
#!/usr/bin/env bash
exec bash /opt/agent-kit/scripts/video2text.sh "$@"
EOF
chmod +x /usr/local/bin/ai-video

ok "命令已安装:ai(启动)/ ai-config(改配置)/ ai-video(转文字)/ ai-install(加装 agent)"

# ---------- 6. 可选:本地语音转写(faster-whisper) ----------
if [ "$WITH_ASR" -eq 1 ]; then
    step "安装本地语音转写(faster-whisper,首次转写时还会自动下载约 500MB 模型)…"
    VENV=/opt/agent-kit-asr
    if [ ! -x "$VENV/bin/python" ]; then
        python3 -m venv "$VENV"
    fi
    retry 3 "$VENV/bin/pip" install -q -i https://pypi.tuna.tsinghua.edu.cn/simple faster-whisper
    chmod -R a+rX "$VENV"
    ok "本地转写就绪(无硅基流动 Key 时自动使用)"
fi

# ---------- 7. 用户级安装(工作区/配置) ----------
if [ "$AGENTS_ONLY" -eq 0 ]; then
    step "初始化 $KIT_USER 的工作区与配置…"
    WIN_DOCS_WSL=""
    if [ -n "$WIN_DOCS" ]; then
        case "$WIN_DOCS" in
            /*) WIN_DOCS_WSL="$WIN_DOCS" ;;                      # 已是 WSL 路径(测试环境)
            *)  WIN_DOCS_WSL="$(wslpath -u "$WIN_DOCS" 2>/dev/null || true)" ;;
        esac
    fi
    runuser -u "$KIT_USER" -- env WIN_USER="$WIN_USER" WIN_DOCS_WSL="$WIN_DOCS_WSL" \
        bash "$KIT_DIR/scripts/setup-user.sh"
fi

printf '\n'
ok "安装完成。已就绪的 agent:"
for c in opencode claude kimi qwen codex gemini hermes openclaw goose; do
    if command -v "$c" >/dev/null 2>&1 \
       || runuser -u "$KIT_USER" -- bash -lc "command -v $c" >/dev/null 2>&1; then
        printf '      · %s\n' "$c"
    fi
done
