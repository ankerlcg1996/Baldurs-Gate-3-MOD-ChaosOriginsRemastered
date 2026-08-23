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

function Write-BuildProcessText {
    param(
        [string]$Text,
        [switch]$ErrorStream
    )

    if ([string]::IsNullOrEmpty($Text)) { return }
    $lines = @([regex]::Split($Text, '\r\n|\n|\r'))
    if ($lines.Count -gt 0 -and $lines[-1].Length -eq 0) {
        $lines = @($lines[0..($lines.Count - 2)])
    }
    foreach ($line in $lines) {
        if ($ErrorStream) {
            Write-Error -Message $line -ErrorAction Continue
        } else {
            Write-Output $line
        }
    }
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
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pwshPath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $resolvedScriptPath)) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
    foreach ($argument in $ArgumentList) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw "无法启动构建子进程: $pwshPath" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $processExitCode = $process.ExitCode
    } finally {
        $process.Dispose()
    }

    Write-BuildProcessText -Text $stdout
    Write-BuildProcessText -Text $stderr -ErrorStream
    if ($processExitCode -ne 0) {
        throw "构建子进程脚本失败，退出码: $processExitCode / $resolvedScriptPath"
    }
}
