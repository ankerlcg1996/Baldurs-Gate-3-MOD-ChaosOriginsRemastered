param(
    [Parameter(Mandatory)][string]$Path,
    [string]$CandidatePak = 'C:/Users/ankerlcg/Desktop/博德之门3mod/ChaosOriginsStory-1.0.1.72.pak',
    [long]$Version64 = 36028799166447690,
    [switch]$SeedOnly,
    [switch]$StatusWatchersRemoved,
    [ValidateSet('SeedOnly', 'CaptureApply')][string]$Partition = 'SeedOnly',
    [string]$LslibPath = 'C:/Users/ankerlcg/Documents/ChatGPT/博德之门3Mod/.tools/lslib-duplication-fix/StoryCompiler/bin/Release/net8.0/LSLib.dll'
)
$ErrorActionPreference = 'Stop'
Add-Type -Path $LslibPath
function Read-Pak([string]$File) {
    $p = ([LSLib.LS.PackageReader]::new()).Read($File, $false)
    try {
        $files = @{}
        foreach ($entry in $p.Files) {
            $s = $entry.CreateContentReader()
            $m = [IO.MemoryStream]::new()
            try { $s.CopyTo($m); $files.Add($entry.Name, $m.ToArray()) }
            finally { $s.Dispose(); $m.Dispose() }
        }
        return $files
    } finally { $p.Dispose() }
}
function Text([byte[]]$Bytes) { [Text.Encoding]::UTF8.GetString($Bytes).Replace("`r`n", "`n").TrimStart([char]0xFEFF) }
function Hash([byte[]]$Bytes) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)) }
$actual = Read-Pak $Path
$candidate = Read-Pak $CandidatePak
$prefix = 'Mods/ChaosOriginsStory/Story/RawFiles/Goals/'
$base = $prefix + 'COS_BaseAfterCreation.txt'
$config = $prefix + 'COS_Config.txt'
$binary = 'Mods/ChaosOriginsStory/Story/story.div.osi'
$metaName = 'Mods/ChaosOriginsStory/meta.lsx'
if (!$StatusWatchersRemoved -and ((Text $actual[$base]) -match 'PROC_COS_ConfigSyncGrants\(_Character\);' -or
    (Text $actual[$config]) -match 'PROC_COS_ConfigSyncGrants\(_Character\);')) {
    throw 'Automatic grant runtime entry is still connected'
}
$baseBlock = "PROC`nPROC_COS_SyncBaseAfterCreation((CHARACTER)_Character)`nTHEN`nPROC_COS_ConfigSyncGrants(_Character);`n"
$configCall = "PROC_COS_ConfigSyncGrants(_Character);`n"
$expectedBase = if ($StatusWatchersRemoved) { Text $candidate[$base] } else { (Text $candidate[$base]).Replace($baseBlock, '') }
if ((Text $actual[$base]) -cne $expectedBase) {
    throw 'Base Story changes exceed removal of automatic grant entry'
}
$expectedConfig = if ($StatusWatchersRemoved) { Text $candidate[$config] } else { (Text $candidate[$config]).Replace($configCall, '') }
if ($StatusWatchersRemoved) {
    foreach ($event in @('StatusApplied', 'StatusRemoved')) {
        $block = "IF`n$event(_Character, _Status, _, _)`nAND`nDB_COS_GrantOrigin(_, _, _Status, _)`nAND`nHasPassive(_Character, `"COS_ChaosOriginMarker`", 1)`nTHEN`nPROC_COS_SyncOriginGrantMirrors(_Character);`n`n"
        if (!$expectedConfig.Contains($block)) { throw "Missing expected watcher: $event" }
        $expectedConfig = $expectedConfig.Replace($block, '')
    }
}
if ($SeedOnly) {
    $boundary = if ($Partition -eq 'CaptureApply') { 'PROC_COS_SyncOriginGrantMirrors' } else { 'PROC_COS_CaptureNativeGrantTags' }
    $start = $expectedConfig.IndexOf("PROC`n$boundary(")
    $end = $expectedConfig.IndexOf('EXITSECTION', $start)
    if ($start -lt 0 -or $end -lt 0) { throw 'Expected grant rule boundaries missing' }
    $expectedConfig = $expectedConfig.Remove($start, $end - $start)
}
if ((Text $actual[$config]) -cne $expectedConfig) {
    throw 'Config Story differs from the selected isolation boundary'
}
if (Compare-Object @($actual.Keys | Sort-Object) @($candidate.Keys | Sort-Object)) {
    throw 'Package inventory changed'
}
foreach ($name in $actual.Keys | Where-Object { $_ -notin @($base, $config, $binary, $metaName) }) {
    if ((Hash $actual[$name]) -ne (Hash $candidate[$name])) { throw "Unexpected content change: $name" }
}
[xml]$meta = Text $actual[$metaName]
[xml]$candidateMeta = Text $candidate[$metaName]
$versions = $meta.SelectNodes('//node[@id="ModuleInfo"]//attribute[@id="Version64"]')
if ($versions.Count -ne 2) { throw 'Expected two version fields' }
foreach ($v in $versions) {
    if ($v.value -ne [string]$Version64) { throw 'Wrong candidate version' }
    $v.value = '0'
}
foreach ($v in $candidateMeta.SelectNodes('//node[@id="ModuleInfo"]//attribute[@id="Version64"]')) { $v.value = '0' }
if ($meta.OuterXml -cne $candidateMeta.OuterXml) { throw 'Metadata changed beyond version' }
$stream = [IO.MemoryStream]::new([byte[]]$actual[$binary])
try {
    $story = ([LSLib.LS.Story.StoryReader]::new()).Read($stream)
    $rules = @($story.Nodes.Values | Where-Object { $_ -is [LSLib.LS.Story.RuleNode] })
    $expectedRules = if ($StatusWatchersRemoved) { 279 } elseif (!$SeedOnly) { 280 } elseif ($Partition -eq 'CaptureApply') { 271 } else { 261 }
    if ($rules.Count -ne $expectedRules) { throw "Expected $expectedRules retained rules; got $($rules.Count)" }
    $requiredRoots = if (!$SeedOnly) { @('PROC_COS_ConfigSyncGrants', 'PROC_COS_SeedGrantMap', 'PROC_COS_CaptureNativeGrantTags', 'PROC_COS_ToggleGrantOption') } elseif ($Partition -eq 'CaptureApply') { @('PROC_COS_SeedGrantMap', 'PROC_COS_CaptureNativeGrantTags', 'PROC_COS_EnsureGrantOptions', 'PROC_COS_ApplyGrantOptions') } else { @('PROC_COS_SeedGrantMap') }
    foreach ($name in $requiredRoots) {
        if (@($rules | Where-Object { $_.GetRoot($story).Name -eq $name }).Count -eq 0) { throw "Missing retained rule: $name" }
    }
    $entryCount = 0
    foreach ($r in $rules) {
        $entryCount += @($r.Calls | Where-Object Name -eq 'PROC_COS_ConfigSyncGrants').Count
        if (!$StatusWatchersRemoved -and @($r.Calls | Where-Object Name -eq 'PROC_COS_ConfigSyncGrants').Count -gt 0) { throw 'Compiled automatic grant entry remains' }
        if ($SeedOnly -and @($r.Calls | Where-Object Name -eq 'PROC_COS_SeedGrantMap').Count -gt 0) { throw 'Seed must remain disconnected' }
    }
    if ($StatusWatchersRemoved -and $entryCount -ne 2) { throw 'Both automatic grant entries must be restored' }
} finally { $stream.Dispose() }
"PASS: isolation boundary verified; StatusWatchersRemoved=$StatusWatchersRemoved; SeedOnly=$SeedOnly; Partition=$Partition; $expectedRules rules retained; remaining content matches .72"
