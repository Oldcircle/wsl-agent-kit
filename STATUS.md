# STATUS

## 当前状态

v2.0 整体重构完成,容器冒烟通过,**尚未真机验证**。相对 v1 的变化:

- **安装位置**:安装包复制到 `%LOCALAPPDATA%\AgentKit\kit`,图标/控制台/修复/卸载都指向这里,删掉下载的 ZIP 不再断链
- **权限**:整个脚本以普通用户运行,只在启用/升级 WSL 时单独弹 UAC(修掉「其他管理员账号提权 → 图标建到别人桌面」)
- **网络**:Ubuntu 从国内镜像测速下载官方 .wsl 并 `wsl --import` 成独立发行版 `AI-Assistant`(SHA256 校验,断点续传);apt/npm/pip/Node 按测速自动选国内镜像或官方源;DNS 全挂时改公共 DNS;检测到本机代理 + Win11 时开 WSL 镜像网络;Hermes/Goose 先测 GitHub,不通就跳过
- **图标与集成**:7 个自绘多尺寸图标;桌面 3 个 + 开始菜单「AI 办公助手」9 项;WT 下拉项;「设置 → 应用」可卸载;工作区文件夹自定义图标,AGENTS.md 等设为隐藏
- **工作区**:改为 `1-收件箱 … 8-归档` 中文序号结构,v1 目录自动迁移;AGENTS.md 由安装包维护(用户偏好改进 `6-笔记/我的偏好.md`),报告同时出 .docx,使用说明改 .txt
- **健壮性**:重启后 RunOnce 自动续装;BIOS 虚拟化预检 + WSL1 兼容模式兜底;`wsl.conf` 合并不覆盖;`.bashrc` 托管块;Key 清洗与 `%q` 转义;换服务商保留转写 Key;选「跳过」不清空配置;Kimi 未装时向导现场补装;GLM Coding Plan 端点修正;Goose 安装不再卡在交互配置;长视频切段转写
- **排障**:`ai doctor` 体检报告(Key 打码);`ai-desktop` 出错停住窗口;安装日志两侧留档,失败时自动打开所在文件夹;`ai update` 一键升级
- **修掉的 v1 bug**:Kimi 装在 `~/.kimi-code/bin`,控制台(非交互 shell)看不到 → 改用 profile.d;控制台「安装」按钮经 WT 时 `;` 被拆成多个标签;AGENTS.md 引用的 pdftotext 实际没装

## 下次入口

1. **真机验证**(容器测不到的,按顺序):
   - 全新 Win11:双击 install.bat → UAC 一次 → 重启后 RunOnce 自动续装 → 镜像下载 + import → 勾选 → 安装 → 图标/开始菜单/WT 下拉项/「设置→应用」条目 → 首次配置
   - 老 Win10(inbox WSL):`--no-distribution` 失败走 DISM 路径 → 重启 → `-Mode update` 升级 WSL
   - 从 v1 升级(已有 Ubuntu-24.04 + 旧工作区):复用发行版、目录迁移、旧图标被覆盖
   - 控制台:打开即显示窗口(后台加载)、各按钮、经 WT 的 `\;` 转义
   - 工作区:desktop.ini 图标生效、隐藏属性、从 WSL 覆盖写被隐藏的 AGENTS.md 是否需要先 `attrib -h`(已做防护)
   - 本机开 Clash 时 mirrored 模式生效;Kimi OAuth;Claude Code 接 DeepSeek 实测一轮对话
   - 卸载两个选项
2. 真机通过后更新 README 截图,把 ZIP 链接发给使用者
3. 待观察:WT `--suppressApplicationTitle` 在旧版 WT 上的兼容性;hermes/goose 安装脚本 URL 稳定性;DeepSeek 模型名

## 已知限制

- Gemini/Codex/Goose/Hermes 的安装或使用依赖海外网络;Win10 上无法自动共用 Windows 代理
- ARM 版 Windows 没有国内镜像导入路径,走微软渠道
- Hermes/OpenClaw 的深度配置不进向导,定位为「安装人陪同的进阶玩法」
- 抖音链接直接下载不做(合规+接口不稳),流程按「用户自行保存视频文件」设计

---

## 归档

- v1.2(2026-07):小白体验七处方、交互勾选列表、AI 控制台、接线广播
- v1.0(2026-07-25):合成版首发,选型调研见 docs/RESEARCH.md
