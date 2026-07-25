# ============================================================
#  AI 控制台:原生 Windows 管理面板(WinForms,零依赖)
#  看有哪些 agent、点谁启动谁、设默认、加装、开工作区、重配 AI。
#  由桌面「AI 控制台」快捷方式调起。
# ============================================================

$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$wslExe = Join-Path $env:SystemRoot 'System32\wsl.exe'

# 中文显示名与说明
$AgentInfo = [ordered]@{
    'opencode' = 'OpenCode|主推引擎,任意 Key'
    'claude'   = 'Claude Code|全网最火(闭源)'
    'kimi'     = 'Kimi Code|中文界面,会员登录'
    'qwen'     = 'Qwen Code|阿里通义'
    'codex'    = 'Codex CLI|OpenAI(进阶)'
    'gemini'   = 'Gemini CLI|谷歌(需海外网络)'
    'hermes'   = 'Hermes 爱马仕|常驻助理(进阶)'
    'openclaw' = 'OpenClaw 小龙虾|常驻助理(进阶)'
    'goose'    = 'Goose|Block 通用 agent'
}

function Get-Distro {
    $raw = & $wslExe --list --quiet 2>$null
    if (-not $raw) { return $null }
    $list = $raw | ForEach-Object { "$_".Trim() } | Where-Object { $_ }
    return ($list | Where-Object { $_ -match '^Ubuntu' } | Select-Object -First 1)
}

$Distro = Get-Distro
if (-not $Distro) {
    [System.Windows.Forms.MessageBox]::Show(
        '没有找到 Ubuntu(WSL)。请先双击 install.bat 完成安装。',
        'AI 控制台', 'OK', 'Warning') | Out-Null
    exit 1
}

function Get-Agents {
    # 返回数组:@{Name; Installed; Default}
    $out = & $wslExe -d $Distro -- bash -lc 'ai list --plain' 2>$null
    $rows = @()
    foreach ($line in @($out)) {
        $t = "$line".Trim()
        if ($t -match '^([a-z]+)\|([01])\|([01])$') {
            $rows += [pscustomobject]@{
                Name      = $Matches[1]
                Installed = ($Matches[2] -eq '1')
                Default   = ($Matches[3] -eq '1')
            }
        }
    }
    return $rows
}

function Invoke-InTerminal([string]$bashCmd) {
    # 在可见终端窗口里执行(优先 Windows Terminal)
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    $wslArgs = @('-d', $Distro, '--cd', '~', '--', 'bash', '-lic', $bashCmd)
    if ($wt) { Start-Process $wt.Source -ArgumentList (@('wsl.exe') + $wslArgs) }
    else     { Start-Process $wslExe -ArgumentList $wslArgs }
}

# ---------------- 界面 ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'AI 控制台'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(560, 430)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)

$statusLbl = New-Object System.Windows.Forms.Label
$statusLbl.Location = New-Object System.Drawing.Point(12, 8)
$statusLbl.Size = New-Object System.Drawing.Size(536, 24)
$statusLbl.ForeColor = [System.Drawing.Color]::FromArgb(30, 90, 190)
$statusLbl.Text = '状态读取中…'
$form.Controls.Add($statusLbl)

$lv = New-Object System.Windows.Forms.ListView
$lv.View = 'Details'
$lv.FullRowSelect = $true
$lv.MultiSelect = $false
$lv.HideSelection = $false
$lv.Location = New-Object System.Drawing.Point(12, 36)
$lv.Size = New-Object System.Drawing.Size(390, 336)
[void]$lv.Columns.Add('AI 助手', 150)
[void]$lv.Columns.Add('说明', 160)
[void]$lv.Columns.Add('状态', 72)
$form.Controls.Add($lv)

$tip = New-Object System.Windows.Forms.Label
$tip.Location = New-Object System.Drawing.Point(12, 380)
$tip.Size = New-Object System.Drawing.Size(536, 40)
$tip.ForeColor = [System.Drawing.Color]::DimGray
$tip.Text = '双击 = 启动;★ 是双击桌面「AI 助手」时的默认。'
$form.Controls.Add($tip)

function New-Btn([string]$text, [int]$y) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point(412, $y)
    $b.Size = New-Object System.Drawing.Size(136, 34)
    $form.Controls.Add($b)
    return $b
}
$btnStart   = New-Btn '▶ 启动'         36
$btnDefault = New-Btn '★ 设为默认'     76
$btnInstall = New-Btn '⬇ 安装选中项'  116
$btnWs      = New-Btn '📁 打开工作区'  176
$btnConfig  = New-Btn '🔑 配置 AI 服务' 216
$btnRefresh = New-Btn '↻ 刷新'         256

function Get-KitStatus {
    $out = & $wslExe -d $Distro -- bash -lc 'ai status --plain' 2>$null
    $st = @{}
    foreach ($line in @($out)) {
        if ("$line" -match '^([a-z_]+)=(.*)$') { $st[$Matches[1]] = $Matches[2] }
    }
    return $st
}

function Update-StatusBar {
    $st = Get-KitStatus
    if ($st.Count -eq 0) { $statusLbl.Text = '状态:未读取到(先完成安装/配置)'; return }
    $parts = @()
    if ($st['model'])                 { $parts += "服务:$($st['model'])" }
    if ($st['default'])               { $parts += "默认:$($st['default'])" }
    if ($st['claude_wired'] -eq '1')  { $parts += 'Claude 已接线' }
    if ($st['transcribe'] -eq '1')    { $parts += '视频转写 ✓' }
    if ($parts.Count -eq 0)           { $parts = @('尚未配置 AI 服务(点右侧「配置 AI 服务」)') }
    $statusLbl.Text = ($parts -join '   ·   ')
}

function Refresh-List {
    $lv.Items.Clear()
    $agents = Get-Agents
    if (-not $agents -or $agents.Count -eq 0) {
        $tip.Text = '读取失败:请确认已完成安装(install.bat),然后点「刷新」。'
        return
    }
    foreach ($a in $agents) {
        $disp, $desc = ($AgentInfo[$a.Name] -split '\|', 2)
        if (-not $disp) { $disp = $a.Name; $desc = '' }
        $status = ''
        if ($a.Installed) { $status = '已装' }
        if ($a.Default)   { $status = '已装 ★' }
        $item = New-Object System.Windows.Forms.ListViewItem($disp)
        [void]$item.SubItems.Add($desc)
        [void]$item.SubItems.Add($status)
        $item.Tag = $a
        if (-not $a.Installed) { $item.ForeColor = [System.Drawing.Color]::Gray }
        [void]$lv.Items.Add($item)
    }
    $tip.Text = '双击 = 启动;★ 是双击桌面「AI 助手」时的默认。灰色 = 未安装。'
    Update-StatusBar
}

function Get-Selected {
    if ($lv.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('先在列表里选一个。', 'AI 控制台', 'OK', 'Information') | Out-Null
        return $null
    }
    return $lv.SelectedItems[0].Tag
}

$startAction = {
    $a = Get-Selected; if (-not $a) { return }
    if (-not $a.Installed) {
        [System.Windows.Forms.MessageBox]::Show("「$($a.Name)」还没安装,先点「安装选中项」。", 'AI 控制台', 'OK', 'Information') | Out-Null
        return
    }
    Invoke-InTerminal "ai $($a.Name)"
}
$btnStart.Add_Click($startAction)
$lv.Add_DoubleClick($startAction)

$btnDefault.Add_Click({
    $a = Get-Selected; if (-not $a) { return }
    if (-not $a.Installed) {
        [System.Windows.Forms.MessageBox]::Show('未安装的不能设为默认。', 'AI 控制台', 'OK', 'Information') | Out-Null
        return
    }
    & $wslExe -d $Distro -- bash -lc "ai use $($a.Name)" | Out-Null
    Refresh-List
})

$btnInstall.Add_Click({
    $a = Get-Selected; if (-not $a) { return }
    if ($a.Installed) {
        [System.Windows.Forms.MessageBox]::Show("「$($a.Name)」已经装好了。", 'AI 控制台', 'OK', 'Information') | Out-Null
        return
    }
    Invoke-InTerminal "ai-install $($a.Name); echo; echo 安装结束,按回车关闭窗口; read -r; exit"
    $tip.Text = "正在新窗口里安装 $($a.Name),装完回来点「刷新」。"
})

$btnWs.Add_Click({
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $ws = Join-Path $docs 'AI工作区'
    if (Test-Path $ws) { Start-Process explorer.exe $ws }
    else { [System.Windows.Forms.MessageBox]::Show("没找到 $ws(先完成安装)。", 'AI 控制台', 'OK', 'Warning') | Out-Null }
})

$btnConfig.Add_Click({ Invoke-InTerminal 'ai-config; echo; echo 配置结束,按回车关闭窗口; read -r; exit' })
$btnRefresh.Add_Click({ Refresh-List })

Refresh-List
[void]$form.ShowDialog()
