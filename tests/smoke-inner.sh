#!/usr/bin/env bash
# 容器内执行:模拟 install.ps1 在 WSL 里做的事,然后跑 setup.sh 两遍并断言结果。
set -euo pipefail

fail() { echo "❌ 断言失败:$*" >&2; exit 1; }
pass() { echo "✅ $*"; }

# ---- 模拟 install.ps1 的前置动作 ----
# 1) uid=1000 默认用户(ubuntu:24.04 镜像自带 ubuntu 用户;没有则创建)
if ! getent passwd 1000 >/dev/null; then
    useradd -m -s /bin/bash -u 1000 tester
fi
KIT_USER="$(getent passwd 1000 | cut -d: -f1)"

# 2) 伪造 Windows 挂载点(含 OneDrive 重定向场景)
mkdir -p "/mnt/c/Users/TestUser/OneDrive/Desktop" \
         "/mnt/c/Users/TestUser/Documents" \
         "/mnt/c/Users/TestUser/Downloads"

# 3) 复制仓库到 /opt/agent-kit 并去 CRLF(与 install.ps1 相同)
rm -rf /opt/agent-kit && mkdir -p /opt/agent-kit
cp -r /kit-src/. /opt/agent-kit/
find /opt/agent-kit -type f \( -name '*.sh' -o -name '*.py' -o -name '*.md' -o -name '*.toml' \
    -o -name '*.json' -o -name '*.txt' \) -exec sed -i 's/\r$//' {} +
chmod +x /opt/agent-kit/scripts/*.sh

# ---- 预置一个用户文件,验证不被覆盖 ----
runuser -u "$KIT_USER" -- bash -c 'mkdir -p ~/workspace/notes && echo "我的私货" > ~/workspace/notes/_index.md'

# ---- 第 1 遍 ----
echo "=========== 第 1 遍 setup.sh ==========="
bash /opt/agent-kit/scripts/setup.sh --win-user TestUser

# ---- 断言 ----
HOMEDIR="$(getent passwd 1000 | cut -d: -f6)"

command -v node >/dev/null || fail "node 未安装"
node -e 'process.exit(+process.versions.node.split(".")[0] >= 20 ? 0 : 1)' || fail "node 版本 < 20"
pass "Node $(node -v)"

command -v opencode >/dev/null || fail "opencode 未安装"
pass "OpenCode $(opencode --version 2>/dev/null | head -1 || echo '(版本命令不可用,但二进制存在)')"

command -v claude >/dev/null || fail "claude 未安装(默认组合应含 Claude Code)"
pass "Claude Code $(claude --version 2>/dev/null | head -1 || echo '(二进制存在)')"

for c in ai ai-config ai-video ai-install; do
    [ -x "/usr/local/bin/$c" ] || fail "缺少命令 $c"
done
pass "ai / ai-config / ai-video / ai-install 就位"

for d in inbox projects/文案 projects/调研 projects/短视频分析 notes templates archive; do
    [ -e "$HOMEDIR/workspace/$d" ] || fail "工作区缺少 $d"
done
[ -f "$HOMEDIR/workspace/AGENTS.md" ] || fail "缺少 AGENTS.md"
pass "工作区脚手架完整"

[ "$(cat "$HOMEDIR/workspace/notes/_index.md")" = "我的私货" ] || fail "用户已有文件被覆盖!"
pass "用户已有文件未被覆盖(--ignore-existing 生效)"

[ -L "$HOMEDIR/workspace/win-桌面" ] || fail "win-桌面 符号链接缺失"
[ "$(readlink "$HOMEDIR/workspace/win-桌面")" = "/mnt/c/Users/TestUser/OneDrive/Desktop" ] \
    || fail "win-桌面 未优先指向 OneDrive 桌面"
[ -L "$HOMEDIR/workspace/win-文档" ] || fail "win-文档 缺失"
[ -L "$HOMEDIR/workspace/win-下载" ] || fail "win-下载 缺失"
pass "Windows 目录桥接正确(含 OneDrive 优先)"

jq -e '."$schema"' "$HOMEDIR/.config/opencode/opencode.json" >/dev/null \
    || fail "opencode.json 缺失或非法"
jq -e '.context.fileName | index("AGENTS.md")' "$HOMEDIR/.qwen/settings.json" >/dev/null \
    || fail "qwen settings.json 缺 AGENTS.md 上下文配置"
pass "opencode.json / qwen settings.json 合法"

grep -c 'agent-kit ---' "$HOMEDIR/.bashrc" | grep -qx 1 || fail ".bashrc 标记数不为 1"
grep -q 'BROWSER=wslview' "$HOMEDIR/.bashrc" || fail ".bashrc 缺 BROWSER"
pass ".bashrc 配置写入 1 次"

grep -q npmmirror "$HOMEDIR/.npmrc" || fail ".npmrc 未设国内镜像"
pass ".npmrc 镜像就位"

ffmpeg -version >/dev/null 2>&1 || fail "ffmpeg 未安装"
python3 -c 'import pandas, openpyxl, docx' || fail "python 办公三件套缺失"
pass "ffmpeg + pandas/openpyxl/docx 就位"

if command -v kimi >/dev/null 2>&1 || command -v kimi-code >/dev/null 2>&1 \
   || runuser -u "$KIT_USER" -- bash -lc 'command -v kimi || command -v kimi-code' >/dev/null 2>&1; then
    pass "Kimi Code 已安装"
else
    echo "⚠️  Kimi Code 未装上(容器网络原因可接受;真机需复核;脚本设计为非致命)"
fi

# ---- agents-only 追加安装(ai-install 的底层路径) ----
echo "=========== agents-only 追加安装 qwen ==========="
bash /opt/agent-kit/scripts/setup.sh --agents qwen --agents-only
command -v qwen >/dev/null || fail "agents-only 方式安装 qwen 失败"
pass "ai-install 底层路径可用(qwen 已装上)"

# ---- 第 2 遍(幂等) ----
echo "=========== 第 2 遍 setup.sh(幂等验证) ==========="
bash /opt/agent-kit/scripts/setup.sh --win-user TestUser

grep -c 'agent-kit ---' "$HOMEDIR/.bashrc" | grep -qx 1 || fail "第 2 遍后 .bashrc 标记重复追加"
[ "$(cat "$HOMEDIR/workspace/notes/_index.md")" = "我的私货" ] || fail "第 2 遍覆盖了用户文件"
pass "幂等性通过(重复运行无副作用)"

# ---- configure.sh 非交互冒烟(DeepSeek 假 Key 全流程) ----
echo "=========== configure.sh 冒烟 ==========="
runuser -u "$KIT_USER" -- bash -c \
    'printf "1\nsk-test-fake-key\n\n\n\n" | bash /opt/agent-kit/scripts/configure.sh' \
    || fail "configure.sh 非交互执行失败"
CONF="$HOMEDIR/.config/agent-kit"
grep -q 'DEEPSEEK_API_KEY="sk-test-fake-key"' "$CONF/env" || fail "env 未写入 DeepSeek Key"
grep -q 'OPENAI_BASE_URL="https://api.deepseek.com/v1"' "$CONF/env" || fail "env 未写入 OPENAI_BASE_URL"
[ "$(stat -c %a "$CONF/env")" = "600" ] || fail "env 权限不是 600"
[ "$(cat "$CONF/default-agent")" = "opencode" ] || fail "default-agent 不是 opencode"
jq -e '.provider.deepseek.options.baseURL == "https://api.deepseek.com/v1"
       and .provider.deepseek.options.apiKey == "{env:DEEPSEEK_API_KEY}"
       and .model == "deepseek/deepseek-v4-flash"' \
    "$HOMEDIR/.config/opencode/opencode.json" >/dev/null || fail "opencode.json provider 配置不对"
pass "configure.sh:env/default-agent/opencode.json 全部正确"

# ---- video2text 无 Key 时的降级提示 ----
set +e
OUT="$(runuser -u "$KIT_USER" -- bash -lc 'ai-video /tmp/不存在.mp4' 2>&1)"
set -e
echo "$OUT" | grep -q '找不到文件' || fail "ai-video 参数校验异常:$OUT"
pass "ai-video 参数校验正常"

echo ""
echo "全部断言通过 🎉"
