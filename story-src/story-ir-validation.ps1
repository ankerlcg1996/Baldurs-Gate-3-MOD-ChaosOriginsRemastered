#requires -Version 7.0

. (Join-Path $PSScriptRoot 'story-ir-attestation.ps1')

function Require-StoryIr([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Assert-CompiledStoryIr {
    param(
        [Parameter(Mandatory)][string]$StoryPath,
        [Parameter(Mandatory)][string]$DebugInfoPath,
        [Parameter(Mandatory)][string]$CompilerDirectory,
        [Parameter(Mandatory)][string]$MasterySourcePath,
        [Parameter(Mandatory)][string]$AttestationPath
    )

    foreach ($path in @($StoryPath, $DebugInfoPath, $MasterySourcePath)) {
        Require-StoryIr (Test-Path -LiteralPath $path -PathType Leaf) "Story IR 验证缺少输入: $path"
    }
    Add-Type -Path (Join-Path $CompilerDirectory 'Google.Protobuf.dll')
    Add-Type -Path (Join-Path $CompilerDirectory 'LSLib.dll')
    Add-Type -Path (Join-Path $CompilerDirectory 'StoryCompiler.dll')

    $debugBytes = [IO.File]::ReadAllBytes($DebugInfoPath)
    Require-StoryIr ($debugBytes.Length -gt 4) 'Story IR调试符号为空'
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
    Require-StoryIr ($masteryGoals.Count -eq 1) '编译IR必须恰好包含一个 COS_ChaosMastery Goal'
    $loadRules = @($debugStory.Rules | Where-Object {
        $_.GoalId -eq $masteryGoals[0].Id -and $_.Name -eq 'LevelGameplayStarted(2)'
    })
    Require-StoryIr ($loadRules.Count -eq 1) '编译IR必须恰好包含一个掌控读档root规则'

    $masteryLines = [IO.File]::ReadAllLines($MasterySourcePath)
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
            Require-StoryIr ($loadStart -eq -1) '掌控读档root规则在源码中重复'
            $loadStart = $lineIndex + 1
        }
    }
    Require-StoryIr ($loadStart -gt 0) '掌控读档root规则源码缺失'
    $loadRule = $loadRules[0]
    Require-StoryIr ($loadRule.ConditionsStartLine -eq $loadStart -and
        $loadRule.ConditionsEndLine -eq ($loadStart + 5) -and
        $loadRule.ActionsStartLine -eq ($loadStart + 7) -and
        $loadRule.ActionsEndLine -eq ($loadStart + 7) -and
        @($loadRule.Actions | Where-Object Line -eq ($loadStart + 7)).Count -eq 1) `
        '编译IR的掌控读档root规则行映射不完整'
    $rootNodeLines = @($debugStory.Nodes | Where-Object RuleId -eq $loadRule.Id | ForEach-Object Line)
    Require-StoryIr (($rootNodeLines -contains ($loadStart + 3)) -and
        ($rootNodeLines -contains ($loadStart + 5))) `
        '编译IR的掌控读档root缺少 DB_Avatars 或 marker AND节点'
    foreach ($functionSignature in @(
        @{ Name = 'LevelGameplayStarted'; Arity = 2 },
        @{ Name = 'DB_Avatars'; Arity = 1 },
        @{ Name = 'HasPassive'; Arity = 3 },
        @{ Name = 'PROC_COS_SyncMastery'; Arity = 1 }
    )) {
        Require-StoryIr (@($debugStory.Functions | Where-Object {
            $_.Name -eq $functionSignature.Name -and $_.Params.Count -eq $functionSignature.Arity
        }).Count -eq 1) "编译IR缺少root函数签名: $($functionSignature.Name)/$($functionSignature.Arity)"
    }

    Write-StoryIrAttestation -StoryPath $StoryPath -DebugInfoPath $DebugInfoPath `
        -AttestationPath $AttestationPath
    return Assert-StoryIrAttestation -StoryPath $StoryPath -DebugInfoPath $DebugInfoPath `
        -AttestationPath $AttestationPath
}
