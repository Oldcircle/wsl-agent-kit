# wsl-agent-kit

给非程序员 Windows 用户的 AI 办公助手一键安装包:独立 WSL 发行版 + 9 选 N 的 agent 菜单(opencode/claude/kimi/qwen/codex/gemini/hermes/openclaw/goose)+ 中文办公工作区 + Windows 原生集成(图标/开始菜单/控制台/卸载)。面向国内网络与国内 AI Key,海外网络自动切官方源。

## 结构

```
install.bat → scripts/install.ps1   # Windows 侧总流程(普通用户身份;仅启用 WSL 时经 enable-wsl.ps1 弹 UAC)
scripts/common.ps1                  # Windows 侧公共函数与路径(%LOCALAPPDATA%\AgentKit、发行版查找、快捷方式、测速)
scripts/enable-wsl.ps1              # 管理员:wsl --install → --web-download → DISM 三级回退;-Mode update 升级老 WSL
scripts/console.ps1                 # 「AI 控制台」WinForms 面板(后台线程读 ai status --plain)
scripts/uninstall.ps1               # 卸载(永不删工作区)
scripts/setup.sh                    # WSL root:用户/wsl.conf 合并 → 网络体检与镜像测速(/etc/agent-kit/net.env)
                                    #   → apt → Node24(SHA256)→ bin/* 与 profile.d → agents → setup-user → HTML 指南
scripts/setup-user.sh               # WSL 用户:工作区(Win 文档\AI工作区 + 软链)/v1 目录迁移/托管 AGENTS.md/.bashrc 托管块
scripts/configure.sh                # ai-config:服务商向导 → env(%q 转义)+ default-agent + opencode.json + Claude 接线
scripts/doctor.sh                   # ai doctor:体检报告写入 8-归档/诊断报告.txt(Key 打码)
scripts/video2text.sh + transcribe_local.py   # ai-video:SenseVoice API(>10 分钟自动切段)/ 本地 faster-whisper
scripts/bin/                        # ai / ai-desktop / ai-install / ai-config / ai-video,装到 /usr/local/bin
scripts/lib.sh                      # bash 公共函数(测速选源、托管块、env_line、agent_bin)
workspace-template/                 # 1-收件箱 … 8-归档;AGENTS.md 由安装包维护(改过的旧版备份到 8-归档)
config-template/                    # opencode/qwen/gemini 基础配置、kimi provider 示例、env 样例
assets/icons/ + tools/make_icons.py # 7 个多尺寸 .ico(改图标:uv run --with pillow tools/make_icons.py)
docs/                               # USAGE / PROVIDERS / TROUBLESHOOTING / RESEARCH;安装时 pandoc 转成 HTML 放开始菜单
VERSION                             # 版本号唯一来源
```

## 安装后的落点

- Windows:`%LOCALAPPDATA%\AgentKit\{kit,guide,logs,cache,distro}`;开始菜单「AI 办公助手」;桌面 3 图标;WT fragment;HKCU Uninstall 键
- WSL:发行版 `AI-Assistant`(v1 旧装在 `Ubuntu-24.04` 的原地复用,记录在 `distro-name.txt`);`/opt/agent-kit`、`/etc/agent-kit/`、`/etc/profile.d/agent-kit.sh`、`/var/log/agent-kit/`

## 硬约束

- **幂等**:所有脚本可重复运行;用户文件一律不覆盖(AGENTS.md 例外:安装包维护,改过的先备份)
- **行尾/编码**:.sh/.py/.md/scripts/bin/* 必须 LF(.gitattributes 已锁);.ps1 需 UTF-8 **带 BOM** + CRLF(PowerShell 5.1 中文)
- **兼容**:.ps1 只用 PowerShell 5.1 语法;原生命令用 `$LASTEXITCODE` 判断(`$ErrorActionPreference='Continue'`);传给 wsl 的参数一律 `-e` 形式,别用 `--`(会被 shell 二次解析);要看输出的 wsl 调用别包进有返回值的函数
- **Windows Terminal 命令行里的 `;` 要写成 `\;`**(否则被当成新标签分隔符)
- bash 脚本过 shellcheck;**无个人信息**(公开仓库)
- 价格/模型名等时效信息只进 docs/,并带「核对于日期」

## 测试(改脚本后必跑)

```bash
# shellcheck
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable -x -S warning -f gcc scripts/*.sh scripts/bin/* tests/*.sh
# Ubuntu 24.04 容器模拟 WSL 全流程:v1 旧版升级迁移 + 两遍幂等 + ai-install + configure + doctor(约 5 分钟)
bash tests/smoke-container.sh
# PowerShell 语法解析(全部 .ps1)
docker run --rm -v "$PWD:/mnt" mcr.microsoft.com/powershell:lts-ubuntu-22.04 pwsh -NoProfile -c \
  'foreach($f in Get-ChildItem /mnt/scripts/*.ps1){$e=$null;[System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$null,[ref]$e)|Out-Null;"$($f.Name): $($e.Count)"}'
```

真实 Windows 端到端(UAC、重启续装、镜像导入、快捷方式、WT、OAuth)容器覆盖不了,发版前需真机过一遍,清单见 STATUS.md。

## 发布

GitHub:Oldcircle/wsl-agent-kit(public,使用者靠 Download ZIP 安装)。改完 → 测试 → 改 VERSION → commit → push 即发布,无构建产物。

## 活跃文档

- STATUS.md(进度与真机验证清单)
- docs/*.md(面向使用者)
