param(
    [string]$AtlasPath = (Join-Path $PSScriptRoot 'source\Public\ChaosOriginsRemastered\Assets\Textures\Icons\Icons_ChaosOrigins.dds')
)

$ErrorActionPreference = 'Stop'
$atlasFull = [IO.Path]::GetFullPath($AtlasPath)
if (-not (Test-Path -LiteralPath $atlasFull -PathType Leaf)) {
    throw "Icon atlas is missing: $atlasFull"
}

$bytes = [IO.File]::ReadAllBytes($atlasFull)
if ($bytes.Length -lt 128 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'DDS ') {
    throw "Icon atlas is not a DDS file: $atlasFull"
}
if ([BitConverter]::ToInt32($bytes, 12) -ne 512 -or [BitConverter]::ToInt32($bytes, 16) -ne 512) {
    throw 'Icon atlas must remain 512 x 512'
}
if ([Text.Encoding]::ASCII.GetString($bytes, 84, 4) -ne 'DXT5') {
    throw 'Icon atlas must remain DXT5/BC3'
}

# BG3 可读取的旧式 DDS 图集要求深度为 1，且保留区不能含编码器签名。
$bytes[24] = 1
for ($index = 32; $index -le 75; $index++) { $bytes[$index] = 0 }
[IO.File]::WriteAllBytes($atlasFull, $bytes)

Write-Host "Normalized BG3 icon-atlas DDS header: $atlasFull"
