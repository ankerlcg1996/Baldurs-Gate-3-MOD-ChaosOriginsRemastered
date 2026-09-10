#requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$StoryPath,
    [Parameter(Mandatory)][string]$LslibPath,
    [Parameter(Mandatory)][string]$ReportPath
)
$ErrorActionPreference = 'Stop'
Add-Type -Path $LslibPath
$stream = [IO.File]::OpenRead($StoryPath)
try { $story = ([LSLib.LS.Story.StoryReader]::new()).Read($stream) } finally { $stream.Dispose() }
$goals = @($story.Goals.Values | ForEach-Object { $_.Name })
if ($goals.Count -ne 1 -or $goals[0] -ne 'EBS_Exploration') { throw "Unexpected goals: $($goals -join ', ')" }
if ($story.Nodes.Count -eq 0) { throw 'Compiled Story has no nodes' }
$count = 0
foreach ($adapter in $story.Adapters.Values) {
    foreach ($pair in $adapter.Constants.Logical.GetEnumerator()) {
        if ($pair.Key -ne $pair.Value.Index -or -not $pair.Value.IsValid -or $pair.Value.TypeId -eq 0) {
            throw "Invalid constant at adapter $($adapter.Index), slot $($pair.Key)"
        }
        $count++
    }
}
[ordered]@{ goals = $goals; nodes = $story.Nodes.Count; validConstants = $count; sha256 = (Get-FileHash -LiteralPath $StoryPath -Algorithm SHA256).Hash } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ReportPath -Encoding utf8
