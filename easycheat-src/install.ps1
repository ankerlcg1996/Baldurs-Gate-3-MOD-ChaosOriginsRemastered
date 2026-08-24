#requires -Version 7.0

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$repo = Split-Path $root -Parent
$baseInfo = Get-Content -LiteralPath (Join-Path $root 'base-pak.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$builtPak = Join-Path (Join-Path $repo 'dist') $baseInfo.fileName
$installedPak = Join-Path $env:LOCALAPPDATA ('Larian Studios\Baldur''s Gate 3\Mods\' + $baseInfo.fileName)

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$gameProcesses = @(Get-Process -Name 'bg3', 'bg3_dx11' -ErrorAction SilentlyContinue)
Require ($gameProcesses.Count -eq 0) '游戏仍在运行，拒绝覆盖已加载的 EasyCheat PAK。'
Require (Test-Path -LiteralPath $builtPak -PathType Leaf) "缺少待安装 PAK: $builtPak"
Require (Test-Path -LiteralPath $installedPak -PathType Leaf) "缺少当前已安装 PAK: $installedPak"

$backupDirectory = Join-Path $root 'backups'
New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
$installedHash = (Get-FileHash -LiteralPath $installedPak -Algorithm SHA256).Hash.ToLowerInvariant()
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPak = Join-Path $backupDirectory ("$timestamp-$installedHash.pak")
Copy-Item -LiteralPath $installedPak -Destination $backupPak
Copy-Item -LiteralPath $builtPak -Destination $installedPak -Force

$builtHash = (Get-FileHash -LiteralPath $builtPak -Algorithm SHA256).Hash
$installedNewHash = (Get-FileHash -LiteralPath $installedPak -Algorithm SHA256).Hash
Require ($builtHash -eq $installedNewHash) '安装后的 PAK 哈希与构建产物不一致'
Write-Host "EasyCheat 已安装；旧包备份: $backupPak"
