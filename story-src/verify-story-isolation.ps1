param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$BaselinePak,
    [Parameter(Mandatory)][string]$CandidatePak,
    [Parameter(Mandatory)][long]$Version64,
    [string]$LslibPath = 'C:/Users/ankerlcg/Documents/ChatGPT/博德之门3Mod/.tools/lslib-duplication-fix/StoryCompiler/bin/Release/net8.0/LSLib.dll'
)
$ErrorActionPreference = 'Stop'
Add-Type -Path $LslibPath
function Read-PackageBytes([string]$Pak) {
    $package = ([LSLib.LS.PackageReader]::new()).Read($Pak, $false)
    try {
        $files = @{}
        foreach ($entry in $package.Files) {
            $stream = $entry.CreateContentReader()
            $buffer = [IO.MemoryStream]::new()
            try { $stream.CopyTo($buffer); $files.Add($entry.Name, $buffer.ToArray()) }
            finally { $buffer.Dispose(); $stream.Dispose() }
        }
        return $files
    } finally { $package.Dispose() }
}
function Get-BytesHash([byte[]]$Bytes) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}
$actual = Read-PackageBytes $Path
$baseline = Read-PackageBytes $BaselinePak
$candidate = Read-PackageBytes $CandidatePak
if (Compare-Object @($actual.Keys | Sort-Object) @($candidate.Keys | Sort-Object)) {
    throw 'Isolation package inventory differs from candidate'
}
foreach ($name in @($actual.Keys | Where-Object { $_ -match '/Story/' })) {
    if (-not $baseline.ContainsKey($name) -or
        (Get-BytesHash $actual[$name]) -ne (Get-BytesHash $baseline[$name])) {
        throw "Story isolation mismatch: $name"
    }
}
$metaName = 'Mods/ChaosOriginsStory/meta.lsx'
foreach ($name in @($actual.Keys | Where-Object { $_ -notmatch '/Story/' -and $_ -ne $metaName })) {
    if ((Get-BytesHash $actual[$name]) -ne (Get-BytesHash $candidate[$name])) {
        throw "Non-Story content changed: $name"
    }
}
[xml]$meta = [Text.Encoding]::UTF8.GetString($actual[$metaName]).TrimStart([char]0xFEFF)
[xml]$candidateMeta = [Text.Encoding]::UTF8.GetString($candidate[$metaName]).TrimStart([char]0xFEFF)
$versions = $meta.SelectNodes('//node[@id="ModuleInfo"]//attribute[@id="Version64"]')
if ($versions.Count -ne 2) { throw 'Expected module and publish versions' }
foreach ($node in $versions) {
    if ($node.value -ne [string]$Version64) { throw 'Wrong isolation version' }
    $node.value = '0'
}
foreach ($node in $candidateMeta.SelectNodes('//node[@id="ModuleInfo"]//attribute[@id="Version64"]')) {
    $node.value = '0'
}
if ($meta.OuterXml -cne $candidateMeta.OuterXml) { throw 'Metadata changed beyond version' }
"PASS: $($actual.Count) entries; Story matches baseline; all other content matches candidate; version=$Version64"
