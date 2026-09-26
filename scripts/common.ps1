# ============================================================
#  Windows 侧公共函数:install.ps1 / console.ps1 / uninstall.ps1 共用
#  只用 PowerShell 5.1 语法。
# ============================================================

$env:WSL_UTF8 = '1'   # 让 wsl.exe 输出 UTF-8
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

$AppName      = 'AI 办公助手'
$KitHome      = Join-Path $env:LOCALAPPDATA 'AgentKit'      # 安装目录(不依赖用户解压到哪)
$KitDir       = Join-Path $KitHome 'kit'                     # 安装包文件副本
$KitLogDir    = Join-Path $KitHome 'logs'
$KitCacheDir  = Join-Path $KitHome 'cache'
$KitDistroDir = Join-Path $KitHome 'distro'                  # 我们自己导入的 Ubuntu 放这
$KitMarker    = Join-Path $KitHome 'distro-name.txt'         # 记录用的是哪个发行版
$DefaultDistroName = 'AI-Assistant'
$WslExe       = Join-Path $env:SystemRoot 'System32\wsl.exe'
$StartMenuDir = Join-Path ([Environment]::GetFolderPath('Programs')) $AppName
$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AgentKit'
$RunOnceKey   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
$WtFragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\AgentKit'
$ResumeLnkName = '▶ 重启后点我继续安装.lnk'

function Get-KitVersion([string]$root) {
    $f = Join-Path $root 'VERSION'
    if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }
    return 'dev'
}

function Get-IconPath([string]$name) {
    return (Join-Path $KitDir "assets\icons\$name.ico")
}

# 已注册的 WSL 发行版(读注册表,不用解析 wsl --list 的 UTF-16 输出,也不会启动虚拟机)
function Get-WslDistros {
    $base = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path $base)) { return @() }
    $list = @()
    foreach ($k in Get-ChildItem $base -ErrorAction SilentlyContinue) {
        $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
        if ($p -and $p.DistributionName) {
            $list += [pscustomobject]@{ Name = $p.DistributionName; BasePath = $p.BasePath; Version = $p.Version }
        }
    }
    return $list
}

function Test-DistroExists([string]$name) {
    return [bool](Get-WslDistros | Where-Object { $_.Name -eq $name })
}

# 找到安装了本工具的那个发行版:先看记录文件,再看默认名,最后兼容旧版(Ubuntu* 里有 /opt/agent-kit)
function Find-KitDistro([switch]$ProbeLegacy) {
    if (Test-Path $KitMarker) {
        $n = (Get-Content $KitMarker -Raw).Trim()
        if ($n -and (Test-DistroExists $n)) { return $n }
    }
    if (Test-DistroExists $DefaultDistroName) { return $DefaultDistroName }
    if ($ProbeLegacy) {
        foreach ($d in (Get-WslDistros | Where-Object { $_.Name -match '^Ubuntu' })) {
            & $WslExe -d $d.Name -u root -e test -d /opt/agent-kit 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { return $d.Name }
        }
    }
    return $null
}

function Save-KitDistro([string]$name) {
    New-Item -ItemType Directory -Force -Path $KitHome | Out-Null
    Set-Content -Path $KitMarker -Value $name -Encoding ASCII
}

# 快捷方式
function New-Shortcut {
    param([string]$Path, [string]$Target, [string]$Arguments = '', [string]$Icon = '',
          [string]$Description = '', [string]$WorkDir = '', [int]$WindowStyle = 1)
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($Path)
    $lnk.TargetPath = $Target
    if ($Arguments)   { $lnk.Arguments = $Arguments }
    if ($Icon)        { $lnk.IconLocation = "$Icon,0" }
    if ($Description) { $lnk.Description = $Description }
    if ($WorkDir)     { $lnk.WorkingDirectory = $WorkDir }
    $lnk.WindowStyle = $WindowStyle
    $lnk.Save()
}

function Find-WT {
    $cands = @((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'))
    foreach ($c in $cands) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# 用户的「下载」文件夹(可能被改到 D 盘,不能直接拼 %USERPROFILE%\Downloads)
function Get-DownloadsFolder {
    try {
        $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' `
              -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
        if ($v) { $p = [Environment]::ExpandEnvironmentVariables($v); if (Test-Path $p) { return $p } }
    } catch { }
    $p = Join-Path $env:USERPROFILE 'Downloads'
    if (Test-Path $p) { return $p }
    return ''
}

function Get-WorkspaceFolder {
    return (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AI工作区')
}

# 测一个网址的耗时(秒);不通返回 $null。用系统自带 curl.exe,不受 IE 代理设置影响
function Test-UrlSpeed([string]$url, [int]$timeout = 6) {
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (-not (Test-Path $curl)) { return $null }
    $out = & $curl -s -o NUL -r 0-32767 -m $timeout -w '%{http_code} %{time_total}' $url 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
    $parts = "$out".Trim() -split ' '
    if ($parts[0] -match '^[23]') { return [double]::Parse($parts[1], [Globalization.CultureInfo]::InvariantCulture) }
    return $null
}

# Windows 系统代理是否指向本机(Clash/v2rayN 之类):WSL2 默认 NAT 模式下用不上它
function Get-LocalProxy {
    try {
        $inet = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ($inet.ProxyEnable -eq 1 -and "$($inet.ProxyServer)" -match '(127\.0\.0\.1|localhost|\[::1\])') {
            return "$($inet.ProxyServer)"
        }
    } catch { }
    return $null
}

# 在可见终端窗口里执行(优先 Windows Terminal)
function Start-InTerminal([string]$distro, [string]$bashCmd, [string]$title = $AppName) {
    # bashCmd 里不要出现双引号(PowerShell 5.1 传参不会替你转义)
    $wt = Find-WT
    if ($wt) {
        # Windows Terminal 把 ; 当成「再开一个标签」的分隔符,命令里的 ; 必须写成 \;
        $escaped = $bashCmd -replace ';', '\;'
        Start-Process $wt -ArgumentList "new-tab --title `"$title`" --suppressApplicationTitle `"$WslExe`" -d $distro --cd ~ -e bash -lic `"$escaped`""
    } else {
        Start-Process $WslExe -ArgumentList "-d $distro --cd ~ -e bash -lic `"$bashCmd`""
    }
}
