# 选型调研:哪个开源 Agent 适合非程序员的中文办公场景?

> 调研日期:**2026-07-25**。AI 圈变化极快,超过 3 个月请重新核对关键事实(尤其价格和免费额度)。
> 需求画像:Windows 用户,非程序员;日常 = 文件整理处理、文案撰写、调研、短视频分析;API 用国内可付费的服务。
> 选型标准(定稿):**不限国内外项目,好用优先,支持自带 API Key 即可**。

## 结论

| 角色 | 选择 | 一句话理由 |
|------|------|-----------|
| **主推** | **OpenCode**(sst/anomaly,MIT,16 万+ star) | 当前公认最好用的开源终端 agent:TUI 打磨最佳、供应商无关设计、任意 OpenAI/Anthropic 兼容 Key 直插、原生 AGENTS.md |
| **并装备选** | **Kimi Code CLI**(MoonshotAI,MIT) | 零 Key 路线:Kimi 会员 OAuth 登录即用(¥49/月),中文界面,内置联网搜索,中文写作口碑最好 |
| 并装备选 2 | **Claude Code**(Anthropic,闭源) | 全网最火;DeepSeek/GLM/Kimi 的 Anthropic 兼容端点均官方支持接入,国内 Key 直接用 |
| 自选 6 家 | Qwen Code / Codex / Gemini CLI / **Hermes(爱马仕)** / **OpenClaw(小龙虾)** / Goose | 合成版菜单,见下文「全景」表 |
| GUI 伴侣(可选) | Cherry Studio(开源桌面客户端) | 想要「聊天窗口」而非终端时装它;但它是客户端不是自主 agent |

本安装包为**合成版**:安装时勾选要装哪些(回车=推荐组合 OpenCode+Claude Code+Kimi Code),之后 `ai-install <名字>` 随时追加;`ai-config` 根据「你的 Key + 已装 agent」自动接线并设定默认启动。

**OpenCode 的已知中文瑕疵(如实记录)**:①界面/文档是英文(对话用中文无碍);②Windows *原生*控制台 GBK 场景下 CJK 乱码(官方 closed as not planned)——本包走 WSL + 建议 Windows Terminal,不踩此坑;③个别 IME 组合输入场景有回车误发报告。若她实际使用中输入体验差,`ai-config` 一键切 Kimi Code(中文原生)即可,两者读同一份工作区规范。

## 评分矩阵(5 分制;「好用优先」权重按定稿标准)

| 维度(权重) | OpenCode | Kimi Code | Qwen Code | OpenManus | Open Interpreter |
|---|---|---|---|---|---|
| Agent 能力与 TUI 品质(×3) | **5**(公认标杆:会话管理/撤销/LSP/主题/子agent) | 4 | 4 | 3 | 3 |
| 任意 API Key 支持(×2) | **5**(供应商无关设计,自定义 baseURL+`{env:}`) | 3(Kimi 为主,第三方可配) | 5(内置多家) | 4 | 3 |
| 非程序员上手门槛 | 3(英文 TUI,但装好即用) | **5**(OAuth 登录,零 Key,中文界面) | 4 | 2 | 3 |
| 中文输入/界面 | 3(界面英文;WSL+Windows Terminal 下输入正常) | **5** | **5** | 3 | 3 |
| 调研能力(联网搜索) | 4(webfetch 内置;搜索靠模型/MCP) | **5**(内置 moonshot_search/fetch) | 2(内置搜索已移除,需 MCP+国外 Key) | 4 | 2 |
| 文件/办公处理 | **5** | 5 | 5 | 3 | 4 |
| 短视频分析潜力 | 4(配多模态模型可读图) | **5**(K3 原生视觉+ReadMediaFile) | 4 | 3 | 3 |
| 安装与维护成本 | 4(npm 一行,国内镜像可达) | **5**(单二进制一行命令) | 4(需 Node 22+) | 2 | 3 |
| 项目活跃与背书 | **5**(16 万+ star,发版极勤) | 5(月之暗面官方) | 5(26k+ star) | 3(社区维护) | 3 |
| 开源许可证 | MIT | MIT | Apache-2.0 | MIT | AGPL |

## 关键事实核查(截至 2026-07-25)

1. **OpenCode**:由 sst/anomaly 团队维护(160k+ star),供应商无关;自定义供应商用 `opencode.json` 的 `provider.<id>` 块(`npm: "@ai-sdk/openai-compatible"` 或 `"@ai-sdk/anthropic"` + `options.baseURL` + `apiKey: "{env:VAR}"`),默认模型 `"model": "id/模型名"`。已知 CJK 议题:Windows 原生控制台 GBK 乱码(#14768,not planned)、中文 UI i18n 尚在请求中(#32514)——WSL+Windows Terminal 环境不受前者影响。
2. **iFlow CLI 已死**:官方 README 明示 2026-04-17 停服。网上大量 2025 年教程仍在推荐它,**不要再装**。
2. **Qwen Code 免费 OAuth 额度已关停**(2026-04-15 起),现在必须自带 Key 或买阿里套餐。同样,忽略过时教程里「每天 2000 次免费」的说法。
3. **Kimi CLI 已升级为 Kimi Code CLI**(旧仓库 MoonshotAI/kimi-cli 处于迁移期,新仓库 MoonshotAI/kimi-code,MIT,单二进制发行)。登录方式:Kimi 账号 OAuth(绑定 Kimi Code Plan 会员额度)或 Moonshot 开放平台 API Key。配置文件 `~/.kimi-code/config.toml` 支持 anthropic/openai 型第三方供应商。内置工具含 `moonshot_search` / `moonshot_fetch`(联网搜索与网页抓取)、`ReadMediaFile`(读图/媒体)。
4. **DeepSeek 已是 V4 时代**:`deepseek-chat`/`deepseek-reasoner` 旧名 **2026-07-24 起废弃**,新模型名 `deepseek-v4-flash`(超便宜,$0.14/M 输入)与 `deepseek-v4-pro`;OpenAI 兼容端点 `https://api.deepseek.com`,Anthropic 兼容 `https://api.deepseek.com/anthropic`。
5. **Kimi Code Plan**:¥49(Andante)/ ¥99(Moderato,含 K3)/ ¥199(Allegretto)每月,额度按 7 天周期滚动刷新。K3(2026-07-16 发布)原生视觉、1M 上下文。
6. **GLM**:GLM-5.2(2026-06-16,MIT 开放权重);Coding Plan 包月 ¥20-49 起,专用 Anthropic 兼容端点 `https://open.bigmodel.cn/api/anthropic`;按量则走 `https://open.bigmodel.cn/api/paas/v4`。智谱另发布了自家桌面端 harness **ZCode**(2026-07,主打编程,本场景未选)。

## 广泛扫描:2026 当红 agent 全景(合成版菜单依据)

> 用户可自选安装,以下是每个候选的入册理由与注意事项(星数为 2026-07 前后公开报道口径,以仓库实时为准)。

**任务型 CLI(在终端里替你干活)**

| Agent | 热度 | 开源 | 国内 Key | 入册理由 / 注意 |
|-------|------|------|---------|----------------|
| OpenCode | 16 万+ ★ | MIT | ✅ 任意兼容端点 | 开源任务型标杆,本包主推与兜底 |
| Claude Code | 事实标准 | ❌ 闭源 | ✅ DeepSeek/GLM/Kimi 官方兼容端点 | 全网最火 agent;DeepSeek 官方文档即有接入页;闭源但免费使用 |
| Kimi Code | 月之暗面官方 | MIT | ✅ 会员 OAuth / API Key | 中文零 Key 路线;内置联网搜索 |
| Qwen Code | 26k+ ★ | Apache-2.0 | ✅ | 通义生态;免费额度已停 |
| Codex CLI | OpenAI 官方 | Apache-2.0 | ⚠️ 需手工配第三方 profile | 优秀但对非 OpenAI Key 的体验一般,标注「进阶」 |
| Gemini CLI | Google 官方 | Apache-2.0 | ❌ 需海外网络+Google 账号 | 全球爆款,但大陆环境不友好,标注「进阶」 |

**常驻助理型(住在电脑/消息软件里的私人助理)**

| Agent | 热度 | 开源 | 入册理由 / 注意 |
|-------|------|------|----------------|
| **OpenClaw**(小龙虾 🦞) | **38 万+ ★**(2026-05,GitHub 史上最快) | 开源 | 现象级个人助理,消息通道(WhatsApp/Telegram/Discord)为核心玩法。⚠️ 两点注意:国内这些通道基本不可用,建议只用本机模式;其技能市场存在供应链安全争议(TheNewStack 等有专文),**非程序员默认别装社区技能** |
| **Hermes Agent**(爱马仕) | **22 万+ ★**(2026-02 发布,全球第 20) | MIT | Nous Research 出品;自我进化技能 + 跨会话长期记忆 + 40+ 内置工具;TUI + 网关双形态;20+ 服务商自带 Key 即用;安装器自动处理 Python/Node 依赖 |
| Goose | Block 出品 | Apache-2.0 | 通用 agent 老牌选手;安装源在 GitHub,国内网络可能失败(脚本已做非致命处理) |

常驻型对非程序员是「进阶玩法」:能力上限高(记忆、主动性、多平台),但心智负担和安全面也更大。本包默认组合只含任务型(OpenCode+Claude Code+Kimi Code),常驻型自选。

## 未入菜单者与原因

- **OpenManus**:Manus 母公司变故后由社区维护(v0.3.0,2026-04);Python + 配置门槛高,浏览器自动化强但办公文件场景不顺手。
- **Open Interpreter**:转型桌面 agent 后仍活跃,但生态与文档投入明显弱于大厂官方 CLI 和两大现象级项目;AGPL 许可证也更麻烦。
- **OpenHands / Suna / Coze Studio / Dify**:平台级方案,要 Docker 甚至多服务编排,超出「一台 Windows 笔记本 + 一个人」的运维能力。
- **Cherry Studio**:非常好用的开源 LLM 桌面客户端(智能体/知识库/MCP),但定位是聊天客户端,做不了「自己动手改文件、跑命令」的 agent 工作,故列为伴侣而非主角。
- **Crush(charmbracelet)/ ZCode(智谱)**:各有拥趸,但与已入册的同类(OpenCode / Claude Code 系)高度重叠,暂不扩菜单。

## 为什么坚持 WSL(而不是 Windows 原生跑)

1. 两个 CLI 的工具生态(bash/ripgrep/ffmpeg/python)在 Linux 侧完整且稳定,Windows 原生路径分隔符/编码坑多;
2. agent 有一定「误操作半径」,关在 WSL 里 + 只通过 `win-*` 符号链接触达 Windows 真实文件,风险面小得多;
3. 与安装人(维护者)自己的开发环境同构,远程排障成本低。

## 主要信息来源

- [QwenLM/qwen-code](https://github.com/QwenLM/qwen-code) · [Qwen Code 文档](https://qwenlm.github.io/qwen-code-docs/)
- [MoonshotAI/kimi-code](https://github.com/MoonshotAI/kimi-code) · [Kimi Code 文档](https://www.kimi.com/code/docs/) · [Kimi Code 配置文件](https://www.kimi.com/code/docs/kimi-code-cli/configuration/config-files.html)
- [iflow-ai/iflow-cli(停服公告)](https://github.com/iflow-ai/iflow-cli)
- [DeepSeek 定价与模型](https://api-docs.deepseek.com/quick_start/pricing)
- [Kimi 开放平台模型列表](https://platform.kimi.com/docs/models) · [Kimi Code Plan 对比](https://coding-plan.org/plans/kimi)
- [智谱 Coding Plan 快速开始](https://docs.bigmodel.cn/cn/coding-plan/quick-start) · [MetaGLM/glm-cookbook](https://github.com/MetaGLM/glm-cookbook)
- [SiliconFlow 转写 API](https://docs.siliconflow.cn/en/api-reference/audio/create-audio-transcriptions)
- [sst/opencode](https://github.com/sst/opencode) · [OpenCode Providers 文档](https://opencode.ai/docs/providers/) · [CJK 乱码议题 #14768](https://github.com/anomalyco/opencode/issues/14768) · [中文 i18n 请求 #32514](https://github.com/anomalyco/opencode/issues/32514)
- [openclaw/openclaw](https://github.com/openclaw/openclaw) · [OpenClaw 安全讨论(TheNewStack)](https://thenewstack.io/openclaw-github-stars-security/) · [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) · [DeepSeek 官方 Claude Code 接入](https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code/)
- [FoundationAgents/OpenManus](https://github.com/FoundationAgents/OpenManus) · [Ubuntu on WSL 安装文档](https://documentation.ubuntu.com/wsl/latest/howto/install-ubuntu-wsl2/)
