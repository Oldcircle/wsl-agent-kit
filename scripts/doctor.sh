#!/usr/bin/env bash
# ============================================================
#  ai doctor:一键体检。输出同时存成「AI工作区\8-归档\诊断报告.txt」,
#  用户把这个文件发给安装人即可远程定位,Key 已打码。
# ============================================================
set -u
# shellcheck source=lib.sh
. /opt/agent-kit/scripts/lib.sh
# shellcheck source=/dev/null
[ -f "$HOME/.config/agent-kit/env" ] && . "$HOME/.config/agent-kit/env"
# shellcheck source=/dev/null
[ -f /etc/agent-kit/net.env ] && . /etc/agent-kit/net.env

REPORT_DIR="$HOME/workspace/8-归档"
[ -d "$REPORT_DIR" ] || REPORT_DIR="$HOME/workspace"
[ -d "$REPORT_DIR" ] && [ -w "$REPORT_DIR" ] || REPORT_DIR="$HOME"   # 工作区丢了/链接断了也要能出报告
REPORT="$REPORT_DIR/诊断报告.txt"

mask() { local v="$1"; [ ${#v} -le 8 ] && { echo "***"; return; }; echo "${v:0:4}…${v: -4}"; }
line() { printf '%-22s %s\n' "$1" "$2"; }

check_url() { # <名字> <url>
    local t
    if t="$(probe_url "$2" 8)"; then line "  $1" "通 (${t}s)"; else line "  $1" "不通"; fi
}

{
echo "===== AI 办公助手 体检报告 $(date '+%F %T') ====="
line "套件版本" "$KIT_VERSION(已装:$(cat /etc/agent-kit/installed-version 2>/dev/null || echo 未知))"
line "Linux 用户" "$(id -un)"
line "发行版" "$(. /etc/os-release; echo "$PRETTY_NAME") / ${WSL_DISTRO_NAME:-?}"
line "内核" "$(uname -r)"
line "网络区域" "${AGENT_KIT_REGION:-未知}  软件源:${AGENT_KIT_APT:-?}"
line "代理变量" "${HTTPS_PROXY:-${https_proxy:-无}}"
line "DNS" "$(grep -m2 '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | xargs)"
line "磁盘(/)" "$(df -h / | awk 'NR==2{print $4" 可用 / 共 "$2}')"

echo; echo "[工作区]"
WS="$(readlink -f "$HOME/workspace" 2>/dev/null || echo "$HOME/workspace")"
line "  位置" "$WS"
if [ -w "$WS" ]; then line "  可写" "是"; else line "  可写" "否 ← 有问题"; fi
case "$WS" in
    /mnt/*) line "  Windows 路径" "$(wslpath -w "$WS" 2>/dev/null || echo ?)" ;;
    *) line "  Windows 路径" "(不在 Windows 文档里)" ;;
esac

echo; echo "[AI 服务配置]"
line "  默认 agent" "$(cat "$HOME/.config/agent-kit/default-agent" 2>/dev/null || echo 未配置)"
line "  OpenCode 模型" "$(jq -r '.model // "未配置"' "$HOME/.config/opencode/opencode.json" 2>/dev/null || echo 未配置)"
for v in DEEPSEEK_API_KEY ZHIPU_API_KEY DASHSCOPE_API_KEY SILICONFLOW_API_KEY MOONSHOT_API_KEY CUSTOM_API_KEY; do
    [ -n "${!v:-}" ] && line "  $v" "$(mask "${!v}")"
done
[ -n "${ANTHROPIC_BASE_URL:-}" ] && line "  Claude 接到" "$ANTHROPIC_BASE_URL ($ANTHROPIC_MODEL)"
[ -n "${OPENAI_BASE_URL:-}" ] && line "  OpenAI 兼容" "$OPENAI_BASE_URL ($OPENAI_MODEL)"

echo; echo "[已装 agent]"
for a in $KNOWN_AGENTS; do
    if b="$(agent_bin "$a")"; then
        v="$(timeout 10 "$b" --version 2>/dev/null | head -1)"
        line "  $a" "${v:-已装}"
    fi
done

echo; echo "[网络连通](国内服务不通=本机网络问题;海外不通在国内属正常)"
check_url "软件源" "${AGENT_KIT_APT:-https://mirrors.tuna.tsinghua.edu.cn/ubuntu}/dists/noble/Release"
check_url "npm 镜像" "${npm_config_registry:-https://registry.npmmirror.com}"
check_url "DeepSeek" "https://api.deepseek.com"
check_url "Kimi" "https://code.kimi.com"
check_url "Moonshot" "https://api.moonshot.cn"
check_url "智谱" "https://open.bigmodel.cn"
check_url "阿里百炼" "https://dashscope.aliyuncs.com"
check_url "硅基流动" "https://api.siliconflow.cn"
check_url "GitHub(海外)" "https://github.com"
check_url "Anthropic(海外)" "https://api.anthropic.com"

if [ -n "${OPENAI_BASE_URL:-}" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' -m 15 -H "Authorization: Bearer $OPENAI_API_KEY" "$OPENAI_BASE_URL/models" 2>/dev/null || echo 000)"
    case "$code" in
        200) r="有效" ;; 401|403) r="被拒绝($code)← Key 可能填错/过期,运行 ai-config 重填" ;;
        000) r="连不上" ;; *) r="返回 $code(不一定有问题)" ;;
    esac
    echo; line "[Key 验证]" "$r"
fi

echo; echo "[最近安装日志]"
tail -n 15 /var/log/agent-kit/setup.log 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^/  /' || echo "  (无)"
} 2>&1 | tee "$REPORT.tmp"
echo
if sed 's/\x1b\[[0-9;]*m//g' "$REPORT.tmp" > "$REPORT" 2>/dev/null; then
    rm -f "$REPORT.tmp"
    case "$REPORT_DIR" in
        "$HOME") ok "体检报告已保存:$REPORT(工作区不可用,存在了 Linux 家目录;Key 已打码)" ;;
        *) ok "体检报告已保存:AI工作区 → $(basename "$REPORT_DIR") → 诊断报告.txt(Key 已打码,可以放心发给安装人)" ;;
    esac
else
    rm -f "$REPORT.tmp"
    warn "体检报告没能保存(上面的内容可以直接截图发给安装人)"
fi
