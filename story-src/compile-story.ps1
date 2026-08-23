#requires -Version 7.0

param(
    [string]$StoryCompilerPath = 'C:\Users\ankerlcg\Documents\ChatGPT\博德之门3Mod\.tools\lslib-v1.20.4-src\StoryCompiler\bin\Release\net8.0\StoryCompiler.exe',
    [string]$DependencyVfsPath = 'C:\Users\ankerlcg\Documents\ChatGPT\博德之门3Mod\.story-vfs'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$module = 'ChaosOriginsStory'
$sourceMod = Join-Path $root "Mods\$module"
$work = Join-Path $root 'work'
$vfs = Join-Path $work 'vfs'
$stagedMods = Join-Path $vfs 'Mods'
$stagedMod = Join-Path $stagedMods $module
$sourceHeader = Join-Path $sourceMod 'Story\RawFiles\story_header.div'
$stagedHeader = Join-Path $stagedMod 'Story\RawFiles\story_header.div'
$output = Join-Path $work 'compiled-story\story.div.osi'
$debugInfo = Join-Path $work 'compiled-story\story.debug-info.pb'
$attestation = Join-Path $work 'compiled-story\story-ir-attestation.json'

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

. (Join-Path $root 'story-ir-validation.ps1')

foreach ($path in @($StoryCompilerPath, $sourceHeader, (Join-Path $sourceMod 'meta.lsx'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "缺少 Story 编译输入: $path" }
}
foreach ($dependency in @('Shared', 'SharedDev', 'Gustav', 'GustavDev', 'GustavX')) {
    $path = Join-Path $DependencyVfsPath "Mods\$dependency"
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "缺少 Story 依赖模块: $path" }
}

New-Item -ItemType Directory -Path $stagedMods, (Split-Path $output -Parent) -Force | Out-Null
if (Test-Path -LiteralPath $attestation -PathType Leaf) {
    [IO.File]::Delete([IO.Path]::GetFullPath($attestation))
}
foreach ($dependency in @('Shared', 'SharedDev', 'Gustav', 'GustavDev', 'GustavX')) {
    $link = Join-Path $stagedMods $dependency
    if (-not (Test-Path -LiteralPath $link)) {
        New-Item -ItemType Junction -Path $link -Target (Join-Path $DependencyVfsPath "Mods\$dependency") | Out-Null
    }
}
if (Test-Path -LiteralPath $stagedMod) {
    $resolved = (Resolve-Path -LiteralPath $stagedMod).Path
    $resolvedWork = (Resolve-Path -LiteralPath $work).Path
    if (-not $resolved.StartsWith($resolvedWork + [IO.Path]::DirectorySeparatorChar)) {
        throw "拒绝清理工作目录外路径: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Copy-Item -LiteralPath $sourceMod -Destination $stagedMod -Recurse

$sourceHeaderLines = [IO.File]::ReadAllLines($sourceHeader)
$aliasTargets = @{}
foreach ($line in $sourceHeaderLines) {
    if ($line -match '^alias_type \{[^,]+,\s*(\d+),\s*(\d+)\}') {
        $aliasTargets[[int]$matches[1]] = [int]$matches[2]
    }
}
function Resolve-IntrinsicAlias([int]$TypeId) {
    $seen = @{}
    while ($TypeId -gt 5) {
        if ($seen.ContainsKey($TypeId) -or -not $aliasTargets.ContainsKey($TypeId)) {
            throw "无法解析别名类型链: $TypeId"
        }
        $seen[$TypeId] = $true
        $TypeId = $aliasTargets[$TypeId]
    }
    return $TypeId
}
$headerLines = foreach ($line in $sourceHeaderLines) {
    if ($line -match '^enum_type \{([^,]+),\s*(\d+),') {
        'alias_type {' + $matches[1] + ', ' + $matches[2] + ', 1}'
    } elseif ($line -match '^alias_type \{([^,]+),\s*(\d+),\s*(\d+)\}') {
        'alias_type {' + $matches[1] + ', ' + $matches[2] + ', ' + (Resolve-IntrinsicAlias ([int]$matches[3])) + '}'
    } else {
        $line
    }
}
[IO.File]::WriteAllLines($stagedHeader, $headerLines, [Text.UTF8Encoding]::new($false))

Push-Location $root
try {
    & $StoryCompilerPath --game bg3 --game-data-path $vfs --no-packages --allow-type-coercion --mod $module `
        --output $output --debug-info $debugInfo --json
    if ($LASTEXITCODE -ne 0) { throw "StoryCompiler 编译失败，退出码: $LASTEXITCODE" }
} finally {
    Pop-Location
}
if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw 'StoryCompiler 未生成 story.div.osi' }
Require (Test-Path -LiteralPath $debugInfo -PathType Leaf) 'StoryCompiler 未生成IR调试符号'

$compilerDirectory = Split-Path $StoryCompilerPath -Parent
$masterySource = Join-Path $sourceMod 'Story\RawFiles\Goals\COS_ChaosMastery.txt'
$irAttestation = Assert-CompiledStoryIr -StoryPath $output -DebugInfoPath $debugInfo `
    -CompilerDirectory $compilerDirectory -MasterySourcePath $masterySource -AttestationPath $attestation
Require ($irAttestation.validated -eq $true) 'Story IR 验证未返回 validated=true'

Write-Host "Story 编译及IR root反解完成并生成哈希证明: $output"
