#requires -Version 7.0

function Assert-StoryIrAttestation {
    param(
        [Parameter(Mandatory)][string]$StoryPath,
        [Parameter(Mandatory)][string]$DebugInfoPath,
        [Parameter(Mandatory)][string]$AttestationPath
    )

    foreach ($artifactPath in @($StoryPath, $DebugInfoPath, $AttestationPath)) {
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
            throw "Story IR 证明缺少文件: $artifactPath"
        }
    }
    $storyFile = Get-Item -LiteralPath $StoryPath
    $debugInfoFile = Get-Item -LiteralPath $DebugInfoPath
    $attestationFile = Get-Item -LiteralPath $AttestationPath
    $attestation = Get-Content -LiteralPath $attestationFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($attestation.schema -ne 1 -or $attestation.validated -isnot [bool] -or -not $attestation.validated) {
        throw 'Story IR 证明未明确记录 validated=true'
    }
    $storySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $storyFile.FullName).Hash.ToLowerInvariant()
    $debugInfoSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $debugInfoFile.FullName).Hash.ToLowerInvariant()
    if ($attestation.storySha256 -cne $storySha256 -or
        $attestation.debugInfoSha256 -cne $debugInfoSha256) {
        throw 'Story IR 证明哈希与当前 story.div.osi/debug-info 不一致'
    }
    if ([int64]$attestation.storyLastWriteTimeUtcTicks -ne $storyFile.LastWriteTimeUtc.Ticks -or
        [int64]$attestation.debugInfoLastWriteTimeUtcTicks -ne $debugInfoFile.LastWriteTimeUtc.Ticks -or
        $attestationFile.LastWriteTimeUtc -lt $storyFile.LastWriteTimeUtc -or
        $attestationFile.LastWriteTimeUtc -lt $debugInfoFile.LastWriteTimeUtc) {
        throw 'Story IR 证明不是当前编译产物的新鲜证明'
    }
    return $attestation
}

function Write-StoryIrAttestation {
    param(
        [Parameter(Mandatory)][string]$StoryPath,
        [Parameter(Mandatory)][string]$DebugInfoPath,
        [Parameter(Mandatory)][string]$AttestationPath
    )

    foreach ($artifactPath in @($StoryPath, $DebugInfoPath)) {
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
            throw "无法为缺失的 Story IR 产物生成证明: $artifactPath"
        }
    }
    $storyFile = Get-Item -LiteralPath $StoryPath
    $debugInfoFile = Get-Item -LiteralPath $DebugInfoPath
    $document = [ordered]@{
        schema = 1
        validated = $true
        validatedAtUtc = [DateTime]::UtcNow.ToString('O')
        storySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $storyFile.FullName).Hash.ToLowerInvariant()
        debugInfoSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $debugInfoFile.FullName).Hash.ToLowerInvariant()
        storyLastWriteTimeUtcTicks = $storyFile.LastWriteTimeUtc.Ticks
        debugInfoLastWriteTimeUtcTicks = $debugInfoFile.LastWriteTimeUtc.Ticks
    }
    $json = $document | ConvertTo-Json
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($AttestationPath), $json, [Text.UTF8Encoding]::new($false))
    Assert-StoryIrAttestation -StoryPath $StoryPath -DebugInfoPath $DebugInfoPath `
        -AttestationPath $AttestationPath | Out-Null
}
