#!/usr/bin/env bash
# ============================================================
#  WSL 内安装脚本(root 运行)
#  用法: bash setup.sh [--create-user <名>] [--win-docs <路径>] [--win-desktop <路径>]
#                      [--win-downloads <路径>] [--agents opencode,kimi,claude]
#                      [--agents-only] [--update] [--with-asr] [--mirror auto|cn|global]
#  可装: opencode kimi claude qwen codex gemini hermes openclaw goose
#  流程: 用户与 wsl.conf → 网络体检与镜像选择 → apt 依赖 → Node → 命令入口
#        → 所选 agents → 用户级初始化(工作区/配置)
#  可重复运行(幂等)。日志:/var/log/agent-kit/setup.log
# ============================================================
set -Eeuo pipefail

KIT_DIR="/opt/agent-kit"
# shellcheck source=lib.sh
. "$KIT_DIR/scripts/lib.sh"

[ "$(id -u)" -eq 0 ] || die "setup.sh 需要 root 运行(由 install.bat 自动调用;手动请加 sudo)"

CREATE_USER=""
WIN_USER=""        # 旧参数,保留兼容(路径改由 --win-* 精确传入)
WIN_DOCS=""
WIN_DESKTOP=""
WIN_DOWNLOADS=""
WIN_KIT_DIR=""     # Windows 侧安装目录(%LOCALAPPDATA%\AgentKit),用来放 HTML 版指南
WITH_ASR=0
MIRROR_MODE="auto"
AGENTS_CSV="opencode,claude,kimi"   # 默认推荐组合
AGENTS_ONLY=0
UPDATE_MODE=0
ORIG_ARGS="$*"
# 带值参数缺了值:明确报错(以前 shift 2 失败会被 set -e 静默退出)
need_val() { [ $# -ge 2 ] || die "参数 $1 后面缺少取值"; }
while [ $# -gt 0 ]; do
    case "$1" in
        --create-user)   need_val "$@"; CREATE_USER="$2"; shift 2 ;;
        --win-user)      need_val "$@"; WIN_USER="$2"; shift 2 ;;
        --win-docs)      need_val "$@"; WIN_DOCS="$2"; shift 2 ;;
        --win-desktop)   need_val "$@"; WIN_DESKTOP="$2"; shift 2 ;;
        --win-downloads) need_val "$@"; WIN_DOWNLOADS="$2"; shift 2 ;;
        --win-kit-dir)   need_val "$@"; WIN_KIT_DIR="$2"; shift 2 ;;
        --agents)        need_val "$@"; AGENTS_CSV="${2:-$AGENTS_CSV}"; shift 2 ;;
        --agents-only)   AGENTS_ONLY=1; shift ;;
        --update)        UPDATE_MODE=1; AGENTS_ONLY=1; shift ;;
        --with-asr)      WITH_ASR=1; shift ;;
        --with-qwen)     AGENTS_CSV="$AGENTS_CSV,qwen"; shift ;;
        --mirror)        need_val "$@"; MIRROR_MODE="${2:-auto}"; shift 2 ;;
        --no-mirror)     MIRROR_MODE="global"; shift ;;
        *) warn "忽略未知参数:$1"; shift ;;
    esac
done

# ---------- 0. 日志(全程留档,出问题把这个文件发给安装人) ----------
LOG_DIR=/var/log/agent-kit
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_DIR/setup.log") 2>&1
printf '\n===== %s  setup.sh v%s  %s =====\n' "$(date '+%F %T')" "$KIT_VERSION" "$ORIG_ARGS"

trap 'die "安装在第 $LINENO 行中断。上面的红字/报错就是原因;完整日志在 $LOG_DIR/setup.log。修好后重新运行 install.bat 即可(可重复运行,不会丢文件)。"' ERR

# ---------- 1. 默认用户与 /etc/wsl.conf ----------
# ini_set <文件> <节> <键> <值> [keep]  —— 合并写入,不覆盖文件其他内容;keep=已有该键则保留原值
ini_set() {
    local file=$1 sec=$2 key=$3 val=$4 keep=${5:-} tmp
    touch "$file"; tmp="$(mktemp)"
    awk -v sec="$sec" -v key="$key" -v val="$val" -v keep="$keep" '
        function flush() { if (insec && !done) { print key " = " val; done = 1 } }
        /^[[:space:]]*\[.*\][[:space:]]*$/ {
            flush()
            s = $0; gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", s)
            insec = (s == sec); if (insec) found = 1
            print; next
        }
        insec && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            if (keep != "") print; else print key " = " val
            done = 1; next
        }
        { print }
        END {
            flush()
            if (!found) printf "\n[%s]\n%s = %s\n", sec, key, val
        }
    ' "$file" > "$tmp"
    cat "$tmp" > "$file"; rm -f "$tmp"
}

KIT_USER="$(default_user)"
if [ -z "$KIT_USER" ]; then
    [ -n "$CREATE_USER" ] || die "找不到 uid=1000 的默认用户,也没传 --create-user"
    name="$CREATE_USER"
    # 与系统账号重名/不合法 → 用 worker
    if ! printf '%s' "$name" | grep -Eq '^[a-z][a-z0-9_-]{0,30}$' || getent passwd "$name" >/dev/null; then
        name="worker"
    fi
    step "创建 Ubuntu 用户 $name(免密码 sudo,个人电脑标准配置)"
    useradd -m -u 1000 -s /bin/bash -G sudo "$name"
    KIT_USER="$name"
fi
mkdir -p /etc/sudoers.d
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$KIT_USER" > /etc/sudoers.d/agent-kit
chmod 440 /etc/sudoers.d/agent-kit
ini_set /etc/wsl.conf user default "$KIT_USER"
ini_set /etc/wsl.conf automount options '"metadata"' keep
ok "默认用户:$KIT_USER(/etc/wsl.conf 已合并更新,原有设置保留)"

# ---------- 2. 网络体检:DNS + 镜像选择 ----------
dns_ok() { getent hosts "$1" >/dev/null 2>&1; }
if [ "$AGENTS_ONLY" -eq 0 ] || [ ! -f /etc/agent-kit/net.env ]; then
    step "网络体检…"
    if ! dns_ok mirrors.tuna.tsinghua.edu.cn && ! dns_ok archive.ubuntu.com && ! dns_ok registry.npmmirror.com; then
        warn "域名解析全部失败(常见于公司网络/VPN 改了 DNS),改用公共 DNS 223.5.5.5 / 119.29.29.29"
        ini_set /etc/wsl.conf network generateResolvConf false
        rm -f /etc/resolv.conf
        printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\nnameserver 8.8.8.8\n' > /etc/resolv.conf
        dns_ok registry.npmmirror.com || dns_ok archive.ubuntu.com \
            || die "仍然无法解析域名。请确认电脑能上网;公司网络可能拦截了 WSL,换手机热点再试。"
        ok "DNS 已修复"
    fi

    # shellcheck source=/dev/null
    . /etc/os-release
    CODENAME="${VERSION_CODENAME:-noble}"
    ARCH="$(dpkg --print-architecture)"
    if [ "$ARCH" = "amd64" ]; then UB_PATH=ubuntu; OFFICIAL_APT=http://archive.ubuntu.com/ubuntu
    else UB_PATH=ubuntu-ports; OFFICIAL_APT=http://ports.ubuntu.com/ubuntu-ports; fi

    case "$MIRROR_MODE" in
        cn)     APT_PICK=tuna ;;
        global) APT_PICK=official ;;
        *)      APT_PICK="$(pick_fastest \
                    "tuna=https://mirrors.tuna.tsinghua.edu.cn/$UB_PATH/dists/$CODENAME/Release" \
                    "ustc=https://mirrors.ustc.edu.cn/$UB_PATH/dists/$CODENAME/Release" \
                    "aliyun=https://mirrors.aliyun.com/$UB_PATH/dists/$CODENAME/Release" \
                    "official=$OFFICIAL_APT/dists/$CODENAME/Release")" \
                || die "所有软件源都连不上。请检查网络(能打开网页吗?),然后重跑 install.bat。" ;;
    esac
    # apt 源用 http:全新系统可能还没装 ca-certificates,https 源会证书校验失败、一个包都装不上。
    # 安全性不受影响:apt 靠 GPG 签名校验包,不靠 TLS。
    case "$APT_PICK" in
        tuna)   APT_BASE="http://mirrors.tuna.tsinghua.edu.cn/$UB_PATH" ;;
        ustc)   APT_BASE="http://mirrors.ustc.edu.cn/$UB_PATH" ;;
        aliyun) APT_BASE="http://mirrors.aliyun.com/$UB_PATH" ;;
        *)      APT_BASE="$OFFICIAL_APT" ;;
    esac
    if [ "$APT_PICK" = "official" ]; then REGION=global; else REGION=cn; fi

    if [ "$REGION" = "cn" ]; then
        NPM_REGISTRY="https://registry.npmmirror.com"
        NODE_DIST="https://npmmirror.com/mirrors/node"
        PYPI_INDEX="https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple"
        [ "$APT_PICK" = "aliyun" ] && PYPI_INDEX="https://mirrors.aliyun.com/pypi/simple"
    else
        NPM_REGISTRY="https://registry.npmjs.org"
        NODE_DIST="https://nodejs.org/dist"
        PYPI_INDEX="https://pypi.org/simple"
    fi
    GITHUB_OK=0; probe_url https://github.com 8 >/dev/null && GITHUB_OK=1

    mkdir -p /etc/agent-kit
    {
        echo "# 由 setup.sh 生成:网络区域与镜像(重跑 install.bat 会按当时网络重新测速)"
        echo "AGENT_KIT_REGION=$REGION"
        echo "AGENT_KIT_APT=$APT_BASE"
        echo "AGENT_KIT_NODE_DIST=$NODE_DIST"
        echo "AGENT_KIT_GITHUB_OK=$GITHUB_OK"
        echo "export npm_config_registry=$NPM_REGISTRY"
        echo "export PIP_INDEX_URL=$PYPI_INDEX"
        echo "export UV_DEFAULT_INDEX=$PYPI_INDEX"
        if [ "$REGION" = "cn" ]; then
            echo "export UV_PYTHON_INSTALL_MIRROR=https://registry.npmmirror.com/-/binary/python-build-standalone"
            echo "export HF_ENDPOINT=https://hf-mirror.com"
        fi
    } > /etc/agent-kit/net.env
    chmod 644 /etc/agent-kit/net.env
    ok "网络区域:$([ "$REGION" = cn ] && echo 国内 || echo 海外);软件源:$APT_PICK;GitHub:$([ "$GITHUB_OK" = 1 ] && echo 可访问 || echo 不通)"
fi
# shellcheck source=/dev/null
. /etc/agent-kit/net.env
NPM_REGISTRY="${npm_config_registry:-https://registry.npmmirror.com}"

if [ "$AGENTS_ONLY" -eq 0 ]; then
# ---------- 3. apt 源 ----------
if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    SRC=/etc/apt/sources.list.d/ubuntu.sources
else
    SRC=/etc/apt/sources.list
fi
if [ -f "$SRC" ]; then
    [ -f "$SRC.agent-kit.bak" ] || cp "$SRC" "$SRC.agent-kit.bak"
    # 只替换 Ubuntu 官方源/安全源和我们用过的镜像;第三方源(docker 等)不碰
    sed -i -E "s#https?://(([a-z0-9-]+\.)?archive\.ubuntu\.com|security\.ubuntu\.com|ports\.ubuntu\.com|mirrors\.tuna\.tsinghua\.edu\.cn|mirrors\.ustc\.edu\.cn|mirrors\.aliyun\.com)/ubuntu(-ports)?/?#${AGENT_KIT_APT}/#g" "$SRC"
    ok "apt 源:$AGENT_KIT_APT(原文件备份为 $(basename "$SRC").agent-kit.bak)"
fi

# ---------- 4. 基础依赖 ----------
step "安装基础工具(约 2-5 分钟)…"
note "git/curl/ripgrep/jq/ffmpeg/pandoc/pdf 工具/中文字体/python 办公库"
export DEBIAN_FRONTEND=noninteractive
# Error-Mode=any:索引下载失败时返回非 0(默认只打警告、照样返回 0,retry 就形同虚设)
retry 3 apt-get update -qq -o APT::Update::Error-Mode=any
retry 3 apt-get install -y -qq --no-install-recommends \
    ca-certificates curl wget git sudo unzip zip xz-utils unar \
    ripgrep jq rsync file less \
    ffmpeg pandoc poppler-utils fonts-noto-cjk \
    python3 python3-venv python3-pip \
    python3-pandas python3-openpyxl python3-docx python3-pil python3-matplotlib \
    wslu >/dev/null
ok "基础工具就绪"
fi  # AGENTS_ONLY

# ---------- 5. Node.js(镜像直装 + SHA256 校验) ----------
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
    die "尚未完成基础安装(缺 Node),请先运行完整安装(install.bat)"
fi
if [ "$need_node" -eq 1 ]; then
    case "$(uname -m)" in
        x86_64)  narch="linux-x64" ;;
        aarch64) narch="linux-arm64" ;;
        *) die "不支持的 CPU 架构:$(uname -m)" ;;
    esac
    fetch_node() { # <dist根>
        local base=$1 sums fname
        sums="$(curl -fsSL --connect-timeout 15 -m 60 "$base/latest-v24.x/SHASUMS256.txt")" || return 1
        fname="$(printf '%s\n' "$sums" | grep -o "node-v24[0-9.]*-$narch.tar.xz" | head -1)"
        [ -n "$fname" ] || return 1
        note "下载 $fname(约 30MB)…"
        retry 2 curl -fsSL --connect-timeout 15 -o /tmp/node.tar.xz "$base/latest-v24.x/$fname" || return 1
        printf '%s\n' "$sums" | grep " $fname\$" | sed "s# $fname\$# /tmp/node.tar.xz#" \
            | sha256sum -c --status || { warn "Node 安装包校验失败(下载不完整),换源重试"; return 1; }
    }
    step "安装 Node.js 24 LTS…"
    fetch_node "$AGENT_KIT_NODE_DIST" || fetch_node "https://npmmirror.com/mirrors/node" \
        || fetch_node "https://nodejs.org/dist" || die "Node.js 下载失败,请检查网络后重跑"
    rm -rf /usr/local/lib/nodejs
    mkdir -p /usr/local/lib/nodejs
    tar -xJf /tmp/node.tar.xz -C /usr/local/lib/nodejs --strip-components=1
    rm -f /tmp/node.tar.xz
    for b in node npm npx corepack; do
        ln -sfn /usr/local/lib/nodejs/bin/$b /usr/local/bin/$b
    done
    ok "Node $(node -v) 安装完成"
fi
NPM_GBIN="$(npm prefix -g)/bin"

# ---------- 6. 命令入口 + 登录环境 ----------
step "安装 ai 系列命令…"
for f in "$KIT_DIR"/scripts/bin/*; do
    install -m 0755 "$f" "/usr/local/bin/$(basename "$f")"
done
# 登录 shell 公共环境。非交互的 bash -lc(「AI 控制台」、桌面图标)也会读到,
# 所以装在用户目录里的 agent(kimi/goose/hermes)和 Key 在任何入口都可见。
cat > /etc/profile.d/agent-kit.sh <<'PROFILE'
# agent-kit:登录环境(由 setup.sh 维护,重装会覆盖)
for _d in "$HOME/.kimi-code/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in *":$_d:"*) ;; *) [ -d "$_d" ] && PATH="$_d:$PATH" ;; esac
done
unset _d
export PATH
[ -r /etc/agent-kit/net.env ] && . /etc/agent-kit/net.env
# Claude Code 装在系统目录,普通用户自动更新会报权限错;统一用「ai update」升级
export DISABLE_AUTOUPDATER=1
export BROWSER=wslview
[ -r "$HOME/.config/agent-kit/env" ] && . "$HOME/.config/agent-kit/env"
PROFILE
chmod 644 /etc/profile.d/agent-kit.sh
ok "命令:ai / ai-config / ai-install / ai-video(详见 ai help)"

# ---------- 7. 安装所选 agents ----------
# npm 系:install_npm_agent <npm包> <命令名> <显示名>
install_npm_agent() {
    local pkg="$1" bin="$2" name="$3"
    if [ "$UPDATE_MODE" -eq 0 ] && command -v "$bin" >/dev/null 2>&1; then
        ok "$name 已安装,跳过(升级用 ai update)"
        return 0
    fi
    note "从 $NPM_REGISTRY 下载 $pkg …"
    if ! retry 3 npm install -g "$pkg@latest" \
        --registry="$NPM_REGISTRY" --no-fund --no-audit --loglevel=error >/dev/null; then
        warn "$name 安装失败(稍后可 ai-install $bin 重试)"
        return 1
    fi
    [ -x "$NPM_GBIN/$bin" ] && ln -sfn "$NPM_GBIN/$bin" "/usr/local/bin/$bin"
    if command -v "$bin" >/dev/null 2>&1; then ok "$name 就绪"; else warn "$name 装完找不到命令 $bin"; fi
}

# 官方脚本系(装在用户目录):install_user_script_agent <名字> <命令> <需要GitHub 0/1> <安装命令>
install_user_script_agent() {
    local name="$1" bin="$2" need_gh="$3" script="$4"
    if [ "$UPDATE_MODE" -eq 0 ] && runuser -u "$KIT_USER" -- bash -lc "command -v $bin" >/dev/null 2>&1; then
        ok "$name 已安装,跳过"
        return 0
    fi
    if [ "$need_gh" = "1" ] && [ "${AGENT_KIT_GITHUB_OK:-0}" != "1" ] && ! probe_url https://github.com 8 >/dev/null; then
        warn "$name 需要访问 GitHub,当前网络连不上,已跳过(开了代理/换网络后:ai-install $bin)"
        return 1
    fi
    if runuser -u "$KIT_USER" -- bash -lc "$script" </dev/null; then
        ok "$name 就绪"
    else
        warn "$name 安装失败(多为网络原因;稍后可 ai-install $bin 重试)"
    fi
}

install_one_agent() {
    case "$1" in
        opencode) step "OpenCode(主推)"
                  install_npm_agent "opencode-ai" "opencode" "OpenCode" \
                      || die "主推 agent OpenCode 安装失败,请检查网络后重跑" ;;
        claude)   step "Claude Code"
                  install_npm_agent "@anthropic-ai/claude-code" "claude" "Claude Code" || true ;;
        qwen)     step "Qwen Code"
                  install_npm_agent "@qwen-code/qwen-code" "qwen" "Qwen Code" || true ;;
        codex)    step "Codex CLI"
                  install_npm_agent "@openai/codex" "codex" "Codex CLI" || true ;;
        gemini)   step "Gemini CLI"
                  install_npm_agent "@google/gemini-cli" "gemini" "Gemini CLI" || true ;;
        openclaw) step "OpenClaw(小龙虾 🦞)"
                  install_npm_agent "openclaw" "openclaw" "OpenClaw" || true
                  if command -v openclaw >/dev/null 2>&1; then
                      note "首次使用需运行 openclaw onboard 完成引导(见 docs/USAGE.md)"
                  fi ;;
        kimi)     step "Kimi Code"
                  install_user_script_agent "Kimi Code" "kimi" 0 \
                      'curl -fsSL --connect-timeout 20 https://code.kimi.com/kimi-code/install.sh | bash' ;;
        hermes)   step "Hermes Agent(爱马仕)"
                  if [ "$UPDATE_MODE" -eq 1 ] && runuser -u "$KIT_USER" -- bash -lc 'command -v hermes' >/dev/null 2>&1; then
                      runuser -u "$KIT_USER" -- bash -lc 'hermes update' </dev/null || warn "Hermes 更新失败"
                  else
                      install_user_script_agent "Hermes Agent" "hermes" 1 \
                          'curl -fsSL --connect-timeout 20 https://hermes-agent.nousresearch.com/install.sh | bash'
                  fi ;;
        goose)    step "Goose"
                  install_user_script_agent "Goose" "goose" 1 \
                      'curl -fsSL --connect-timeout 20 https://github.com/block/goose/releases/latest/download/download_cli.sh | CONFIGURE=false bash' ;;
        *)        warn "未知 agent:$1(可选:$KNOWN_AGENTS)" ;;
    esac
}

if [ "$UPDATE_MODE" -eq 1 ]; then
    # 升级模式:只动已经装了的
    AGENTS_CSV=""
    for a in $KNOWN_AGENTS; do
        if command -v "$a" >/dev/null 2>&1 || runuser -u "$KIT_USER" -- bash -lc "command -v $a" >/dev/null 2>&1; then
            AGENTS_CSV="$AGENTS_CSV,$a"
        fi
    done
    step "升级已安装的 agent:${AGENTS_CSV#,}"
fi
for a in $(echo "$AGENTS_CSV" | tr ',' ' '); do
    install_one_agent "$a"
done

# ---------- 8. 可选:本地语音转写(faster-whisper) ----------
if [ "$WITH_ASR" -eq 1 ]; then
    step "安装本地语音转写(faster-whisper,首次转写时还会下载约 500MB 模型)…"
    VENV=/opt/agent-kit-asr
    [ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
    retry 3 "$VENV/bin/pip" install -q -i "$PIP_INDEX_URL" faster-whisper
    chmod -R a+rX "$VENV"
    ok "本地转写就绪(无硅基流动 Key 时自动使用)"
fi

# ---------- 9. 用户级安装(工作区/配置) ----------
to_wsl_path() { # Windows 路径 → /mnt/x/…;已是 Linux 路径原样返回
    case "$1" in
        "") return 0 ;;
        /*) printf '%s' "$1" ;;
        *)  wslpath -u "$1" 2>/dev/null || true ;;
    esac
}
if [ "$AGENTS_ONLY" -eq 0 ]; then
    step "初始化 $KIT_USER 的工作区与配置…"
    runuser -u "$KIT_USER" -- env \
        WIN_USER="$WIN_USER" \
        WIN_DOCS_WSL="$(to_wsl_path "$WIN_DOCS")" \
        WIN_DESKTOP_WSL="$(to_wsl_path "$WIN_DESKTOP")" \
        WIN_DOWNLOADS_WSL="$(to_wsl_path "$WIN_DOWNLOADS")" \
        bash "$KIT_DIR/scripts/setup-user.sh"
    echo "$KIT_VERSION" > /etc/agent-kit/installed-version
fi

# ---------- 10. HTML 版指南(开始菜单里点开就是网页;.md 在 Windows 上双击常常打不开) ----------
if [ -n "$WIN_KIT_DIR" ] && command -v pandoc >/dev/null 2>&1; then
    GUIDE_DIR="$(to_wsl_path "$WIN_KIT_DIR")/guide"
    if mkdir -p "$GUIDE_DIR" 2>/dev/null; then
        for doc in USAGE PROVIDERS TROUBLESHOOTING RESEARCH; do
            title="$(head -1 "$KIT_DIR/docs/$doc.md" | sed 's/^# *//')"
            pandoc "$KIT_DIR/docs/$doc.md" -f gfm -s --metadata pagetitle="$title" \
                -H "$KIT_DIR/docs/guide-style.html" -o "$GUIDE_DIR/$doc.html" 2>/dev/null \
                && sed -i -E 's#href="([A-Z]+)\.md#href="\1.html#g' "$GUIDE_DIR/$doc.html" \
                || warn "指南 $doc 生成失败(不影响使用)"
        done
        ok "HTML 版指南已生成(开始菜单 → AI 办公助手)"
    fi
fi

printf '\n'
ok "完成。已就绪的 agent:"
for c in $KNOWN_AGENTS; do
    if command -v "$c" >/dev/null 2>&1 \
       || runuser -u "$KIT_USER" -- bash -lc "command -v $c" >/dev/null 2>&1; then
        printf '      · %s\n' "$c"
    fi
done
