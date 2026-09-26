# AI 办公助手一键安装包(Windows)

给非程序员的开箱即用方案:在 Windows 上一键装好 **WSL2 + Ubuntu + 你自选的 AI Agent + 中文办公工作区**。2026 年当红的 9 个 agent 任选(OpenCode / Claude Code / Kimi Code / Qwen Code / Codex / Gemini CLI / Hermes「爱马仕」/ OpenClaw「小龙虾」/ Goose),共享同一套工作区与规范,随时换、随时加。专为「文件整理、文案撰写、调研、短视频分析」四类日常工作设计,国内网络、国内 AI Key 即插即用。

| 文档 | 给谁看 |
|------|--------|
| [docs/USAGE.md](docs/USAGE.md) 使用教程 | 使用者(装好后开始菜单里有网页版) |
| [docs/PROVIDERS.md](docs/PROVIDERS.md) 开通 AI 账号指南 | 使用者 |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) 常见问题 | 使用者 + 安装人 |
| [docs/RESEARCH.md](docs/RESEARCH.md) 选型调研 | 安装人 |

## 三步安装

> 前提:Windows 10 2004 以上或 Windows 11;C 盘留 6GB。全程 10-20 分钟,大部分时间在下载。

1. **下载**:点本页绿色 `Code` 按钮 → `Download ZIP` → 在下载文件夹里**右键 ZIP → 全部解压**
2. **双击解压出来的 `install.bat`**
   - 如果弹出「Windows 已保护你的电脑」:点「更多信息」→「仍要运行」
   - 中途会出现 **agent 勾选列表**(↑↓ 移动、空格勾选、回车确认;**什么都不动直接回车 = 推荐组合** OpenCode + Claude Code + Kimi Code)
   - 电脑第一次装 WSL 时会弹一次管理员授权(点「是」),并需要**重启一次**;重启登录后安装会**自动继续**
3. 装完自动进入**配置向导**:选你开通的 AI 服务(没开通的先选「跳过」,看开始菜单里的「开通 AI 账号指南」:图便宜办 DeepSeek Key,图省心买 Kimi 会员登录即用)

完成后桌面出现 3 个图标,解压出来的文件夹和 ZIP 可以删掉。装坏了/想升级:开始菜单 →「AI 办公助手」→「修复或升级」(不会丢文件)。

## 装完你会得到

| 位置 | 东西 | 说明 |
|------|------|------|
| 桌面 | **AI 助手** | 和 AI 说话、派活的窗口(Windows Terminal,中文与复制粘贴都顺手) |
| 桌面 | **AI 工作区** | 就是「文档\AI工作区」文件夹,AI 做的东西都在这;Word/Excel/视频双击就看 |
| 桌面 | **AI 控制台** | 原生管理面板:看 9 个 agent 的状态、双击启动任意一个、设默认、加装、一键升级、体检 |
| 开始菜单「AI 办公助手」 | 配置 AI 服务 / 使用教程 / 开通 AI 账号指南 / 常见问题 / 修复或升级 / 卸载 | 教程是网页版,不用认识 .md |
| 设置 → 应用 | AI 办公助手 | 可以像普通软件一样卸载(工作区文件永远保留) |

工作区结构(中文、带序号,资源管理器里按顺序排):

```
文档\AI工作区\
├── 使用说明.txt     一分钟速查卡
├── 1-收件箱\        把要处理的文件拖进来
├── 2-文案\          成品文案(另附可直接复制的 -纯文本.txt)
├── 3-调研\          调研报告(另附 Word 版)
├── 4-短视频\        转写稿 + 拆解报告
├── 5-文件处理\      整理/转换后的表格和文档
├── 6-笔记\          长期笔记 + 我的偏好.md(AI 每次开工先读)
├── 7-模板\          6 套产出模板
└── 8-归档\          AI 从不删文件,过时的挪到这
```

## 网络:国内 / 海外都能装

| 环节 | 做法 |
|------|------|
| Ubuntu 本体 | 从清华/中科大/阿里/华为/官方里测速选最快的,下载官方 WSL 镜像并校验 SHA256 后导入;绕开 `wsl --install` 依赖的 GitHub 列表和微软商店(国内常失败)。失败再回退微软渠道 |
| apt / npm / pip / Node / Python | 安装时测速:国内自动用镜像,海外自动用官方源;Node 下载做 SHA256 校验 |
| DNS | WSL 里域名全解析不了时(公司网络/VPN 常见),自动改用公共 DNS |
| 本机代理 | 检测到 Clash/v2rayN 等本机代理且系统支持时,开启 WSL 镜像网络,代理在 WSL 里直接可用 |
| 需要 GitHub 的 agent | Hermes / Goose 安装前先测 GitHub,连不上就跳过并提示,不会卡住;失败不影响其他 agent |
| 出问题 | `ai doctor` 一键体检(各服务连通性、Key 有效性、配置),报告存进工作区,Key 已打码,可以直接发给安装人 |

## 可选的 9 个 Agent

| # | Agent | 定位 | Key 要求 | 备注 |
|---|-------|------|---------|------|
| 1 | **OpenCode** | 任务型·主推 | 任意 OpenAI/Anthropic 兼容 Key | 开源里最好用;必装(兜底启动器) |
| 2 | **Claude Code** | 任务型·全网最火 | DeepSeek/智谱/Moonshot 兼容端点,或 Anthropic 官方 | ⚠️ 闭源;配置向导自动接国内端点 |
| 3 | **Kimi Code** | 任务型·中文零 Key | Kimi 会员登录 | 中文界面,自带联网搜索 |
| 4 | Qwen Code | 任务型 | 任意 OpenAI 兼容 Key | 阿里通义生态 |
| 5 | Codex CLI | 任务型 | OpenAI Key | 进阶 |
| 6 | Gemini CLI | 任务型 | Google 账号/Key | ⚠️ 需海外网络 |
| 7 | **Hermes Agent** 爱马仕 | 常驻助理 | 任意 Key | 自我进化技能 + 长期记忆;安装需 GitHub |
| 8 | **OpenClaw** 小龙虾 🦞 | 常驻助理 | 任意 Key | 消息通道型;安全注意见常见问题 |
| 9 | Goose | 通用 agent | 任意 OpenAI 兼容 Key | Block 出品;安装需 GitHub |

装后随时追加:控制台里选中点「安装」,或终端里 `ai-install hermes`。

## 怎么发给朋友用(给安装人的话术模板)

> 给你装了个 AI 办公助手,能帮你写文案、做调研、整理文件、拆视频。
> 1️⃣ 点这个链接下载,在下载文件夹里**右键 → 全部解压**:(ZIP 链接)
> 2️⃣ 双击解压出来的 `install.bat`,弹窗点「是」/「仍要运行」,然后等着;要是让重启就重启,开机后会自动接着装
> 3️⃣ 手机装个 Kimi App,买个 Kimi Code 会员(49/月,像买视频会员)
> 装完桌面多三个图标:「AI 助手」是和它说话的,「AI 工作区」是看它干的活的。打开 AI 助手先说:「介绍一下你能帮我做什么」。
> 卡住了:开始菜单找「AI 办公助手」→「常见问题」;还不行就截图发我。

## 给安装人

```bash
ai help                     # 全部命令
ai doctor                   # 体检(远程排障先让对方跑这个,报告在 8-归档\诊断报告.txt)
ai update                   # 升级所有已装 agent
sudo bash /opt/agent-kit/scripts/setup.sh --agents-only --agents opencode --with-asr   # 加装本地离线转写
sudo bash /opt/agent-kit/scripts/setup.sh --mirror global   # 强制用官方源(默认 auto 自动测速)
```

- Windows 侧日志:`%LOCALAPPDATA%\AgentKit\logs\`;WSL 侧日志:`/var/log/agent-kit/setup.log`(安装失败时会自动拷到 Windows 侧并打开所在文件夹)
- AI 运行环境是一个独立的 WSL 发行版 `AI-Assistant`(装在 `%LOCALAPPDATA%\AgentKit\distro`),不碰你自己已有的 Ubuntu;v1 旧版装在 `Ubuntu-24.04` 的会原地升级、继续使用

## 安全说明

- API Key 仅存于 WSL 内 `~/.config/agent-kit/env`(权限 600),不上传任何地方;`ai doctor` 报告里的 Key 已打码
- 工作区规范(AGENTS.md)要求:删除/覆盖前先列清单确认,「删除」默认改为移到 8-归档;对桌面/下载等真实目录从严执行
- 只从官方源或知名镜像下载(微软 / Ubuntu / 清华·中科大·阿里·华为镜像 / npmmirror / 各 AI 官网),关键安装包做 SHA256 校验
- 本仓库不含任何账号、密钥、个人信息

## 许可证

MIT(见 [LICENSE](LICENSE))。各 agent 版权归各自项目所有。
