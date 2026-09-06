param(
    [Parameter(Mandatory)][string]$Path,
    [string]$LslibPath = "$PSScriptRoot/.tools/lslib-duplication-fix/StoryCompiler/bin/Release/net8.0/LSLib.dll"
)
$ErrorActionPreference = 'Stop'
Add-Type -Path $LslibPath
$package = $null
$stream = $null
try {
    if ([IO.Path]::GetExtension($Path) -eq '.pak') {
        $package = ([LSLib.LS.PackageReader]::new()).Read($Path, $false)
        $entries = @($package.Files | Where-Object Name -match '(^|/)story.div.osi$')
        if ($entries.Count -ne 1) { throw "Expected one Story binary: $Path" }
        $stream = $entries[0].CreateContentReader()
    } else { $stream = [IO.File]::OpenRead($Path) }
    $story = ([LSLib.LS.Story.StoryReader]::new()).Read($stream)
    if ($story.Goals.Count -eq 0 -or $story.Nodes.Count -eq 0) { throw 'Empty Story' }
    $count = 0
    foreach ($adapter in $story.Adapters.Values) {
        foreach ($pair in $adapter.Constants.Logical.GetEnumerator()) {
            if ($pair.Key -ne $pair.Value.Index -or -not $pair.Value.IsValid -or $pair.Value.TypeId -eq 0) {
                throw "Invalid constant at adapter $($adapter.Index), slot $($pair.Key)"
            }
            $count++
        }
    }
    "PASS: $Path; $($story.Goals.Count) goals, $($story.Nodes.Count) nodes, $count valid constants"
} finally {
    if ($null -ne $stream) { $stream.Dispose() }
    if ($null -ne $package) { $package.Dispose() }
}
