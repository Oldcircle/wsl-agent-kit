# AI 办公助手一键安装包(Windows · 合成版)

给非程序员的开箱即用方案:在 Windows 上一键装好 **WSL2 + Ubuntu + 你自选的 AI Agent + 中文办公工作区**。2026 年当红的 9 个 agent 任选(OpenCode / Claude Code / Kimi Code / Qwen Code / Codex / Gemini CLI / Hermes「爱马仕」/ OpenClaw「小龙虾」/ Goose),共享同一套工作区与规范,随时换、随时加。专为「文件整理、文案撰写、调研、短视频分析」四类日常工作设计,国内 API Key 即插即用。

- 装什么、为什么这么选:[docs/RESEARCH.md](docs/RESEARCH.md)(2026-07 完整选型调研)
- 国内 AI 账号怎么开通:[docs/PROVIDERS.md](docs/PROVIDERS.md)
- 装好后怎么用:[docs/USAGE.md](docs/USAGE.md)
- 出问题查:[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

## 三步安装

> 前提:Windows 10 22H2 或 Windows 11,管理员账号,预留 6GB 磁盘。全程 10-20 分钟,大部分在等下载。

1. **下载本仓库**:点本页绿色 `Code` 按钮 → `Download ZIP` → 解压到任意位置(如 `D:\ai-kit`)
2. **双击 `install.bat`**,弹管理员授权点「是」。中途会让你**勾选要装哪些 agent**(直接回车 = 推荐组合:OpenCode + Claude Code + Kimi Code)
   - 若提示「需要重启」:重启电脑后**再次双击 install.bat**,会自动续装
3. 装完自动进入**配置向导**:按提示选你开通的 AI 服务(没开通先看 [docs/PROVIDERS.md](docs/PROVIDERS.md):图便宜办 DeepSeek Key,图省心买 Kimi ¥49/月 会员登录即用),向导会把 Key 自动接到你选的 agent 上

完成后桌面出现「**AI 助手**」图标,双击即用。所有脚本可重复运行,装坏了重跑 `install.bat` 即可。

## 可选的 9 个 Agent

| # | Agent | 定位 | Key 要求 | 备注 |
|---|-------|------|---------|------|
| 1 | **OpenCode** | 任务型·主推 | 任意 OpenAI/Anthropic 兼容 Key | 16 万+ star,开源里最好用;必装(兜底启动器) |
| 2 | **Claude Code** | 任务型·全网最火 | DeepSeek/GLM/Kimi 兼容端点或 Anthropic 官方 | ⚠️ 闭源;各家国产端点官方支持接入 |
| 3 | **Kimi Code** | 任务型·中文零 Key | Kimi 会员 OAuth(¥49/月起)| 中文界面,自带联网搜索 |
| 4 | Qwen Code | 任务型 | 任意 OpenAI 兼容 Key | 阿里通义生态 |
| 5 | Codex CLI | 任务型 | OpenAI Key(国内 Key 需手工配)| 进阶 |
| 6 | Gemini CLI | 任务型 | Google 账号/Key | ⚠️ 需海外网络 |
| 7 | **Hermes Agent** 爱马仕 | 常驻助理 | 任意 Key(20+ 服务商)| 22 万+ star,自我进化技能+长期记忆 |
| 8 | **OpenClaw** 小龙虾 🦞 | 常驻助理 | 任意 Key | 38 万+ star;消息通道型;安全注意见 docs |
| 9 | Goose | 通用 agent | 任意 OpenAI 兼容 Key | Block 出品;安装源在 GitHub,网络需畅通 |

装后随时追加:终端里 `ai-install <名字>`(如 `ai-install hermes`)。

## 装完你会得到

| 东西 | 说明 |
|------|------|
| WSL2 + Ubuntu 24.04 | AI 的独立工作环境,和 Windows 互不干扰 |
| 你勾选的 agents | 全部共享下面这套工作区与规范,`ai-config` 一键切换默认启动哪个 |
| `~/workspace` 中文工作区 | inbox 收件箱 + 文案/调研/短视频项目区 + 6 套产出模板 + AI 工作规范(AGENTS.md) |
| `win-桌面`/`win-文档`/`win-下载` | 直通 Windows 真实文件夹的桥,AI 可以直接处理你桌面上的文件 |
| `ai` 命令族 | `ai` 启动默认;`ai claude` 临时换人;`ai use kimi` 换默认;`ai list` 看阵容;`ai-config` 改 Key;`ai-video` 转写;`ai-install` 加装 |
| 桌面「AI 助手」 | 自动优先用 Windows Terminal 打开(中文显示/复制粘贴体验更好,缺失时尝试自动安装) |
| ffmpeg + 转写通道 | 短视频→文字稿(硅基流动 SenseVoice 在线,或本地 faster-whisper) |

## 常用参数(给安装人)

在 Ubuntu 内手动重跑安装时:

```bash
sudo bash /opt/agent-kit/scripts/setup.sh --win-user <Windows用户名> \
    [--agents opencode,claude,kimi] [--agents-only] [--with-asr] [--no-mirror]
```

- `--agents`:逗号分隔的安装清单(可选:opencode kimi claude qwen codex gemini hermes openclaw goose)
- `--agents-only`:只装 agent,跳过基础环境(`ai-install` 的底层)
- `--with-asr`:额外安装本地离线语音转写(faster-whisper,适合没有硅基流动 Key 的场景)
- `--no-mirror`:不切换清华 apt 镜像(海外网络时用)

## 安全说明

- API Key 仅存于 WSL 内 `~/.config/agent-kit/env`(权限 600),不上传任何地方
- Agent 默认工作在 WSL 的 `~/workspace`,触达 Windows 文件仅通过三个显式桥接目录;工作区规范(AGENTS.md)要求删除/覆盖前必须清单确认
- 本仓库不含任何账号、密钥、个人信息;安装脚本只从官方源(微软/Ubuntu/清华镜像/npmmirror/各 AI 官网)下载

## 许可证

MIT(见 [LICENSE](LICENSE))。Kimi Code CLI(MIT)、Qwen Code(Apache-2.0)版权归各自项目所有。
