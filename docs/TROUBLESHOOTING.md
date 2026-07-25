# 排障手册

> 按症状查。每条:症状 → 原因 → 解决。解决不了就把报错截图发给安装人。

## 1. Ubuntu 启动报错 0x80370102 / "please enable the Virtual Machine Platform"

**原因**:BIOS 里 CPU 虚拟化没开(很多品牌机出厂关闭)。
**解决**:重启进 BIOS(开机狂按 F2/F10/Del,品牌不同),找到 Intel VT-x / AMD SVM / Virtualization Technology,设为 Enabled,保存重启,再跑 install.bat。

## 2. install.bat 提示要重启,重启后又提示重启(循环)

**原因**:Windows 更新挂起或功能启用失败。
**解决**:先去「设置→Windows 更新」把所有更新装完并重启;管理员 PowerShell 跑 `wsl --update`;再运行 install.bat。仍不行:控制面板→程序→启用或关闭 Windows 功能→勾选「适用于 Linux 的 Windows 子系统」和「虚拟机平台」→ 重启。

## 3. Ubuntu 下载特别慢或失败

**原因**:微软商店通道被网络环境干扰。
**解决**:脚本已自动尝试 `--web-download` 备用通道;还不行就换网络(手机热点往往有效)再跑一次 install.bat。

## 4. 「AI 助手」窗口一闪就没

**原因**:多为发行版没起来或 ai 命令缺失。
**解决**:开始菜单打开 Ubuntu 看真实报错。若显示 `ai: command not found`,重跑 install.bat(幂等,可放心重复)。

## 5. Kimi OAuth 登录时浏览器没弹出来

**解决**:终端里会同时印出一个网址,手动复制到 Windows 浏览器打开即可完成登录。之后要让自动弹出生效:关掉窗口重开一次(需要 `BROWSER=wslview` 生效)。

## 6. 提示 Key 无效 / 401

**解决**:`ai-config` 重新粘一遍(注意别带空格/引号/换行);确认对应平台余额>0、Key 没被删。GLM Coding Plan 的 Key 走专用端点:向导里选 3 后类型要选 `b`,选成 `a`(按量)就会 401(见 PROVIDERS.md 第 3 节)。

## 7. 公司电脑/域策略装不上

WSL 需要管理员权限,部分公司电脑被 IT 策略禁用虚拟化组件。**解决**:找 IT 开通,或换个人电脑。这个没有绕过办法(也不该绕)。

## 8. Gemini CLI / Codex / Goose / Hermes 装不上或用不了

这几个的安装源或服务在海外(GitHub / Google / OpenAI),国内网络经常失败——**脚本已设计为非致命**,不影响其他 agent。确有需要:换网络环境后 `ai-install <名字>` 重试;Gemini 还需要能登录 Google 账号,没有海外网络就别选它。

## 8b. OpenClaw(小龙虾)注意事项

- 首次使用要跑 `openclaw onboard` 引导(建议安装人远程陪同)
- 它主打的 WhatsApp/Telegram/Discord 通道国内基本不可用,按「本机对话助理」用即可
- **不要随便安装社区技能/插件**:其技能市场有公开的供应链安全争议;非程序员保持默认配置

## 9. 磁盘空间

整套约占 3-6GB(Ubuntu+工具+模型缓存)。C 盘紧张时:`wsl --manage Ubuntu-24.04 --set-sparse true` 可回收空间;或先清理 C 盘再装。

## 10. 想彻底卸载

管理员 PowerShell:`wsl --unregister Ubuntu-24.04`(⚠️ 会删掉 WSL 里所有文件,但你的产出都在 Windows「文档\AI工作区」里,不受影响);再删掉桌面快捷方式即可。

## 11. 换了新电脑怎么搬家

工作区就在「文档\AI工作区」,用你平时搬文档的任何方式(U 盘/网盘)拷到新机同位置;新机跑 install.bat → `ai-config` 重配 Key 即可。

## 给安装人:远程排障要点

- 一切脚本幂等,重跑 install.bat 是万能第一步
- WSL 内日志现场:`/opt/agent-kit`(脚本)、`~/.config/agent-kit/`(env/default-agent)、`~/.qwen/settings.json`、`~/.kimi-code/config.toml`
- 网络类问题优先怀疑:公司代理、家用路由的境外 DNS 污染;npm/pip/apt 已全部指向国内镜像,Kimi/DeepSeek 等 API 本身是国内直连
