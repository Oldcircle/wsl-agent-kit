# STATUS

## 当前状态

v1.0.0 合成版:选型调研完成(docs/RESEARCH.md,2026-07-25,含 9 个当红 agent 全景);安装时可自选 agent(默认组合 OpenCode+Claude Code+Kimi Code),`ai-install` 可追加;`ai-config` 按「Key + 已装 agent」自动接线(含 DeepSeek/GLM/Moonshot → Claude Code 的 Anthropic 兼容端点)。容器冒烟测试通过(shellcheck + Ubuntu24.04 双跑幂等 + agents-only 路径 + configure 非交互 + ps1 语法解析)。

## 下次入口

1. **真机验证**(容器测不到的):真实 Windows 完整跑 install.bat——WSL 安装/重启续装、agent 多选、Kimi OAuth 浏览器弹出、Claude Code 接 DeepSeek 端点实测一轮对话、桌面快捷方式
2. 真机通过后把 Download ZIP 链接 + docs/PROVIDERS.md 发给使用者
3. 待观察:hermes/goose 安装脚本 URL 稳定性;DeepSeek V4 模型名;OpenClaw 安全议题进展;opencode `{env:}` 配置语法演进

## 已知限制(记录在案)

- WSL 首装需重启一次,靠用户重跑 install.bat 续装(不做 RunOnce 自动续,保持简单可解释)
- Gemini/Codex/Goose/Hermes 的安装或使用依赖海外网络,脚本按非致命处理并在文档标注
- Hermes/OpenClaw 的深度配置(网关/技能)不进向导,定位为「安装人陪同的进阶玩法」;OpenClaw 文档中明确提示技能市场供应链风险
- 抖音链接直接下载不做(合规+接口不稳),流程按「用户自行保存视频文件」设计
