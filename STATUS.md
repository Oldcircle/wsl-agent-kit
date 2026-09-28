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

### v2.0.1 健壮性修复(2026-09-26)

一轮可用性/健壮性测试后的修复。Linux 侧有容器回归断言(smoke-inner.sh「健壮性回归」段);Windows 侧只过了语法解析与 PSScriptAnalyzer,**需真机验证**(见下方清单带 🆕 的项)。

- **apt 源改 http**:全新系统没有 ca-certificates 时,https 镜像证书校验失败 → 一个包都装不上(国内网络下官方冒烟必挂)。包仍由 GPG 签名校验;`apt-get update` 加 `Error-Mode=any`,失败时 retry 才真正生效
- **配置向导不再丢 Key**:以前选完服务商就清空 env,中途关窗口/Kimi 安装失败会清空配置,再跑一次连 env.bak 也被覆盖。现在写临时文件,走完才替换;非交互下空 Key 直接报错
- **AGENTS.md 路径转义**:Windows 用户名含 `&`/`#` 时路径被写坏或 sed 报错中断安装
- setup.sh 带值参数缺值时明确报错(以前静默退出);CRLF 的 .bashrc 先规范化(以前会重复加托管块);`ai doctor` 工作区不可用时报告落到家目录;ai-video 用法提示换行、认 `C:/…` 路径
- 测试自身:`命令 | grep -q` 在 pipefail 下有 SIGPIPE 竞态(随机误报),改为先存变量
- Windows:重启计数上限 2 次 + 老 wsl.exe 不认 `--status` 时按 LxssManager 服务判就绪(防 DISM 路径无限重启);失败退出清掉 RunOnce/续装图标;WSL 升级 UAC 被拒不再中止安装;老 WSL UTF-16 输出去 NUL 后再匹配虚拟化错误码;勾选列表先占位再定位(WT 滚屏错位);卸载快捷方式不再最小化;SHA256SUMS 优先取 releases.ubuntu.com;开镜像网络前先问再 `wsl --shutdown`;商店版 appx 未注册时用 `ubuntu2404.exe install --root` 补注册;卸载时 unregister 失败保留 distro 目录;控制台刷新防重入、「设为默认」移到后台线程

### v2.0.2 安装卡死修复(2026-09-28)

容器冒烟时实测:npm 连接被重置后既不报错也不退出(单次挂 25 分钟以上),外层 `retry 3` 永远轮不到,安装窗口无声卡死。

- **agent 安装硬超时**:npm 系与官方脚本系(kimi/hermes/goose)单次最长 900 秒(`AGENT_KIT_INSTALL_TIMEOUT` 可调),超时算失败交给 retry;npm 另加 `--fetch-timeout=60000 --fetch-retries=2`
- **sudo 保留代理变量**:`ai-install` / `ai update` / `ai-config` 经 sudo 调 setup.sh,sudo 默认清空环境,用户手动设的 `HTTPS_PROXY` 等会丢 → `/etc/sudoers.d/agent-kit` 加 `env_keep`(`--agents-only` 也会重写,老用户 `ai update` 一次即生效)
- 回归断言:sudo 透传代理变量;假 npm 卡死时限时内报失败且安装继续

## 下次入口

1. **真机验证**(容器测不到的,按顺序):
   - 全新 Win11:双击 install.bat → UAC 一次 → 重启后 RunOnce 自动续装 → 镜像下载 + import → 勾选 → 安装 → 图标/开始菜单/WT 下拉项/「设置→应用」条目 → 首次配置
   - 老 Win10(inbox WSL):`--no-distribution` 失败走 DISM 路径 → 重启 → `-Mode update` 升级 WSL
   - 从 v1 升级(已有 Ubuntu-24.04 + 旧工作区):复用发行版、目录迁移、旧图标被覆盖
   - 控制台:打开即显示窗口(后台加载)、各按钮、经 WT 的 `\;` 转义
   - 工作区:desktop.ini 图标生效、隐藏属性、从 WSL 覆盖写被隐藏的 AGENTS.md 是否需要先 `attrib -h`(已做防护)
   - 本机开 Clash 时 mirrored 模式生效;Kimi OAuth;Claude Code 接 DeepSeek 实测一轮对话
   - 卸载两个选项
   - 🆕 v2.0.1:老 Win10 DISM 路径重启后不再二次要求重启;UAC 拒绝 WSL 升级后安装继续;「卸载」窗口正常显示;勾选列表在 WT 底部位置不错位;失败后下次登录不再自动弹安装;开 Clash 时先询问再重启 WSL
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
