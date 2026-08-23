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

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

foreach ($path in @($StoryCompilerPath, $sourceHeader, (Join-Path $sourceMod 'meta.lsx'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "缺少 Story 编译输入: $path" }
}
foreach ($dependency in @('Shared', 'SharedDev', 'Gustav', 'GustavDev', 'GustavX')) {
    $path = Join-Path $DependencyVfsPath "Mods\$dependency"
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "缺少 Story 依赖模块: $path" }
}

New-Item -ItemType Directory -Path $stagedMods, (Split-Path $output -Parent) -Force | Out-Null
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
Add-Type -Path (Join-Path $compilerDirectory 'Google.Protobuf.dll')
Add-Type -Path (Join-Path $compilerDirectory 'LSLib.dll')
Add-Type -Path (Join-Path $compilerDirectory 'StoryCompiler.dll')
$debugBytes = [IO.File]::ReadAllBytes($debugInfo)
Require ($debugBytes.Length -gt 4) 'Story IR调试符号为空'
$debugSize = [BitConverter]::ToUInt32($debugBytes, $debugBytes.Length - 4)
$compressedDebug = [byte[]]::new($debugBytes.Length - 4)
[Array]::Copy($debugBytes, $compressedDebug, $compressedDebug.Length)
$debugFlags = [LSLib.LS.CompressionHelpers]::MakeCompressionFlags(
    [LSLib.LS.CompressionMethod]::LZ4,
    [LSLib.LS.LSCompressionLevel]::Fast
)
$debugProto = [LSLib.LS.CompressionHelpers]::Decompress(
    $compressedDebug,
    [int]$debugSize,
    $debugFlags
)
$debugStory = [LSTools.StoryCompiler.StoryDebugInfoMsg]::Parser.ParseFrom($debugProto)
$masteryGoals = @($debugStory.Goals | Where-Object Name -eq 'COS_ChaosMastery')
Require ($masteryGoals.Count -eq 1) '编译IR必须恰好包含一个 COS_ChaosMastery Goal'
$loadRules = @($debugStory.Rules | Where-Object {
    $_.GoalId -eq $masteryGoals[0].Id -and $_.Name -eq 'LevelGameplayStarted(2)'
})
Require ($loadRules.Count -eq 1) '编译IR必须恰好包含一个掌控读档root规则'

$masterySource = Join-Path $sourceMod 'Story\RawFiles\Goals\COS_ChaosMastery.txt'
$masteryLines = [IO.File]::ReadAllLines($masterySource)
$loadSequence = @(
    'IF',
    'LevelGameplayStarted(_, _)',
    'AND',
    'DB_Avatars(_Character)',
    'AND',
    'HasPassive(_Character, "COS_ChaosOriginMarker", 1)',
    'THEN',
    'PROC_COS_SyncMastery(_Character);'
)
$loadStart = -1
for ($lineIndex = 0; $lineIndex -le $masteryLines.Length - $loadSequence.Count; $lineIndex++) {
    $matchesSequence = $true
    for ($sequenceIndex = 0; $sequenceIndex -lt $loadSequence.Count; $sequenceIndex++) {
        if ($masteryLines[$lineIndex + $sequenceIndex] -cne $loadSequence[$sequenceIndex]) {
            $matchesSequence = $false
            break
        }
    }
    if ($matchesSequence) {
        Require ($loadStart -eq -1) '掌控读档root规则在源码中重复'
        $loadStart = $lineIndex + 1
    }
}
Require ($loadStart -gt 0) '掌控读档root规则源码缺失'
$loadRule = $loadRules[0]
Require ($loadRule.ConditionsStartLine -eq $loadStart -and `
    $loadRule.ConditionsEndLine -eq ($loadStart + 5) -and `
    $loadRule.ActionsStartLine -eq ($loadStart + 7) -and `
    $loadRule.ActionsEndLine -eq ($loadStart + 7) -and `
    @($loadRule.Actions | Where-Object Line -eq ($loadStart + 7)).Count -eq 1) `
    '编译IR的掌控读档root规则行映射不完整'
$rootNodeLines = @($debugStory.Nodes | Where-Object RuleId -eq $loadRule.Id | ForEach-Object Line)
Require (($rootNodeLines -contains ($loadStart + 3)) -and ($rootNodeLines -contains ($loadStart + 5))) `
    '编译IR的掌控读档root缺少 DB_Avatars 或 marker AND节点'
foreach ($functionSignature in @(
    @{ Name = 'LevelGameplayStarted'; Arity = 2 },
    @{ Name = 'DB_Avatars'; Arity = 1 },
    @{ Name = 'HasPassive'; Arity = 3 },
    @{ Name = 'PROC_COS_SyncMastery'; Arity = 1 }
)) {
    Require (@($debugStory.Functions | Where-Object {
        $_.Name -eq $functionSignature.Name -and $_.Params.Count -eq $functionSignature.Arity
    }).Count -eq 1) "编译IR缺少root函数签名: $($functionSignature.Name)/$($functionSignature.Arity)"
}

Write-Host "Story 编译及IR root反解完成: $output"
