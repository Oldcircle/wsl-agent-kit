#!/usr/bin/env bash
# 公共函数库:被 setup.sh / setup-user.sh / configure.sh / video2text.sh 引用

C_RESET='\033[0m'; C_CYAN='\033[36m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_RED='\033[31m'

step() { printf "\n${C_CYAN}==> %s${C_RESET}\n" "$*"; }
ok()   { printf "${C_GREEN}    [OK] %s${C_RESET}\n" "$*"; }
warn() { printf "${C_YELLOW}    [!] %s${C_RESET}\n" "$*"; }
die()  { printf "\n${C_RED}[失败] %s${C_RESET}\n" "$*" >&2; exit 1; }

# retry <次数> <命令...>
retry() {
    local n=$1 i=1; shift
    while true; do
        "$@" && return 0
        if [ "$i" -ge "$n" ]; then return 1; fi
        warn "第 $i 次失败,3 秒后重试:$*"
        sleep 3
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

# 当前发行版里 uid=1000 的用户名(WSL 默认用户)
default_user() { getent passwd 1000 | cut -d: -f1; }
