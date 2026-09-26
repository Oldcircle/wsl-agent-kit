# ============================================================
#  卸载 AI 办公助手
#  「AI 工作区」(文档里的文件夹)永远不删:那是用户的劳动成果。
# ============================================================
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Host ''
Write-Host "=========== 卸载 $AppName ===========" -ForegroundColor Magenta
$ws = Get-WorkspaceFolder
$distro = Find-KitDistro
Write-Host ''
Write-Host "你的文件在「$ws」,卸载不会动它们。" -ForegroundColor Green
Write-Host ''
Write-Host '请选择:'
Write-Host '  1) 完全卸载:删掉图标、开始菜单,以及 AI 运行环境(Ubuntu,约 3-6GB)'
Write-Host '  2) 只删图标和开始菜单,保留 AI 运行环境(以后重装更快)'
Write-Host '  0) 取消'
$c = Read-Host '输入 1 / 2 / 0'
$unregFailed = $false
if ($c -ne '1' -and $c -ne '2') { Write-Host '已取消。'; Start-Sleep 2; exit 0 }

if ($c -eq '1' -and $distro) {
    if ($distro -ne $DefaultDistroName) {
        # 旧版装在通用的 Ubuntu 里,可能也装着别的东西:再确认一次
        Write-Host ''
        Write-Host "AI 环境装在「$distro」里。如果你自己也在用这个 Ubuntu,里面的东西会一起删掉。" -ForegroundColor Yellow
        $y = Read-Host "确定删除 $distro?输入 yes 确认,其他任意键跳过这一步"
        if ($y -ne 'yes') { $distro = $null }
    }
    if ($distro) {
        Write-Host "删除 AI 运行环境 $distro …"
        & $WslExe --unregister $distro
        if ($LASTEXITCODE -ne 0) {
            $unregFailed = $true
            Write-Host "删除 $distro 没成功(代码 $LASTEXITCODE),它的磁盘文件先保留,其余照常卸载。" -ForegroundColor Yellow
            Write-Host '可以重启电脑后再运行一次卸载。' -ForegroundColor Yellow
        }
    }
}

Write-Host '删除图标、开始菜单、终端配置…'
$desktop = [Environment]::GetFolderPath('Desktop')
foreach ($n in @('AI 助手', 'AI 工作区', 'AI 控制台', '▶ 重启后点我继续安装')) {
    Remove-Item (Join-Path $desktop "$n.lnk") -Force -ErrorAction SilentlyContinue
}
Remove-Item $StartMenuDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $WtFragmentDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $UninstallKey -Recurse -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $RunOnceKey -Name 'AgentKitResume' -ErrorAction SilentlyContinue

# 工作区文件夹换回普通图标(文件本身不动)
$ini = Join-Path $ws 'desktop.ini'
if (Test-Path $ini) {
    & attrib.exe -s -h $ini
    Remove-Item $ini -Force -ErrorAction SilentlyContinue
    & attrib.exe -r $ws
}

# 安装目录最后删(本脚本就在里面;PowerShell 已把脚本读进内存,删除不影响执行)
Set-Location $env:TEMP
if ($c -eq '1' -and $unregFailed) {
    # 发行版还注册着:保留它的磁盘文件和记录,否则留下一个「注册了但文件没了」的坏环境,重装时会被误复用
    Get-ChildItem $KitHome -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $KitDistroDir -and $_.FullName -ne $KitMarker } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
} elseif ($c -eq '1') {
    Remove-Item $KitHome -Recurse -Force -ErrorAction SilentlyContinue
} else {
    # 保留安装文件和记录,方便以后「重装」直接复用环境
    Write-Host "安装文件保留在 $KitHome(想重新装:双击里面 kit\install.bat)"
}

Write-Host ''
Write-Host '卸载完成。' -ForegroundColor Green
Write-Host "你的 AI 工作区还在:$ws"
Read-Host '按回车关闭'
