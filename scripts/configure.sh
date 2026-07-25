#!/usr/bin/env bash
# ============================================================
#  配置向导:选服务商 → 填 Key → 设默认 agent → 测试连通
#  随时可重跑:终端输入 ai-config
#  产物: ~/.config/agent-kit/env(Key)
#        ~/.config/agent-kit/default-agent(opencode|kimi|qwen)
#        ~/.config/opencode/opencode.json(OpenCode 供应商与默认模型)
# ============================================================
set -euo pipefail

KIT_DIR="/opt/agent-kit"
# shellcheck source=lib.sh
. "$KIT_DIR/scripts/lib.sh"

CONF_DIR="$HOME/.config/agent-kit"
ENV_FILE="$CONF_DIR/env"
mkdir -p "$CONF_DIR"

OC_CONF="$HOME/.config/opencode/opencode.json"
[ -f "$OC_CONF" ] || { mkdir -p "$HOME/.config/opencode"; cp "$KIT_DIR/config-template/opencode-base.json" "$OC_CONF"; }

# ---------- 工具函数 ----------
ask() { # ask <提示> <变量名> [默认值]
    local prompt="$1" var="$2" def="${3:-}" val=""
    if [ -n "$def" ]; then
        read -r -p "$prompt(回车用默认:$def): " val || true
        val="${val:-$def}"
    else
        read -r -p "$prompt: " val || true
    fi
    printf -v "$var" '%s' "$val"
}

test_openai_endpoint() { # <baseUrl> <key> → 打印结果,不中断
    local base="$1" key="$2" code
    printf "    正在测试连通性…"
    code="$(curl -s -o /dev/null -w '%{http_code}' -m 15 -H "Authorization: Bearer $key" "$base/models" 2>/dev/null || echo 000)"
    case "$code" in
        200) printf "\r"; ok "Key 有效,连接正常                      " ;;
        401|403) printf "\r"; warn "服务商返回 $code:Key 可能填错了(可重跑 ai-config 改)" ;;
        000) printf "\r"; warn "网络不通或超时(不一定是 Key 问题;实际使用时再观察)" ;;
        *)   printf "\r"; warn "返回 $code:无法确认(有些服务商没有该测试接口,不一定有问题)" ;;
    esac
}

# 写一个 provider 进 OpenCode 配置,并设为默认模型
# add_opencode_provider <id> <显示名> <npm包> <baseURL> <env变量名> <key值> <模型ID>
add_opencode_provider() {
    local id="$1" name="$2" npmpkg="$3" base="$4" envkey="$5" key="$6" model="$7"
    {
        echo "export $envkey=\"$key\""
        # 兼容层:Qwen Code(可选装)走 OpenAI 兼容三件套
        if [ "$npmpkg" = "@ai-sdk/openai-compatible" ]; then
            echo "export OPENAI_API_KEY=\"$key\""
            echo "export OPENAI_BASE_URL=\"$base\""
            echo "export OPENAI_MODEL=\"$model\""
        fi
    } >> "$ENV_FILE"
    local tmp
    tmp="$(mktemp)"
    jq --arg id "$id" --arg name "$name" --arg npm "$npmpkg" --arg base "$base" \
       --arg envref "{env:$envkey}" --arg model "$model" \
       '.provider[$id] = {npm:$npm, name:$name, options:{baseURL:$base, apiKey:$envref}, models:{($model):{name:$model}}}
        | .model = ($id + "/" + $model)' \
       "$OC_CONF" > "$tmp" && mv "$tmp" "$OC_CONF"
    echo "opencode" > "$CONF_DIR/default-agent"
    ok "OpenCode 已配置:$name / $model"
}

# Claude Code 接线(各家官方支持的 Anthropic 兼容端点)
wire_claude() { # <anthropic_base> <key> <model>
    {
        echo "export ANTHROPIC_BASE_URL=\"$1\""
        echo "export ANTHROPIC_AUTH_TOKEN=\"$2\""
        echo "export ANTHROPIC_MODEL=\"$3\""
        echo "export ANTHROPIC_SMALL_FAST_MODEL=\"$3\""
        echo "export API_TIMEOUT_MS=600000"
        echo "export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
    } >> "$ENV_FILE"
    echo "claude" > "$CONF_DIR/default-agent"
    ok "Claude Code 已接线:$3"
}

# 该服务商同时有 Anthropic 兼容端点时,让用户选启动界面
pick_agent_for_anthropic() { # <anthropic_base> <key> <model> [rec=claude]
    command -v claude >/dev/null 2>&1 || return 0   # 没装 Claude Code 就维持 OpenCode
    local pick
    if [ "${4:-}" = "claude" ]; then
        printf '\n该套餐官方主打的用法就是接 Claude Code(全网最火 agent,闭源)。\n'
        ask "用哪个界面打开?1=Claude Code(推荐) 2=OpenCode" pick "1"
        if [ "$pick" != "2" ]; then wire_claude "$1" "$2" "$3"; fi
    else
        printf '\n这家服务商也能接到 Claude Code(全网最火 agent,闭源)。\n'
        ask "用哪个界面打开?1=OpenCode(推荐) 2=Claude Code" pick "1"
        if [ "$pick" = "2" ]; then wire_claude "$1" "$2" "$3"; fi
    fi
}

# ---------- 开始 ----------
printf '\n'
printf '┌──────────────────────────────────────────────┐\n'
printf '│           AI 助手配置向导(1 分钟)           │\n'
printf '└──────────────────────────────────────────────┘\n'
cat <<'MENU'

你打算用哪家 AI?(不知道选什么就看括号里的说明)

  1) DeepSeek         ← 推荐:便宜好用,充 ¥10 能用很久
  2) Kimi 会员套餐    ← 最省心:不碰 API Key,登录即用;¥49/月起,中文写作强
  3) 智谱 GLM(按量或 Coding Plan 包月)
  4) 阿里云百炼(通义千问)
  5) 硅基流动 SiliconFlow(一个 Key 用多家模型,还带语音转写)
  6) Moonshot 开放平台(Kimi 按量付费,不买会员)
  7) 其他 OpenAI 兼容服务(自己填地址/模型/Key;中转站也走这里)
  0) 暂不配置,先看看

  各家 Key 怎么申请:见仓库 docs/PROVIDERS.md(step by step)
MENU
ask "输入序号" CHOICE "1"

# 重新生成 env(旧的备份)
[ -f "$ENV_FILE" ] && cp "$ENV_FILE" "$ENV_FILE.bak"
: > "$ENV_FILE"
chmod 600 "$ENV_FILE"

case "$CHOICE" in
    1)
        ask "粘贴 DeepSeek API Key(sk-开头)" KEY
        ask "模型" MODEL "deepseek-v4-flash"
        add_opencode_provider "deepseek" "DeepSeek" "@ai-sdk/openai-compatible" \
            "https://api.deepseek.com/v1" "DEEPSEEK_API_KEY" "$KEY" "$MODEL"
        test_openai_endpoint "https://api.deepseek.com/v1" "$KEY"
        pick_agent_for_anthropic "https://api.deepseek.com/anthropic" "$KEY" "$MODEL"
        ;;
    2)
        echo "kimi" > "$CONF_DIR/default-agent"
        ok "已设为 Kimi Code。"
        printf '\n接下来:启动 AI 助手后,首次会让你选登录方式 → 选 OAuth/浏览器登录,\n'
        printf 'Windows 浏览器会自动弹出,用 Kimi 账号(手机号)登录即可。\n'
        printf '会员购买入口与套餐说明:docs/PROVIDERS.md 第 2 节。\n'
        ;;
    3)
        ask "你用的是哪种?a=按量付费(普通 API Key) b=Coding Plan 包月套餐" GLMKIND "a"
        ask "粘贴智谱 API Key" KEY
        ask "模型" MODEL "glm-5.2"
        if [ "$GLMKIND" = "b" ]; then
            add_opencode_provider "zhipu" "智谱GLM(CodingPlan)" "@ai-sdk/anthropic" \
                "https://open.bigmodel.cn/api/anthropic" "ZHIPU_API_KEY" "$KEY" "$MODEL"
            pick_agent_for_anthropic "https://open.bigmodel.cn/api/anthropic" "$KEY" "$MODEL" "claude"
        else
            add_opencode_provider "zhipu" "智谱GLM" "@ai-sdk/openai-compatible" \
                "https://open.bigmodel.cn/api/paas/v4" "ZHIPU_API_KEY" "$KEY" "$MODEL"
            test_openai_endpoint "https://open.bigmodel.cn/api/paas/v4" "$KEY"
            pick_agent_for_anthropic "https://open.bigmodel.cn/api/anthropic" "$KEY" "$MODEL"
        fi
        ;;
    4)
        ask "粘贴百炼 API Key(sk-开头)" KEY
        ask "模型" MODEL "qwen-max"
        add_opencode_provider "dashscope" "阿里百炼" "@ai-sdk/openai-compatible" \
            "https://dashscope.aliyuncs.com/compatible-mode/v1" "DASHSCOPE_API_KEY" "$KEY" "$MODEL"
        test_openai_endpoint "https://dashscope.aliyuncs.com/compatible-mode/v1" "$KEY"
        ;;
    5)
        ask "粘贴硅基流动 API Key(sk-开头)" KEY
        ask "模型" MODEL "deepseek-ai/DeepSeek-V3.2"
        add_opencode_provider "siliconflow" "硅基流动" "@ai-sdk/openai-compatible" \
            "https://api.siliconflow.cn/v1" "SILICONFLOW_API_KEY" "$KEY" "$MODEL"
        test_openai_endpoint "https://api.siliconflow.cn/v1" "$KEY"
        ok "这个 Key 同时用于「视频转文字」(ai-video 命令)"
        ;;
    6)
        ask "粘贴 Moonshot API Key(sk-开头)" KEY
        ask "模型" MODEL "kimi-k2.7-code"
        add_opencode_provider "moonshot" "Moonshot Kimi" "@ai-sdk/openai-compatible" \
            "https://api.moonshot.cn/v1" "MOONSHOT_API_KEY" "$KEY" "$MODEL"
        test_openai_endpoint "https://api.moonshot.cn/v1" "$KEY"
        pick_agent_for_anthropic "https://api.moonshot.cn/anthropic" "$KEY" "$MODEL"
        ;;
    7)
        ask "服务地址 baseUrl(形如 https://xxx/v1)" BASE
        ask "模型名" MODEL
        ask "API Key" KEY
        add_opencode_provider "custom" "自定义" "@ai-sdk/openai-compatible" \
            "$BASE" "CUSTOM_API_KEY" "$KEY" "$MODEL"
        test_openai_endpoint "$BASE" "$KEY"
        ;;
    0)
        warn "跳过配置。之后终端输入 ai-config 随时可配。"
        exit 0
        ;;
    *)
        warn "没有这个选项。重新运行 ai-config 即可。"
        exit 0
        ;;
esac

# ---------- 可选:视频转文字 Key ----------
if [ "$CHOICE" != "5" ]; then
    printf '\n【可选】视频/语音转文字需要一个硅基流动 Key(很便宜,注册送额度;docs/PROVIDERS.md 第 5 节)\n'
    ask "有就粘贴,没有直接回车跳过" SFKEY ""
    if [ -n "${SFKEY:-}" ]; then
        echo "export SILICONFLOW_API_KEY=\"$SFKEY\"" >> "$ENV_FILE"
        ok "视频转文字已启用(命令:ai-video 文件名)"
    fi
fi

printf '\n'
ok "配置完成!"
printf '\n日常使用:双击桌面「AI 助手」,或在终端输入 ai\n'
printf '改配置:终端输入 ai-config\n\n'
