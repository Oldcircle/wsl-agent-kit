# 国内 AI 服务开通指南(给使用者)

> 价格与模型名核对于 2026-07-25,之后可能变化,以各家官网为准。
> 只需要选**一家**开通;编号与电脑上 `ai-config` 向导菜单一一对应。不知道选哪家:图便宜选 1,图省心选 2。

## 1. DeepSeek(推荐:便宜好用)

**适合谁**:想按用多少付多少、预算极低的人(轻度使用一个月几块钱)。

1. 打开 platform.deepseek.com → 注册 → 左侧「API Keys」→ 创建,**立即复制**(只显示一次)
2. 充值 ¥10 起步
3. 电脑上运行 `ai-config` → 选 1 → 粘贴 Key

- 默认模型 `deepseek-v4-flash`(便宜、快、带思考);要更强改 `deepseek-v4-pro`
- 注意:2026-07-24 起旧模型名 `deepseek-chat`/`deepseek-reasoner` 已废弃,网上旧教程里的名字别用
- 端点:OpenAI 兼容 `https://api.deepseek.com/v1`;Anthropic 兼容 `https://api.deepseek.com/anthropic`
- 装了 Claude Code 的话,向导会问「用哪个界面打开」——选 Claude Code 就是 DeepSeek 官方文档推荐的组合

## 2. Kimi 会员套餐(最省心:不碰 Key)

**适合谁**:不想碰「API Key」这种东西、希望费用固定的人。走 Kimi Code CLI(而非 OpenCode)。

1. 手机装 Kimi App 或打开 kimi.com,注册/登录(手机号即可)
2. 购买 **Kimi Code Plan**:入门 Andante ¥49/月(日常文案/调研足够);要用最强 K3 模型选 Moderato ¥99/月。额度每 7 天滚动刷新
3. 电脑上 `ai-config` → 选 2;双击「AI 助手」,首次启动选 **OAuth / 浏览器登录** → 浏览器自动弹出 → 登录 Kimi 账号 → 完成

不用复制任何 Key;套餐内限速,不额外扣费。

## 3. 智谱 GLM

**适合谁**:想用 GLM-5.x 系列(开源旗舰,能力第一梯队)。

- **按量付费**:bigmodel.cn 注册 → 实名 → API Key → `ai-config` 选 3 → 类型选 `a`。默认模型 `glm-5.2`,端点 `https://open.bigmodel.cn/api/paas/v4`
- **Coding Plan 包月**(¥20-49/月起,量大更划算):同样 `ai-config` 选 3 → 类型选 `b`,向导会自动改走套餐专用端点 `https://open.bigmodel.cn/api/anthropic`(Anthropic 兼容)。Key 在 bigmodel.cn 的 Coding Plan 页面生成

## 4. 阿里云百炼(通义千问)

**适合谁**:已有阿里云账号的人。

bailian.console.aliyun.com → 开通百炼 → API-KEY 管理 → 创建 → `ai-config` 选 4。默认模型 `qwen-max`(写作好),省钱可改 `qwen-plus`。端点:`https://dashscope.aliyuncs.com/compatible-mode/v1`。

## 5. 硅基流动 SiliconFlow(一 Key 多模型 + 语音转写)

**适合谁**:想一个 Key 试遍 DeepSeek/Qwen/GLM 各家开源模型;以及**所有想用「视频转文字」功能的人**(强烈建议人手一个,注册送额度,转写费用极低)。

1. siliconflow.cn 注册 → API 密钥 → 新建,复制
2. `ai-config` 选 5(作主力);或主力选了别家时,在向导最后一步把这个 Key 填进「视频转文字」
3. 对话模型名去官网「模型广场」抄(形如 `deepseek-ai/DeepSeek-V3.2`);转写用的 `FunAudioLLM/SenseVoiceSmall` 已内置在脚本里,不用管

## 6. Moonshot 开放平台(Kimi 按量)

**适合谁**:想用 Kimi 模型但不想包月。

platform.kimi.com 注册 → API Key → `ai-config` 选 6。默认模型 `kimi-k2.7-code`(¥ 低、能力强);土豪可改 `kimi-k3`(原生视觉、1M 上下文,但 $3/百万输入)。端点:`https://api.moonshot.cn/v1`。

## 7. 其他 / 中转站

任何 OpenAI 兼容服务(包括自建中转)都能用:`ai-config` 选 7,填 baseUrl、模型名、Key 三样即可。

---

## 费用参考(轻中度办公使用,每月)

| 方案 | 预估月费 | 特点 |
|------|---------|------|
| DeepSeek 按量 | ¥5-20 | 最便宜,能力足够 |
| Kimi Andante | ¥49 固定 | 零 Key 省心,写作强,自带联网搜索 |
| GLM Coding Plan | ¥20-49 固定 | 性价比高 |
| 百炼按量 | ¥10-40 | 阿里生态 |
| 硅基流动按量 | ¥5-30 | 模型多,含转写 |

## 安全提醒

- API Key 等于「能花你钱的密码」:只粘贴到 `ai-config` 向导里,不发微信、不存网盘明文
- 泄露疑虑时:去对应平台**删除旧 Key 重建一个**,再跑一遍 `ai-config`
- 本安装包把 Key 存在 WSL 内 `~/.config/agent-kit/env`(权限 600,仅本机本用户可读)
