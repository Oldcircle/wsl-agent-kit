# ============================================================
#  启用 WSL(需要管理员;由 install.ps1 通过 UAC 单独提权调用)
#  -Mode install:启用 WSL 组件(依次尝试 3 条路,最后一条完全不需要网络)
#  -Mode update :把系统自带的旧版 WSL 升级成新版(老 Win10 常见)
#  退出码:0 成功;1 失败。结果另写入 -ResultFile,供非管理员的父进程读取。
# ============================================================
param(
    [ValidateSet('install', 'update')] [string]$Mode = 'install',
    [string]$ResultFile = ''
)
$ErrorActionPreference = 'Continue'
$env:WSL_UTF8 = '1'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$wsl = Join-Path $env:SystemRoot 'System32\wsl.exe'
$ok = $false

function Say($m, $c = 'Cyan') { Write-Host $m -ForegroundColor $c }

if ($Mode -eq 'install') {
    Say '==> 启用 WSL(适用于 Linux 的 Windows 子系统)…'
    & $wsl --install --no-distribution
    if ($LASTEXITCODE -eq 0) { $ok = $true }
    if (-not $ok) {
        Say '    微软商店通道失败,改用网页下载通道…' Yellow
        & $wsl --install --no-distribution --web-download
        if ($LASTEXITCODE -eq 0) { $ok = $true }
    }
    if (-not $ok) {
        # 老版系统自带的 wsl.exe 不认上面的参数,或网络不通:直接用 DISM 打开两个系统组件(离线可用)
        Say '    改用系统组件方式启用(不需要网络)…' Yellow
        $a = Start-Process dism.exe -ArgumentList '/online','/enable-feature','/featurename:Microsoft-Windows-Subsystem-Linux','/all','/norestart' -Wait -PassThru -NoNewWindow
        $b = Start-Process dism.exe -ArgumentList '/online','/enable-feature','/featurename:VirtualMachinePlatform','/all','/norestart' -Wait -PassThru -NoNewWindow
        # 3010 = 成功但需要重启
        if (@(0, 3010) -contains $a.ExitCode -and @(0, 3010) -contains $b.ExitCode) { $ok = $true }
    }
} else {
    Say '==> 升级 WSL 到新版…'
    & $wsl --update
    if ($LASTEXITCODE -eq 0) { $ok = $true }
    if (-not $ok) {
        Say '    微软商店通道失败,改用网页下载通道…' Yellow
        & $wsl --update --web-download
        if ($LASTEXITCODE -eq 0) { $ok = $true }
    }
}

if ($ResultFile) { Set-Content -Path $ResultFile -Value ([int](-not $ok)) -Encoding ASCII }
if ($ok) { Say '    [OK] 完成' Green; exit 0 }
Say '    [失败] 没能启用 WSL,详见上方输出' Red
Start-Sleep -Seconds 5
exit 1
