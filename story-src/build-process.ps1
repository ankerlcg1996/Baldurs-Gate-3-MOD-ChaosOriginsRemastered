#requires -Version 7.0

function Assert-BuildPwshPath {
    param([Parameter(Mandatory)][string]$PwshPath)

    $expectedPath = [IO.Path]::GetFullPath((Join-Path $PSHOME 'pwsh.exe'))
    $candidatePath = [IO.Path]::GetFullPath($PwshPath)
    if ([IO.Path]::GetFileName($candidatePath) -cne 'pwsh.exe' -or
        -not $candidatePath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "构建子进程必须使用当前 PowerShell 7 安装目录中的 pwsh.exe: expected=$expectedPath actual=$candidatePath"
    }
    if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
        throw "缺少 PowerShell 7 子进程可执行文件: $candidatePath"
    }
    $resolvedPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $candidatePath).Path)
    if (-not $resolvedPath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "PowerShell 7 子进程解析路径错误: expected=$expectedPath actual=$resolvedPath"
    }
    return $resolvedPath
}

function Invoke-BuildScriptProcess {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$ArgumentList = @()
    )

    $pwshPath = Join-Path $PSHOME 'pwsh.exe'
    $pwshPath = Assert-BuildPwshPath -PwshPath $pwshPath
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "构建子进程脚本不存在: $ScriptPath"
    }
    $resolvedScriptPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ScriptPath).Path)
    & $pwshPath -NoLogo -NoProfile -NonInteractive -File $resolvedScriptPath @ArgumentList
    $processExitCode = $LASTEXITCODE
    if ($processExitCode -ne 0) {
        throw "构建子进程脚本失败，退出码: $processExitCode / $resolvedScriptPath"
    }
}
