# ============================================================
#  AI 控制台:原生 Windows 管理面板(WinForms,零依赖)
#  看有哪些 agent、点谁启动谁、设默认、加装/升级、体检、开工作区、重配 AI。
#  由桌面「AI 控制台」快捷方式调起;-Action config 直接打开配置向导。
# ============================================================
param([string]$Action = '')

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'common.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Show-Msg([string]$text, [string]$icon = 'Information') {
    [void][System.Windows.Forms.MessageBox]::Show($text, $AppName, 'OK', $icon)
}

$Distro = Find-KitDistro
if (-not $Distro) {
    Show-Msg '没有找到 AI 运行环境(Ubuntu)。请先双击安装包里的 install.bat 完成安装。' 'Warning'
    exit 1
}

if ($Action -eq 'config') {
    Start-InTerminal $Distro 'ai-config; echo; read -r -p 配置结束,按回车关闭窗口… _' '配置 AI 服务'
    exit 0
}

$AgentInfo = [ordered]@{
    'opencode' = @('OpenCode',         '主推,任意 Key')
    'claude'   = @('Claude Code',      '全网最火(闭源)')
    'kimi'     = @('Kimi Code',        '中文界面,会员登录')
    'qwen'     = @('Qwen Code',        '阿里通义')
    'codex'    = @('Codex CLI',        'OpenAI(进阶)')
    'gemini'   = @('Gemini CLI',       '谷歌(需海外网络)')
    'hermes'   = @('Hermes 爱马仕',    '常驻助理(进阶)')
    'openclaw' = @('OpenClaw 小龙虾',  '常驻助理(进阶)')
    'goose'    = @('Goose',            'Block 通用 agent')
}

# ---------------- 界面 ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "AI 控制台 · $(Get-KitVersion $KitDir)"
$form.StartPosition = 'CenterScreen'
$form.AutoScaleMode = 'Dpi'
$form.ClientSize = New-Object System.Drawing.Size(600, 468)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$icoPath = Get-IconPath 'console'
if (Test-Path $icoPath) { try { $form.Icon = New-Object System.Drawing.Icon($icoPath) } catch { } }

$statusLbl = New-Object System.Windows.Forms.Label
$statusLbl.Location = New-Object System.Drawing.Point(12, 10)
$statusLbl.Size = New-Object System.Drawing.Size(576, 24)
$statusLbl.ForeColor = [System.Drawing.Color]::FromArgb(30, 90, 190)
$statusLbl.Text = '正在启动 AI 运行环境,第一次可能要十几秒…'
$form.Controls.Add($statusLbl)

$lv = New-Object System.Windows.Forms.ListView
$lv.View = 'Details'
$lv.FullRowSelect = $true
$lv.MultiSelect = $false
$lv.HideSelection = $false
$lv.Location = New-Object System.Drawing.Point(12, 40)
$lv.Size = New-Object System.Drawing.Size(420, 370)
[void]$lv.Columns.Add('AI 助手', 150)
[void]$lv.Columns.Add('说明', 180)
[void]$lv.Columns.Add('状态', 80)
$form.Controls.Add($lv)

$tip = New-Object System.Windows.Forms.Label
$tip.Location = New-Object System.Drawing.Point(12, 418)
$tip.Size = New-Object System.Drawing.Size(576, 44)
$tip.ForeColor = [System.Drawing.Color]::DimGray
$tip.Text = '双击一行 = 启动它;★ 是双击桌面「AI 助手」时打开的那个。'
$form.Controls.Add($tip)

$script:btnY = 40
function New-Btn([string]$text, [int]$gap = 6) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point(444, $script:btnY)
    $b.Size = New-Object System.Drawing.Size(144, 34)
    $form.Controls.Add($b)
    $script:btnY += 34 + $gap
    return $b
}
$btnStart   = New-Btn '启动'
$btnDefault = New-Btn '★ 设为默认'
$btnInstall = New-Btn '安装选中的' 18
$btnWs      = New-Btn '打开 AI 工作区'
$btnConfig  = New-Btn '配置 AI 服务'
$btnUpdate  = New-Btn '全部升级'
$btnDoctor  = New-Btn '体检 / 排障' 18
$btnGuide   = New-Btn '使用教程'
$btnRefresh = New-Btn '刷新'

# ---------------- 数据:一次 wsl 调用读全,后台线程执行,窗口不卡 ----------------
$script:job = $null
function Start-Refresh {
    $statusLbl.Text = '读取中…'
    $lv.Enabled = $false
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript({
        param($wsl, $distro)
        $env:WSL_UTF8 = '1'
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        & $wsl -d $distro -e bash -lc 'ai status --plain' 2>$null
    }).AddArgument($WslExe).AddArgument($Distro)
    $script:job = @{ PS = $ps; Handle = $ps.BeginInvoke() }
    $timer.Start()
}

function Apply-Status($lines) {
    $st = @{}; $agents = @()
    foreach ($line in @($lines)) {
        $t = "$line".Trim()
        if ($t -match '^agent=([a-z]+)\|([01])\|([01])$') {
            $agents += [pscustomobject]@{ Name = $Matches[1]; Installed = ($Matches[2] -eq '1'); Default = ($Matches[3] -eq '1') }
        } elseif ($t -match '^([a-z_]+)=(.*)$') { $st[$Matches[1]] = $Matches[2] }
    }
    $lv.Items.Clear()
    $lv.Enabled = $true
    if ($agents.Count -eq 0) {
        $statusLbl.Text = '没读到状态:AI 环境可能还没装好'
        $tip.Text = '先运行开始菜单里的「修复或升级」,完成后回来点「刷新」。'
        return
    }
    foreach ($a in $agents) {
        $info = $AgentInfo[$a.Name]; if (-not $info) { $info = @($a.Name, '') }
        $status = ''
        if ($a.Installed) { $status = '已装' }
        if ($a.Default)   { $status = '已装 ★' }
        $item = New-Object System.Windows.Forms.ListViewItem($info[0])
        [void]$item.SubItems.Add($info[1])
        [void]$item.SubItems.Add($status)
        $item.Tag = $a
        if (-not $a.Installed) { $item.ForeColor = [System.Drawing.Color]::Gray }
        [void]$lv.Items.Add($item)
    }
    $parts = @()
    if ($st['model'])                { $parts += "服务:$($st['model'])" }
    if ($st['default'])              { $parts += "默认:$($st['default'])" }
    if ($st['claude_wired'] -eq '1') { $parts += 'Claude 已接国内服务' }
    if ($st['transcribe'] -eq '1')   { $parts += '视频转文字 ✓' }
    if (-not $st['default'])         { $parts = @('还没配置 AI 服务 → 点右边「配置 AI 服务」') }
    $statusLbl.Text = ($parts -join '   ·   ')
    $tip.Text = '双击一行 = 启动它;★ 是双击桌面「AI 助手」时打开的那个;灰色 = 没装,选中后点「安装选中的」。'
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 200
$timer.Add_Tick({
    if ($script:job -and $script:job.Handle.IsCompleted) {
        $timer.Stop()
        $out = $null
        try { $out = $script:job.PS.EndInvoke($script:job.Handle) } catch { }
        $script:job.PS.Dispose(); $script:job = $null
        Apply-Status $out
    }
})

function Get-Selected {
    if ($lv.SelectedItems.Count -eq 0) { Show-Msg '先在左边列表里点选一个。'; return $null }
    return $lv.SelectedItems[0].Tag
}

# ---------------- 按钮 ----------------
$startAction = {
    $a = Get-Selected; if (-not $a) { return }
    if (-not $a.Installed) { Show-Msg "「$($a.Name)」还没安装,先点「安装选中的」。"; return }
    Start-InTerminal $Distro "ai $($a.Name)" $AgentInfo[$a.Name][0]
}
$btnStart.Add_Click($startAction)
$lv.Add_DoubleClick($startAction)

$btnDefault.Add_Click({
    $a = Get-Selected; if (-not $a) { return }
    if (-not $a.Installed) { Show-Msg '没安装的不能设为默认。'; return }
    & $WslExe -d $Distro -e bash -lc "ai use $($a.Name)" | Out-Null
    Start-Refresh
})

$btnInstall.Add_Click({
    $a = Get-Selected; if (-not $a) { return }
    if ($a.Installed) { Show-Msg "「$($a.Name)」已经装好了。"; return }
    Start-InTerminal $Distro "ai-install $($a.Name); echo; read -r -p 安装结束,按回车关闭窗口… _" '安装 AI 助手'
    $tip.Text = "正在新窗口里安装 $($a.Name),装完回来点「刷新」。"
})

$btnUpdate.Add_Click({
    Start-InTerminal $Distro 'ai update; echo; read -r -p 升级结束,按回车关闭窗口… _' '升级 AI 助手'
    $tip.Text = '正在新窗口里升级,完成后回来点「刷新」。'
})

$btnWs.Add_Click({
    $ws = Get-WorkspaceFolder
    if (Test-Path $ws) { Start-Process explorer.exe "`"$ws`"" }
    else { Show-Msg "没找到 $ws(先完成安装)。" 'Warning' }
})

$btnConfig.Add_Click({ Start-InTerminal $Distro 'ai-config; echo; read -r -p 配置结束,按回车关闭窗口… _' '配置 AI 服务' })
$btnDoctor.Add_Click({ Start-InTerminal $Distro 'ai doctor; echo; read -r -p 按回车关闭窗口… _' '体检' })
$btnGuide.Add_Click({
    $g = Join-Path $KitHome 'guide\USAGE.html'
    if (Test-Path $g) { Start-Process $g } else { Start-Process (Join-Path $KitDir 'docs') }
})
$btnRefresh.Add_Click({ Start-Refresh })

$form.Add_Shown({ Start-Refresh })
[void]$form.ShowDialog()
