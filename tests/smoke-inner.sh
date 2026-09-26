#!/usr/bin/env bash
# 容器内执行:模拟 install.ps1 在 WSL 里做的事,然后跑 setup.sh 两遍并断言结果。
# 覆盖:全新安装路径 + 从 v1 旧版升级(目录迁移/AGENTS.md 备份/.bashrc 旧块替换)+ 幂等。
set -euo pipefail

fail() { echo "❌ 断言失败:$*" >&2; exit 1; }
pass() { echo "✅ $*"; }

# ---- 模拟 install.ps1 的前置动作 ----
# 1) uid=1000 默认用户(ubuntu:24.04 镜像自带 ubuntu 用户;没有则由 --create-user 创建)
KIT_USER="$(getent passwd 1000 | cut -d: -f1 || true)"
[ -n "$KIT_USER" ] || KIT_USER=tester
HOMEDIR="$(getent passwd 1000 | cut -d: -f6 || echo "/home/$KIT_USER")"

# 2) 伪造 Windows 挂载点(桌面在 OneDrive、下载被改到 D 盘)
W=/mnt/c/Users/TestUser
mkdir -p "$W/OneDrive/Desktop" "$W/Documents" /mnt/d/下载 "$W/AppData/Local/AgentKit"

# 3) 复制仓库到 /opt/agent-kit(与 install.ps1 相同)
rm -rf /opt/agent-kit && mkdir -p /opt/agent-kit
cp -r /kit-src/. /opt/agent-kit/
find /opt/agent-kit -type f \( -name '*.sh' -o -name '*.py' -o -name '*.md' -o -name '*.json' \
    -o -name '*.txt' -o -path '*/scripts/bin/*' \) -exec sed -i 's/\r$//' {} +

# ---- 预置 v1 旧版状态:旧目录结构、改过的 AGENTS.md、旧 .bashrc 块、已有 wsl.conf ----
WSD="$W/Documents/AI工作区"
mkdir -p "$WSD/inbox" "$WSD/projects/文案" "$WSD/projects/我的项目" "$WSD/notes" "$WSD/templates" "$WSD/archive"
echo "待处理" > "$WSD/inbox/a.txt"
echo "旧文案" > "$WSD/projects/文案/x.md"
echo "自建" > "$WSD/projects/我的项目/y.md"
echo "我的私货" > "$WSD/notes/_index.md"
echo "2026-07-01" > "$WSD/archive/初次导览已完成.txt"
printf '# 旧规范\n用户自己加的一句\n' > "$WSD/AGENTS.md"
chmod -R a+rwX /mnt/c /mnt/d
printf '[boot]\nsystemd=true\n' > /etc/wsl.conf
if [ -d "$HOMEDIR" ]; then
    cat >> "$HOMEDIR/.bashrc" <<'OLD'

# --- agent-kit ---
export BROWSER=wslview                      # OAuth 登录时自动打开 Windows 浏览器
export HF_ENDPOINT=https://hf-mirror.com     # HuggingFace 国内镜像(本地转写模型用)
export PATH="$HOME/.local/bin:$PATH"
[ -f "$HOME/.config/agent-kit/env" ] && . "$HOME/.config/agent-kit/env"
# 开终端若正处在家目录,自动站到工作区(这样直接敲 opencode/claude 也带上工作区规范)
case $- in *i*) [ "$PWD" = "$HOME" ] && [ -d "$HOME/workspace" ] && cd "$HOME/workspace";; esac

export PATH="$HOME/.kimi-code/bin:$PATH"
OLD
fi

SETUP_ARGS=(--create-user tester --win-docs "$W/Documents" --win-desktop "$W/OneDrive/Desktop"
            --win-downloads /mnt/d/下载 --win-kit-dir "$W/AppData/Local/AgentKit")

# ---- 第 1 遍 ----
echo "=========== 第 1 遍 setup.sh ==========="
bash /opt/agent-kit/scripts/setup.sh "${SETUP_ARGS[@]}"
KIT_USER="$(getent passwd 1000 | cut -d: -f1)"
HOMEDIR="$(getent passwd 1000 | cut -d: -f6)"
WS="$HOMEDIR/workspace"

# ---- 断言:系统层 ----
command -v node >/dev/null || fail "node 未安装"
node -e 'process.exit(+process.versions.node.split(".")[0] >= 20 ? 0 : 1)' || fail "node 版本 < 20"
command -v opencode >/dev/null || fail "opencode 未安装"
command -v claude >/dev/null || fail "claude 未安装(默认组合应含 Claude Code)"
for c in ai ai-config ai-video ai-install ai-desktop; do
    [ -x "/usr/local/bin/$c" ] || fail "缺少命令 $c"
done
pass "Node $(node -v) + OpenCode + Claude Code + ai 系列命令"

grep -q '^systemd=true' /etc/wsl.conf || fail "wsl.conf 原有设置被覆盖"
grep -q "^default = $KIT_USER" /etc/wsl.conf || fail "wsl.conf 缺默认用户"
grep -q 'metadata' /etc/wsl.conf || fail "wsl.conf 缺 metadata 挂载选项"
pass "wsl.conf 合并写入(原有 [boot] 保留)"

[ -f /etc/agent-kit/net.env ] && grep -q '^AGENT_KIT_REGION=' /etc/agent-kit/net.env || fail "net.env 未生成"
[ -f /etc/profile.d/agent-kit.sh ] || fail "profile.d 未安装"
pass "网络体检:$(grep '^AGENT_KIT_REGION' /etc/agent-kit/net.env);软件源 $(grep '^AGENT_KIT_APT' /etc/agent-kit/net.env | cut -d= -f2)"

for b in ffmpeg pandoc pdftotext unar; do command -v "$b" >/dev/null || fail "缺 $b"; done
python3 -c 'import pandas, openpyxl, docx, PIL, matplotlib' || fail "python 办公库缺失"
grep -qi 'Noto Sans CJK' <<<"$(fc-list)" || fail "缺中文字体"
pass "ffmpeg/pandoc/pdftotext/unar + python 办公库 + 中文字体"

# ---- 断言:工作区与迁移 ----
[ -L "$WS" ] && [ "$(readlink "$WS")" = "$WSD" ] || fail "workspace 软链不对:$(readlink "$WS")"
for d in 1-收件箱 2-文案 3-调研 4-短视频 5-文件处理 6-笔记 7-模板 8-归档 .agent-kit; do
    [ -d "$WS/$d" ] || fail "工作区缺少 $d"
done
[ "$(cat "$WS/1-收件箱/a.txt")" = "待处理" ] || fail "inbox 文件没迁过去"
[ "$(cat "$WS/2-文案/x.md")" = "旧文案" ] || fail "文案没迁过去"
[ "$(cat "$WS/6-笔记/笔记索引.md")" = "我的私货" ] || fail "笔记索引被覆盖或没改名"
[ -f "$WS/.agent-kit/初次导览已完成.txt" ] || fail "导览标记没迁移"
[ -f "$WS/projects/我的项目/y.md" ] || fail "用户自建的 projects 子目录被动了"
for d in inbox notes templates archive; do [ ! -e "$WS/$d" ] || fail "旧目录 $d 还在"; done
[ -f "$WS/使用说明.txt" ] || fail "缺 使用说明.txt"
pass "旧版目录迁移到 1-收件箱…8-归档,用户文件全部保留"

grep -q '1-收件箱' "$WS/AGENTS.md" || fail "AGENTS.md 没更新为新版"
grep -q "$W/OneDrive/Desktop" "$WS/AGENTS.md" || fail "AGENTS.md 未注入 OneDrive 桌面路径"
grep -q '/mnt/d/下载' "$WS/AGENTS.md" || fail "AGENTS.md 未注入改过位置的下载路径"
ls "$WS/8-归档/"旧版AI规范-*.md >/dev/null 2>&1 || fail "改过的旧 AGENTS.md 没备份"
grep -q '用户自己加的一句' "$WS"/8-归档/旧版AI规范-*.md || fail "备份内容不对"
pass "AGENTS.md 更新到新版,改过的旧版已备份到 8-归档"

B="$HOMEDIR/.bashrc"
[ "$(grep -c '^# --- agent-kit ---$' "$B")" = 1 ] || fail ".bashrc begin 标记数不为 1"
[ "$(grep -c '^# --- agent-kit end ---$' "$B")" = 1 ] || fail ".bashrc end 标记数不为 1"
grep -q 'HF_ENDPOINT' "$B" && fail ".bashrc 旧块内容没清掉"
grep -q 'kimi-code/bin' "$B" || fail ".bashrc 里别人追加的配置被误删"
pass ".bashrc 旧块替换为托管块,块外内容保留"

jq -e '."$schema"' "$HOMEDIR/.config/opencode/opencode.json" >/dev/null || fail "opencode.json 缺失或非法"
jq -e '.context.fileName | index("AGENTS.md")' "$HOMEDIR/.qwen/settings.json" >/dev/null || fail "qwen 配置不对"
jq -e '.context.fileName | index("AGENTS.md")' "$HOMEDIR/.gemini/settings.json" >/dev/null || fail "gemini 配置不对"
grep -q 'break-system-packages' "$HOMEDIR/.config/pip/pip.conf" || fail "pip.conf 未写"
grep -q '^registry=' "$HOMEDIR/.npmrc" || fail ".npmrc 未写 registry"
pass "OpenCode/Qwen/Gemini/pip/npm 配置就位"

G="$W/AppData/Local/AgentKit/guide"
for d in USAGE PROVIDERS TROUBLESHOOTING; do
    [ -s "$G/$d.html" ] || fail "HTML 指南 $d 没生成"
done
grep -q '<table' "$G/PROVIDERS.html" || fail "HTML 指南没渲染表格"
pass "HTML 版指南已生成"

if runuser -u "$KIT_USER" -- bash -lc 'command -v kimi' >/dev/null 2>&1; then
    pass "Kimi Code 已安装,且登录 shell 能找到(profile.d PATH 生效)"
else
    echo "⚠️  Kimi Code 未装上(容器网络原因可接受;脚本设计为非致命)"
fi

# ---- ai 命令接口 ----
PLAIN="$(runuser -u "$KIT_USER" -- bash -lc 'ai list --plain')"
[ "$(echo "$PLAIN" | wc -l)" -eq 9 ] || fail "ai list --plain 应输出 9 行:$PLAIN"
echo "$PLAIN" | grep -q '^opencode|1|' || fail "--plain 缺 opencode 已装标记"
STATUS="$(runuser -u "$KIT_USER" -- bash -lc 'ai status --plain')"
[ "$(echo "$STATUS" | grep -c '^agent=')" -eq 9 ] || fail "ai status --plain 应含 9 行 agent=:$STATUS"
# 注意:pipefail 下别写「命令 | grep -q」:grep 匹配即退出,前面的命令写输出时收到 SIGPIPE,整条管道会随机判失败
HELP="$(runuser -u "$KIT_USER" -- bash -lc 'ai help')"
grep -q 'ai doctor' <<<"$HELP" || fail "ai help 输出不对"
pass "ai list/status/help 接口正确"

# ---- agents-only 追加安装 ----
echo "=========== ai-install qwen ==========="
runuser -u "$KIT_USER" -- bash -lc 'ai-install qwen'
command -v qwen >/dev/null || fail "ai-install qwen 失败"
runuser -u "$KIT_USER" -- bash -lc 'ai-install 不存在的' >/dev/null 2>&1 && fail "ai-install 应拒绝未知名字"
pass "ai-install 可用,且会拒绝未知名字"

# ---- 第 2 遍(幂等) ----
echo "=========== 第 2 遍 setup.sh(幂等验证) ==========="
count_baks() { local n=0 f; for f in "$WS"/8-归档/旧版AI规范-*.md; do [ -e "$f" ] && n=$((n + 1)); done; echo "$n"; }
BAKS_BEFORE="$(count_baks)"
bash /opt/agent-kit/scripts/setup.sh "${SETUP_ARGS[@]}"
[ "$(grep -c '^# --- agent-kit ---$' "$B")" = 1 ] || fail "第 2 遍后 .bashrc 块重复"
[ "$(cat "$WS/6-笔记/笔记索引.md")" = "我的私货" ] || fail "第 2 遍覆盖了用户文件"
[ "$(count_baks)" = "$BAKS_BEFORE" ] || fail "第 2 遍又多备份了一次 AGENTS.md"
[ "$(grep -c '^default = ' /etc/wsl.conf)" = 1 ] || fail "wsl.conf 默认用户重复写入"
pass "幂等性通过(重复运行无副作用)"

# ---- configure.sh(DeepSeek,Key 里带 $ 和引号;带转写 Key) ----
echo "=========== configure.sh 冒烟 ==========="
CONF="$HOMEDIR/.config/agent-kit"
runuser -u "$KIT_USER" -- bash -c \
    'printf "2\n  sk-te\$t\"x  \n\n\nsf-key-123\n" | bash /opt/agent-kit/scripts/configure.sh' \
    || fail "configure.sh 非交互执行失败"
[ "$(stat -c %a "$CONF/env")" = "600" ] || fail "env 权限不是 600"
got="$(runuser -u "$KIT_USER" -- bash -c '. ~/.config/agent-kit/env; printf %s "$DEEPSEEK_API_KEY"')"
[ "$got" = 'sk-te$tx' ] || fail "Key 清洗/转义不对:[$got]"
[ "$(cat "$CONF/default-agent")" = "opencode" ] || fail "default-agent 不是 opencode"
jq -e '.provider.deepseek.options.apiKey == "{env:DEEPSEEK_API_KEY}" and .model == "deepseek/deepseek-flash"' \
    "$HOMEDIR/.config/opencode/opencode.json" >/dev/null || fail "opencode.json provider 配置不对"
STATUS="$(runuser -u "$KIT_USER" -- bash -lc 'ai status --plain')"
grep -qx 'claude_wired=1' <<<"$STATUS" || fail "Claude 接线广播失效"
pass "configure:Key 去空格去引号、\$ 安全转义、OpenCode + Claude 同步接线"

# 换一家(硅基流动以外)且转写 Key 直接回车 → 旧转写 Key 保留
runuser -u "$KIT_USER" -- bash -c \
    'printf "4\nsk-bailian\n\n\n" | bash /opt/agent-kit/scripts/configure.sh' >/dev/null || fail "第二次配置失败"
runuser -u "$KIT_USER" -- bash -c '. ~/.config/agent-kit/env; [ "$SILICONFLOW_API_KEY" = sf-key-123 ]' \
    || fail "换服务商后转写 Key 丢了"
# 选「先跳过」→ 原配置不变
runuser -u "$KIT_USER" -- bash -c 'printf "0\n" | bash /opt/agent-kit/scripts/configure.sh' >/dev/null
grep -q DASHSCOPE_API_KEY "$CONF/env" || fail "选跳过把原配置清空了"
pass "换服务商保留转写 Key;选跳过不动原配置"

# ---- 诊断与转写 ----
runuser -u "$KIT_USER" -- bash -lc 'ai doctor' >/dev/null 2>&1 || true
[ -s "$WS/8-归档/诊断报告.txt" ] || fail "ai doctor 没生成报告"
grep -q 'sk-bailian' "$WS/8-归档/诊断报告.txt" && fail "诊断报告里 Key 没打码"
pass "ai doctor 生成报告,Key 已打码"

set +e
OUT="$(runuser -u "$KIT_USER" -- bash -lc 'ai-video /tmp/不存在.mp4' 2>&1)"
set -e
echo "$OUT" | grep -q '找不到文件' || fail "ai-video 参数校验异常:$OUT"
pass "ai-video 参数校验正常"

# ---- 健壮性回归(2026-09 修复的问题) ----
echo "=========== 健壮性回归 ==========="
set +e
OUT="$(bash /opt/agent-kit/scripts/setup.sh --agents 2>&1)"; rc=$?
set -e
[ "$rc" -ne 0 ] && echo "$OUT" | grep -q '缺少取值' || fail "setup.sh 参数缺值没有明确报错:rc=$rc [$OUT]"
pass "setup.sh 参数缺值会明确报错"

# 向导中途被关掉 / 选 Kimi 但安装失败:原 Key 都不能丢,再跑一次也不能丢
runuser -u "$KIT_USER" -- bash -c \
    'printf "2\nsk-keep-me\n\n\n" | bash /opt/agent-kit/scripts/configure.sh' >/dev/null || fail "预置配置失败"
runuser -u "$KIT_USER" -- bash -c \
    '{ printf "2\n"; sleep 5; } | timeout -s INT 2 bash /opt/agent-kit/scripts/configure.sh' >/dev/null 2>&1 || true
grep -q 'sk-keep-me' "$CONF/env" || fail "向导中断后原 Key 丢了"
runuser -u "$KIT_USER" -- bash -c 'printf "0\n" | bash /opt/agent-kit/scripts/configure.sh' >/dev/null
grep -q 'sk-keep-me' "$CONF/env" || fail "中断后再运行向导,原 Key 丢了"
runuser -u "$KIT_USER" -- bash -c 'printf "2\n" | bash /opt/agent-kit/scripts/configure.sh' >/dev/null 2>&1 \
    && fail "非交互下 Key 为空应当报错退出"
grep -q 'sk-keep-me' "$CONF/env" || fail "空 Key 把原配置覆盖了"
ls "$CONF"/.env.new.* >/dev/null 2>&1 && fail "向导退出后残留临时文件"
pass "配置向导:中断/空 Key 都不会破坏原配置,无临时文件残留"

# Windows 用户名里带 & # 的路径写进 AGENTS.md
for u in 'Tom&Jerry' 'A#B'; do
    mkdir -p "/mnt/c/Users/$u/Desktop" "/mnt/c/Users/$u/Documents"; chmod -R a+rwX "/mnt/c/Users/$u"
    runuser -u "$KIT_USER" -- env HOME=/tmp/h-$$ WIN_DOCS_WSL="/mnt/c/Users/$u/Documents" \
        WIN_DESKTOP_WSL="/mnt/c/Users/$u/Desktop" bash -c 'mkdir -p "$HOME" && bash /opt/agent-kit/scripts/setup-user.sh' \
        >/dev/null 2>&1 || fail "用户名含特殊字符 [$u] 时 setup-user.sh 失败"
    grep -qF "/mnt/c/Users/$u/Desktop" "/mnt/c/Users/$u/Documents/AI工作区/AGENTS.md" || fail "AGENTS.md 路径被写坏:[$u]"
    rm -rf "/tmp/h-$$"
done
pass "路径含 & / # 时 AGENTS.md 渲染正确"

# CRLF 的 .bashrc 不出重复块
printf 'alias x=1\r\n' >> "$B"; sed -i 's/$/\r/' "$B"
bash /opt/agent-kit/scripts/setup.sh "${SETUP_ARGS[@]}" --agents opencode >/dev/null 2>&1 || fail "CRLF .bashrc 下重跑失败"
[ "$(grep -c '^# --- agent-kit ---$' "$B")" = 1 ] || fail "CRLF .bashrc 出现重复托管块"
grep -q $'\r' "$B" && fail ".bashrc 里仍有 CR"
pass "CRLF 的 .bashrc 被规范化,托管块不重复"

# 工作区不可用时 ai doctor 仍能出报告
mv "$WS" "$WS.off"
runuser -u "$KIT_USER" -- bash -lc 'ai doctor' >/dev/null 2>&1 || true
[ -s "$HOMEDIR/诊断报告.txt" ] || fail "工作区不可用时 ai doctor 没有出报告"
mv "$WS.off" "$WS"
pass "工作区不可用时 ai doctor 报告存到家目录"

echo ""
echo "全部断言通过 🎉"
