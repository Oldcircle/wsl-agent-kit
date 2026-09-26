#!/usr/bin/env bash
# 公共函数库:被 setup.sh / setup-user.sh / configure.sh / video2text.sh / bin/* 引用

C_RESET='\033[0m'; C_CYAN='\033[36m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_RED='\033[31m'
C_DIM='\033[2m'

step() { printf "\n${C_CYAN}==> %s${C_RESET}\n" "$*"; }
ok()   { printf "${C_GREEN}    [OK] %s${C_RESET}\n" "$*"; }
warn() { printf "${C_YELLOW}    [!] %s${C_RESET}\n" "$*"; }
note() { printf "${C_DIM}        %s${C_RESET}\n" "$*"; }
die()  { printf "\n${C_RED}[失败] %s${C_RESET}\n" "$*" >&2; exit 1; }

# shellcheck disable=SC2034  # 被 setup.sh / ai / doctor 使用
KIT_VERSION="$(cat /opt/agent-kit/VERSION 2>/dev/null || echo dev)"
# shellcheck disable=SC2034  # 被 setup.sh / ai 使用
KNOWN_AGENTS="opencode claude kimi qwen codex gemini hermes openclaw goose"

# retry <次数> <命令...>
retry() {
    local n=$1 i=1; shift
    while true; do
        "$@" && return 0
        if [ "$i" -ge "$n" ]; then return 1; fi
        warn "第 $i 次失败,5 秒后重试:$*"
        sleep 5
        i=$((i + 1))
    done
}

# 追加一段带标记的内容到文件(幂等:已有标记则跳过)
# append_once <文件> <标记> <内容>
append_once() {
    local file=$1 marker=$2 content=$3
    mkdir -p "$(dirname "$file")"
    touch "$file"
    if ! grep -qF "$marker" "$file"; then
        printf '\n%s\n%s\n' "$marker" "$content" >> "$file"
    fi
}

# 托管块:文件里 <begin>…<end> 之间的内容由本工具维护,每次重写;块外的内容不碰。
# 兼容旧版只有 begin 标记、没有 end 的写法(旧块从 begin 到文件末尾整体替换)。
# write_block <文件> <begin> <end> <内容>
write_block() {
    local file=$1 begin=$2 end=$3 content=$4 tmp has_end=0
    mkdir -p "$(dirname "$file")"
    touch "$file"
    # 先统一去掉 CR:.bashrc 被 Windows 编辑器存成 CRLF 时,标记行对不上会重复加块(bash 本身也读不了 CRLF)
    # --follow-symlinks:.bashrc 可能是 dotfiles 仓库的软链,别把链接替换成普通文件
    sed -i --follow-symlinks 's/\r*$//' "$file"
    grep -qxF "$end" "$file" && has_end=1
    tmp="$(mktemp)"
    # 旧版(v1)块没有 end 标记:只删掉紧跟 begin 的那几行已知内容,别误删后面别人追加的配置
    awk -v b="$begin" -v e="$end" -v has_end="$has_end" '
        $0 == b { skip = 1; next }
        skip && has_end == 1 && $0 == e { skip = 0; next }
        skip && has_end == 0 {
            if ($0 ~ /^(export (BROWSER|HF_ENDPOINT|PATH)=|\[ -f "\$HOME\/\.config\/agent-kit\/env" \]|# |case \$- in)/) next
            skip = 0
        }
        !skip { print }
    ' "$file" > "$tmp"
    # 去掉末尾多余空行,再追加新块
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp"
    printf '\n%s\n%s\n%s\n' "$begin" "$content" "$end" >> "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

# 往 env 文件写一行 export,值用 %q 转义(Key 里有 $ " 空格也安全)
# env_line <变量名> <值>
env_line() { printf 'export %s=%q\n' "$1" "$2"; }

# 测一个地址的响应耗时(秒,小数);不通返回非 0。只取前 32KB,不会真下完大文件。
# probe_url <url> [超时秒]
probe_url() {
    local out code t
    if ! command -v curl >/dev/null 2>&1; then
        # 极简系统还没有 curl:退而测 TCP 建连耗时(bash 自带 /dev/tcp)
        local rest host port t0 t1
        rest="${1#*://}"; host="${rest%%/*}"; port=443
        case "$1" in http://*) port=80 ;; esac
        t0="$(date +%s%N)"
        timeout "${2:-6}" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null || return 1
        t1="$(date +%s%N)"
        awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", (b-a)/1e9}'
        return 0
    fi
    out="$(curl -s -o /dev/null -r 0-32767 -m "${2:-6}" -w '%{http_code} %{time_total}' "$1" 2>/dev/null)" || return 1
    code="${out%% *}"; t="${out##* }"
    case "$code" in 2*|3*) printf '%s' "$t" ;; *) return 1 ;; esac
}

# 从候选里挑最快能通的;打印选中的那个。候选格式:"<名字>=<探测URL>"
# pick_fastest <候选...>
pick_fastest() {
    local best="" best_t="" c name url t
    for c in "$@"; do
        name="${c%%=*}"; url="${c#*=}"
        t="$(probe_url "$url")" || continue
        if [ -z "$best_t" ] || awk -v a="$t" -v b="$best_t" 'BEGIN{exit !(a<b)}'; then
            best="$name"; best_t="$t"
        fi
    done
    [ -n "$best" ] || return 1
    printf '%s' "$best"
}

# 当前发行版里 uid=1000 的用户名(WSL 默认用户)
default_user() { getent passwd 1000 | cut -d: -f1; }

# 某个 agent 是否已安装(含装在用户目录里的那几个)
agent_bin() { # <agent名> → 打印可执行文件路径
    local a=$1 c d
    local cands=("$a")
    [ "$a" = "kimi" ] && cands=(kimi kimi-code)
    for c in "${cands[@]}"; do
        if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi
        for d in "$HOME/.local/bin" "$HOME/.kimi-code/bin" "$HOME/.hermes/bin"; do
            if [ -x "$d/$c" ]; then printf '%s' "$d/$c"; return 0; fi
        done
    done
    return 1
}
