# ============================================================
#  AI 办公助手一键安装(Windows 侧)
#  以普通用户身份运行;只有「启用 WSL」那一步会单独弹 UAC。
#  流程:安装包就位 → 系统检查 → WSL → 网络 → Ubuntu → 选 agent
#        → WSL 内安装 → 图标/开始菜单/卸载入口 → 首次配置
#  兼容:Windows 10 2004(19041)+ / Windows 11,PowerShell 5.1
# ============================================================
param([switch]$Resume)

$ErrorActionPreference = 'Continue'   # 原生命令靠 $LASTEXITCODE 判断;5.1 的 Stop 会把 stderr 当异常
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'common.ps1')

$SourceRoot = Split-Path -Parent $PSScriptRoot   # 本次运行的安装包根目录(可能是解压目录)
$KitVersion = Get-KitVersion $SourceRoot
$Distro = $null

function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "    [!] $msg" -ForegroundColor Yellow }
function Write-Note($msg)  { Write-Host "        $msg" -ForegroundColor DarkGray }
function Write-Fail($msg)  { Write-Host "`n[失败] $msg" -ForegroundColor Red }

function Exit-WithPause($code) {
    try { Stop-Transcript | Out-Null } catch { }
    Write-Host ''
    Read-Host '按回车键关闭窗口'
    if ($code -ne 0) { $code = 2 }   # 2 = 已经停住让用户看过了,install.bat 不必再 pause
    exit $code
}

function Ask-YesNo([string]$q, [bool]$default = $true) {
    $hint = '[Y/n]'; if (-not $default) { $hint = '[y/N]' }
    $a = Read-Host "$q $hint"
    if (-not $a) { return $default }
    return ($a -match '^[yY是]')
}

# 以 root 在发行版里执行(-e:不经过 shell,参数原样传递,不会被二次解析)。
# 输出直接交给屏幕(Out-Host),函数只返回退出码——否则输出会混进返回值里。
function Invoke-WslRoot([string[]]$argv) {
    & $WslExe -d $Distro -u root -e @argv | Out-Host
    return $LASTEXITCODE
}

# ---------- 0. 横幅 + 日志 ----------
New-Item -ItemType Directory -Force -Path $KitLogDir | Out-Null
$LogFile = Join-Path $KitLogDir ("install-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
try { Start-Transcript -Path $LogFile -Force | Out-Null } catch { }

Write-Host ''
Write-Host '=============================================' -ForegroundColor Magenta
Write-Host "  $AppName 一键安装  v$KitVersion"             -ForegroundColor Magenta
Write-Host '  WSL2 + Ubuntu + 自选 AI Agent + 中文工作区'  -ForegroundColor Magenta
Write-Host '=============================================' -ForegroundColor Magenta
if ($Resume) { Write-Host '  (重启后自动继续安装)' -ForegroundColor Magenta }

# ---------- 1. 安装包就位:复制到 %LOCALAPPDATA%\AgentKit\kit ----------
# 这样用户删掉下载的 ZIP/解压目录也不影响;桌面图标、控制台、修复、卸载都指向这里。
Write-Step '准备安装文件…'
$srcFull = (Resolve-Path $SourceRoot).Path.TrimEnd('\')
$dstFull = $KitDir.TrimEnd('\')
if ($srcFull -ne $dstFull) {
    New-Item -ItemType Directory -Force -Path $KitDir | Out-Null
    $null = & robocopy.exe $srcFull $dstFull /MIR /NFL /NDL /NJH /NJS /NP /R:2 /W:1 /XD .git
    if ($LASTEXITCODE -ge 8) {
        Write-Fail "复制安装文件到 $KitDir 失败(robocopy 代码 $LASTEXITCODE)。请把本窗口截图发给安装人。"
        Exit-WithPause 1
    }
}
Get-ChildItem $KitDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue   # 去掉「来自网络」标记
Write-Ok "安装文件在 $KitDir(下载的 ZIP 和解压出来的文件夹,装完可以删)"

# ---------- 2. 系统检查 ----------
Write-Step '检查电脑环境…'
$os = Get-CimInstance Win32_OperatingSystem
$build = [int]$os.BuildNumber
if ($build -lt 19041) {
    Write-Fail "Windows 版本太旧(内部版本 $build)。需要 Windows 10 2004 以上或 Windows 11:设置 → Windows 更新 → 装完所有更新后再试。"
    Exit-WithPause 1
}
if ($build -lt 22000) { Write-Ok "Windows 10(build $build)" } else { Write-Ok "Windows 11(build $build)" }

$arch = $env:PROCESSOR_ARCHITECTURE
if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }

$sysDrive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
if ($sysDrive) {
    $freeGB = [math]::Round($sysDrive.Free / 1GB, 1)
    if ($freeGB -lt 5) {
        Write-Fail "$env:SystemDrive 盘只剩 $freeGB GB,至少需要 6GB。清理一下 C 盘(或清空回收站)后再试。"
        Exit-WithPause 1
    } elseif ($freeGB -lt 10) {
        Write-Warn2 "$env:SystemDrive 盘剩余 $freeGB GB,够用但偏紧(整套约占 4-6GB)"
    } else { Write-Ok "$env:SystemDrive 盘剩余 $freeGB GB" }
}

# CPU 虚拟化:提前发现「BIOS 没开虚拟化」,别等重启完才报 0x80370102
$virtOff = $false
try {
    $hv = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
    $vf = @(Get-CimInstance Win32_Processor | ForEach-Object { $_.VirtualizationFirmwareEnabled })
    if (-not $hv -and ($vf -notcontains $true)) { $virtOff = $true }
} catch { }
if ($virtOff) {
    Write-Warn2 'CPU 虚拟化看起来没有开启(BIOS 里的 Intel VT-x / AMD SVM)。'
    Write-Note '可以先继续装;万一最后提示 0x80370102,按「常见问题」第 1 节进 BIOS 打开即可,'
    Write-Note '实在进不了 BIOS,安装程序也会提供「兼容模式」继续。'
}

# ---------- 3. WSL 本体 ----------
Write-Step '检查 WSL…'
function Test-RebootPending {
    return (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
}

function Set-ResumeAfterReboot {
    # 双保险:登录后自动续装(RunOnce)+ 桌面放一个显眼的续装图标
    try {
        $bat = Join-Path $KitDir 'install.bat'
        Set-ItemProperty -Path $RunOnceKey -Name 'AgentKitResume' -Value "`"$bat`" /resume"
    } catch { }
    try {
        New-Shortcut -Path (Join-Path ([Environment]::GetFolderPath('Desktop')) $ResumeLnkName) `
            -Target (Join-Path $KitDir 'install.bat') -Arguments '/resume' -WorkDir $KitDir `
            -Icon (Get-IconPath 'repair') -Description '重启电脑后双击这里,安装会自动继续'
    } catch { }
}

function Clear-ResumeAfterReboot {
    try { Remove-ItemProperty -Path $RunOnceKey -Name 'AgentKitResume' -ErrorAction SilentlyContinue } catch { }
    $p = Join-Path ([Environment]::GetFolderPath('Desktop')) $ResumeLnkName
    if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
}

function Request-Reboot {
    Set-ResumeAfterReboot
    Write-Host ''
    Write-Host '┌──────────────────────────────────────────────┐' -ForegroundColor Yellow
    Write-Host '│  第一阶段完成!需要重启一次电脑。             │' -ForegroundColor Yellow
    Write-Host '│  重启并登录后,安装会自动继续;                │' -ForegroundColor Yellow
    Write-Host '│  没自动继续的话,双击桌面上的                 │' -ForegroundColor Yellow
    Write-Host '│  「▶ 重启后点我继续安装」即可。               │' -ForegroundColor Yellow
    Write-Host '└──────────────────────────────────────────────┘' -ForegroundColor Yellow
    if (Ask-YesNo '现在就重启吗?(先保存好其他正在编辑的文件)' $true) {
        try { Stop-Transcript | Out-Null } catch { }
        & shutdown.exe /r /t 5 /c "${AppName}:重启后会自动继续安装"
        exit 0
    }
    Exit-WithPause 0
}

function Invoke-Elevated([string]$mode) {
    # 只有这一步需要管理员:单独弹一次 UAC,其余步骤都以当前用户身份进行
    $result = Join-Path $env:TEMP "agentkit-wsl-$mode.txt"
    Remove-Item $result -ErrorAction SilentlyContinue
    $script = Join-Path $KitDir 'scripts\enable-wsl.ps1'
    Write-Note '会弹出「是否允许此应用对你的设备进行更改」,请点「是」'
    try {
        $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`"", '-Mode', $mode, '-ResultFile', "`"$result`"")
    } catch {
        Write-Fail '没有获得管理员授权(可能点了「否」)。重新双击 install.bat,弹窗时点「是」。'
        Write-Note '如果这台电脑的账号不是管理员,需要让有管理员密码的人来点这一下。'
        Exit-WithPause 1
    }
    return ((Test-Path $result) -and ((Get-Content $result -Raw).Trim() -eq '0'))
}

$wslReady = $false
if (Test-Path $WslExe) {
    & $WslExe --status *> $null
    if ($LASTEXITCODE -eq 0) { $wslReady = $true }
}
if (-not $wslReady) {
    if (Test-RebootPending) {
        Write-Warn2 '系统有更新/组件在等待重启,先重启一次再继续。'
        Request-Reboot
    }
    Write-Warn2 'WSL 还没启用,现在启用(需要管理员授权,约 2-5 分钟)…'
    Set-ResumeAfterReboot   # 先放好续装入口:万一系统自己弹重启也不怕
    if (-not (Invoke-Elevated 'install')) {
        Write-Fail '启用 WSL 失败。常见原因:公司电脑策略禁止、Windows 更新损坏。见「常见问题」第 2、7 节。'
        Exit-WithPause 1
    }
    Request-Reboot
}
# 系统自带的老版 WSL(wsl --version 不认)缺新功能,升级到商店版
& $WslExe --version *> $null
$modernWsl = ($LASTEXITCODE -eq 0)
if (-not $modernWsl) {
    Write-Warn2 '检测到老版 WSL,升级到新版(需要管理员授权)…'
    if (Invoke-Elevated 'update') { & $WslExe --version *> $null; $modernWsl = ($LASTEXITCODE -eq 0) }
    if (-not $modernWsl) { Write-Warn2 'WSL 升级没成功,先用老版本继续(一般也能用)' }
}
Clear-ResumeAfterReboot
Write-Ok 'WSL 已就绪'

# ---------- 4. 网络:本机代理 → WSL 镜像网络模式 ----------
$proxy = Get-LocalProxy
if ($proxy) {
    Write-Step "检测到本机代理 $proxy …"
    $wslconfig = Join-Path $env:USERPROFILE '.wslconfig'
    $cfg = ''
    if (Test-Path $wslconfig) { $cfg = Get-Content $wslconfig -Raw }
    if ($cfg -match '(?im)^\s*networkingMode\s*=') {
        Write-Ok '.wslconfig 里已有你的网络设置,保持不动'
    } elseif ($build -ge 22621 -and $modernWsl) {
        # 镜像模式:WSL 与 Windows 共用网络,Clash/v2rayN 等本机代理在 WSL 里直接可用
        if ($cfg -match '(?im)^\s*\[wsl2\]') {
            $cfg = [regex]::Replace($cfg, '(?im)^\s*\[wsl2\]\s*$', "[wsl2]`r`nnetworkingMode=mirrored", 1)
        } else {
            $cfg = $cfg.TrimEnd() + "`r`n`r`n[wsl2]`r`nnetworkingMode=mirrored`r`n"
        }
        [IO.File]::WriteAllText($wslconfig, $cfg.TrimStart(), (New-Object System.Text.UTF8Encoding($false)))
        & $WslExe --shutdown *> $null
        Write-Ok '已开启 WSL 镜像网络(用得上你的代理,访问 GitHub 等海外服务更顺)'
        Write-Note '想关掉:删除 用户目录\.wslconfig 里的 networkingMode 一行'
    } else {
        Write-Note '你的系统版本不支持 WSL 共用代理,海外服务(GitHub/Gemini 等)在 WSL 里可能连不上;国内服务不受影响。'
    }
}

# ---------- 5. Ubuntu 发行版 ----------
Write-Step '准备 Ubuntu(AI 的运行环境)…'
$Distro = Find-KitDistro -ProbeLegacy
$importFile = $null

function Get-UbuntuImage {
    # 从国内镜像/官方站里挑最快的,下载官方 Ubuntu 24.04 WSL 镜像并校验 SHA256。
    # 绕开 wsl --install 依赖的 GitHub 分发列表和微软商店(国内经常失败)。
    $mirrors = @(
        'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-releases/noble',
        'https://mirrors.ustc.edu.cn/ubuntu-releases/noble',
        'https://mirrors.aliyun.com/ubuntu-releases/noble',
        'https://mirrors.huaweicloud.com/ubuntu-releases/noble',
        'https://releases.ubuntu.com/noble'
    )
    $best = $null; $bestT = [double]::MaxValue
    foreach ($m in $mirrors) {
        $t = Test-UrlSpeed "$m/SHA256SUMS" 6
        if ($t -ne $null -and $t -lt $bestT) { $best = $m; $bestT = $t }
    }
    if (-not $best) { Write-Warn2 '所有 Ubuntu 镜像站都连不上'; return $null }
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    $sums = & $curl -fsSL -m 30 "$best/SHA256SUMS" 2>$null
    $entry = @($sums | Where-Object { $_ -match '^([0-9a-f]{64}) \*?(ubuntu-24\.04(\.\d+)?-wsl-amd64\.wsl)$' }) | Select-Object -Last 1
    if (-not $entry) { Write-Warn2 '镜像站上没找到 WSL 镜像'; return $null }
    $null = $entry -match '^([0-9a-f]{64}) \*?(\S+)$'
    $hash = $Matches[1]; $name = $Matches[2]
    New-Item -ItemType Directory -Force -Path $KitCacheDir | Out-Null
    $file = Join-Path $KitCacheDir $name
    if ((Test-Path $file) -and ((Get-FileHash $file -Algorithm SHA256).Hash -eq $hash)) {
        Write-Ok "用上次下好的 $name"
        return $file
    }
    Write-Note "从 $(([uri]$best).Host) 下载 $name(约 370MB)…"
    for ($i = 1; $i -le 3; $i++) {
        & $curl -fL --retry 3 --retry-delay 3 -C - --connect-timeout 20 -o $file "$best/$name"
        if ((Test-Path $file) -and ((Get-FileHash $file -Algorithm SHA256).Hash -eq $hash)) { return $file }
        Write-Warn2 "第 $i 次下载不完整,重试…"
        if ($i -ge 2) { Remove-Item $file -Force -ErrorAction SilentlyContinue }
    }
    return $null
}

function Import-KitDistro([string]$file, [int]$version) {
    $dir = Join-Path $KitDistroDir $DefaultDistroName
    # 上次导入失败留下的 ext4.vhdx 会让这次 --import 报「文件已存在」;发行版没注册时可以放心清掉
    if ((Test-Path $dir) -and -not (Test-DistroExists $DefaultDistroName)) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    & $WslExe --import $DefaultDistroName $dir $file --version $version
    return ($LASTEXITCODE -eq 0)
}

if ($Distro) {
    Write-Ok "复用已有的环境:$Distro"
} else {
    if ($arch -eq 'AMD64') {
        $importFile = Get-UbuntuImage
        if ($importFile) {
            Write-Note '导入 Ubuntu(约 1 分钟)…'
            if (Import-KitDistro $importFile 2) { $Distro = $DefaultDistroName }
            else { Write-Warn2 '导入失败,改用微软官方渠道…' }
        }
    }
    if (-not $Distro) {
        # 备用:微软商店 / GitHub 渠道(海外网络或 ARM 电脑)
        $fallback = 'Ubuntu-24.04'
        if (Test-DistroExists $fallback) {
            $Distro = $fallback
        } else {
            Write-Note "通过微软渠道下载 $fallback …"
            & $WslExe --install -d $fallback --no-launch
            if ($LASTEXITCODE -ne 0) { & $WslExe --install -d $fallback --no-launch --web-download }
            if ($LASTEXITCODE -eq 0 -or (Test-DistroExists $fallback)) { $Distro = $fallback }
        }
    }
    if (-not $Distro) {
        Write-Fail 'Ubuntu 下载失败。请换个网络(手机热点往往有效)后重新双击 install.bat;已下载的部分会接着下。'
        Exit-WithPause 1
    }
    Write-Ok "Ubuntu 已就位:$Distro"
}
Save-KitDistro $Distro

# 冒烟:能不能跑起来。WSL2 起不来多半是 BIOS 没开虚拟化 → 提供 WSL1 兼容模式
$smoke = & $WslExe -d $Distro -u root -e true 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Ubuntu 启动失败:$smoke"
    if ("$smoke" -match '0x80370102|0x80370114|virtualiz|虚拟|Hyper-V') {
        Write-Host ''
        Write-Host '  原因:CPU 虚拟化没有开启。两个办法:' -ForegroundColor Yellow
        Write-Host '   1) 推荐:重启进 BIOS 打开 Intel VT-x / AMD SVM(见「常见问题」第 1 节),再双击 install.bat' -ForegroundColor Yellow
        Write-Host '   2) 进不了 BIOS:用「兼容模式」(WSL1)继续,功能都能用,只是个别情况稍慢' -ForegroundColor Yellow
        if ($importFile -and $Distro -eq $DefaultDistroName -and (Ask-YesNo '现在用兼容模式继续吗?' $false)) {
            & $WslExe --unregister $Distro *> $null
            if (Import-KitDistro $importFile 1) {
                & $WslExe -d $Distro -u root -e true *> $null
            }
        }
        if ($LASTEXITCODE -ne 0) { Exit-WithPause 1 }
        Write-Ok '已切换到兼容模式(WSL1)'
    } else {
        Write-Note '常见问题里按报错码查;或把本窗口截图发给安装人。'
        Exit-WithPause 1
    }
}
if ($importFile) { Remove-Item $importFile -Force -ErrorAction SilentlyContinue }   # 省 370MB

# ---------- 6. 选择要安装的 AI 工具 ----------
$installed = @()
$plain = & $WslExe -d $Distro -e bash -lc 'command -v ai >/dev/null && ai list --plain' 2>$null
foreach ($l in @($plain)) { if ("$l" -match '^([a-z]+)\|1\|') { $installed += $Matches[1] } }

function Select-AgentsChecklist([string[]]$already) {
    $items = @(
        @{ Name='opencode'; Label='OpenCode        主推,任意 API Key 都能用(必装)';        Checked=$true  },
        @{ Name='claude';   Label='Claude Code     全网最火,接 DeepSeek/智谱/Kimi 国内服务';  Checked=$true  },
        @{ Name='kimi';     Label='Kimi Code       中文界面,Kimi 会员扫码登录,不碰 Key';     Checked=$true  },
        @{ Name='qwen';     Label='Qwen Code       阿里通义生态';                              Checked=$false },
        @{ Name='codex';    Label='Codex CLI       OpenAI 出品(进阶)';                      Checked=$false },
        @{ Name='gemini';   Label='Gemini CLI      谷歌出品(需海外网络)';                    Checked=$false },
        @{ Name='hermes';   Label='Hermes 爱马仕   常驻助理,长期记忆(需 GitHub 网络)';       Checked=$false },
        @{ Name='openclaw'; Label='OpenClaw 小龙虾 常驻助理,消息通道型(进阶)';               Checked=$false },
        @{ Name='goose';    Label='Goose           Block 出品通用 agent(需 GitHub 网络)';    Checked=$false }
    )
    foreach ($it in $items) {
        $it.Locked = ($it.Name -eq 'opencode') -or ($already -contains $it.Name)
        if ($it.Locked) { $it.Checked = $true }
        if ($already -contains $it.Name) { $it.Label = $it.Label + '  [已装]' }
    }
    Write-Host ''
    Write-Host '   ↑↓ 移动, 空格 勾选/取消, 回车 确认' -ForegroundColor Gray
    Write-Host '   什么都不动直接回车 = 推荐组合' -ForegroundColor Gray
    Write-Host ''
    $width = [Math]::Max(40, [Console]::WindowWidth - 2)
    $top = [Console]::CursorTop
    $idx = 0
    try { [Console]::CursorVisible = $false } catch { }
    while ($true) {
        [Console]::SetCursorPosition(0, $top)
        for ($i = 0; $i -lt $items.Count; $i++) {
            $it = $items[$i]
            $mark = '[ ]'; if ($it.Checked) { $mark = '[√]' }
            $ptr = '   ';  if ($i -eq $idx) { $ptr = ' > ' }
            # 中文占两格:按显示宽度截断/补齐,避免折行把列表画乱
            $line = "$ptr$mark $($it.Label)"
            $w = 0; $sb = New-Object System.Text.StringBuilder
            foreach ($ch in $line.ToCharArray()) {
                $cw = 1; if ([int]$ch -gt 0x2E80) { $cw = 2 }
                if ($w + $cw -gt $width) { break }
                [void]$sb.Append($ch); $w += $cw
            }
            $line = $sb.ToString() + (' ' * [Math]::Max(0, $width - $w))
            if ($i -eq $idx) { Write-Host $line -ForegroundColor Cyan } else { Write-Host $line -ForegroundColor Gray }
        }
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { if ($idx -gt 0) { $idx-- } else { $idx = $items.Count - 1 } }
            'DownArrow' { if ($idx -lt $items.Count - 1) { $idx++ } else { $idx = 0 } }
            'Spacebar'  { if (-not $items[$idx].Locked) { $items[$idx].Checked = -not $items[$idx].Checked } }
            'Enter'     {
                try { [Console]::CursorVisible = $true } catch { }
                return @($items | Where-Object { $_.Checked } | ForEach-Object { $_.Name })
            }
        }
    }
}

Write-Step '选择要安装的 AI 助手…'
$agentNames = $null
$canInteractive = ($Host.Name -eq 'ConsoleHost') -and
                  (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected)
if ($canInteractive) {
    try { $agentNames = Select-AgentsChecklist $installed }
    catch { Write-Warn2 "列表显示不了($($_.Exception.Message)),改用编号输入"; $agentNames = $null }
}
if (-not $agentNames) {
    Write-Host '  1 OpenCode(必装) 2 Claude Code 3 Kimi Code 4 Qwen 5 Codex 6 Gemini 7 Hermes 8 OpenClaw 9 Goose' -ForegroundColor Gray
    $sel = Read-Host '输入编号(逗号分隔);直接回车 = 推荐组合 1,2,3'
    if (-not $sel) { $sel = '1,2,3' }
    $agentMap = @{ '1'='opencode'; '2'='claude'; '3'='kimi'; '4'='qwen'; '5'='codex';
                   '6'='gemini'; '7'='hermes'; '8'='openclaw'; '9'='goose' }
    $agentNames = @()
    foreach ($n in ($sel -split '[,,、\s]+')) {
        $k = $n.Trim()
        if ($k -and $agentMap.ContainsKey($k)) { $agentNames += $agentMap[$k] }
        elseif ($k) { Write-Warn2 "忽略无效编号:$k" }
    }
}
if ($agentNames -notcontains 'opencode') { $agentNames = @('opencode') + $agentNames }
$agentsCsv = (@($agentNames) | Select-Object -Unique) -join ','
Write-Ok "将安装:$agentsCsv"

# ---------- 7. 把安装包复制进 Ubuntu ----------
Write-Step '复制安装文件到 Ubuntu…'
$null = Invoke-WslRoot @('rm', '-rf', '/opt/agent-kit')
$null = Invoke-WslRoot @('mkdir', '-p', '/opt/agent-kit')
# 主路:--cd 让 WSL 自己翻译 Windows 路径(含中文/空格),再 cp
& $WslExe -d $Distro -u root --cd $KitDir -e cp -r . /opt/agent-kit/ 2>$null
$copied = ($LASTEXITCODE -eq 0) -and ((Invoke-WslRoot @('test', '-f', '/opt/agent-kit/workspace-template/使用说明.txt')) -eq 0)
if (-not $copied) {
    # 备路:tar 管道(不依赖盘符挂载)。必须经 cmd.exe:PowerShell 5.1 的管道会破坏二进制流
    Write-Note '改用备用方式复制…'
    $tarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
    $pipeCmd = "`"$tarExe`" -C `"$KitDir`" -cf - . | `"$WslExe`" -d $Distro -u root -e tar -xf - -C /opt/agent-kit"
    & $env:ComSpec /d /c $pipeCmd
    $copied = ($LASTEXITCODE -eq 0) -and ((Invoke-WslRoot @('test', '-f', '/opt/agent-kit/scripts/setup.sh')) -eq 0)
}
if (-not $copied) {
    Write-Fail '复制安装文件进 Ubuntu 失败。请把本窗口截图发给安装人。'
    Exit-WithPause 1
}
# 行尾保险:万一文件被转成了 CRLF(用 git 在 Windows 上 clone 时会这样),统一改回 LF
$null = Invoke-WslRoot @('find', '/opt/agent-kit', '-type', 'f', '(', '-name', '*.sh', '-o', '-name', '*.py',
    '-o', '-name', '*.md', '-o', '-name', '*.json', '-o', '-name', '*.toml', '-o', '-name', '*.txt',
    '-o', '-name', '*.html', '-o', '-name', 'VERSION', '-o', '-path', '*/scripts/bin/*', ')',
    '-exec', 'sed', '-i', 's/\r$//', '{}', '+')
Write-Ok '文件已就位'

# ---------- 8. 在 Ubuntu 里安装 ----------
$uname = ($env:UserName.ToLower() -replace '[^a-z0-9]', '')
if (-not $uname -or $uname -notmatch '^[a-z]') { $uname = 'worker' }
$docsPath = [Environment]::GetFolderPath('MyDocuments')     # 自动识别 OneDrive / 改过位置的文档目录
$deskPath = [Environment]::GetFolderPath('Desktop')
$dlPath   = Get-DownloadsFolder
Write-Step '在 Ubuntu 里安装 AI 助手(首次约 5-15 分钟,取决于网速,请耐心等待)…'
$setupArgs = @('bash', '/opt/agent-kit/scripts/setup.sh', '--create-user', $uname,
               '--win-docs', $docsPath, '--win-desktop', $deskPath, '--win-kit-dir', $KitHome,
               '--agents', $agentsCsv)
if ($dlPath) { $setupArgs += @('--win-downloads', $dlPath) }
# 直接在顶层调用(不包进函数):进度条、颜色原样显示在窗口里
& $WslExe -d $Distro -u root -e @setupArgs
if ($LASTEXITCODE -ne 0) {
    $wslLog = Join-Path $KitLogDir 'setup-wsl.log'
    & $WslExe -d $Distro -u root -e cat /var/log/agent-kit/setup.log > $wslLog 2>$null
    Write-Fail 'Ubuntu 里的安装没有完成。上方红字就是原因;修好后重新双击 install.bat 即可(可重复运行)。'
    Write-Note "安装日志:$wslLog —— 需要求助时把这个文件发给安装人"
    try { Start-Process explorer.exe "/select,`"$wslLog`"" } catch { }
    Exit-WithPause 1
}
& $WslExe --terminate $Distro *> $null   # 让 /etc/wsl.conf(默认用户等)生效
Write-Ok 'Ubuntu 里安装完成'

# ---------- 9. Windows 集成:图标 / 开始菜单 / 终端 / 卸载入口 ----------
Write-Step '创建桌面图标和开始菜单…'
$wt = Find-WT
if (-not $wt) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Note '安装 Windows Terminal(显示中文和复制粘贴更好用,约 1 分钟)…'
        # 先走微软商店源(国内 CDN 快),不行再走 winget 源(安装包在 GitHub)
        & winget install --id 9N0DX20HK701 -s msstore -e --silent --accept-source-agreements --accept-package-agreements *> $null
        $wt = Find-WT
        if (-not $wt) {
            & winget install --id Microsoft.WindowsTerminal -s winget -e --silent --accept-source-agreements --accept-package-agreements *> $null
            $wt = Find-WT
        }
    }
    if (-not $wt) { Write-Warn2 '没装上 Windows Terminal,先用系统自带窗口(之后在微软商店装上,再运行「修复安装」即可升级)' }
}

$desktop = [Environment]::GetFolderPath('Desktop')
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$consoleArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $KitDir 'scripts\console.ps1')`""
$wsFolder = Get-WorkspaceFolder
New-Item -ItemType Directory -Force -Path $wsFolder | Out-Null

# 「AI 助手」:在终端里运行 ai-desktop(异常退出会停住窗口,方便看报错)
$wslCmd = "-d $Distro --cd ~ -e bash -lic ai-desktop"
if ($wt) { $aiTarget = $wt;     $aiArgs = "new-tab --title `"AI 助手`" --suppressApplicationTitle `"$WslExe`" $wslCmd" }
else     { $aiTarget = $WslExe; $aiArgs = $wslCmd }

$shortcuts = @(
    @{ Name='AI 助手';        Target=$aiTarget; Args=$aiArgs; Icon='assistant'; Desk=$true;  Desc='和 AI 说话、派活' },
    @{ Name='AI 工作区';      Target=$wsFolder; Args='';      Icon='workspace'; Desk=$true;  Desc='AI 做出来的文件都在这里' },
    @{ Name='AI 控制台';      Target=$psExe;    Args=$consoleArgs; Icon='console'; Desk=$true; Desc='查看/启动/管理所有 AI 助手' },
    @{ Name='配置 AI 服务';   Target=$psExe;    Args="$consoleArgs -Action config"; Icon='config'; Desk=$false; Desc='换 AI 服务商、重填 Key' },
    @{ Name='使用教程';       Target=(Join-Path $KitHome 'guide\USAGE.html'); Args=''; Icon='guide'; Desk=$false; Desc='怎么用、照抄就能用的话术' },
    @{ Name='开通 AI 账号指南'; Target=(Join-Path $KitHome 'guide\PROVIDERS.html'); Args=''; Icon='guide'; Desk=$false; Desc='Kimi/DeepSeek 等怎么开通' },
    @{ Name='常见问题';       Target=(Join-Path $KitHome 'guide\TROUBLESHOOTING.html'); Args=''; Icon='guide'; Desk=$false; Desc='出问题按症状查' },
    @{ Name='修复或升级';     Target=(Join-Path $KitDir 'install.bat'); Args=''; Icon='repair'; Desk=$false; Desc='重新运行安装(不会丢文件)' },
    @{ Name="卸载 $AppName";  Target=$psExe;    Args="-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $KitDir 'scripts\uninstall.ps1')`""; Icon='uninstall'; Desk=$false; Desc='卸载(AI 工作区里的文件会保留)' }
)
New-Item -ItemType Directory -Force -Path $StartMenuDir | Out-Null
$made = 0
foreach ($s in $shortcuts) {
    try {
        if (-not (Test-Path $s.Target)) { continue }   # 例如指南没生成出来
        $icon = Get-IconPath $s.Icon
        $style = 1; if ($s.Target -eq $psExe) { $style = 7 }   # 控制台脚本本身不显示黑窗
        New-Shortcut -Path (Join-Path $StartMenuDir "$($s.Name).lnk") -Target $s.Target -Arguments $s.Args `
            -Icon $icon -Description $s.Desc -WorkDir $KitDir -WindowStyle $style
        if ($s.Desk) {
            New-Shortcut -Path (Join-Path $desktop "$($s.Name).lnk") -Target $s.Target -Arguments $s.Args `
                -Icon $icon -Description $s.Desc -WorkDir $KitDir -WindowStyle $style
        }
        $made++
    } catch { Write-Warn2 "「$($s.Name)」创建失败:$($_.Exception.Message)" }
}
Write-Ok "桌面 3 个图标:AI 助手 / AI 工作区 / AI 控制台;开始菜单「$AppName」里还有教程、修复、卸载"

# Windows Terminal 下拉菜单里也加一个「AI 助手」(带图标)
try {
    New-Item -ItemType Directory -Force -Path $WtFragmentDir | Out-Null
    $frag = @{ profiles = @(@{
        guid = '{5c2b3d4e-8f1a-4b6c-9d7e-a1b2c3d4e5f6}'; name = 'AI 助手'
        commandline = "`"$WslExe`" $wslCmd"; icon = (Get-IconPath 'assistant')
        tabTitle = 'AI 助手'; suppressApplicationTitle = $true
    }) } | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText((Join-Path $WtFragmentDir 'agent-kit.json'), $frag, (New-Object System.Text.UTF8Encoding($false)))
} catch { }

# 工作区文件夹:换上自己的图标;把 AI 规范文件和点开头的内部文件夹设为隐藏
try {
    $ini = Join-Path $wsFolder 'desktop.ini'
    if (Test-Path $ini) { & attrib.exe -s -h $ini }
    $iniText = "[.ShellClassInfo]`r`nIconResource=$(Get-IconPath 'workspace'),0`r`nInfoTip=AI 做出来的文件都在这里`r`n"
    [IO.File]::WriteAllText($ini, $iniText, [System.Text.Encoding]::Unicode)
    & attrib.exe +s +h $ini
    & attrib.exe +r $wsFolder
    foreach ($n in @('AGENTS.md', 'CLAUDE.md', '.agent-kit', '.claude', '.opencode', '.obsidian')) {
        $p = Join-Path $wsFolder $n
        if (Test-Path $p) { & attrib.exe +h $p }
    }
} catch { }

# 「设置 → 应用」里能看到并卸载
try {
    New-Item -Path $UninstallKey -Force | Out-Null
    $props = @{
        DisplayName = $AppName; DisplayVersion = $KitVersion; Publisher = 'wsl-agent-kit'
        DisplayIcon = (Get-IconPath 'assistant'); InstallLocation = $KitHome
        UninstallString = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $KitDir 'scripts\uninstall.ps1')`""
        URLInfoAbout = 'https://github.com/Oldcircle/wsl-agent-kit'
    }
    foreach ($k in $props.Keys) { Set-ItemProperty -Path $UninstallKey -Name $k -Value $props[$k] }
    Set-ItemProperty -Path $UninstallKey -Name NoModify -Value 1 -Type DWord
    Set-ItemProperty -Path $UninstallKey -Name NoRepair -Value 1 -Type DWord
} catch { }

# ---------- 10. 可选:Obsidian(舒服地读 AI 写的 Markdown) ----------
$obsExe = Join-Path $env:LOCALAPPDATA 'Programs\Obsidian\Obsidian.exe'
if (-not (Test-Path $obsExe) -and -not (Test-Path (Join-Path $KitHome 'obsidian-asked.txt'))) {
    Set-Content -Path (Join-Path $KitHome 'obsidian-asked.txt') -Value (Get-Date) -Encoding ASCII
    Write-Host ''
    if (Ask-YesNo '顺便装 Obsidian 吗?(免费,用来舒服地阅读 AI 写的文档;以后可在控制台里装)' $false) {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            & winget install --id Obsidian.Obsidian -e --silent --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -eq 0) { Write-Ok 'Obsidian 已安装' }
            else { Write-Warn2 'Obsidian 自动安装失败(它的安装包在 GitHub,国内常下不动),可到 obsidian.md 官网下载' }
        } else { Write-Warn2 '本机没有 winget,请到 obsidian.md 官网下载' }
    }
}
# 装了 Obsidian 且从没打开过:预先登记好仓库,第一次打开直接就是 AI 工作区
$obsCfg = Join-Path $env:APPDATA 'obsidian\obsidian.json'
if ((Test-Path $obsExe) -and -not (Test-Path $obsCfg)) {
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path $obsCfg) | Out-Null
        $id = -join ((1..16) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
        $ts = [long]([DateTimeOffset]::Now.ToUnixTimeMilliseconds())
        $json = @{ vaults = @{ $id = @{ path = $wsFolder; ts = $ts; open = $true } } } | ConvertTo-Json -Depth 5
        [IO.File]::WriteAllText($obsCfg, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Ok 'Obsidian 已设好:打开就是「AI 工作区」'
    } catch { }
}

# ---------- 11. 首次配置 ----------
& $WslExe -d $Distro -e bash -lc 'test -f ~/.config/agent-kit/default-agent' 2>$null
$configured = ($LASTEXITCODE -eq 0)
if (-not $configured) {
    Write-Step '配置 AI 服务(选你开通的那家,填入 Key 或扫码登录)…'
    Write-Note '还没开通?可以选最后一项「先跳过」,之后双击「AI 助手」会再引导。'
    & $WslExe -d $Distro -e bash -lic 'ai-config || true'
} elseif (Ask-YesNo "`nAI 服务之前已经配置过。要重新配置吗?" $false) {
    & $WslExe -d $Distro -e bash -lic 'ai-config || true'
}

try { Stop-Transcript | Out-Null } catch { }
Write-Host ''
Write-Host '=============================================' -ForegroundColor Green
Write-Host '  安装完成!'                                  -ForegroundColor Green
Write-Host '  · 和 AI 说话:双击桌面「AI 助手」'            -ForegroundColor Green
Write-Host '    第一句可以说:介绍一下你能帮我做什么'        -ForegroundColor Green
Write-Host '  · 看 AI 做的文件:双击桌面「AI 工作区」'      -ForegroundColor Green
Write-Host "  · 教程/常见问题:开始菜单 →「$AppName」"      -ForegroundColor Green
Write-Host '=============================================' -ForegroundColor Green
if (Ask-YesNo '现在就打开 AI 助手吗?' $true) {
    Start-Process (Join-Path $desktop 'AI 助手.lnk')
}
exit 0
