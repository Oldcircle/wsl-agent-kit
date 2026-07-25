# ============================================================
#  AI 办公助手一键安装(Windows 侧)
#  职责:检测/安装 WSL2 + Ubuntu → 调用 WSL 内 setup.sh → 建桌面快捷方式
#  兼容:Windows 10 19045+ / Windows 11,PowerShell 5.1+
# ============================================================

$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'   # 让 wsl.exe 输出 UTF-8,避免 PowerShell 捕获乱码

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

$KitVersion = '1.0.0'
$Distro     = 'Ubuntu-24.04'
$RepoRoot   = Split-Path -Parent $PSScriptRoot   # 仓库根目录(scripts 的上级)

function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "    [!] $msg" -ForegroundColor Yellow }
function Write-Fail($msg)  { Write-Host "`n[失败] $msg" -ForegroundColor Red }

function Exit-WithPause($code) {
    Write-Host ''
    Read-Host '按回车键关闭窗口'
    exit $code
}

Write-Host ''
Write-Host '=============================================' -ForegroundColor Magenta
Write-Host "  AI 办公助手一键安装 v$KitVersion" -ForegroundColor Magenta
Write-Host '  WSL2 + Ubuntu + Kimi Code / Qwen Code'      -ForegroundColor Magenta
Write-Host '=============================================' -ForegroundColor Magenta

# ---------- 0. 管理员自提权 ----------
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Step '需要管理员权限,正在弹出授权窗口…(请点"是")'
    $self = $MyInvocation.MyCommand.Path
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$self`""
    )
    exit 0
}

# ---------- 1. 系统检查 ----------
Write-Step '检查 Windows 版本…'
$build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
if ($build -lt 19045) {
    Write-Fail "当前 Windows 内部版本号 $build 过旧,WSL2 需要 Windows 10 22H2(19045)或 Windows 11。请先升级系统。"
    Exit-WithPause 1
}
if ($build -lt 22000) {
    Write-Warn2 "检测到 Windows 10(build $build)。可以用,但微软已停止 Win10 主流支持,建议有条件时升级 Win11。"
} else {
    Write-Ok "Windows 11(build $build)"
}

# ---------- 2. WSL 本体 ----------
Write-Step '检查 WSL…'
$wslReady = $false
$wslExe = Join-Path $env:SystemRoot 'System32\wsl.exe'
if (Test-Path $wslExe) {
    & $wslExe --status *> $null
    if ($LASTEXITCODE -eq 0) { $wslReady = $true }
}

if (-not $wslReady) {
    Write-Warn2 'WSL 尚未启用,现在自动安装(需要几分钟)…'
    & $wslExe --install --no-distribution
    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 '常规通道失败,改用 --web-download 重试…'
        & $wslExe --install --no-distribution --web-download
    }
    if ($LASTEXITCODE -ne 0) {
        # 老版内置 wsl.exe 不认 --no-distribution:退回最朴素形式(会顺带装默认 Ubuntu,后面直接复用)
        Write-Warn2 '仍失败,尝试最基础的 wsl --install …'
        & $wslExe --install
    }
    Write-Host ''
    Write-Host '┌──────────────────────────────────────────────┐' -ForegroundColor Yellow
    Write-Host '│  WSL 组件已安装,但需要重启电脑才能生效。      │' -ForegroundColor Yellow
    Write-Host '│                                              │' -ForegroundColor Yellow
    Write-Host '│  请现在重启电脑,然后再次双击 install.bat,   │' -ForegroundColor Yellow
    Write-Host '│  安装会自动从这里继续。                      │' -ForegroundColor Yellow
    Write-Host '└──────────────────────────────────────────────┘' -ForegroundColor Yellow
    Exit-WithPause 0
}
Write-Ok 'WSL 已启用'

# 尽量把 WSL 内核更新到最新(失败不阻塞)
& $wslExe --update *> $null
& $wslExe --set-default-version 2 *> $null

# ---------- 3. Ubuntu 发行版 ----------
Write-Step '检查 Ubuntu 发行版…'
$existing = @()
$raw = & $wslExe --list --quiet 2>$null
if ($raw) {
    $existing = $raw | ForEach-Object { "$_".Trim() } | Where-Object { $_ }
}
$ubuntu = $existing | Where-Object { $_ -match '^Ubuntu' } | Select-Object -First 1

if ($ubuntu) {
    $Distro = $ubuntu
    Write-Ok "检测到已有发行版:$Distro,直接复用"
} else {
    Write-Warn2 "未发现 Ubuntu,开始安装 $Distro(下载约 300-600MB,取决于网速)…"
    & $wslExe --install -d $Distro --no-launch
    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 '常规通道失败,改用 --web-download 重试…'
        & $wslExe --install -d $Distro --no-launch --web-download
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Ubuntu 下载失败。请检查网络后重试;若在公司网络,可能需要放行 Microsoft Store。详见 docs/TROUBLESHOOTING.md"
            Exit-WithPause 1
        }
    }
    Write-Ok "$Distro 安装完成"
}

# 确保是 WSL2(老机器上可能默认 WSL1,失败不阻塞)
& $wslExe --set-version $Distro 2 *> $null

function Invoke-WslRoot([string]$cmd) {
    & $wslExe -d $Distro -u root -- bash -lc $cmd
    return $LASTEXITCODE
}

# 冒烟:发行版能不能跑起来
& $wslExe -d $Distro -u root -- true *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Fail ("Ubuntu 无法启动。最常见原因是 BIOS 未开启 CPU 虚拟化(错误码 0x80370102)。`n" +
                "解决办法见 docs/TROUBLESHOOTING.md 第 1 节。")
    Exit-WithPause 1
}

# ---------- 4. 确保有默认(非 root)用户 ----------
Write-Step '检查 Ubuntu 用户…'
$uid1000 = (& $wslExe -d $Distro -u root -- bash -lc "getent passwd 1000 | cut -d: -f1") 2>$null
$uid1000 = "$uid1000".Trim()

if (-not $uid1000) {
    # 由 Windows 用户名生成合法 Linux 用户名(小写字母开头,仅 a-z0-9);中文名等取不到就叫 worker
    $sanitized = ($env:UserName.ToLower() -replace '[^a-z0-9]', '')
    if (-not $sanitized -or $sanitized -notmatch '^[a-z]') { $sanitized = 'worker' }
    Write-Warn2 "创建 Ubuntu 用户:$sanitized(免密码 sudo,个人电脑标准配置)"
    $null = Invoke-WslRoot ("useradd -m -s /bin/bash -G sudo $sanitized && " +
        "printf '%s ALL=(ALL) NOPASSWD:ALL\n' $sanitized > /etc/sudoers.d/agent-kit && chmod 440 /etc/sudoers.d/agent-kit && " +
        "printf '[user]\ndefault=%s\n' $sanitized > /etc/wsl.conf")
    & $wslExe --terminate $Distro *> $null   # 重启发行版使默认用户生效
    $uid1000 = $sanitized
}
Write-Ok "Ubuntu 用户:$uid1000"

# ---------- 5. 选择要安装的 AI 工具 ----------
Write-Step '选择要安装的 AI 工具(可多选)…'
Write-Host @'

    【任务型:在终端里帮你干活,推荐日常办公用】
      1. OpenCode     主推,任意 API Key 直插(16 万+ star)
      2. Claude Code  全网最火(闭源),可接 DeepSeek/GLM/Kimi 的兼容端点
      3. Kimi Code    中文界面,买 Kimi 会员登录即用,不碰 Key
      4. Qwen Code    阿里通义生态
      5. Codex CLI    OpenAI 出品(国内 Key 需手工配,进阶)
      6. Gemini CLI   谷歌出品(需海外网络,进阶)
    【常驻助理型:住在电脑里的私人助理,进阶玩法】
      7. Hermes Agent 爱马仕(22 万+ star,自我进化技能+长期记忆)
      8. OpenClaw     小龙虾(38 万+ star,消息通道型助理;安全注意见文档)
      9. Goose        Block 出品通用 agent

'@ -ForegroundColor Gray
$sel = Read-Host '输入编号(逗号分隔,如 1,2,3);直接回车 = 推荐组合 1,2,3'
if (-not $sel) { $sel = '1,2,3' }
$agentMap = @{ '1'='opencode'; '2'='claude'; '3'='kimi'; '4'='qwen'; '5'='codex';
               '6'='gemini'; '7'='hermes'; '8'='openclaw'; '9'='goose' }
$agentList = @()
foreach ($n in ($sel -split '[,,、 ]+')) {
    $k = $n.Trim()
    if ($k -and $agentMap.ContainsKey($k)) { $agentList += $agentMap[$k] }
    elseif ($k) { Write-Warn2 "忽略无效编号:$k" }
}
if ($agentList -notcontains 'opencode') {
    $agentList = @('opencode') + $agentList   # OpenCode 是兜底启动器,必装
    Write-Warn2 '已自动加上 OpenCode(它是其余工具缺席时的兜底)'
}
$agentsCsv = ($agentList | Select-Object -Unique) -join ','
Write-Ok "将安装:$agentsCsv"

# ---------- 6. 把安装包复制进 WSL 并执行 setup.sh ----------
Write-Step '复制安装文件到 Ubuntu…'
$repoWsl = (& $wslExe -d $Distro -u root -- wslpath -u "$RepoRoot").Trim()
if (-not $repoWsl) {
    Write-Fail '无法转换仓库路径(wslpath 失败)。'
    Exit-WithPause 1
}
$copyCmd = "rm -rf /opt/agent-kit && mkdir -p /opt/agent-kit && cp -r '$repoWsl'/. /opt/agent-kit/ && " +
           "find /opt/agent-kit -type f \( -name '*.sh' -o -name '*.py' -o -name '*.md' -o -name '*.toml' " +
           "-o -name '*.json' -o -name '*.txt' \) -exec sed -i 's/\r\$//' {} + && " +
           "chmod +x /opt/agent-kit/scripts/*.sh"
if ((Invoke-WslRoot $copyCmd) -ne 0) {
    Write-Fail '复制文件进 WSL 失败。'
    Exit-WithPause 1
}
Write-Ok '文件已就位(/opt/agent-kit)'

Write-Step '在 Ubuntu 内安装 AI 助手(首次约 3-10 分钟,请耐心等待)…'
& $wslExe -d $Distro -u root -- bash /opt/agent-kit/scripts/setup.sh --win-user "$env:UserName" --agents "$agentsCsv"
if ($LASTEXITCODE -ne 0) {
    Write-Fail 'Ubuntu 内安装失败。上方日志有具体原因;修复后重新双击 install.bat 即可(可重复运行)。'
    Exit-WithPause 1
}
Write-Ok 'Ubuntu 内安装完成'

# ---------- 7. 桌面快捷方式 ----------
Write-Step '创建桌面快捷方式…'
try {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut((Join-Path $desktop 'AI 助手.lnk'))
    $lnk.TargetPath = $wslExe
    $lnk.Arguments = "-d $Distro --cd ~ -- bash -lic ai"
    $lnk.IconLocation = "$wslExe,0"
    $lnk.Description = 'AI 办公助手(WSL)'
    $lnk.Save()
    Write-Ok "桌面已创建「AI 助手」快捷方式"
} catch {
    Write-Warn2 "快捷方式创建失败(不影响使用):$($_.Exception.Message)"
}

# ---------- 8. 首次配置(交互) ----------
Write-Step '进入首次配置(选择你的 AI 服务商并填入 API Key)…'
Write-Host '    提示:如果现在还没办好 Key,可以按 Ctrl+C 跳过,之后随时双击「AI 助手」会自动引导配置。' -ForegroundColor DarkGray
& $wslExe -d $Distro -- bash -lic 'ai-config || true'

Write-Host ''
Write-Host '=============================================' -ForegroundColor Green
Write-Host '  安装完成!'                                   -ForegroundColor Green
Write-Host '  日常使用:双击桌面「AI 助手」即可。'           -ForegroundColor Green
Write-Host '  使用教程:docs/USAGE.md(仓库里)'             -ForegroundColor Green
Write-Host '=============================================' -ForegroundColor Green
Exit-WithPause 0
