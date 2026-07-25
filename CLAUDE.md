# wsl-agent-kit

给非程序员 Windows 用户的 AI 办公助手一键安装包(合成版):WSL2 检测安装 + Ubuntu 初始化 + 9 选 N 的 agent 菜单(opencode/kimi/claude/qwen/codex/gemini/hermes/openclaw/goose)+ 中文办公工作区。面向国内网络与国内 AI Key。

## 结构

```
install.bat → scripts/install.ps1   # Windows 侧:WSL/Ubuntu/用户/agent 选择/快捷方式,调 setup.sh
scripts/setup.sh                    # WSL root:镜像源/apt/Node22/所选 agents/命令入口(ai*4);--agents/--agents-only
scripts/setup-user.sh               # WSL 用户:工作区(建在 Win 文档目录+软链 ~/workspace)/路径注入/shell 配置
scripts/configure.sh                # ai-config:服务商向导 → env + default-agent + opencode.json + Claude 接线
scripts/video2text.sh + transcribe_local.py   # ai-video:SenseVoice API / 本地 faster-whisper
workspace-template/                 # 复制到 ~/workspace;AGENTS.md 是 agent 行为规范(各家共读)
config-template/                    # opencode/qwen 基础配置、kimi provider 示例、env 样例
docs/                               # RESEARCH(选型调研)/ PROVIDERS / USAGE / TROUBLESHOOTING
```

## 硬约束

- **幂等**:所有脚本必须可重复运行;用户已有文件一律不覆盖(rsync --ignore-existing / 存在即跳过)
- **行尾**:.sh/.py/.md 必须 LF(.gitattributes 已锁);install.ps1 需 UTF-8 **带 BOM**(PowerShell 5.1 中文)
- **兼容**:install.ps1 只用 PowerShell 5.1 语法;bash 脚本过 shellcheck
- **无个人信息**:仓库公开发行,禁提交任何 Key/姓名/内部路径
- 价格/模型名等时效信息只进 docs/,并带「核对于日期」

## 测试(改脚本后必跑)

```bash
# shellcheck
docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:stable -x -S warning -f gcc scripts/*.sh tests/*.sh
# Ubuntu 24.04 容器模拟 WSL 全流程(建 uid1000 用户 + 伪 /mnt/c),跑两遍验证幂等
bash tests/smoke-container.sh
# PowerShell 语法解析
docker run --rm -v "$PWD:/mnt" mcr.microsoft.com/powershell:lts-ubuntu-22.04 \
  pwsh -c '$e=$null;[System.Management.Automation.Language.Parser]::ParseFile("/mnt/scripts/install.ps1",[ref]$null,[ref]$e)|Out-Null;$e'
```

真实 Windows/WSL 端到端(WSL 安装、OOBE、OAuth、快捷方式)无法在容器覆盖,发版前需真机过一遍。

## 发布

GitHub:Oldcircle/wsl-agent-kit(public,使用者靠 Download ZIP 安装)。改完 → 测试 → commit → push 即发布,无构建产物。
