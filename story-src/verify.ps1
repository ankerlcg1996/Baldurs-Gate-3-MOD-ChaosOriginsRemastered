#requires -Version 7.0

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$module = 'ChaosOriginsStory'
$moduleUuid = 'a5062238-0d2b-46d1-a093-cb02775b9f57'
$originUuid = 'b751ba19-8aeb-4da5-a515-cf853e4c459c'
$originTagUuid = '2c237035-d1a9-4469-91de-d74d8464c8d5'
$displayHandle = 'hcd7a5c95gbdd1g5784gac8bg86b0dcd0e16a'
$descriptionHandle = 'h50753d28gdf41g50dfgb648gd2f4f9635fec'

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-GitBlobBytes([string]$RepositoryRoot, [string]$ObjectSpec) {
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.WorkingDirectory = $RepositoryRoot
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.ArgumentList.Add('cat-file')
    $startInfo.ArgumentList.Add('blob')
    $startInfo.ArgumentList.Add($ObjectSpec)
    $process = [Diagnostics.Process]::Start($startInfo)
    $stream = [IO.MemoryStream]::new()
    try {
        $process.StandardOutput.BaseStream.CopyTo($stream)
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "git cat-file 失败: $ObjectSpec / $stderr" }
        return $stream.ToArray()
    } finally {
        $stream.Dispose()
        $process.Dispose()
    }
}

$buildProcessHelperPath = Join-Path $root 'build-process.ps1'
$storyIrAttestationHelperPath = Join-Path $root 'story-ir-attestation.ps1'
$storyIrValidationHelperPath = Join-Path $root 'story-ir-validation.ps1'
Require (Test-Path -LiteralPath $buildProcessHelperPath -PathType Leaf) '缺少 build-process.ps1'
Require (Test-Path -LiteralPath $storyIrAttestationHelperPath -PathType Leaf) '缺少 story-ir-attestation.ps1'
Require (Test-Path -LiteralPath $storyIrValidationHelperPath -PathType Leaf) '缺少 story-ir-validation.ps1'

$versionPath = Join-Path $root 'version.json'
Require (Test-Path -LiteralPath $versionPath -PathType Leaf) '缺少 version.json'
$version = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json
Require ($version.schema -eq 1) '不支持的版本文件格式'
foreach ($field in @('major', 'minor', 'revision', 'lastBuild')) {
    Require ($version.$field -is [int] -or $version.$field -is [long]) "版本字段必须为整数: $field"
    Require ([int64]$version.$field -ge 0) "版本字段不得为负数: $field"
}
Require ([int64]$version.lastBuild -le 2147483647) '末位版本号超出 BG3 Version64 范围'
$expectedVersion64 = ([int64]$version.major * 36028797018963968) + `
    ([int64]$version.minor * 140737488355328) + `
    ([int64]$version.revision * 2147483648) + [int64]$version.lastBuild

$repositoryReadmePath = Join-Path (Split-Path $root -Parent) 'README.md'
$storyReadmePath = Join-Path $root 'README.md'
foreach ($readmePath in @($repositoryReadmePath, $storyReadmePath)) {
    Require (Test-Path -LiteralPath $readmePath -PathType Leaf) "缺少工程说明: $readmePath"
    $readmeText = Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8
    Require (-not ($readmeText -match '1\.0\.1\.(?:28|44)|23\s*(?:个|/23)|三个\s*(?:Raw\s*)?Goal')) `
        "工程说明仍含过时版本、23文件或3 Goal口径: $readmePath"
    Require ($readmeText.Contains('version.json')) "工程说明必须以version.json为准: $readmePath"
    if ($readmePath -ceq $repositoryReadmePath) {
        foreach ($repositoryContract in @('38 个正式文件', '六个 Raw Goal', 'DB_Players', '50 倍负重')) {
            Require ($readmeText.Contains($repositoryContract)) `
                "根工程说明缺少全体玩家负重精确契约: $repositoryContract"
        }
    } else {
        foreach ($storyContract in @('38 个正式文件和六个 Goal', '全体玩家 50 倍负重')) {
            Require ($readmeText.Contains($storyContract)) `
                "Story 工程说明缺少全体玩家负重精确契约: $storyContract"
        }
    }
    foreach ($configBoundary in @(
        '每角色 Story DB 随存档保存', '旧存档只补缺失键不覆盖',
        'XAML只发送固定 TutorialEvent不接受任意字符串键', '静态/编译/hash不等于实机验收'
    )) {
        Require ($readmeText.Contains($configBoundary)) `
            "工程说明必须明确原生核心设置边界: $configBoundary ($readmePath)"
    }
}

$storyPath = Join-Path $root "Mods\$module\Story"
$configGoalPath = Join-Path $storyPath 'RawFiles\Goals\COS_Config.txt'
$configStatsPath = Join-Path $root "Public\$module\Stats\Generated\Data\ChaosConfig.txt"
$tutorialEventsPath = Join-Path $root "Public\$module\Tutorials\TutorialEvents.lsx"
$missingConfigInputs = @($configGoalPath, $configStatsPath, $tutorialEventsPath | Where-Object {
    -not (Test-Path -LiteralPath $_ -PathType Leaf)
})
Require ($missingConfigInputs.Count -eq 0) (
    '缺少原生核心设置输入: ' + ($missingConfigInputs -join '; '))

$configGoalEarly = (Get-Content -LiteralPath $configGoalPath -Raw -Encoding UTF8).Replace("`r`n", "`n")
$toggleBlocksEarly = @([regex]::Matches($configGoalEarly,
    '(?ms)^PROC\nPROC_COS_ConfigToggleMechanic\([^\n]*\)\n.*?(?=^(?:PROC|IF|EXITSECTION)\n|\z)') |
    ForEach-Object { $_.Value })
Require ($toggleBlocksEarly.Count -eq 1) `
    '核心设置切换必须且只能定义一个单规则 PROC_COS_ConfigToggleMechanic'
$toggleBlockEarly = $toggleBlocksEarly[0]
$toggleConditionsEarly = $toggleBlockEarly.Substring(
    0, $toggleBlockEarly.IndexOf("`nTHEN`n", [StringComparison]::Ordinal))
Require ($toggleConditionsEarly -match '(?m)^DB_COS_ConfigMechanic\(_Character, _Key, _Enabled\)$' -and
    $toggleConditionsEarly -match '(?m)^IntegerSubtract\(1, _Enabled, _Next\)$') `
    '核心设置切换必须从唯一当前值计算 1 - Enabled'
$toggleActionsEarly = @([regex]::Match($toggleBlockEarly, '(?ms)\nTHEN\n(?<Actions>.*)$').Groups['Actions'].Value -split "`n" |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })
$expectedToggleActionsEarly = @(
    'NOT DB_COS_ConfigMechanic(_Character, _Key, _Enabled);',
    'DB_COS_ConfigMechanic(_Character, _Key, _Next);',
    'PROC_COS_ConfigApplyMechanic(_Character, _Key, _Next);',
    'PROC_COS_ConfigSyncMechanicMirrors(_Character);'
)
Require ($toggleActionsEarly.Count -eq 4 -and
    ($toggleActionsEarly -join "`n") -ceq ($expectedToggleActionsEarly -join "`n")) `
    '核心设置切换 THEN 必须且只能删除当前值、写入反值、应用反值并同步一次镜像'
Require (-not ($toggleBlockEarly -match '(?m)^(?:NOT )?DB_COS_ConfigMechanic\(_Character, _Key, [01]\);?$')) `
    '核心设置切换不得恢复字面量0/1双规则'

. $buildProcessHelperPath
. $storyIrAttestationHelperPath

$buildProcessHelper = Get-Content -LiteralPath $buildProcessHelperPath -Raw -Encoding UTF8
foreach ($processApiToken in @(
    '[Diagnostics.ProcessStartInfo]::new()', 'UseShellExecute = $false',
    'ArgumentList.Add($argument)', 'ReadToEndAsync()', 'WaitForExit()', '$process.ExitCode'
)) {
    Require ($buildProcessHelper.Contains($processApiToken)) `
        "build-process.ps1 缺少真实 Process API 隔离步骤: $processApiToken"
}
Require (-not $buildProcessHelper.Contains('& $pwshPath')) `
    'build-process.ps1 不得退回受调用者 native preference 影响的原生命令调用'
Require (-not $buildProcessHelper.Contains('$LASTEXITCODE')) `
    'build-process.ps1 必须只读取 Process.ExitCode，不得依赖 LASTEXITCODE'
Require (-not $buildProcessHelper.Contains('$PSNativeCommandUseErrorActionPreference =')) `
    'build-process.ps1 不得修改调用者的 PSNativeCommandUseErrorActionPreference'

$cmdMutationRejected = $false
try {
    Assert-BuildPwshPath -PwshPath $env:ComSpec | Out-Null
} catch {
    $cmdMutationRejected = $_.Exception.Message.Contains(
        '构建子进程必须使用当前 PowerShell 7 安装目录中的 pwsh.exe')
}
Require $cmdMutationRejected '构建进程 helper 必须实际拒绝 cmd.exe 变异'
Write-Host 'MUTATION_CMD_EXE=KILLED'

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd(
    [IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$tempFull = [IO.Path]::GetFullPath((Join-Path $tempRoot (
    'cos-build-process-test-' + [guid]::NewGuid().ToString('N'))))
Require ($tempFull.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase) -and
    [IO.Path]::GetFileName($tempFull).StartsWith('cos-build-process-test-',
        [StringComparison]::Ordinal)) "拒绝使用未验证的构建进程临时目录: $tempFull"
[void][IO.Directory]::CreateDirectory($tempFull)
try {
    $unicodeTestDirectory = Join-Path $tempFull '含 空格 中文'
    [void][IO.Directory]::CreateDirectory($unicodeTestDirectory)
    $successScript = Join-Path $unicodeTestDirectory '成功 helper.ps1'
    $exitSevenScript = Join-Path $unicodeTestDirectory '失败 exit 7.ps1'
    $ifFalseScript = Join-Path $unicodeTestDirectory 'IR if false.ps1'
    [IO.File]::WriteAllText($successScript, @'
param([string]$Value)
Write-Output "BUILD_PROCESS_OK:$Value"
[Console]::Error.WriteLine("BUILD_PROCESS_ERROR:$Value")
'@, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($exitSevenScript, @'
Write-Output 'BUILD_PROCESS_EXIT7'
[Console]::Error.WriteLine('BUILD_PROCESS_ERROR_EXIT7')
exit 7
'@, [Text.UTF8Encoding]::new($false))

    $nativePreferenceBeforeTests = $PSNativeCommandUseErrorActionPreference
    try {
        foreach ($nativePreference in @($false, $true)) {
            $PSNativeCommandUseErrorActionPreference = $nativePreference
            $preferenceBeforeCall = $PSNativeCommandUseErrorActionPreference
            $firstOutput = @(Invoke-BuildScriptProcess -ScriptPath $successScript `
                -ArgumentList @('第一次 中文 空格') 2>&1)
            $secondOutput = @(Invoke-BuildScriptProcess -ScriptPath $successScript `
                -ArgumentList @('第二次 中文 空格') 2>&1)
            $firstText = @($firstOutput | ForEach-Object { $_.ToString() })
            $secondText = @($secondOutput | ForEach-Object { $_.ToString() })
            $firstText | ForEach-Object { Write-Host $_ }
            $secondText | ForEach-Object { Write-Host $_ }
            Require ($firstText -contains 'BUILD_PROCESS_OK:第一次 中文 空格' -and
                $firstText -contains 'BUILD_PROCESS_ERROR:第一次 中文 空格') `
                "构建进程 helper 在 nativePreference=$nativePreference 时吞掉首次输出或破坏中文空格参数"
            Require ($secondText -contains 'BUILD_PROCESS_OK:第二次 中文 空格' -and
                $secondText -contains 'BUILD_PROCESS_ERROR:第二次 中文 空格') `
                "构建进程 helper 在 nativePreference=$nativePreference 时重复调用失败或吞掉输出"
            Require ($PSNativeCommandUseErrorActionPreference -eq $preferenceBeforeCall) `
                '构建进程 helper 修改了调用者的 PSNativeCommandUseErrorActionPreference'

            $exitSevenRejected = $false
            try {
                Invoke-BuildScriptProcess -ScriptPath $exitSevenScript | ForEach-Object { Write-Host $_ }
            } catch {
                $exitSevenRejected = $_.Exception.Message.Contains('退出码: 7')
            }
            Require $exitSevenRejected `
                "构建进程 helper 在 nativePreference=$nativePreference 时未严格传播 exit 7"
            Require ($PSNativeCommandUseErrorActionPreference -eq $preferenceBeforeCall) `
                'exit 7 后 helper 修改了调用者的 PSNativeCommandUseErrorActionPreference'
            Write-Host "BUILD_PROCESS_NATIVE_PREFERENCE_$($nativePreference.ToString().ToUpperInvariant())=PASS"
        }
    } finally {
        $PSNativeCommandUseErrorActionPreference = $nativePreferenceBeforeTests
    }
    Require ($PSNativeCommandUseErrorActionPreference -eq $nativePreferenceBeforeTests) `
        '构建进程 helper 双态测试未恢复调用者的 PSNativeCommandUseErrorActionPreference'
    Write-Host 'MUTATION_EXIT7_SWALLOWED=KILLED'

    $fakeStory = Join-Path $unicodeTestDirectory 'story.div.osi'
    $fakeDebug = Join-Path $unicodeTestDirectory 'story.debug-info.pb'
    $missingAttestation = Join-Path $unicodeTestDirectory 'story-ir-attestation.json'
    [IO.File]::WriteAllBytes($fakeStory, [byte[]](1, 2, 3, 4))
    [IO.File]::WriteAllBytes($fakeDebug, [byte[]](5, 6, 7, 8))
    $escapedAttestation = $missingAttestation.Replace("'", "''")
    [IO.File]::WriteAllText($ifFalseScript, @"
if (`$false) {
    [IO.File]::WriteAllText('$escapedAttestation', '{"validated":true}')
}
"@, [Text.UTF8Encoding]::new($false))
    Invoke-BuildScriptProcess -ScriptPath $ifFalseScript
    $ifFalseMutationRejected = $false
    try {
        Assert-StoryIrAttestation -StoryPath $fakeStory -DebugInfoPath $fakeDebug `
            -AttestationPath $missingAttestation | Out-Null
    } catch {
        $ifFalseMutationRejected = $_.Exception.Message.Contains('Story IR 证明缺少文件')
    }
    Require $ifFalseMutationRejected 'Story IR attestation 必须实际拒绝 if(false) 跳过验证变异'
    Write-Host 'MUTATION_IR_IF_FALSE=KILLED'
} finally {
    if ([IO.Directory]::Exists($tempFull)) {
        [IO.Directory]::Delete($tempFull, $true)
    }
}

$buildScriptPath = Join-Path $root 'build.ps1'
Require (Test-Path -LiteralPath $buildScriptPath -PathType Leaf) '缺少 build.ps1'
$buildScript = Get-Content -LiteralPath $buildScriptPath -Raw -Encoding UTF8
foreach ($buildIsolationToken in @(
    '#requires -Version 7.0', "Join-Path `$root 'build-process.ps1'",
    'Invoke-BuildScriptProcess -ScriptPath $compileStoryScript',
    '[IO.File]::Delete([IO.Path]::GetFullPath($storyIrAttestationPath))',
    'Assert-StoryIrAttestation -StoryPath $compiledStoryPath',
    '[AppDomain]::CurrentDomain.GetAssemblies()', 'Add-Type -Path $selectedLslibPath'
)) {
    Require ($buildScript.Contains($buildIsolationToken)) `
        "build.ps1 缺少构建进程或 Story IR 证明门: $buildIsolationToken"
}
Require (-not $buildScript.Contains('(Get-Process -Id $PID).Path')) `
    'build.ps1 不得从宿主进程 MainModule 推断 pwsh 路径'
Require (-not $buildScript.Contains("& (Join-Path `$root 'compile-story.ps1')")) `
    'build.ps1 不得恢复同进程 Story 编译调用'

$compileStorySourcePath = Join-Path $root 'compile-story.ps1'
Require (Test-Path -LiteralPath $compileStorySourcePath -PathType Leaf) '缺少 compile-story.ps1'
$compileStorySource = Get-Content -LiteralPath $compileStorySourcePath -Raw -Encoding UTF8
Require ($compileStorySource.Contains('Assert-CompiledStoryIr') -and
    $compileStorySource.Contains('story-ir-attestation.json')) `
    'compile-story.ps1 必须执行独立 IR root 验证并生成哈希证明'

$compiledStoryPath = Join-Path $root 'work\compiled-story\story.div.osi'
$compiledDebugInfoPath = Join-Path $root 'work\compiled-story\story.debug-info.pb'
$compiledAttestationPath = Join-Path $root 'work\compiled-story\story-ir-attestation.json'
if (Test-Path -LiteralPath $compiledAttestationPath -PathType Leaf) {
    [IO.File]::Delete([IO.Path]::GetFullPath($compiledAttestationPath))
}
Invoke-BuildScriptProcess -ScriptPath $compileStorySourcePath
$verifiedIrAttestation = Assert-StoryIrAttestation -StoryPath $compiledStoryPath `
    -DebugInfoPath $compiledDebugInfoPath -AttestationPath $compiledAttestationPath
Require ($verifiedIrAttestation.validated -eq $true) `
    'verify.ps1 未获得当前 Story 编译产物的 validated=true 运行证明'

$masteryStatsPath = Join-Path $root "Public\$module\Stats\Generated\Data\ChaosMastery.txt"
Require (Test-Path -LiteralPath $masteryStatsPath -PathType Leaf) '缺少 ChaosMastery.txt'
$forbiddenMasteryPaths = @(
    "Public\$module\Lists\PassiveLists.lsx",
    "Public\$module\Progressions\ProgressionDescriptions.lsx",
    "Public\$module\Progressions\Progressions.lsx"
)
foreach ($relative in $forbiddenMasteryPaths) {
    Require (-not (Test-Path -LiteralPath (Join-Path $root $relative))) `
        "失败的 Origin Progression 资源仍存在: $relative"
}

$expectedPackageFiles = @(
    'Localization/Chinese/ChaosOriginsStory.loca',
    'Localization/English/ChaosOriginsStory.loca',
    'Localization/Japanese/ChaosOriginsStory.loca',
    'Localization/Korean/ChaosOriginsStory.loca',
    'Mods/ChaosOriginsStory/GUI/metadata.lsf',
    'Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigEscButton.xaml',
    'Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigEscButton_c.xaml',
    'Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu.xaml',
    'Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu_c.xaml',
    'Mods/ChaosOriginsStory/GUI/StateMachines/Controller.xaml',
    'Mods/ChaosOriginsStory/GUI/StateMachines/Keyboard.xaml',
    'Mods/ChaosOriginsStory/meta.lsx',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_BaseAfterCreation.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMastery.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMechanics.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_GlobalPlayerBenefits.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_OriginStoryRewards.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/story_header.div',
    'Mods/ChaosOriginsStory/Story/story.div.osi',
    'Public/ChaosOriginsStory/Origins/Origins.lsx',
    'Public/ChaosOriginsStory/ActionResourceDefinitions/ActionResourceDefinitions.lsx',
    'Public/ChaosOriginsStory/Assets/Textures/Icons/Icons_ChaosOrigins.dds',
    'Public/ChaosOriginsStory/Assets/Textures/Icons/UIOrigin_Portraits_Chaos.dds',
    'Public/ChaosOriginsStory/Content/UI/[PAK]_ChaosOriginsStory/_merged.lsf',
    'Public/ChaosOriginsStory/GUI/Icons_ChaosOrigins.lsx',
    'Public/ChaosOriginsStory/GUI/UIOrigin_Portraits_Chaos.lsx',
    'Public/ChaosOriginsStory/RootTemplates/COS_Raspberry.lsf',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosDamage.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosFeatures.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosConfig.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosMastery.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosRuntime.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/Interrupt.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/Passive.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/Status_BOOST.txt',
    'Public/ChaosOriginsStory/Tutorials/TutorialEvents.lsx',
    'Public/ChaosOriginsStory/Tags/2c237035-d1a9-4469-91de-d74d8464c8d5.lsf'
) | Sort-Object

$manifestPath = Join-Path $root 'package-files.json'
Require (Test-Path -LiteralPath $manifestPath -PathType Leaf) '缺少 package-files.json'
$manifestDocument = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Require ($manifestDocument.schema -eq 1) '不支持的打包清单格式'
$manifest = @($manifestDocument.files | Sort-Object)
Require ($manifest.Count -eq 38 -and @($manifest | Select-Object -Unique).Count -eq 38) `
    '原生 Story 打包清单必须恰好包含38个唯一文件'
Require (-not (Compare-Object $expectedPackageFiles $manifest)) '原生 Story 打包清单内容错误'

$metaPath = Join-Path $root "Mods\$module\meta.lsx"
Require (Test-Path -LiteralPath $metaPath -PathType Leaf) '缺少模块 meta.lsx'
[xml]$meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$moduleInfo = $meta.SelectSingleNode('//node[@id="ModuleInfo"]')
Require ($null -ne $moduleInfo) 'meta.lsx 缺少 ModuleInfo'
$moduleAttributes = @{}
foreach ($attribute in @($moduleInfo.SelectNodes('attribute'))) { $moduleAttributes[[string]$attribute.id] = [string]$attribute.value }
Require ($moduleAttributes.UUID -eq $moduleUuid) '模块 UUID 错误'
Require ($moduleAttributes.Folder -eq $module) '模块目录名错误'
Require ($moduleAttributes.Type -eq 'Add-on') '模块类型必须为 Add-on'
Require ([int64]$moduleAttributes.Version64 -eq $expectedVersion64) 'meta.lsx Version64 与 version.json 不一致'
$publishVersion = $moduleInfo.SelectSingleNode('children/node[@id="PublishVersion"]/attribute[@id="Version64"]')
Require ($null -ne $publishVersion -and [int64]$publishVersion.value -eq $expectedVersion64) `
    'meta.lsx PublishVersion 与 version.json 不一致'
$dependencies = @($meta.SelectNodes('//node[@id="Dependencies"]/children/node[@id="ModuleShortDesc"]'))
Require ($dependencies.Count -eq 0) '原生 Story 包装必须与已运行 MOD 一致，不声明模块依赖'
$scripts = @($moduleInfo.SelectNodes('children/node[@id="Scripts"]/children/node[@id="Script"]'))
Require ($scripts.Count -eq 2) '原生 Story 包装必须声明两个固定脚本入口'
$scriptUuids = @($scripts | ForEach-Object { [string]$_.SelectSingleNode('attribute[@id="UUID"]').value } | Sort-Object)
Require (-not (Compare-Object $scriptUuids @('0d6510f5-50a3-4ecd-83d8-134c9a640324', '1953f77d-a201-45d7-a194-9b84c34b8461'))) `
    '原生 Story 脚本 UUID 未与已运行 MOD 对齐'
Require ($null -eq $moduleInfo.SelectSingleNode('children/node[@id="TargetModes"]')) `
    '原生 Story 包装不得额外声明 TargetModes'

$originPath = Join-Path $root "Public\$module\Origins\Origins.lsx"
Require (Test-Path -LiteralPath $originPath -PathType Leaf) '缺少 Origins.lsx'
[xml]$originDocument = Get-Content -LiteralPath $originPath -Raw -Encoding UTF8
$origins = @($originDocument.SelectNodes('//node[@id="Origin"]'))
Require ($origins.Count -eq 1) '最小包必须恰好注册一个起源'
$origin = $origins[0]
$originAttributes = @{}
foreach ($attribute in @($origin.SelectNodes('attribute'))) { $originAttributes[[string]$attribute.id] = [string]$attribute.value }
$requiredOrigin = @{
    AppearanceLocked = 'false'
    AvailableInCharacterCreation = '1'
    BackgroundUUID = '76925f0b-3ec8-4f42-86a9-cd4f745af2ac'
    BodyShape = '0'
    BodyType = '0'
    ClassUUID = '784001e2-c96d-4153-beb6-2adbef5abc92'
    DefaultsTemplate = '782183f9-ceb5-4a96-8ac4-56af0319641d'
    IntroDialogUUID = 'f015fd39-a9f2-6ee5-a77b-a28806ac1b7a'
    LockBody = 'false'
    LockClass = 'false'
    LockRace = 'false'
    Name = 'ChaosStoryMinimal'
    Passives = 'DeathSavingThrows;COS_ChaosOriginMarker;COS_Origin_Astarion;COS_Origin_Gale;COS_Origin_Laezel;COS_Origin_Shadowheart;COS_Origin_Wyll;COS_Origin_Karlach;COS_Origin_DarkUrge'
    RaceUUID = '45f4ac10-3c89-4fb2-b37d-f973bb9110c0'
    SubClassUUID = 'd379fdae-b401-4731-8d50-277c73919ae3'
    SubRaceUUID = '30fafb0b-7c8b-4917-bd2a-536233b35d3c'
    UUID = $originUuid
    VoiceTableUUID = '2949c570-0a52-4cfd-8434-50925e18d44b'
}
foreach ($entry in $requiredOrigin.GetEnumerator()) {
    Require ($originAttributes[$entry.Key] -eq $entry.Value) "Origin 字段错误: $($entry.Key)"
}
Require ([string]$origin.SelectSingleNode('attribute[@id="DisplayName"]').handle -eq $displayHandle) '起源名称 handle 错误'
Require ([string]$origin.SelectSingleNode('attribute[@id="Description"]').handle -eq $descriptionHandle) '起源说明 handle 错误'
foreach ($forbidden in @('GlobalTemplate', 'Identity', 'IsHenchman', 'ProgressionTableUUID', 'Unique')) {
    Require (-not $originAttributes.ContainsKey($forbidden)) "Origin 包含风险字段: $forbidden"
}
Require ($null -eq $origin.SelectSingleNode('children/node[@id="AppearanceTags"]')) 'Origin 不得包含 AppearanceTags'
$reallyTags = @($origin.SelectNodes('children/node[@id="ReallyTags"]/attribute[@id="Object"]'))
Require ($reallyTags.Count -eq 1 -and [string]$reallyTags[0].value -eq $originTagUuid) `
    'Origin 必须只包含新的混沌 ReallyTag'

function Normalize-LineEndings([string]$Text) {
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}
$masteryStats = (Normalize-LineEndings (Get-Content -LiteralPath $masteryStatsPath -Raw -Encoding UTF8)).Trim()
$masteryEntryNames = @([regex]::Matches($masteryStats, 'new entry "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
$masteryCarrierEntries = @(1..12 | ForEach-Object { 'COS_ChaosMasteryPointL{0:D2}' -f $_ })
$expectedMasteryEntries = @('COS_ChaosMasteryGuide') + $masteryCarrierEntries + @(
    'Shout_COS_ChaosMastery',
    'Shout_COS_ChaosMasteryTune',
    'Shout_COS_ChaosMasteryCorrect',
    'COS_CHAOS_MASTERY_TUNE',
    'COS_CHAOS_MASTERY_CORRECT',
    'COS_CHAOS_MASTERY_POSITIVE_INFO',
    'COS_CHAOS_MASTERY_NEGATIVE_INFO',
    'COS_CHAOS_MASTERY_CALM_INFO',
    'COS_CHAOS_MASTERY_CALM_LOG',
    'COS_CHAOS_MASTERY_RESULT_L01'
)
Require ($masteryEntryNames.Count -eq 23 -and -not (Compare-Object $expectedMasteryEntries $masteryEntryNames)) `
    'ChaosMastery.txt 必须且只能包含12级掌控资源、母子技能、路线状态和结果状态'
function Get-MasteryBlock([string]$Entry) {
    $pattern = '(?ms)^new entry "' + [regex]::Escape($Entry) + '".*?(?=^new entry |\z)'
    return [regex]::Match($masteryStats, $pattern).Value
}
function Require-MasteryData([string]$Entry, [string]$Field, [string]$Value) {
    $pattern = '(?m)^data "' + [regex]::Escape($Field) + '" "([^"]*)"$'
    $block = Normalize-LineEndings (Get-MasteryBlock $Entry)
    $matches = @([regex]::Matches($block, $pattern))
    Require ($matches.Count -eq 1 -and $matches[0].Groups[1].Value -eq $Value) `
        "掌控混沌字段必须恰好一次且值准确: $Entry / $Field"
}

$actionResourcePath = Join-Path $root "Public\$module\ActionResourceDefinitions\ActionResourceDefinitions.lsx"
[xml]$actionResources = Get-Content -LiteralPath $actionResourcePath -Raw -Encoding UTF8
$masteryResources = @($actionResources.SelectNodes('//node[@id="ActionResourceDefinition"]') | Where-Object {
    [string]$_.SelectSingleNode('attribute[@id="Name"]').value -eq 'COS_ChaosMasteryPoint'
})
Require ($masteryResources.Count -eq 1) '必须且只能定义一个 COS_ChaosMasteryPoint 行动资源'
$masteryResource = $masteryResources[0]
$masteryResourceAttributes = @{}
foreach ($attribute in @($masteryResource.SelectNodes('attribute'))) { $masteryResourceAttributes[[string]$attribute.id] = [string]$attribute.value }
Require ($masteryResourceAttributes.UUID -eq '377db753-9c76-4d31-a2f6-cb02687c95eb') 'COS_ChaosMasteryPoint UUID 错误'
Require ([string]$masteryResource.SelectSingleNode('attribute[@id="DisplayName"]').handle -eq 'h0d010313gb67fg4c89ga5b9g30c58d4fb2f9') 'COS_ChaosMasteryPoint DisplayName handle 错误'
Require ([string]$masteryResource.SelectSingleNode('attribute[@id="Description"]').handle -eq 'hf1437f68g6231g4f22gb12ega9bcfc6189d8') 'COS_ChaosMasteryPoint Description handle 错误'
foreach ($field in @{ IsHidden = 'true'; MaxValue = '12'; ReplenishType = 'Never'; ShowOnActionResourcePanel = 'false' }.GetEnumerator()) {
    Require ($masteryResourceAttributes[$field.Key] -eq $field.Value) "COS_ChaosMasteryPoint 字段错误: $($field.Key)"
}

$lifeSkillResources = @($actionResources.SelectNodes('//node[@id="ActionResourceDefinition"]') | Where-Object {
    [string]$_.SelectSingleNode('attribute[@id="Name"]').value -eq 'COS_ConfigLifeSkill'
})
Require ($lifeSkillResources.Count -eq 1) '必须且只能定义一个 COS_ConfigLifeSkill 设置显示资源'
$lifeSkillResourceAttributes = @{}
foreach ($attribute in @($lifeSkillResources[0].SelectNodes('attribute'))) {
    $lifeSkillResourceAttributes[[string]$attribute.id] = [string]$attribute.value
}
foreach ($field in @{
    UUID = '54b91bc1-2c0f-4e12-9103-7c1555614be6'
    IsHidden = 'true'
    MaxValue = '20'
    PartyActionResource = 'true'
    ReplenishType = 'Never'
    ShowOnActionResourcePanel = 'false'
}.GetEnumerator()) {
    Require ($lifeSkillResourceAttributes[$field.Key] -eq $field.Value) `
        "COS_ConfigLifeSkill 字段错误: $($field.Key)"
}

$masteryRequiredLines = @{
    COS_ChaosMasteryGuide = @('type "PassiveData"', 'data "DisplayName" "h1253cd25g6db6g4704g90e7gadf6ad0df3ed;1"', 'data "Description" "h11f157e4g81c1g4dc8gbd3eg20fbb820812f;1"', 'data "Icon" "COS_Mastery"', 'data "Properties" "Highlighted"', 'data "Boosts" ""')
    COS_ChaosMasteryPointL01 = @('type "PassiveData"', 'data "Icon" "COS_Mastery"', 'data "Properties" "IsHidden"', 'data "Boosts" "ActionResource(COS_ChaosMasteryPoint,1,0)"', 'data "StatsFunctorContext" "OnCreate"', 'data "StatsFunctors" "RestoreResource(COS_ChaosMasteryPoint,1,0)"')
    Shout_COS_ChaosMastery = @('type "SpellData"', 'using "Shout_ActionSurge"', 'data "SpellType" "Shout"', 'data "Level" "0"', 'data "ContainerSpells" "Shout_COS_ChaosMasteryTune;Shout_COS_ChaosMasteryCorrect"', 'data "AIFlags" "CanNotUse"', 'data "TargetConditions" "Self()"', 'data "Icon" "COS_Mastery"', 'data "DisplayName" "h1253cd25g6db6g4704g90e7gadf6ad0df3ed;1"', 'data "Description" "h11f157e4g81c1g4dc8gbd3eg20fbb820812f;1"', 'data "UseCosts" ""', 'data "SpellFlags" "IsLinkedSpellContainer"', 'data "SpellProperties" ""', 'data "TooltipStatusApply" ""', 'data "Requirements" ""', 'data "Cooldown" ""')
    Shout_COS_ChaosMasteryTune = @('type "SpellData"', 'using "Shout_COS_ChaosMastery"', 'data "SpellContainerID" "Shout_COS_ChaosMastery"', 'data "ContainerSpells" ""', 'data "Icon" "COS_MasteryTune"', 'data "DisplayName" "hbfabec61g3070g4e70g8e71gc20633da5d52;1"', 'data "Description" "h0cf72805gf1e4g4f89gbc8fgb4eb4561d859;1"', 'data "UseCosts" "COS_ChaosMasteryPoint:1"', 'data "SpellProperties" ""', 'data "TooltipStatusApply" "ApplyStatus(COS_CHAOS_MASTERY_TUNE,100,1)"', 'data "SpellFlags" ""', 'data "AIFlags" ""', 'data "Requirements" ""', 'data "Cooldown" ""', 'data "TargetConditions" "Self()"')
    Shout_COS_ChaosMasteryCorrect = @('type "SpellData"', 'using "Shout_COS_ChaosMastery"', 'data "SpellContainerID" "Shout_COS_ChaosMastery"', 'data "ContainerSpells" ""', 'data "Icon" "COS_MasteryCorrect"', 'data "DisplayName" "h03a4fec8gb0efg45f9g8c5fgfd91d085f127;1"', 'data "Description" "h0a9761a0g8ebeg4517ga88bgc9605641ea43;1"', 'data "UseCosts" "COS_ChaosMasteryPoint:1"', 'data "SpellProperties" ""', 'data "TooltipStatusApply" "ApplyStatus(COS_CHAOS_MASTERY_CORRECT,100,1)"', 'data "SpellFlags" ""', 'data "AIFlags" ""', 'data "Requirements" ""', 'data "Cooldown" ""', 'data "TargetConditions" "Self()"')
    COS_CHAOS_MASTERY_TUNE = @('type "StatusData"', 'using "COS_CHAOS_RACE_TEMPLATE"', 'data "DisplayName" "hbfabec61g3070g4e70g8e71gc20633da5d52;1"', 'data "Description" "h46000001g0001g4001g8001g000000000001;1"', 'data "Icon" "COS_MasteryTune"', 'data "StackId" "COS_CHAOS_MASTERY_TUNE"', 'data "StackType" "Additive"', 'data "StatusPropertyFlags" "DisableOverhead;DisableCombatlog;IgnoreResting;FreezeDuration;MultiplyEffectsByDuration"')
    COS_CHAOS_MASTERY_CORRECT = @('type "StatusData"', 'using "COS_CHAOS_RACE_TEMPLATE"', 'data "DisplayName" "h03a4fec8gb0efg45f9g8c5fgfd91d085f127;1"', 'data "Description" "h46000002g0002g4002g8002g000000000002;1"', 'data "Icon" "COS_MasteryCorrect"', 'data "StackId" "COS_CHAOS_MASTERY_CORRECT"', 'data "StackType" "Additive"', 'data "StatusPropertyFlags" "DisableOverhead;DisableCombatlog;IgnoreResting;FreezeDuration;MultiplyEffectsByDuration"')
    COS_CHAOS_MASTERY_POSITIVE_INFO = @('type "StatusData"', 'using "COS_CHAOS_RACE_TEMPLATE"', 'data "DisplayName" "h5a27b995g2d15g4a0ega6a1g0e3a96807685;1"', 'data "Description" "hfb12183cg2eefg4c66g88cbg1d4452ea0277;1"', 'data "Icon" "COS_MasteryTune"', 'data "StackId" "COS_CHAOS_MASTERY_POSITIVE_INFO"')
    COS_CHAOS_MASTERY_NEGATIVE_INFO = @('type "StatusData"', 'using "COS_CHAOS_RACE_TEMPLATE"', 'data "DisplayName" "h4cb49a94g6cdag4be4g87eag95893020d052;1"', 'data "Description" "h6a7fc261g0307g46aeg9efcgea4e9d2add92;1"', 'data "Icon" "COS_MasteryCorrect"', 'data "StackId" "COS_CHAOS_MASTERY_NEGATIVE_INFO"')
    COS_CHAOS_MASTERY_CALM_INFO = @('type "StatusData"', 'using "COS_CHAOS_RACE_TEMPLATE"', 'data "DisplayName" "h0f888c08ge96ag4ac4ga02fgd41297ea527e;1"', 'data "Description" "hb04f8bb6g8fceg4b25gaf0egb62b3a9f1b0e;1"', 'data "Icon" "COS_Echo"', 'data "StackId" "COS_CHAOS_MASTERY_CALM_INFO"')
    COS_CHAOS_MASTERY_CALM_LOG = @('type "StatusData"', 'using "COS_CHAOS_RACE_TEMPLATE"', 'data "DisplayName" "h02971056gdde9g4363g80d5gdaf480557af7;1"', 'data "Description" "h8fae3635gba76g4614ga776gf8054d011d82;1"', 'data "Icon" "COS_Echo"', 'data "StackId" "COS_CHAOS_MASTERY_CALM_LOG"', 'data "StackType" "Overwrite"', 'data "StatusPropertyFlags" "DisableOverhead;DisablePortraitIndicator"')
    COS_CHAOS_MASTERY_RESULT_L01 = @('type "StatusData"', 'using "COS_CHAOS_RACE_TEMPLATE"', 'data "DisplayName" "h7f3cf979gec23g46b4g87a5g17724ad407e7;1"', 'data "Description" "hdb91fe36gf912g4c6bga223g06a6647455f7;1"', 'data "Icon" "COS_Echo"', 'data "StackId" "COS_CHAOS_MASTERY_RESULT_L01"', 'data "Boosts" "TemporaryHP(1d4+ProficiencyBonus)"', 'data "StatusPropertyFlags" "DisableOverhead;IgnoreResting"')
}
foreach ($entry in $masteryRequiredLines.Keys) {
    $block = Get-MasteryBlock $entry
    foreach ($line in $masteryRequiredLines[$entry]) {
        $dataMatch = [regex]::Match($line, '^data "([^"]+)" "([^"]*)"$')
        if ($dataMatch.Success) {
            Require-MasteryData $entry $dataMatch.Groups[1].Value $dataMatch.Groups[2].Value
        } else {
            Require ($block.Contains($line)) "掌控混沌字段错误: $entry / $line"
        }
    }
}
foreach ($level in 2..12) {
    $entry = 'COS_ChaosMasteryPointL{0:D2}' -f $level
    $block = (Normalize-LineEndings (Get-MasteryBlock $entry)).Trim()
    $expectedBlock = "new entry `"$entry`"`ntype `"PassiveData`"`nusing `"COS_ChaosMasteryPointL01`""
    Require ($block -ceq $expectedBlock) "掌控点载体必须只继承L01定义: $entry"
}
Require (-not ((Get-MasteryBlock 'COS_ChaosMasteryGuide') -match '(?m)^data "UnlockSpell"')) '掌控混沌指南不得授予技能'
foreach ($entry in @('Shout_COS_ChaosMastery', 'Shout_COS_ChaosMasteryTune', 'Shout_COS_ChaosMasteryCorrect')) {
    Require (-not ((Get-MasteryBlock $entry) -match '(?m)^data "UseCosts" ".*(ActionPoint|BonusActionPoint)')) "掌控混沌技能不得消耗行动点或附赠动作: $entry"
}
foreach ($entry in @('COS_CHAOS_MASTERY_TUNE', 'COS_CHAOS_MASTERY_CORRECT')) {
    Require (-not (Get-MasteryBlock $entry).Contains('DisablePortraitIndicator')) "路线状态不得隐藏肖像提示: $entry"
}
$allMasteryStats = (Get-ChildItem -LiteralPath (Join-Path $root "Public\$module\Stats\Generated\Data") -File -Filter '*.txt' | ForEach-Object {
    Normalize-LineEndings (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8)
}) -join "`n"
foreach ($entry in $expectedMasteryEntries) {
    $pattern = '(?m)^new entry "' + [regex]::Escape($entry) + '"$'
    Require ([regex]::Matches($allMasteryStats, $pattern).Count -eq 1) "掌控混沌条目必须在完整 Stats 中全局唯一: $entry"
}

[xml]$masteryIconDocument = Get-Content -LiteralPath (Join-Path $root "Public\$module\GUI\Icons_ChaosOrigins.lsx") -Raw -Encoding UTF8
$iconUvNodes = @($masteryIconDocument.SelectNodes('//node[@id="IconUV"]'))
$registeredMasteryIcons = @($iconUvNodes | ForEach-Object { [string]$_.SelectSingleNode('attribute[@id="MapKey"]').value })
$expectedIconUv = @{
    COS_Identity = @('0.0009765625', '0.1240234375', '0.0009765625', '0.1240234375')
    COS_Origin = @('0.0009765625', '0.1240234375', '0.0009765625', '0.1240234375')
    COS_Status = @('0.1259765625', '0.2490234375', '0.0009765625', '0.1240234375')
    COS_Lost = @('0.2509765625', '0.3740234375', '0.0009765625', '0.1240234375')
    COS_Power = @('0.3759765625', '0.4990234375', '0.0009765625', '0.1240234375')
    COS_AllIn = @('0.0009765625', '0.1240234375', '0.1259765625', '0.2490234375')
    COS_Echo = @('0.1259765625', '0.2490234375', '0.1259765625', '0.2490234375')
    COS_Strike = @('0.2509765625', '0.3740234375', '0.1259765625', '0.2490234375')
    COS_Genesis = @('0.3759765625', '0.4990234375', '0.1259765625', '0.2490234375')
    COS_Finisher = @('0.0009765625', '0.1240234375', '0.2509765625', '0.3740234375')
    COS_Wound = @('0.1259765625', '0.2490234375', '0.2509765625', '0.3740234375')
    COS_Duality = @('0.2509765625', '0.3740234375', '0.2509765625', '0.3740234375')
    COS_FateRevision = @('0.3759765625', '0.4990234375', '0.2509765625', '0.3740234375')
    COS_Mastery = @('0.0009765625', '0.1240234375', '0.3759765625', '0.4990234375')
    COS_MasteryTune = @('0.1259765625', '0.2490234375', '0.3759765625', '0.4990234375')
    COS_MasteryCorrect = @('0.2509765625', '0.3740234375', '0.3759765625', '0.4990234375')
}
Require ($registeredMasteryIcons.Count -eq 16 -and @($registeredMasteryIcons | Select-Object -Unique).Count -eq 16 -and `
    -not (Compare-Object @($expectedIconUv.Keys | Sort-Object) @($registeredMasteryIcons | Sort-Object))) `
    '技能图集必须恰好注册16个唯一图标键并闭合 COS_Origin'
$uvOwners = @{}
foreach ($node in $iconUvNodes) {
    $key = [string]$node.SelectSingleNode('attribute[@id="MapKey"]').value
    $actualUv = @('U1', 'U2', 'V1', 'V2') | ForEach-Object {
        [string]$node.SelectSingleNode("attribute[@id='$_']").value
    }
    Require (($actualUv -join '|') -ceq ($expectedIconUv[$key] -join '|')) "技能图标UV坐标错误: $key"
    $uvKey = $actualUv -join '|'
    if (-not $uvOwners.ContainsKey($uvKey)) { $uvOwners[$uvKey] = [Collections.Generic.List[string]]::new() }
    $uvOwners[$uvKey].Add($key)
}
$duplicateUvGroups = @($uvOwners.Values | Where-Object { $_.Count -gt 1 })
Require ($duplicateUvGroups.Count -eq 1 -and $duplicateUvGroups[0].Count -eq 2 -and `
    ($duplicateUvGroups[0] -contains 'COS_Identity') -and ($duplicateUvGroups[0] -contains 'COS_Origin')) `
    '图标UV坐标只允许 COS_Origin 有意别名到 COS_Identity'
$masteryIcons = @([regex]::Matches($masteryStats, '(?m)^data "Icon" "([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
foreach ($icon in $masteryIcons) {
    Require (($icon -in @('COS_Mastery', 'COS_MasteryTune', 'COS_MasteryCorrect', 'COS_Echo')) -and `
        ($registeredMasteryIcons -contains $icon)) "掌控混沌使用了未注册或未批准图标: $icon"
}

$passivePath = Join-Path $root "Public\$module\Stats\Generated\Data\Passive.txt"
$passive = (Get-Content -LiteralPath $passivePath -Raw -Encoding UTF8).Trim()
$passiveEntries = @([regex]::Matches($passive, 'new entry "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
$tooltipSourceStatuses = @(
    'COS_CHAOS_ALLIN_L1','COS_CHAOS_ALLIN_L3','COS_CHAOS_ALLIN_L7','COS_CHAOS_GENESIS','COS_CHAOS_KILL',
    'COS_CHAOS_LOST_ARMORCLASS_1','COS_CHAOS_LOST_ATTACK_1','COS_CHAOS_LOST_SAVINGTHROW_1','COS_CHAOS_LOST_SLOW','COS_CHAOS_LOST_SPELLDC_1',
    'COS_CHAOS_MASTERY_CALM_INFO','COS_CHAOS_MASTERY_NEGATIVE_INFO','COS_CHAOS_MASTERY_POSITIVE_INFO','COS_CHAOS_MASTERY_RESULT_L01','COS_CHAOS_STRIKE_ACTIVE',
    'COS_CHAOS_WOUND_LOG_BLEEDING','COS_CHAOS_WOUND_LOG_BLESS','COS_CHAOS_WOUND_LOG_BLINDED','COS_CHAOS_WOUND_LOG_BLOODLUST',
    'COS_CHAOS_WOUND_LOG_BLUR','COS_CHAOS_WOUND_LOG_BURNING','COS_CHAOS_WOUND_LOG_EXTRADAMAGE_ACID','COS_CHAOS_WOUND_LOG_FRIGHTENED',
    'COS_CHAOS_WOUND_LOG_HASTE','COS_CHAOS_WOUND_LOG_HEROISM','COS_CHAOS_WOUND_LOG_INVISIBILITY','COS_CHAOS_WOUND_LOG_MADNESS',
    'COS_CHAOS_WOUND_LOG_MELEEADVANTAGE','COS_CHAOS_WOUND_LOG_MELEEDISADVANTAGE','COS_CHAOS_WOUND_LOG_POISONED','COS_CHAOS_WOUND_LOG_PRONE',
    'COS_CHAOS_WOUND_LOG_RANGEDADVANTAGE','COS_CHAOS_WOUND_LOG_RANGEDDISADVANTAGE','COS_CHAOS_WOUND_LOG_RESTOREDAMAGE',
    'COS_CHAOS_WOUND_LOG_SILENCED','COS_CHAOS_WOUND_LOG_SLOWED','COS_CHAOS_WOUND_LOG_SPELLADVANTAGE',
    'COS_CHAOS_WOUND_LOG_SPELLDISADVANTAGE','COS_CHAOS_WOUND_LOG_STUNNED','COS_CHAOS_WOUND_LOG_VULNERABILITY_ACID','COS_CHAOS_WOUND_LOG_WET'
)
$tooltipPassiveEntries = @($tooltipSourceStatuses | ForEach-Object { 'COS_TT_' + $_.Substring(4) })
$expectedPassiveEntries = @(
    'COS_FixedGuidance30',
    'COS_ChaosOriginMarker',
    'COS_BaseProficiencies',
    'COS_CFG_LIFE_SKILL_CARRIER',
    'COS_BaseStarterSpells',
    'COS_GlobalCarryCapacity50x',
    'COS_Origin_Astarion',
    'COS_Origin_Gale',
    'COS_Origin_Laezel',
    'COS_Origin_Shadowheart',
    'COS_Origin_Wyll',
    'COS_Origin_Karlach',
    'COS_Origin_DarkUrge',
    'COS_FateRevision',
    'COS_ChaosTooltipTemplate'
) + @(1..20 | ForEach-Object { 'COS_CFG_LIFE_SKILL_BONUS_{0:D2}' -f $_ }) + $tooltipPassiveEntries
Require ($passiveEntries.Count -eq $expectedPassiveEntries.Count -and -not (Compare-Object $expectedPassiveEntries $passiveEntries)) `
    'Passive.txt 必须且只能定义基础、生活熟练项、身份、命运改签与黄色词条代理被动'
Require ([regex]::Matches($passive, 'data "Properties" "IsHidden"').Count -eq 25) `
    '基础、全局负重、生活熟练项资源载体与20档技能检定加值必须全部隐藏'
Require ([regex]::Matches($passive, 'data "Properties" "IsToggled;ToggledDefaultOn"').Count -eq 2) `
    '起源身份开关基类与命运改签必须在获得时默认开启'
Require ([regex]::Matches($passive, 'data "ToggleOnFunctors" "ApplyStatus\(COS_ORIGIN_TAG_').Count -eq 7) `
    '七个起源身份被动必须各自应用一个隐藏状态'
Require ([regex]::Matches($passive, 'data "ToggleOffFunctors" "RemoveStatus\(COS_ORIGIN_TAG_').Count -eq 7) `
    '七个起源身份被动必须各自移除一个隐藏状态'
Require ($passive.Contains('new entry "COS_FateRevision"') -and `
    $passive.Contains('data "ToggleOnFunctors" "ApplyStatus(COS_CHAOS_FATE_ENABLED,100,-1)"') -and `
    $passive.Contains('data "ToggleOffFunctors" "RemoveStatus(COS_CHAOS_FATE_ENABLED)"')) `
    '命运改签必须是默认开启且可关闭的状态驱动被动'
foreach ($tooltipPassive in $tooltipPassiveEntries) {
    Require ([regex]::Matches($passive, '(?m)^new entry "' + [regex]::Escape($tooltipPassive) + '"\r?$').Count -eq 1) `
        "黄色词条说明被动缺失或重复: $tooltipPassive"
}
$allTooltipStats = Normalize-LineEndings ((Get-ChildItem -LiteralPath (Join-Path $root "Public\$module\Stats\Generated\Data") -File -Filter '*.txt' | `
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n")
function Resolve-COSTooltipStatsField([string]$Entry, [string]$Field) {
    $currentEntry = $Entry
    $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    while ($visited.Add($currentEntry)) {
        $entryPattern = '(?ms)^new entry "' + [regex]::Escape($currentEntry) + '".*?(?=^new entry |\z)'
        $entryBlocks = @([regex]::Matches($allTooltipStats, $entryPattern))
        Require ($entryBlocks.Count -eq 1) "黄色词条字段解析目标缺失或重复: $Entry -> $currentEntry"
        $fieldMatches = @([regex]::Matches($entryBlocks[0].Value, '(?m)^data "' + [regex]::Escape($Field) + '" "([^"]*)"$'))
        Require ($fieldMatches.Count -le 1) "黄色词条字段重复: $currentEntry / $Field"
        if ($fieldMatches.Count -eq 1) { return $fieldMatches[0].Groups[1].Value }
        $usingMatches = @([regex]::Matches($entryBlocks[0].Value, '(?m)^using "([^"]+)"$'))
        Require ($usingMatches.Count -eq 1) "黄色词条字段无值且无唯一父项: $currentEntry / $Field"
        $currentEntry = $usingMatches[0].Groups[1].Value
    }
    throw "黄色词条 Stats 继承出现循环: $Entry / $Field"
}
foreach ($sourceStatus in $tooltipSourceStatuses) {
    $proxyPassive = 'COS_TT_' + $sourceStatus.Substring(4)
    foreach ($field in @('DisplayName', 'Description', 'Icon')) {
        $sourceValue = Resolve-COSTooltipStatsField $sourceStatus $field
        $proxyValue = Resolve-COSTooltipStatsField $proxyPassive $field
        Require ($sourceValue -ceq $proxyValue) "黄色词条代理字段与原状态不一致: $sourceStatus -> $proxyPassive / $field"
    }
}
$expectedBaseProficienciesBoosts = 'Proficiency(LightArmor);Proficiency(MediumArmor);Proficiency(HeavyArmor);Proficiency(Shields);Proficiency(SimpleWeapons);Proficiency(MartialWeapons);Proficiency(MusicalInstrument)'
$baseProficienciesBlocks = @([regex]::Matches(
    $passive,
    '(?ms)^new entry "COS_BaseProficiencies".*?(?=^new entry |\z)'
))
Require ($baseProficienciesBlocks.Count -eq 1) '必须唯一声明混沌起源基础熟练被动'
$baseProficienciesBoosts = @([regex]::Matches(
    $baseProficienciesBlocks[0].Value,
    '(?m)^data "Boosts" "([^"]*)"\r?$'
))
Require ($baseProficienciesBoosts.Count -eq 1 -and
    $baseProficienciesBoosts[0].Groups[1].Value -ceq $expectedBaseProficienciesBoosts) `
    '混沌起源基础熟练必须只包含装备熟练，不得叠加固定技能检定加值'
$lifeSkillBonusEntries = @([regex]::Matches(
    $passive,
    '(?ms)^new entry "COS_CFG_LIFE_SKILL_BONUS_(?<Value>\d{2})".*?(?=^new entry |\z)'
))
Require ($lifeSkillBonusEntries.Count -eq 20) '生活熟练项必须定义1至20共20个固定技能检定加值被动'
foreach ($lifeSkillBonusEntry in $lifeSkillBonusEntries) {
    $value = [int]$lifeSkillBonusEntry.Groups['Value'].Value
    Require ($value -ge 1 -and $value -le 20) "生活熟练项被动编号必须位于1至20: $value"
    $boostMatches = @([regex]::Matches($lifeSkillBonusEntry.Value,
        '(?m)^data "Boosts" "([^"]*)"\r?$'))
    Require ($boostMatches.Count -eq 1 -and
        $boostMatches[0].Groups[1].Value -ceq (('Athletics,Acrobatics,SleightOfHand,Stealth,Arcana,History,Investigation,Nature,Religion,AnimalHandling,Insight,Medicine,Perception,Survival,Deception,Intimidation,Performance,Persuasion' -split ',' | ForEach-Object { "Skill($_,$value)" }) -join ';')) `
        "生活熟练项被动必须只提供对应的固定技能检定加值: $value"
}
Require (@($lifeSkillBonusEntries | ForEach-Object { $_.Groups['Value'].Value } | Sort-Object -Unique).Count -eq 20) `
    '生活熟练项1至20的被动编号必须唯一'
$lifeSkillCarrierBlocks = @([regex]::Matches($passive,
    '(?ms)^new entry "COS_CFG_LIFE_SKILL_CARRIER".*?(?=^new entry |\z)'))
Require ($lifeSkillCarrierBlocks.Count -eq 1 -and
    $lifeSkillCarrierBlocks[0].Value.Contains('data "Properties" "IsHidden"') -and
    $lifeSkillCarrierBlocks[0].Value.Contains('data "Boosts" "ActionResource(COS_ConfigLifeSkill,20,0)"')) `
    '生活熟练项设置显示资源必须由唯一且固定提供20点隐藏载体'
Require (-not ($passive -match 'ProficiencyBonus\(Skill,|ExpertiseBonus\(')) `
    'Story 版不得额外授予任何技能熟练或专精'
foreach ($spellGrant in @('Target_BoomingBlade_ClassSpell','Target_Guidance','Target_MageHand,,,,Charisma','Target_MinorIllusion,,,,Intelligence','Shout_FeatherFall','Target_Jump','Shout_DisguiseSelf,AddChildren')) {
    Require ($passive.Contains("UnlockSpell($spellGrant)")) "缺少初始法术授予: $spellGrant"
}
Require ([regex]::Matches($passive, 'UnlockSpell\(').Count -eq 7) `
    '静态包必须严格只包含七个基础法术，不得授予种族主动能力'
Require (-not ($passive -match 'COR_|COS_Racial')) '静态被动不得夹带 SE 命名空间或种族主动开关'
foreach ($deferredPassive in @('COS_BaseProficiencies', 'COS_BaseStarterSpells')) {
    Require (-not $originAttributes.Passives.Split(';').Contains($deferredPassive)) `
        "创建阶段不得授予延迟能力: $deferredPassive"
}
$creationIdentityPassives = @($expectedPassiveEntries | Where-Object { $_.StartsWith('COS_Origin_') })
foreach ($identityPassive in $creationIdentityPassives) {
    Require ($originAttributes.Passives.Split(';').Contains($identityPassive)) `
        "创建阶段必须直接授予起源身份开关: $identityPassive"
}

$tagPath = Join-Path $root "resource-src\Public\$module\Tags\$originTagUuid.lsf.lsx"
Require (Test-Path -LiteralPath $tagPath -PathType Leaf) '缺少混沌起源标签源文件'
[xml]$tagDocument = Get-Content -LiteralPath $tagPath -Raw -Encoding UTF8
$tag = $tagDocument.SelectSingleNode('//region[@id="Tags"]/node[@id="Tags"]')
Require ($null -ne $tag) '标签源必须使用 Remastered 的单 Tags 节点结构'
$tagAttributes = @{}
foreach ($attribute in @($tag.SelectNodes('attribute'))) { $tagAttributes[[string]$attribute.id] = [string]$attribute.value }
Require ($tagAttributes.UUID -eq $originTagUuid) '起源标签 UUID 错误'
Require ($tagAttributes.Name -eq 'COS_REALLY_CHAOS') '起源标签名称错误'
$categories = @($tag.SelectNodes('children/node[@id="Categories"]/children/node[@id="Category"]/attribute[@id="Name"]') | ForEach-Object { [string]$_.value } | Sort-Object)
Require (-not (Compare-Object $categories @('Code', 'Dialog', 'DialogHidden'))) `
    '起源标签分类必须严格为 Code、Dialog、DialogHidden'
Require ($categories -notcontains 'Race' -and $categories -notcontains 'PlayerRace') `
    '起源身份标签绝不能注册成 Race 或 PlayerRace'

$identityHandles = @(
    'hfa05cce9gef4dg570bgbc1fg7187d154129d',
    'h4bf4229cg4ca7g5b86ga678g71397f548bd6',
    'hc53c9c68g2e77g5942gb976gef3da865ae2f',
    'h8e938e08g4ff5g5681gab82gc0174825c89b',
    'hbb2cc0a8gfdcdg5a4ag9783gf62a2527e686',
    'hcf23c2c6ga9a3g55bega9c4g60781e86156a',
    'h47aa1ba3g2956g5ba5gb309g7e66f6e19d84',
    'hdc7f2089gaa8bg493bg910fg96d1eae6ce0e'
)
$configMirrorDisplayHandles = [ordered]@{
    COS_CFG_MECH_POWER = 'h73000111g0111g4111g8111g000000000111'
    COS_CFG_MECH_WOUND = 'h73000112g0112g4112g8112g000000000112'
    COS_CFG_MECH_KILLPOWER = 'h73000113g0113g4113g8113g000000000113'
    COS_CFG_MECH_DUALITY = 'h73000114g0114g4114g8114g000000000114'
    COS_CFG_MECH_ALLIN = 'h73000115g0115g4115g8115g000000000115'
    COS_CFG_MECH_FATE = 'h73000116g0116g4116g8116g000000000116'
    COS_CFG_MECH_GENESIS = 'h73000117g0117g4117g8117g000000000117'
    COS_CFG_MECH_STRIKE = 'h73000118g0118g4118g8118g000000000118'
    COS_CFG_MECH_MASTERY = 'h73000119g0119g4119g8119g000000000119'
}
$masteryLocalizationHandles = @(
    'h0d010313gb67fg4c89ga5b9g30c58d4fb2f9',
    'hf1437f68g6231g4f22gb12ega9bcfc6189d8',
    'h1253cd25g6db6g4704g90e7gadf6ad0df3ed',
    'h11f157e4g81c1g4dc8gbd3eg20fbb820812f',
    'hbfabec61g3070g4e70g8e71gc20633da5d52',
    'h0cf72805gf1e4g4f89gbc8fgb4eb4561d859',
    'h03a4fec8gb0efg45f9g8c5fgfd91d085f127',
    'h0a9761a0g8ebeg4517ga88bgc9605641ea43',
    'h5a27b995g2d15g4a0ega6a1g0e3a96807685',
    'hfb12183cg2eefg4c66g88cbg1d4452ea0277',
    'h4cb49a94g6cdag4be4g87eag95893020d052',
    'h6a7fc261g0307g46aeg9efcgea4e9d2add92',
    'h0f888c08ge96ag4ac4ga02fgd41297ea527e',
    'hb04f8bb6g8fceg4b25gaf0egb62b3a9f1b0e',
    'h02971056gdde9g4363g80d5gdaf480557af7',
    'h8fae3635gba76g4614ga776gf8054d011d82',
    'h7f3cf979gec23g46b4g87a5g17724ad407e7',
    'hdb91fe36gf912g4c6bga223g06a6647455f7',
    'h46000001g0001g4001g8001g000000000001',
    'h46000002g0002g4002g8002g000000000002'
)
$expectedHandles = (@($descriptionHandle, $displayHandle) + $identityHandles +
    $masteryLocalizationHandles + @($configMirrorDisplayHandles.Values)) | Sort-Object
$masterySimpleDescriptionHandles = @(
    'h11f157e4g81c1g4dc8gbd3eg20fbb820812f',
    'h0cf72805gf1e4g4f89gbc8fgb4eb4561d859',
    'h0a9761a0g8ebeg4517ga88bgc9605641ea43',
    'h09c3063egc130g48c2g8414g0535ea4196eb'
)
$masteryExactTexts = @{
    Chinese = @{
        h0d010313gb67fg4c89ga5b9g30c58d4fb2f9 = '掌控点'
        hf1437f68g6231g4f22gb12ega9bcfc6189d8 = '隐藏资源。混沌起源每级获得1点，最多12点；休息不会恢复。'
        h1253cd25g6db6g4704g90e7gadf6ad0df3ed = '掌控混沌'
        h11f157e4g81c1g4dc8gbd3eg20fbb820812f = '消耗1点掌控混沌，选择增加1层调律或厄兆纠偏。洗点会清空两条路线，并返还当前等级已经获得的全部点数。'
        hbfabec61g3070g4e70g8e71gc20633da5d52 = '调律'
        h0cf72805gf1e4g4f89gbc8fgb4eb4561d859 = '消耗1点掌控混沌，增加1层调律。'
        h03a4fec8gb0efg45f9g8c5fgfd91d085f127 = '厄兆纠偏'
        h0a9761a0g8ebeg4517ga88bgc9605641ea43 = '消耗1点掌控混沌，增加1层厄兆纠偏。'
        h1d501940gbda0g4737g8fecg66e1bbc85fe4 = '浮光护体'
        h09c3063egc130g48c2g8414g0535ea4196eb = '1级自动将浮光护体加入正面结果池：获得1d4+熟练加值点临时生命，持续2回合。'
        h5a27b995g2d15g4a0ega6a1g0e3a96807685 = '正面受创结果'
        hfb12183cg2eefg4c66g88cbg1d4452ea0277 = '正面格数=162+2A。受击轮盘先按300格判定类别，再从正面权重池抽取具体结果。'
        h4cb49a94g6cdag4be4g87eag95893020d052 = '负面受创结果'
        h6a7fc261g0307g46aeg9efcgea4e9d2add92 = '负面格数=138-2A-4B。受击轮盘判定为负面类别后，只从按惩罚强度加权的负面池抽取具体结果。'
        h0f888c08ge96ag4ac4ga02fgd41297ea527e = '平息'
        hb04f8bb6g8fceg4b25gaf0egb62b3a9f1b0e = '平息格数=4B。平息不施加正面或负面结果，也不增加混沌迷失。'
        h02971056gdde9g4363g80d5gdaf480557af7 = '混沌平息'
        h8fae3635gba76g4614ga776gf8054d011d82 = '本次受击轮盘平息：不施加正面或负面结果，也不增加混沌迷失。'
        h7f3cf979gec23g46b4g87a5g17724ad407e7 = '浮光护体'
        hdb91fe36gf912g4c6bga223g06a6647455f7 = '判定为正面类别后，浮光护体可能替代普通正面结果。获得1d4+熟练加值点临时生命，持续2回合。临时生命不叠加，只保留较高值。'
        h46000001g0001g4001g8001g000000000001 = '每层将受击轮盘中的2个负面格改为正面格。状态图标上的数字就是当前层数；正面格=162+2×层数，负面格=138-2×层数。'
        h46000002g0002g4002g8002g000000000002 = '每层将受击轮盘中的4个负面格改为平息格。状态图标上的数字就是当前层数；负面格=138-4×层数，平息格=4×层数。'
    }
    English = @{
        h0d010313gb67fg4c89ga5b9g30c58d4fb2f9 = 'Chaos Mastery Point'
        hf1437f68g6231g4f22gb12ega9bcfc6189d8 = 'Hidden resource. Chaos Origin gains 1 point per level, up to 12 points; resting does not restore it.'
        h1253cd25g6db6g4704g90e7gadf6ad0df3ed = 'Chaos Mastery'
        h11f157e4g81c1g4dc8gbd3eg20fbb820812f = 'Spend 1 Chaos Mastery point to gain 1 Attunement or Omen Correction stack. Respeccing clears both routes and returns every point earned at the current level.'
        hbfabec61g3070g4e70g8e71gc20633da5d52 = 'Attunement'
        h0cf72805gf1e4g4f89gbc8fgb4eb4561d859 = 'Spend 1 Chaos Mastery point to gain 1 Attunement stack.'
        h03a4fec8gb0efg45f9g8c5fgfd91d085f127 = 'Omen Correction'
        h0a9761a0g8ebeg4517ga88bgc9605641ea43 = 'Spend 1 Chaos Mastery point to gain 1 Omen Correction stack.'
        h1d501940gbda0g4737g8fecg66e1bbc85fe4 = 'Glimmering Guard'
        h09c3063egc130g48c2g8414g0535ea4196eb = 'At level 1, Glimmering Guard automatically enters the positive pool: gain 1d4 + Proficiency Bonus temporary hit points for 2 turns.'
        h5a27b995g2d15g4a0ega6a1g0e3a96807685 = 'Positive Wound Results'
        hfb12183cg2eefg4c66g88cbg1d4452ea0277 = 'Positive cells=162+2A. The Wound wheel first determines the category across 300 cells, then draws a specific result from the weighted positive pool.'
        h4cb49a94g6cdag4be4g87eag95893020d052 = 'Negative Wound Results'
        h6a7fc261g0307g46aeg9efcgea4e9d2add92 = 'Negative cells=138-2A-4B. After the Wound wheel selects the negative category, it draws only from the negative pool weighted by penalty strength.'
        h0f888c08ge96ag4ac4ga02fgd41297ea527e = 'Calm'
        hb04f8bb6g8fceg4b25gaf0egb62b3a9f1b0e = 'Calm cells=4B. Calm applies no positive or negative result and adds no Chaos Lost.'
        h02971056gdde9g4363g80d5gdaf480557af7 = 'Chaos Calmed'
        h8fae3635gba76g4614ga776gf8054d011d82 = 'This Wound wheel trial is calmed: it applies no positive or negative result and adds no Chaos Lost.'
        h7f3cf979gec23g46b4g87a5g17724ad407e7 = 'Glimmering Guard'
        hdb91fe36gf912g4c6bga223g06a6647455f7 = 'After the positive category is selected, Glimmering Guard may replace an ordinary positive result. Gain temporary hit points equal to 1d4 + Proficiency Bonus for 2 turns. Temporary hit points do not stack; only the higher value remains.'
        h46000001g0001g4001g8001g000000000001 = 'Each stack turns 2 negative Wound cells into positive cells. The number on the status icon is the current stack count; Positive=162+2×stacks and Negative=138-2×stacks.'
        h46000002g0002g4002g8002g000000000002 = 'Each stack turns 4 negative Wound cells into Calm cells. The number on the status icon is the current stack count; Negative=138-4×stacks and Calm=4×stacks.'
    }
    Japanese = @{
        h0d010313gb67fg4c89ga5b9g30c58d4fb2f9 = '混沌掌握ポイント'
        hf1437f68g6231g4f22gb12ega9bcfc6189d8 = '非表示のリソース。混沌の起源はレベルごとに1ポイントを獲得し、最大12ポイント。休息では回復しない。'
        h1253cd25g6db6g4704g90e7gadf6ad0df3ed = '混沌掌握'
        h11f157e4g81c1g4dc8gbd3eg20fbb820812f = '混沌掌握ポイントを1消費し、調律または凶兆補正を1スタック得る。再訓練すると両ルートを消去し、現在レベルで獲得済みの全ポイントを返還する。'
        hbfabec61g3070g4e70g8e71gc20633da5d52 = '調律'
        h0cf72805gf1e4g4f89gbc8fgb4eb4561d859 = '混沌掌握ポイントを1消費し、調律を1スタック得る。'
        h03a4fec8gb0efg45f9g8c5fgfd91d085f127 = '凶兆補正'
        h0a9761a0g8ebeg4517ga88bgc9605641ea43 = '混沌掌握ポイントを1消費し、凶兆補正を1スタック得る。'
        h1d501940gbda0g4737g8fecg66e1bbc85fe4 = '微光の守り'
        h09c3063egc130g48c2g8414g0535ea4196eb = 'レベル1で微光の守りが正効果プールへ加わる。2ターンの間、1d4＋習熟ボーナスの一時的ヒットポイントを得る。'
        h5a27b995g2d15g4a0ega6a1g0e3a96807685 = '正の被撃結果'
        hfb12183cg2eefg4c66g88cbg1d4452ea0277 = '正効果マス=162+2A。被撃ルーレットは先に300マスで結果区分を決め、その後、重み付き正効果プールから具体的な結果を抽選する。'
        h4cb49a94g6cdag4be4g87eag95893020d052 = '負の被撃結果'
        h6a7fc261g0307g46aeg9efcgea4e9d2add92 = '負効果マス=138-2A-4B。被撃ルーレットが負効果区分を選んだ後、ペナルティの強さで重み付けされた負効果プールだけから結果を抽選する。'
        h0f888c08ge96ag4ac4ga02fgd41297ea527e = '鎮静'
        hb04f8bb6g8fceg4b25gaf0egb62b3a9f1b0e = '鎮静マス=4B。鎮静は正・負いずれの結果も適用せず、混沌の喪失も増加させない。'
        h02971056gdde9g4363g80d5gdaf480557af7 = '混沌鎮静'
        h8fae3635gba76g4614ga776gf8054d011d82 = '今回の被撃ルーレットは鎮静された。正・負いずれの結果も適用せず、混沌の喪失も増加させない。'
        h7f3cf979gec23g46b4g87a5g17724ad407e7 = '微光の守り'
        hdb91fe36gf912g4c6bga223g06a6647455f7 = '正効果区分が選ばれた後、微光の守りが通常の正効果結果を置き換えることがある。1d4+習熟ボーナスに等しい一時的ヒット・ポイントを2ターン得る。一時的ヒット・ポイントは累積せず、高い値だけが残る。'
        h46000001g0001g4001g8001g000000000001 = '1スタックごとに被撃ルーレットの負効果2マスを正効果へ変更する。状態アイコンの数字が現在のスタック数。正効果=162+2×スタック、負効果=138-2×スタック。'
        h46000002g0002g4002g8002g000000000002 = '1スタックごとに被撃ルーレットの負効果4マスを鎮静へ変更する。状態アイコンの数字が現在のスタック数。負効果=138-4×スタック、鎮静=4×スタック。'
    }
    Korean = @{
        h0d010313gb67fg4c89ga5b9g30c58d4fb2f9 = '혼돈 통제 점수'
        hf1437f68g6231g4f22gb12ega9bcfc6189d8 = '숨겨진 자원입니다. 혼돈 기원은 레벨마다 1점을 얻으며 최대 12점까지 보유합니다. 휴식으로 회복되지 않습니다.'
        h1253cd25g6db6g4704g90e7gadf6ad0df3ed = '혼돈 통제'
        h11f157e4g81c1g4dc8gbd3eg20fbb820812f = '혼돈 통제 점수 1을 소모해 조율 또는 흉조 교정 1중첩을 얻습니다. 재분배하면 두 경로를 초기화하고 현재 레벨에서 얻은 모든 점수를 돌려받습니다.'
        hbfabec61g3070g4e70g8e71gc20633da5d52 = '조율'
        h0cf72805gf1e4g4f89gbc8fgb4eb4561d859 = '혼돈 통제 점수 1을 소모해 조율 1중첩을 얻습니다.'
        h03a4fec8gb0efg45f9g8c5fgfd91d085f127 = '흉조 교정'
        h0a9761a0g8ebeg4517ga88bgc9605641ea43 = '혼돈 통제 점수 1을 소모해 흉조 교정 1중첩을 얻습니다.'
        h1d501940gbda0g4737g8fecg66e1bbc85fe4 = '잔광 수호'
        h09c3063egc130g48c2g8414g0535ea4196eb = '1레벨에 잔광 수호가 긍정 결과 풀에 추가됩니다. 2턴 동안 1d4＋숙련 보너스만큼 임시 생명력을 얻습니다.'
        h5a27b995g2d15g4a0ega6a1g0e3a96807685 = '긍정 피격 결과'
        hfb12183cg2eefg4c66g88cbg1d4452ea0277 = '긍정 칸=162+2A. 피격 룰렛은 먼저 300칸으로 결과 범주를 정한 뒤 긍정 가중치 풀에서 구체적인 결과를 뽑습니다.'
        h4cb49a94g6cdag4be4g87eag95893020d052 = '부정 피격 결과'
        h6a7fc261g0307g46aeg9efcgea4e9d2add92 = '부정 칸=138-2A-4B. 피격 룰렛이 부정 범주를 선택한 뒤에는 페널티 강도로 가중된 부정 풀에서만 결과를 뽑습니다.'
        h0f888c08ge96ag4ac4ga02fgd41297ea527e = '진정'
        hb04f8bb6g8fceg4b25gaf0egb62b3a9f1b0e = '진정 칸=4B. 진정은 긍정 또는 부정 결과를 적용하지 않고 혼돈 상실도 증가시키지 않습니다.'
        h02971056gdde9g4363g80d5gdaf480557af7 = '혼돈 진정'
        h8fae3635gba76g4614ga776gf8054d011d82 = '이번 피격 룰렛은 진정되었습니다. 긍정 또는 부정 결과를 적용하지 않고 혼돈 상실도 증가시키지 않습니다.'
        h7f3cf979gec23g46b4g87a5g17724ad407e7 = '잔광 수호'
        hdb91fe36gf912g4c6bga223g06a6647455f7 = '긍정 범주가 선택된 뒤 잔광 수호가 일반 긍정 결과를 대체할 수 있습니다. 1d4+숙련 보너스만큼 임시 생명력을 2턴 동안 얻습니다. 임시 생명력은 중첩되지 않으며 더 높은 값만 남습니다.'
        h46000001g0001g4001g8001g000000000001 = '중첩마다 피격 룰렛의 부정 2칸을 긍정으로 바꿉니다. 상태 아이콘의 숫자가 현재 중첩 수입니다. 긍정=162+2×중첩, 부정=138-2×중첩.'
        h46000002g0002g4002g8002g000000000002 = '중첩마다 피격 룰렛의 부정 4칸을 진정으로 바꿉니다. 상태 아이콘의 숫자가 현재 중첩 수입니다. 부정=138-4×중첩, 진정=4×중첩.'
    }
}
$referenceLocalizationHandles = $null
$referenceProxyTooltipKeys = $null
$lifeSkillDescriptionHandles = @(
    'h71000002g0002g4002g8002g000000000002',
    'h71000003g0003g4003g8003g000000000003',
    'h71000004g0004g4004g8004g000000000004',
    'h71000005g0005g4005g8005g000000000005',
    'h71000006g0006g4006g8006g000000000006',
    'h71000007g0007g4007g8007g000000000007',
    'h71000008g0008g4008g8008g000000000008'
)
$lifeSkillDescriptionTemplates = @{
    Chinese = '混沌起源的所有技能检定固定+5；此等级成长状态使纯属性检定+{0}。不授予熟练或专精，不影响攻击、豁免与法术难度。'
    English = 'All Skill Checks for the Chaos Origin gain a fixed +5; this level-based status grants +{0} to raw Ability Checks. It grants no proficiency or expertise and does not affect attacks, saves, or spell DC.'
    Japanese = '混沌の起源はすべての技能判定に固定+5を得る。このレベル成長状態は能力値判定に+{0}を与える。習熟や専門化は付与せず、攻撃、セーヴ、呪文DCには影響しない。'
    Korean = '혼돈 기원은 모든 기술 판정에 고정 +5를 얻습니다. 이 레벨 성장 상태는 순수 능력 판정에 +{0} 보너스를 부여합니다. 숙련이나 전문화를 부여하지 않으며 공격, 내성, 주문 DC에는 영향을 주지 않습니다.'
}
foreach ($language in @('Chinese', 'English', 'Japanese', 'Korean')) {
    $path = Join-Path $root "Localization\$language\ChaosOriginsStory.xml"
    Require (Test-Path -LiteralPath $path -PathType Leaf) "缺少本地化源: $language"
    [xml]$localization = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $contents = @($localization.contentList.content)
    $handles = @($contents | ForEach-Object { [string]$_.contentuid } | Sort-Object)
    $contentsByHandle = @{}
    foreach ($content in $contents) {
        Require (-not [string]::IsNullOrWhiteSpace([string]$content.InnerText)) "本地化包含空文本: $language"
        $contentsByHandle[[string]$content.contentuid] = $content
    }
    for ($lifeSkillBonus = 1; $lifeSkillBonus -le 7; $lifeSkillBonus++) {
        $handle = $lifeSkillDescriptionHandles[$lifeSkillBonus - 1]
        $expectedText = $lifeSkillDescriptionTemplates[$language] -f $lifeSkillBonus
        Require ($contentsByHandle.ContainsKey($handle) -and
            [string]$contentsByHandle[$handle].InnerText -ceq $expectedText) `
            "混沌阅历说明必须精确显示固定技能检定+5和当前纯属性档位: $language / $lifeSkillBonus"
    }
    foreach ($mirror in $configMirrorDisplayHandles.Keys) {
        $handle = [string]$configMirrorDisplayHandles[$mirror]
        Require ($contentsByHandle.ContainsKey($handle) -and
            [string]$contentsByHandle[$handle].InnerText -ceq $mirror) `
            "核心设置回显被动的显示名必须在每种语言中严格解析为内部标识: $language / $mirror"
    }
    $tuneDescription = [string]$contentsByHandle['h0cf72805gf1e4g4f89gbc8fgb4eb4561d859'].InnerText
    Require (-not [regex]::IsMatch($tuneDescription, '(?:\+1%|-1%)')) `
        "调律说明仍使用旧百分比: $language"
    Require ($handles.Count -eq 720 -and @($handles | Select-Object -Unique).Count -eq 720) `
        "完整本地化必须包含 720 个唯一文本: $language"
    foreach ($settingsHandle in @(
        'h74000001g0001g4001g8001g000000000001',
        'h74000010g0010g4010g8010g000000000010',
        'h74000020g0020g4020g8020g000000000020',
        'h74000201g0201g4201g8201g000000000201',
        'h74000220g0220g4220g8220g000000000220'
    )) {
        Require ($handles -contains $settingsHandle) "完整本地化缺少生活熟练项或种族被动文本: $language / $settingsHandle"
    }
    Require (-not ($handles | Where-Object { $_ -in @(
        'hb6537e8cg9428g4fd3g9af1gfd1e3f258ec7',
        'hae5f271agdd7cg4353gb02bga5d4ede408e6',
        'h1a80c312g8552g4430gb0b2g115b7a43e6a9',
        'hab0e6d02gcc1fg4a4egb59dg85a8d9f4f8dd'
    ) })) "本地化不得保留测试技能文本: $language"
    Require (-not ($expectedHandles | Where-Object { $handles -notcontains $_ })) `
        "完整本地化缺少起源、身份或掌控混沌文本: $language"
    if ($null -eq $referenceLocalizationHandles) {
        $referenceLocalizationHandles = $handles
    } else {
        Require (-not (Compare-Object $referenceLocalizationHandles $handles)) `
            "四语本地化 handle 集合不一致: $language"
    }
    foreach ($handle in $masteryExactTexts[$language].Keys) {
        $actualText = [string]$contentsByHandle[$handle].InnerText
        $expectedText = [string]$masteryExactTexts[$language][$handle]
        Require ($actualText -ceq $expectedText) `
            "掌控混沌本地化正文不匹配: $language / $handle"
    }
    foreach ($description in $masterySimpleDescriptionHandles) {
        $descriptionText = [string]$contentsByHandle[$description].InnerText
        Require (-not $descriptionText.Contains('<LSTag ') -and -not ($descriptionText -match '[AB]=|162\+2A|138-2A-4B|4B')) `
            "掌控混沌技能说明必须只描述直接效果，不得包含嵌套词条或公式: $language / $description"
    }
    $customStatusTooltips = @([regex]::Matches((Get-Content -LiteralPath $path -Raw -Encoding UTF8), 'Type="Status" Tooltip="COS_'))
    Require ($customStatusTooltips.Count -eq 0) "自定义黄色词条不得继续使用空白的 Status 嵌套目标: $language"
    $proxyTooltipKeys = @([regex]::Matches((Get-Content -LiteralPath $path -Raw -Encoding UTF8), 'Type="Passive" Tooltip="(COS_TT_[^"]+)"') | `
        ForEach-Object { $_.Groups[1].Value })
    $unusedMasteryTooltipPassiveEntries = @(
        'COS_TT_CHAOS_MASTERY_CALM_INFO',
        'COS_TT_CHAOS_MASTERY_NEGATIVE_INFO',
        'COS_TT_CHAOS_MASTERY_POSITIVE_INFO',
        'COS_TT_CHAOS_MASTERY_RESULT_L01'
    )
    $expectedLinkedTooltipKeys = @($tooltipPassiveEntries | Where-Object { $unusedMasteryTooltipPassiveEntries -notcontains $_ })
    $expectedLinkedTooltipOccurrences = @($expectedLinkedTooltipKeys + 'COS_TT_CHAOS_GENESIS' | Sort-Object)
    Require ($proxyTooltipKeys.Count -eq 38 -and `
        -not (Compare-Object $expectedLinkedTooltipOccurrences @($proxyTooltipKeys | Sort-Object))) `
        "自定义黄色词条必须严格保留37种、38处 Passive 说明代理: $language"
    foreach ($tooltipKey in $proxyTooltipKeys) {
        Require ($tooltipPassiveEntries -contains $tooltipKey) "黄色词条指向未注册的说明被动: $language / $tooltipKey"
    }
    $uniqueProxyTooltipKeys = @($proxyTooltipKeys | Sort-Object -Unique)
    if ($null -eq $referenceProxyTooltipKeys) {
        $referenceProxyTooltipKeys = $uniqueProxyTooltipKeys
    } else {
        Require (-not (Compare-Object $referenceProxyTooltipKeys $uniqueProxyTooltipKeys)) `
            "四语黄色词条代理集合不一致: $language"
    }
}

$headerPath = Join-Path $storyPath 'RawFiles\story_header.div'
$goalPath = Join-Path $storyPath 'RawFiles\Goals\COS_BaseAfterCreation.txt'
Require (Test-Path -LiteralPath $headerPath -PathType Leaf) '缺少 Story 编译头文件'
$headerText = Get-Content -LiteralPath $headerPath -Raw -Encoding UTF8
Require ($headerText.Replace("`r`n", "`n").Length -eq 126581) `
    'Story 编译头未与本机已运行原生 Story MOD 的当前头对齐'
Require ([regex]::Matches($headerText, '(?m)^enum_type ').Count -eq 14) `
    'Story 编译必须使用含 14 个 enum_type 的原始头文件，不能使用已转换的暂存头'
Require ([regex]::Matches($headerText, '(?m)^alias_type ').Count -eq 25) `
    'Story 原始头文件 alias_type 数量错误'
$rewardGoalPath = Join-Path $storyPath 'RawFiles\Goals\COS_OriginStoryRewards.txt'
$masteryGoalPath = Join-Path $storyPath 'RawFiles\Goals\COS_ChaosMastery.txt'
$mechanicsGoalPath = Join-Path $storyPath 'RawFiles\Goals\COS_ChaosMechanics.txt'
$globalBenefitsGoalPath = Join-Path $storyPath 'RawFiles\Goals\COS_GlobalPlayerBenefits.txt'
$goals = @(Get-ChildItem -LiteralPath (Split-Path $goalPath -Parent) -File -Filter '*.txt')
Require ($goals.Count -eq 6 -and ($goals.FullName -contains $goalPath) -and `
    ($goals.FullName -contains $masteryGoalPath) -and ($goals.FullName -contains $rewardGoalPath) -and `
    ($goals.FullName -contains $mechanicsGoalPath) -and ($goals.FullName -contains $configGoalPath) -and `
    ($goals.FullName -contains $globalBenefitsGoalPath)) `
    '当前 Story 必须且只能包含基础同步、掌控混沌、混沌机制、核心设置、起源剧情奖励和全体玩家增益六个 Goal'
$globalBenefitsGoal = Normalize-LineEndings ([IO.File]::ReadAllText($globalBenefitsGoalPath))
$expectedGlobalBenefitsGoal = Normalize-LineEndings @'
Version 1
SubGoalCombiner SGC_AND
INITSECTION
NOT DB_Players((CHARACTER)NULL_00000000-0000-0000-0000-000000000000);
KBSECTION

PROC
PROC_COS_SyncGlobalPlayerBenefits((CHARACTER)_Character)
AND
DB_Players(_Character)
AND
HasPassive(_Character, "COS_GlobalCarryCapacity50x", 0)
THEN
AddPassive(_Character, "COS_GlobalCarryCapacity50x");

IF
LevelGameplayStarted(_, _)
AND
DB_Players(_Character)
THEN
PROC_COS_SyncGlobalPlayerBenefits(_Character);

IF
GainedControl(_Character)
THEN
PROC_COS_SyncGlobalPlayerBenefits(_Character);

IF
CharacterJoinedParty(_Character)
THEN
PROC_COS_SyncGlobalPlayerBenefits(_Character);

IF
RespecCompleted(_Character)
THEN
PROC_COS_SyncGlobalPlayerBenefits(_Character);

EXITSECTION
ENDEXITSECTION
'@
Require ($globalBenefitsGoal.Trim() -ceq $expectedGlobalBenefitsGoal.Trim()) `
    '全体玩家增益 Goal 必须只按既定四入口和 DB_Players 幂等同步50倍负重'
Require ([regex]::Matches($globalBenefitsGoal,
    '(?m)^NOT DB_Players\(\(CHARACTER\)NULL_00000000-0000-0000-0000-000000000000\);$').Count -eq 1) `
    '独立模块必须用NULL删除声明官方合并Story的DB_Players签名，且不得写入虚构玩家'
Require (-not $globalBenefitsGoal.Contains('COS_ChaosOriginMarker')) `
    '全体玩家负重不得依赖混沌起源标记'
$masteryGoal = Normalize-LineEndings ([IO.File]::ReadAllText($masteryGoalPath))
if ($masteryGoal.EndsWith("`n")) {
    $masteryGoal = $masteryGoal.Substring(0, $masteryGoal.Length - 1)
}
Require ($masteryGoal.StartsWith("Version 1`nSubGoalCombiner SGC_AND`nINITSECTION`n") -and `
    $masteryGoal.EndsWith("`nEXITSECTION`nENDEXITSECTION")) `
    '掌控混沌 Goal 头尾结构错误'
function Get-MasteryStoryBlocks([string]$Story, [string]$Kind, [string]$Name) {
    $pattern = '(?ms)^' + [regex]::Escape($Kind) + '\n' + [regex]::Escape($Name) +
        '\([^\n]*\)\n.*?(?=^(?:PROC|IF|EXITSECTION)\n|\z)'
    return @([regex]::Matches($Story, $pattern) | ForEach-Object { $_.Value })
}

function Get-MasteryThenActions([string]$Block) {
    $parts = @([regex]::Split($Block, '(?m)^THEN$'))
    if ($parts.Count -ne 2) { return @() }
    return @($parts[1] -split '\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Test-MasteryActions([string]$Block, [string[]]$Expected) {
    $actual = @(Get-MasteryThenActions $Block)
    return (($actual -join "`n") -ceq ($Expected -join "`n"))
}

function Test-COSMasteryLevelSemantics([string]$Story) {
    if ($Story -match 'GetActionResourceValuePersonal|TimerLaunch|SetEntityEvent|ParentTargetEdge') {
        return $false
    }

    $carrierFacts = @([regex]::Matches(
        $Story,
        '(?m)^DB_COS_MasteryCarrier\(([0-9]+), "(COS_ChaosMasteryPointL[0-9]{2})"\);$'
    ))
    if ($carrierFacts.Count -ne 12) { return $false }
    foreach ($level in 1..12) {
        $expected = 'DB_COS_MasteryCarrier({0}, "COS_ChaosMasteryPointL{0:D2}");' -f $level
        if ([regex]::Matches($Story, '(?m)^' + [regex]::Escape($expected) + '$').Count -ne 1) {
            return $false
        }
    }

    foreach ($requiredText in @(
        'DB_COS_MasterySchema46To47(_Character)',
        'PROC_COS_SyncMasteryAfterSchema47(_Character);',
        'IntegerMin(_Level, 12, _Cap)',
        'DB_COS_MasteryAvailableCount(_Character, 0);',
        'PROC_COS_IncrementMasteryAvailable(_Character);',
        'PROC_COS_ConsumeMasteryAvailable((CHARACTER)_Character);',
        'PROC_COS_ResetMasteryCarrier(_Character, 1);'
    )) {
        if (-not $Story.Contains($requiredText)) { return $false }
    }
    foreach ($forbiddenText in @(
        'PROC_COS_SyncMasteryAfterSchema45',
        'PROC_COS_ConsumeMasteryCarrier',
        'IntegerMin(_Level, 1, _Cap)'
    )) {
        if ($Story.Contains($forbiddenText)) { return $false }
    }

    $syncAfter = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_SyncMasteryAfterSchema47')
    if ($syncAfter.Count -ne 1 -or
        -not (Test-MasteryActions $syncAfter[0] @(
            'PROC_COS_EnsureMasteryCounts(_Character);',
            'PROC_COS_GrantMasteryFrom(_Character, 1, _Cap);'
        ))) { return $false }

    $applyRouteStatus = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_ApplyMasteryRouteStatus')
    if ($applyRouteStatus.Count -ne 1 -or
        -not $applyRouteStatus[0].Contains('DB_COS_ConfigMechanic((CHARACTER)_Character, "Mastery", 1)') -or
        -not $applyRouteStatus[0].Contains('_Count > 0') -or
        -not $applyRouteStatus[0].Contains('IntegerProduct(_Count, 6, _DurationSeconds)') -or
        -not $applyRouteStatus[0].Contains('IntegerToReal(_DurationSeconds, _Duration)') -or
        -not (Test-MasteryActions $applyRouteStatus[0] @(
            'ApplyStatus(_Character, _Status, _Duration, 100, _Character);'
        ))) { return $false }

    $syncStatuses = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_SyncMasteryStatuses')
    if ($syncStatuses.Count -ne 1 -or
        -not $syncStatuses[0].Contains('DB_COS_MasteryTuneCount(_Character, _TuneCount)') -or
        -not $syncStatuses[0].Contains('DB_COS_MasteryCorrectCount(_Character, _CorrectCount)') -or
        -not (Test-MasteryActions $syncStatuses[0] @(
            'RemoveStatus(_Character, "COS_CHAOS_MASTERY_TUNE", _Character);',
            'RemoveStatus(_Character, "COS_CHAOS_MASTERY_CORRECT", _Character);',
            'PROC_COS_ApplyMasteryRouteStatus(_Character, "COS_CHAOS_MASTERY_TUNE", _TuneCount);',
            'PROC_COS_ApplyMasteryRouteStatus(_Character, "COS_CHAOS_MASTERY_CORRECT", _CorrectCount);'
        ))) { return $false }

    $syncStatusEntry = @(@(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_SyncMastery') | Where-Object {
        $_.Contains('DB_COS_MasteryTuneCount(_Character, _)') -and
        $_.Contains('DB_COS_MasteryCorrectCount(_Character, _)')
    })
    if ($syncStatusEntry.Count -ne 1 -or
        -not (Test-MasteryActions $syncStatusEntry[0] @(
            'PROC_COS_SyncMasteryStatuses(_Character);',
            'PROC_COS_UpdateMasterySpell(_Character);'
        ))) { return $false }

    $consumeAvailable = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_ConsumeMasteryAvailable')
    if ($consumeAvailable.Count -ne 1 -or
        -not $consumeAvailable[0].Contains('DB_COS_ConfigMechanic((CHARACTER)_Character, "Mastery", 1)') -or
        -not $consumeAvailable[0].Contains('DB_COS_MasteryAvailableCount(_Character, _Count)') -or
        -not $consumeAvailable[0].Contains('_Count > 0') -or
        -not $consumeAvailable[0].Contains('IntegerSubtract(_Count, 1, _Next)') -or
        -not (Test-MasteryActions $consumeAvailable[0] @(
            'NOT DB_COS_MasteryAvailableCount(_Character, _Count);',
            'DB_COS_MasteryAvailableCount(_Character, _Next);',
            'PROC_COS_UpdateMasterySpell(_Character);'
        ))) { return $false }

    $grantBlocks = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_GrantMasteryFrom')
    $freshGrant = @($grantBlocks | Where-Object {
        $_.Contains('NOT DB_COS_MasteryEarned(_Character, _Cursor)')
    })
    if ($grantBlocks.Count -ne 3 -or $freshGrant.Count -ne 1 -or
        -not (Test-MasteryActions $freshGrant[0] @(
            'AddPassive(_Character, _Carrier);',
            'DB_COS_MasteryEarned(_Character, _Cursor);',
            'PROC_COS_IncrementMasteryAvailable(_Character);',
            'PROC_COS_GrantMasteryFrom(_Character, _Next, _Cap);'
        ))) { return $false }

    $updateBlocks = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_UpdateMasterySpell')
    $showMastery = @($updateBlocks | Where-Object {
        $_.Contains('DB_COS_MasteryAvailableCount(_Character, _Count)') -and $_.Contains('_Count > 0')
    })
    $hideMastery = @($updateBlocks | Where-Object {
        $_.Contains('DB_COS_MasteryAvailableCount(_Character, 0)')
    })
    if ($showMastery.Count -ne 1 -or $hideMastery.Count -ne 1) { return $false }

    $migration = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_MigrateMasterySchema46To47')
    if ($migration.Count -ne 1 -or
        -not (Test-MasteryActions $migration[0] @('PROC_COS_ResetMastery(_Character);'))) {
        return $false
    }

    $reset = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_ResetMastery')
    if ($reset.Count -ne 1 -or
        -not (Test-MasteryActions $reset[0] @(
            'DB_COS_MasterySchema46To47(_Character);',
            'RemoveStatus(_Character, "COS_CHAOS_MASTERY_TUNE", _Character);',
            'RemoveStatus(_Character, "COS_CHAOS_MASTERY_CORRECT", _Character);',
            'PROC_COS_ResetMasteryCarrier(_Character, 1);'
        ))) { return $false }

    $resetCarrier = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_ResetMasteryCarrier')
    if ($resetCarrier.Count -ne 3 -or
        @($resetCarrier | Where-Object { $_.Contains('_Cursor > 12') }).Count -ne 1) {
        return $false
    }

    foreach ($route in @(
        @{ Spell = 'Shout_COS_ChaosMasteryTune'; Count = 'DB_COS_MasteryTuneCount' },
        @{ Spell = 'Shout_COS_ChaosMasteryCorrect'; Count = 'DB_COS_MasteryCorrectCount' }
    )) {
        $blocks = @(@(Get-MasteryStoryBlocks $Story 'IF' 'CastedSpell') | Where-Object {
            $_.Contains('CastedSpell(_Character, "' + $route.Spell + '", _, _, _)')
        })
        if ($blocks.Count -ne 1) { return $false }
        $block = $blocks[0]
        if ($block.Contains('DB_COS_MasteryUnspent') -or $block.Contains('DB_COS_MasteryCarrier') -or
            -not (Test-MasteryActions $block @(
                ('NOT ' + $route.Count + '((CHARACTER)_Character, _Count);'),
                ($route.Count + '((CHARACTER)_Character, _Next);'),
                'PROC_COS_SyncMasteryStatuses((CHARACTER)_Character);',
                'PROC_COS_ConsumeMasteryAvailable((CHARACTER)_Character);'
            ))) { return $false }
    }

    if ([regex]::Matches($Story, '(?m)^ApplyStatus\(').Count -ne 1) { return $false }

    return $true
}

Require (Test-COSMasteryLevelSemantics $masteryGoal) `
    '掌控混沌必须按1至12级逐级发点、消费可用点并在洗点后按当前等级完整重建'

$masteryCapMutant = $masteryGoal.Replace('IntegerMin(_Level, 12, _Cap)', 'IntegerMin(_Level, 1, _Cap)')
Require ($masteryCapMutant -cne $masteryGoal -and -not (Test-COSMasteryLevelSemantics $masteryCapMutant)) `
    '掌控混沌静态变异检查未拒绝升级发点上限退回1级'

$masteryCarrierMutant = $masteryGoal.Replace(
    'DB_COS_MasteryCarrier(12, "COS_ChaosMasteryPointL12");',
    ''
)
Require ($masteryCarrierMutant -cne $masteryGoal -and -not (Test-COSMasteryLevelSemantics $masteryCarrierMutant)) `
    '掌控混沌静态变异检查未拒绝缺少12级点数载体'

$masteryGrantMutant = $masteryGoal.Replace('PROC_COS_IncrementMasteryAvailable(_Character);', '')
Require ($masteryGrantMutant -cne $masteryGoal -and -not (Test-COSMasteryLevelSemantics $masteryGrantMutant)) `
    '掌控混沌静态变异检查未拒绝升级后未增加可用点数'

$masteryStatusApplyMutant = $masteryGoal.Replace(
    'ApplyStatus(_Character, _Status, _Duration, 100, _Character);',
    ''
)
Require ($masteryStatusApplyMutant -cne $masteryGoal -and -not (Test-COSMasteryLevelSemantics $masteryStatusApplyMutant)) `
    '掌控混沌静态变异检查未拒绝路线状态未按数据库层数重建'

$masteryCastStatusSyncMutant = $masteryGoal.Replace(
    'PROC_COS_SyncMasteryStatuses((CHARACTER)_Character);',
    ''
)
Require ($masteryCastStatusSyncMutant -cne $masteryGoal -and -not (Test-COSMasteryLevelSemantics $masteryCastStatusSyncMutant)) `
    '掌控混沌静态变异检查未拒绝选择后未刷新状态栏层数'

foreach ($eventPattern in @(
    '(?ms)IF\nLevelGameplayStarted\(_, _\)\nAND\nDB_Avatars\(_Character\)\nAND\nHasPassive\(_Character, "COS_ChaosOriginMarker", 1\)\nTHEN\nPROC_COS_SyncMastery\(_Character\);',
    '(?ms)IF\nGainedControl\(_Character\)\nAND\nHasPassive\(_Character, "COS_ChaosOriginMarker", 1\)\nTHEN\nPROC_COS_SyncMastery\(_Character\);',
    '(?ms)IF\nLeveledUp\(_Character\)\nAND\nHasPassive\(_Character, "COS_ChaosOriginMarker", 1\)\nTHEN\nPROC_COS_SyncMastery\(_Character\);',
    '(?ms)IF\nRespecCompleted\(_Character\)\nAND\nHasPassive\(_Character, "COS_ChaosOriginMarker", 1\)\nTHEN\nPROC_COS_ResetMastery\(_Character\);'
)) {
    Require ($masteryGoal -match $eventPattern) '掌控同步、迁移和洗点事件必须逐角色限制为混沌起源'
}
Require ([regex]::Matches($masteryGoal,
    '(?m)^NOT DB_Avatars\(\(CHARACTER\)NULL_00000000-0000-0000-0000-000000000000\);$').Count -eq 1) `
    '独立模块必须用NULL删除声明官方合并Story的DB_Avatars签名，且不得写入虚构化身'
Require ((-not ($masteryGoal -match '(?m)^DB_Avatars\([^_\r\n]')) -and `
    ($masteryGoal.Contains('GetHostCharacter(') -eq $false)) `
    '掌控读档同步不得写入虚构DB_Avatars事实或退回仅主机角色'
foreach ($forbiddenMasteryStoryPattern in @(
    '(?m)^UsingSpell\(', '(?m)^CastSpell\(', '(?i)Preview', 'TimerLaunch', 'SetEntityEvent',
    'ParentTargetEdge', 'ScriptExtender', '(?i)\bSE\b', '(?i)\bN?MCM\b',
    '(?i)Dialog(?:ue)?', '(?i)Default'
)) {
    Require (-not ($masteryGoal -match $forbiddenMasteryStoryPattern)) `
        "掌控混沌 Story 包含禁用延迟、外部依赖、自动路线或回退: $forbiddenMasteryStoryPattern"
}
$goal = Get-Content -LiteralPath $goalPath -Raw -Encoding UTF8
$expectedRaceTags = @(
    '60f6b464-752f-4970-a855-f729565b5e07','78adf3cd-4741-47a8-94f6-f3d322432591',
    '534098fa-601d-4f6e-8c4e-b3a8d4b1f141','1dc20a7a-00e7-4126-80ad-aa1152a2136c',
    '4fa13243-199d-4c9a-b455-d844276a98f5','eae44d86-3321-4a0a-811d-4fd8e48b5723',
    '52b71dea-9d4e-402d-9700-fb9c360a44c9','5ffb703c-3ef4-493b-966d-749bc038f6bd',
    'ef9c5b74-56a8-48cc-b0b9-169ee16bf026','6e913b6e-58b1-41bf-8751-89250dd17bff',
    '492c3200-1226-4114-bad1-f6b1ba737f3d','889e0db5-d03e-4b63-86d7-13418f69729f',
    '57a00605-9e74-477c-bd9d-53c721e25e56','8d545fa1-8416-493f-8325-7d112bceced8',
    '02e5e9ed-b6b2-4524-99cd-cb2bc84c754a','a672ac1d-d088-451a-9537-3da4bf74466c',
    '486a2562-31ae-437b-bf63-30393e18cbdd','50e7beca-4e90-43cd-b7c5-c235e236077f',
    '351f4e42-1217-4c06-b47a-443dcf69b111','677ffa76-2562-4217-873e-2253d4720ba4',
    '1f0551f3-d769-47a9-b02b-5d3a8c51978c','34317158-8e6e-45a2-bd1e-6604d82fdda2',
    '3311a9a9-cdbc-4b05-9bf6-e02ba1fc72a3','b99b6a5d-8445-44e4-ac58-81b2ee88aab1',
    '69fd1443-7686-4ca9-9516-72ec0b9d94d7','aaef5d43-c6f3-434d-b11e-c763290dbe0c',
    'c3fd1fc3-2edf-4d17-935d-44ab92406df1','ec5bea6b-26f1-4917-919c-375f67ac13d1',
    'ab677895-e08a-479f-a043-eac2d8447188','2bbc3217-3d8c-46e6-b599-a0f1c9063f9a',
    '09518377-4ea1-4ce2-b8e8-61477c26ebdd','664cc044-a0ea-43a1-b21f-d8cad7721102'
) | Sort-Object
$actualRaceTags = @([regex]::Matches($goal, 'DB_COS_RaceIdentityTag\(\(TAG\)([0-9a-f-]{36})\);') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Require ($actualRaceTags.Count -eq 32 -and @($actualRaceTags | Select-Object -Unique).Count -eq 32 -and -not (Compare-Object $expectedRaceTags $actualRaceTags)) `
    'Story Goal 必须且只能包含 32 个官方可选种族身份标签'
$expectedOriginTags = @(
    'ffd08582-7396-4cac-bcd4-8f9cd0fd8ef3',
    '9b0354c0-56d9-4723-8034-918ac9abab19',
    'b5682d1d-c395-489c-9675-1f9b0c328ea5',
    '642d2aee-e3df-47e3-9f47-bbcd441bb9e0',
    '5f40def5-d3ec-4698-a367-01a339888956',
    '1a2f70d6-8ead-4eb5-a824-79ee1971764a',
    'cd611d7d-b67d-42b4-a75c-a0c6091ef8a2'
) | Sort-Object
$actualOriginTags = @([regex]::Matches($goal, 'DB_COS_OriginIdentityToggle\("[^"]+", "[^"]+", \(TAG\)([0-9a-f-]{36})\);') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Require ($actualOriginTags.Count -eq 7 -and @($actualOriginTags | Select-Object -Unique).Count -eq 7 -and -not (Compare-Object $expectedOriginTags $actualOriginTags)) `
    'Story Goal 必须且只能包含阿斯代伦、盖尔、莱埃泽尔、影心、威尔、卡菈克和邪念七个官方身份标签'
$expectedOriginToggleMappings = @(
    'COS_Origin_Astarion|COS_ORIGIN_TAG_ASTARION|ffd08582-7396-4cac-bcd4-8f9cd0fd8ef3',
    'COS_Origin_Gale|COS_ORIGIN_TAG_GALE|9b0354c0-56d9-4723-8034-918ac9abab19',
    'COS_Origin_Laezel|COS_ORIGIN_TAG_LAEZEL|b5682d1d-c395-489c-9675-1f9b0c328ea5',
    'COS_Origin_Shadowheart|COS_ORIGIN_TAG_SHADOWHEART|642d2aee-e3df-47e3-9f47-bbcd441bb9e0',
    'COS_Origin_Wyll|COS_ORIGIN_TAG_WYLL|5f40def5-d3ec-4698-a367-01a339888956',
    'COS_Origin_Karlach|COS_ORIGIN_TAG_KARLACH|1a2f70d6-8ead-4eb5-a824-79ee1971764a',
    'COS_Origin_DarkUrge|COS_ORIGIN_TAG_DARKURGE|cd611d7d-b67d-42b4-a75c-a0c6091ef8a2'
) | Sort-Object
$actualOriginToggleMappings = @([regex]::Matches($goal, 'DB_COS_OriginIdentityToggle\("([^"]+)", "([^"]+)", \(TAG\)([0-9a-f-]{36})\);') | ForEach-Object {
    "$($_.Groups[1].Value)|$($_.Groups[2].Value)|$($_.Groups[3].Value)"
} | Sort-Object)
Require ($actualOriginToggleMappings.Count -eq 7 -and -not (Compare-Object $expectedOriginToggleMappings $actualOriginToggleMappings)) `
    '七个起源身份被动、隐藏状态与官方标签映射错误'
foreach ($requiredGoalText in @(
    'LevelGameplayStarted(_, _)',
    'GainedControl(_Character)',
    'DB_Avatars(_Character)',
    'IsTagged(_Character, _Tag, 0)',
    'SetTag(_Character, _Tag)',
    'ClearTag(_Character, _Tag)',
    'StatusApplied(_Character, _Status, _, _)',
    'StatusRemoved(_Character, _Status, _, _)',
    'DB_COS_OriginIdentityToggle(_Passive, _Status, _Tag)',
    'AddPassive(_Character, _Passive)',
    'HasActiveStatus(_Character, _Status, 1)',
    'HasPassive(_Character, "COS_ChaosOriginMarker", 1)',
    'AddPassive(_Character, "COS_BaseProficiencies")',
    'AddPassive(_Character, "COS_BaseStarterSpells")'
)) {
    Require ($goal.Contains($requiredGoalText)) "基础同步 Goal 缺少: $requiredGoalText"
}
$forbiddenRacialPassives = @(
    'DeepGnome_StoneCamouflage','Drow_DrowWeaponTraining','Duergar_DuergarResilience',
    'Dwarf_DwarvenCombatTraining','Dwarf_DwarvenResilience','Elf_WeaponTraining','FeyAncestry',
    'Gith_MartialProdigy','Gnome_Cunning','Halfling_Brave','Halfling_LightfootStealth',
    'Halfling_Lucky','Halfling_StoutResilience','HumanMilitia','MountainDwarf_DwarvenArmorTraining',
    'RelentlessEndurance','RockGnome_ArtificersLore','SavageAttacks','SuperiorDarkvision',
    'Tiefling_HellishResistance'
)
foreach ($racialPassive in $forbiddenRacialPassives) {
    Require (-not $passive.Contains($racialPassive) -and -not $goal.Contains($racialPassive)) `
        "默认关闭的种族被动不得被静态定义或 Story 授予: $racialPassive"
}
$originSpellMappings = @([regex]::Matches($goal, 'DB_COS_OriginIdentitySpell\("([^"]+)", "([^"]+)"\);') | ForEach-Object {
    "$($_.Groups[1].Value)|$($_.Groups[2].Value)"
})
Require ($originSpellMappings.Count -eq 1 -and $originSpellMappings[0] -eq 'COS_ORIGIN_TAG_ASTARION|Target_VampireBite_Astarion') `
    '阿斯代伦身份必须且只能授予吸血'
$originPassiveMappings = @([regex]::Matches($goal, 'DB_COS_OriginIdentityPassive\("([^"]+)", "([^"]+)"\);') | ForEach-Object {
    "$($_.Groups[1].Value)|$($_.Groups[2].Value)"
} | Sort-Object)
$expectedOriginPassiveMappings = @(
    'COS_ORIGIN_TAG_WYLL|BladeOfFrontiers',
    'COS_ORIGIN_TAG_KARLACH|ORI_Karlach_SweatImmune',
    'COS_ORIGIN_TAG_KARLACH|ORI_Karlach_Rage_Flames'
) | Sort-Object
Require ($originPassiveMappings.Count -eq 3 -and -not (Compare-Object $expectedOriginPassiveMappings $originPassiveMappings)) `
    '威尔与卡菈克身份即时被动映射错误'
foreach ($requiredOriginFeatureRule in @('AddSpell((CHARACTER)_Character, _Spell, 0, 0)', 'RemoveSpell((CHARACTER)_Character, _Spell, 0)', 'AddPassive(_Character, _FeaturePassive)', 'RemovePassive(_Character, _FeaturePassive)')) {
    Require ($goal.Contains($requiredOriginFeatureRule)) "缺少身份即时能力同步规则: $requiredOriginFeatureRule"
}
foreach ($runtimeSensitiveCast in @(
    'HasSpell((CHARACTER)_Character, _Spell, 0)',
    'HasSpell((CHARACTER)_Character, _Spell, 1)'
)) {
    Require ($goal.Contains($runtimeSensitiveCast)) "基础同步缺少当前游戏 Story 头要求的类型转换: $runtimeSensitiveCast"
}
foreach ($forbiddenGoalText in @('UserAvatarCreated', 'GetHostCharacter', 'COS_AllSkillMastery', 'ProficiencyBonus(Skill', 'ExpertiseBonus', 'MCM', 'TutorialEvent', 'COS_RacialSpells_', 'DB_COS_RacialSpellPassive', 'TogglePassive(')) {
    Require (-not $goal.Contains($forbiddenGoalText)) "基础同步 Goal 包含禁用行为: $forbiddenGoalText"
}
Require ([regex]::Matches($goal, '(?ms)IF\r?\nLevelGameplayStarted\(_, _\)\r?\nAND\r?\nDB_Avatars\(_Character\)\r?\nAND\r?\nHasPassive\(_Character, "COS_ChaosOriginMarker", 1\)\r?\nTHEN\r?\nPROC_COS_SyncBaseAfterCreation\(_Character\);').Count -eq 1) `
    '读档时必须为每个混沌起源玩家角色迁移基础能力和命运改签'
Require (-not ($goal -match '(?m)^DB_Avatars\([^_]')) `
    '基础同步只能查询官方玩家角色数据库，不得写入虚构化身事实'
Require (-not $goal.Contains('DB_COS_CorePassive(1, "COS_ChaosEcho")')) `
    '基础同步不得再授予混沌回响'
Require ($goal.Contains('RemovePassive(_Character, "COS_ChaosEcho")')) `
    '基础同步必须移除旧存档残留的混沌回响被动'
$rewardGoal = Get-Content -LiteralPath $rewardGoalPath -Raw -Encoding UTF8
Require ([regex]::Matches($rewardGoal, 'DB_COS_OriginStoryFlag\(\(FLAG\)').Count -eq 11) `
    '起源剧情奖励必须严格监听 11 个已审核官方 Flag'
foreach ($rewardToken in @(
    'LOW_Astarion_VampireAscendant','Shout_EPI_Astarion_TurnIntoBat',
    'Target_END_Gale_ActivateNethereseOrb','ORI_Gale_ShadowSpellSlots','Target_ORI_Gale_ShadowSummon','EPI_GALEGOD',
    'Shout_ORI_Wyll_FireShield_Warm','Target_ORI_Wyll_SummonCambion',
    'ORI_KARLACH_FIRSTUPGRADE','ORI_KARLACH_SECONDUPGRADE',
    'Shout_DarkUrge_Slayer','Target_LOW_DarkUrge_PowerWordKill'
)) {
    Require ($rewardGoal.Contains($rewardToken)) "起源剧情奖励缺少: $rewardToken"
}
foreach ($forbiddenRewardText in @('TemplateAddTo','TemplateAddedTo','ProficiencyBonus(Skill','ExpertiseBonus','UserAvatarCreated','DB_Avatars','ScriptExtender','MCM')) {
    Require (-not $rewardGoal.Contains($forbiddenRewardText)) "起源剧情奖励包含禁用行为: $forbiddenRewardText"
}
foreach ($runtimeSensitiveRewardCast in @(
    'PROC_COS_SyncOriginStoryRewards((CHARACTER)_Character)',
    'HasSpell((CHARACTER)_Character, "Shout_DarkUrge_Slayer", 1)',
    'DB_COS_PowerWordKillConsumed((CHARACTER)_Character)'
)) {
    Require ($rewardGoal.Contains($runtimeSensitiveRewardCast)) "剧情奖励缺少当前游戏 Story 头要求的类型转换: $runtimeSensitiveRewardCast"
}
$mechanicsGoal = Normalize-LineEndings (Get-Content -LiteralPath $mechanicsGoalPath -Raw -Encoding UTF8)
$configGoal = Normalize-LineEndings (Get-Content -LiteralPath $configGoalPath -Raw -Encoding UTF8)
$configStats = Normalize-LineEndings (Get-Content -LiteralPath $configStatsPath -Raw -Encoding UTF8)
Require (-not $mechanicsGoal.Contains('COS_ChaosMastery')) `
    '一级原生选择切片不得提前修改两仪或受击轮盘逻辑'
foreach ($requiredMechanicsText in @(
    'PROC_COS_RollWound', 'PROC_COS_ResolveDuality', 'PROC_COS_AddPower', 'PROC_COS_AddLost',
    'Shout_COS_ChaosGenesis', 'AttackedBy(', 'TurnStarted(', 'EnteredCombat(', 'LeftCombat(',
    'Random(100, _DualityRoll)',
    'PROC_COS_QueueDualityDamage', 'RealtimeObjectTimerLaunch(_Target, "COS_DualityApplyDamage", 50)',
    'ObjectTimerFinished(_Target, "COS_DualityApplyDamage")', 'DB_COS_DualityDamagePending',
    'PROC_COS_QueueDelayedDualityDamage', 'DB_COS_DualityDelayed', 'DB_COS_DualityDelaySerial',
    'SetHitpoints(_Target, _FinalHitpoints, "Guaranteed")',
    'COS_CHAOS_DUALITY_LOG_RETURN', 'COS_CHAOS_DUALITY_LOG_ELEMENTAL',
    'COS_CHAOS_DUALITY_LOG_BOOST_80', 'COS_CHAOS_DUALITY_LOG_DEVOUR_40'
)) {
    Require ($mechanicsGoal.Contains($requiredMechanicsText)) "混沌核心机制缺少: $requiredMechanicsText"
}
Require ([regex]::Matches($mechanicsGoal, '(?ms)IF\r?\nLevelGameplayStarted\(_, _\)\r?\nAND\r?\nDB_Avatars\(_Character\)\r?\nAND\r?\nHasPassive\(_Character, "COS_ChaosOriginMarker", 1\)\r?\nTHEN\r?\nPROC_COS_Sync\(_Character\);').Count -eq 1 -and `
    -not $mechanicsGoal.Contains('GetHostCharacter(')) `
    '读档时必须为每个混沌起源玩家角色同步核心机制数据'
Require ([regex]::Matches($mechanicsGoal, '(?ms)^PROC\r?\nPROC_COS_EnsurePowerState\(\(CHARACTER\)_Character\)\r?\nAND\r?\nNOT DB_COS_ConfigMechanic\(_Character, "Power", _\)\r?\nTHEN\r?\nDB_COS_ConfigMechanic\(_Character, "Power", 1\);').Count -eq 1 -and `
    [regex]::Matches($mechanicsGoal, '(?ms)^PROC\r?\nPROC_COS_EnsurePowerState\(\(CHARACTER\)_Character\)\r?\nAND\r?\nNOT DB_COS_Power\(_Character, _\)\r?\nTHEN\r?\nDB_COS_Power\(_Character, 0\);').Count -eq 1 -and `
    ($mechanicsGoal.Contains("PROC_COS_MigrateLegacyFatePending(_Character);`r`nPROC_COS_Register(_Character);`r`nPROC_COS_EnsurePowerState(_Character);`r`nPROC_COS_SyncPowerFromDatabase(_Character);") -or `
     $mechanicsGoal.Contains("PROC_COS_MigrateLegacyFatePending(_Character);`nPROC_COS_Register(_Character);`nPROC_COS_EnsurePowerState(_Character);`nPROC_COS_SyncPowerFromDatabase(_Character);"))) `
    '核心同步必须明确补齐旧存档缺失的混沌之力配置和数值行'
foreach ($forbiddenMechanicsText in @(
    'UserAvatarCreated', 'LevelGameplayReady', 'TemplateAddTo', 'TemplateAddedTo', 'TutorialEvent',
    'PROC_COS_ConfigEnsureBook', 'PROC_COS_ConfigSyncOrigins', 'PROC_COS_ConfigSyncRacialPassives',
    'PROC_COS_StarterRewards', 'PROC_COS_GrantFeatures', 'PROC_COS_GrantTags', 'PROC_COS_RemoveForbidden',
    'DB_COS_Spell(', 'DB_COS_Passive(', 'DB_COS_ConfigOrigin(', 'ProficiencyBonus(Skill', 'ExpertiseBonus',
    'PROC_COS_Echo', 'COS_CHAOS_ECHO_LOG_', 'COS_CHAOS_SENTINEL_ECHO_', '"Echo", 1'
)) {
    Require (-not $mechanicsGoal.Contains($forbiddenMechanicsText)) "混沌核心机制包含禁用旧逻辑: $forbiddenMechanicsText"
}
Require ([regex]::Matches($mechanicsGoal, 'DB_COS_WoundLog\(\d+, "COS_CHAOS_WOUND_LOG_').Count -eq 24) `
    '受击轮盘必须为 24 个状态结果提供具名战斗日志'
$dualityBands = @([regex]::Matches($mechanicsGoal, 'DB_COS_DualityBand\((\d+), (\d+), (\d+), "([^"]+)"\);'))
Require ($dualityBands.Count -eq 8) '两仪必须包含八档连续伤害倍率'
$expectedDualityBands = @('0,2,70','2,9,85','9,23,95','23,53,100','53,75,105','75,90,115','90,98,130','98,100,150')
$actualDualityBands = @($dualityBands | ForEach-Object { '{0},{1},{2}' -f $_.Groups[1].Value,$_.Groups[2].Value,$_.Groups[3].Value })
Require (($actualDualityBands -join '|') -eq ($expectedDualityBands -join '|')) `
    '两仪倍率必须覆盖 100 格且保持确认的递减极端概率'
foreach ($timingBoundary in @('_TimingRoll < _ImmediateEnd','_TimingRoll >= _ImmediateEnd','_TimingRoll < _SplitEnd','_TimingRoll >= _SplitEnd','IntegerSum(_Percent, _SplitBonus','IntegerSum(_Percent, _DelayBonus')) {
    Require ($mechanicsGoal.Contains($timingBoundary)) "两仪缺少确认的立即、分期或延迟边界: $timingBoundary"
}
foreach ($timingTier in @(
    'DB_COS_DualityTiming(1, 90, 98, 5, 15, 80);',
    'DB_COS_DualityTiming(2, 75, 90, 10, 25, 65);',
    'DB_COS_DualityTiming(3, 60, 85, 15, 35, 50);'
)) {
    Require ($mechanicsGoal.Contains($timingTier)) "两仪缺少等级成长时机档: $timingTier"
}
foreach ($postLevelMechanic in @(
    'IntegerMin(_Level, 30, _CappedLevel)',
    'IntegerProduct(_PostLevels, 2, _SplitGrowth)',
    'IntegerProduct(_PostLevels, 3, _DelayGrowth)',
    'IntegerMin(_AdjustedPercentRaw, 200, _AdjustedPercent)'
)) {
    Require ($mechanicsGoal.Contains($postLevelMechanic)) "13至30级逐级成长缺少: $postLevelMechanic"
}
$positiveWoundWeights = @([regex]::Matches($mechanicsGoal, 'DB_COS_WoundPositiveWeight\((\d+), (\d+)\);'))
$positiveWoundWeightTotal = ($positiveWoundWeights | ForEach-Object { [int]$_.Groups[2].Value } | Measure-Object -Sum).Sum
Require ($positiveWoundWeightTotal -eq 164) '正面受击结果目录总权重必须严格为164'
$actualPositiveWoundWeights = @($positiveWoundWeights | ForEach-Object { '{0}:{1}' -f $_.Groups[1].Value,$_.Groups[2].Value } | Sort-Object)
$expectedPositiveWoundWeights = @('13:20','14:4','15:12','16:20','17:4','18:24','19:24','20:24','21:12','22:16','25:4') | Sort-Object
Require ($positiveWoundWeights.Count -eq 11 -and -not (Compare-Object $expectedPositiveWoundWeights $actualPositiveWoundWeights)) `
    '正面受击结果目录必须严格包含11个指定结果及权重'

$negativeWoundWeights = @([regex]::Matches($mechanicsGoal, 'DB_COS_WoundNegativeWeight\((\d+), (\d+)\);'))
$negativeWoundWeightTotal = ($negativeWoundWeights | ForEach-Object { [int]$_.Groups[2].Value } | Measure-Object -Sum).Sum
Require ($negativeWoundWeightTotal -eq 35) '负面受击结果目录总权重必须严格为35'
$actualNegativeWoundWeights = @($negativeWoundWeights | ForEach-Object { '{0}:{1}' -f $_.Groups[1].Value,$_.Groups[2].Value } | Sort-Object)
$expectedNegativeWoundWeights = @('0:4','1:2','2:1','3:4','4:2','5:1','6:4','7:2','8:1','9:4','10:2','11:1','12:4','23:2','24:1') | Sort-Object
Require ($negativeWoundWeights.Count -eq 15 -and -not (Compare-Object $expectedNegativeWoundWeights $actualNegativeWoundWeights)) `
    '负面受击结果目录必须严格包含15个指定结果及权重'

$woundLayers = @([regex]::Matches($mechanicsGoal, 'DB_COS_WoundLayer\((\d+)\);') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object)
Require ($woundLayers.Count -eq 24 -and (($woundLayers -join ',') -eq ((1..24) -join ','))) `
    '受击候选层必须严格为整数1至24'
Require ([regex]::Matches($mechanicsGoal, 'DB_COS_MasteryGift\(1, 26, 4, 17\);').Count -eq 1) `
    '一级掌控混沌礼物必须严格为结果26、权重4、评级17'
$expectedWoundFateRanks = @(
    '0:10','1:5','2:0','3:10','4:5','5:0','6:10','7:5','8:0','9:12','10:7','11:2','12:12',
    '13:20','14:25','15:21','16:20','17:24','18:22','19:22','20:22','21:23','22:16','23:6','24:1','25:25',
    '26:17','38:15'
) | Sort-Object
$woundFateRanks = @([regex]::Matches($mechanicsGoal, 'DB_COS_WoundFateRank\((\d+), (\d+)\);'))
$actualWoundFateRanks = @($woundFateRanks | ForEach-Object { '{0}:{1}' -f $_.Groups[1].Value,$_.Groups[2].Value } | Sort-Object)
Require ($woundFateRanks.Count -eq 28 -and -not (Compare-Object $expectedWoundFateRanks $actualWoundFateRanks)) `
    '受击命运评级必须保留0至25并新增结果26/38的指定评级'

foreach ($staleWoundIdentifier in @(
    'DB_COS_WoundWeight(', 'DB_COS_WoundPositive(', 'DB_COS_WoundGrowthWeight',
    'PROC_COS_AddPositiveWoundGrowth', 'PROC_COS_RebuildWoundPool', 'PROC_COS_CommitWoundRoll',
    'PROC_COS_ContinueFateWound', 'PROC_COS_ChooseFateWound', 'PROC_COS_RollWoundPostGrowth',
    '_PositiveThreshold', 'IntegerProduct(_PostLevels, 5, _PositiveThreshold)'
)) {
    Require (-not $mechanicsGoal.Contains($staleWoundIdentifier)) "受击轮盘包含废弃标识符: $staleWoundIdentifier"
}

function Get-MechanicsProcBlocks([string]$Name) {
    $escapedName = [regex]::Escape($Name)
    return @([regex]::Matches($mechanicsGoal, "(?ms)^PROC\r?\n$escapedName\([^\r\n]*\)\r?\n.*?(?=^PROC\r?\n|^KBSECTION\r?$|\z)") | ForEach-Object { $_.Value })
}

function Get-MechanicsThenActions([string]$Block) {
    $parts = @([regex]::Split($Block, '(?m)^THEN\r?$'))
    Require ($parts.Count -eq 2) 'Story 过程必须严格包含一个 THEN 动作段'
    return @($parts[1] -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-MechanicsConditions([string]$Block) {
    $parts = @([regex]::Split($Block, '(?m)^THEN\r?$'))
    Require ($parts.Count -eq 2) 'Story 规则必须严格包含一个 THEN 动作段'
    return @($parts[0] -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notin @('IF', 'PROC', 'AND') })
}

$requiredWoundProcedures = @(
    'PROC_COS_RebuildPositiveWoundPool','PROC_COS_RebuildNegativeWoundPool','PROC_COS_BeginWoundTrials',
    'PROC_COS_RollWoundTrial','PROC_COS_DispatchWoundCategory','PROC_COS_SelectWoundTrial',
    'PROC_COS_ConsiderWoundTrial','PROC_COS_ContinueWoundTrials','PROC_COS_FinishWoundTrials'
)
foreach ($procedureName in $requiredWoundProcedures) {
    Require (@(Get-MechanicsProcBlocks $procedureName).Count -gt 0) "受击轮盘缺少过程: $procedureName"
}

$positiveCandidateBlocks = @(Get-MechanicsProcBlocks 'PROC_COS_AddPositiveWoundCandidates')
Require ($positiveCandidateBlocks.Count -eq 1 -and $positiveCandidateBlocks[0].Contains('DB_COS_WoundPositiveWeight(_Outcome, _Weight)') -and `
    $positiveCandidateBlocks[0].Contains('DB_COS_WoundLayer(_Layer)') -and $positiveCandidateBlocks[0].Contains('_Layer <= _Weight')) `
    '正面候选只能按正面目录权重和层数加入'
$giftCandidateBlocks = @(Get-MechanicsProcBlocks 'PROC_COS_AddMasteryGiftWoundCandidates')
Require ($giftCandidateBlocks.Count -eq 1 -and $giftCandidateBlocks[0].Contains('GetLevel(_Character, _Level)') -and `
    $giftCandidateBlocks[0].Contains('DB_COS_ConfigMechanic((CHARACTER)_Character, "Mastery", 1)') -and `
    $giftCandidateBlocks[0].Contains('DB_COS_MasteryGift(_MinimumLevel, _Outcome, _Weight, _Rank)') -and `
    $giftCandidateBlocks[0].Contains('_Level >= _MinimumLevel') -and $giftCandidateBlocks[0].Contains('_Layer <= _Weight')) `
    '掌控混沌礼物候选必须在 Mastery=1 时按等级和权重加入'
$negativeCandidateBlocks = @(Get-MechanicsProcBlocks 'PROC_COS_AddEnabledNegativeWoundCandidates')
Require ($negativeCandidateBlocks.Count -eq 1 -and $negativeCandidateBlocks[0].Contains('DB_COS_ConfigWound(_Character, _Key, 1)') -and `
    $negativeCandidateBlocks[0].Contains('DB_COS_ConfigWoundOutcome(_Key, _Outcome)') -and `
    $negativeCandidateBlocks[0].Contains('DB_COS_WoundNegativeWeight(_Outcome, _Weight)') -and `
    $negativeCandidateBlocks[0].Contains('_Layer <= _Weight')) `
    '负面候选只能从已启用配置和负面目录加入'

$positiveRebuildBlocks = @(Get-MechanicsProcBlocks 'PROC_COS_RebuildPositiveWoundPool')
$positiveRebuildActions = @(Get-MechanicsThenActions $positiveRebuildBlocks[0])
$expectedPositiveRebuildActions = @(
    'PROC_COS_ClearWoundPool(_Character);',
    'DB_COS_WoundPoolCount(_Character, 0);',
    'PROC_COS_AddPositiveWoundCandidates(_Character);',
    'PROC_COS_AddMasteryGiftWoundCandidates(_Character);'
)
Require ($positiveRebuildBlocks.Count -eq 1 -and `
    (($positiveRebuildActions -join "`n") -ceq ($expectedPositiveRebuildActions -join "`n"))) `
    '正面池必须按清池、计数归零、普通正面、等级礼物的唯一顺序重建'
$negativeRebuildBlocks = @(Get-MechanicsProcBlocks 'PROC_COS_RebuildNegativeWoundPool')
$negativeRebuildActions = @(Get-MechanicsThenActions $negativeRebuildBlocks[0])
$expectedNegativeRebuildActions = @(
    'PROC_COS_ClearWoundPool(_Character);',
    'DB_COS_WoundPoolCount(_Character, 0);',
    'PROC_COS_AddEnabledNegativeWoundCandidates(_Character);'
)
Require ($negativeRebuildBlocks.Count -eq 1 -and `
    (($negativeRebuildActions -join "`n") -ceq ($expectedNegativeRebuildActions -join "`n"))) `
    '负面池必须按清池、计数归零、已启用负面的唯一顺序重建'

$beginTrialBlocks = @(Get-MechanicsProcBlocks 'PROC_COS_BeginWoundTrials')
$beginTrialActions = @(Get-MechanicsThenActions $beginTrialBlocks[0])
Require ($beginTrialBlocks.Count -eq 1 -and $beginTrialBlocks[0].Contains('_RollCount > 0') -and `
    $beginTrialActions.Count -eq 1 -and `
    $beginTrialActions[0] -ceq 'PROC_COS_RollWoundTrial(_Character, _Damage, _PowerEligible, _RollCount, 0, 0, 0);') `
    '受击试炼必须从无最佳结果状态开始且只调用一次首轮试炼'
$rollTrialBlocks = @(Get-MechanicsProcBlocks 'PROC_COS_RollWoundTrial')
$enabledRollTrialBlocks = @($rollTrialBlocks | Where-Object {
    $_.Contains('DB_COS_ConfigMechanic((CHARACTER)_Character, "Mastery", 1)')
})
$disabledRollTrialBlocks = @($rollTrialBlocks | Where-Object {
    $_.Contains('DB_COS_ConfigMechanic((CHARACTER)_Character, "Mastery", 0)')
})
Require ($rollTrialBlocks.Count -eq 2 -and $enabledRollTrialBlocks.Count -eq 1 -and `
    $disabledRollTrialBlocks.Count -eq 1) `
    '受击试炼必须严格包含 Mastery=1 与 Mastery=0 两个互斥同签名分支'
$enabledRollTrialBlock = $enabledRollTrialBlocks[0]
$disabledRollTrialBlock = $disabledRollTrialBlocks[0]
$rollTrialActions = @(Get-MechanicsThenActions $enabledRollTrialBlock)
$tuneCellPattern = '(?m)^IntegerProduct\(_TuneCount, (\d+), _TuneCells\)$'
$tuneCellMatches = @([regex]::Matches($enabledRollTrialBlock, $tuneCellPattern))
$crlfEquivalentTuneCellMatches = @([regex]::Matches(
    (Normalize-LineEndings ($enabledRollTrialBlock.Replace("`n", "`r`n"))), $tuneCellPattern))
Require ($tuneCellMatches.Count -eq 1) `
    '每次调律的 LF 试炼规则必须解析为唯一正面格定义'
Require ($crlfEquivalentTuneCellMatches.Count -eq 1) `
    '每次调律的 CRLF 试炼规则必须解析为唯一正面格定义'
Require ($crlfEquivalentTuneCellMatches[0].Groups[1].Value -eq $tuneCellMatches[0].Groups[1].Value) `
    '受击试炼规则在 CRLF 与 LF 下必须解析为相同的调律格数'
$calmCellMatches = @([regex]::Matches($enabledRollTrialBlock, '(?m)^IntegerProduct\(_CorrectCount, (\d+), _CalmCells\)$'))
$positiveBaseMatches = @([regex]::Matches($enabledRollTrialBlock, '(?m)^IntegerSum\((\d+), _TuneCells, _PositiveEnd\)$'))
$calmEndMatches = @([regex]::Matches($enabledRollTrialBlock, '(?m)^IntegerSum\(_PositiveEnd, _CalmCells, _CalmEnd\)$'))
Require ([int]$tuneCellMatches[0].Groups[1].Value -eq 2) `
    '每次调律必须从实际受击试炼规则解析为2个正面格'
Require ($calmCellMatches.Count -eq 1 -and [int]$calmCellMatches[0].Groups[1].Value -eq 4) `
    '每次校准必须从实际受击试炼规则解析为4个平静格'
Require ($positiveBaseMatches.Count -eq 1 -and [int]$positiveBaseMatches[0].Groups[1].Value -eq 162) `
    '受击试炼必须以IntegerSum(162, _TuneCells, _PositiveEnd)计算正面边界'
Require ($calmEndMatches.Count -eq 1) `
    '受击试炼必须以IntegerSum(_PositiveEnd, _CalmCells, _CalmEnd)计算平静边界'
$tuneCellsPerTune = [int]$tuneCellMatches[0].Groups[1].Value
$calmCellsPerCorrection = [int]$calmCellMatches[0].Groups[1].Value
$positiveBase = [int]$positiveBaseMatches[0].Groups[1].Value
for ($a = 0; $a -le 12; $a++) {
    for ($b = 0; $b -le (12 - $a); $b++) {
        $positive = $positiveBase + $tuneCellsPerTune * $a
        $calm = $calmCellsPerCorrection * $b
        $negative = 300 - $positive - $calm
        Require (($positive + $negative + $calm) -eq 300) "实际Story掌控混沌轮盘总格数错误: A=$a B=$b"
        Require ($positive -ge 0 -and $negative -ge 90 -and $calm -ge 0) "实际Story掌控混沌轮盘类别出现负数或负面低于90格: A=$a B=$b"
        Require (($positive - $negative) -eq (24 + 4 * ($a + $b))) "实际Story掌控混沌轮盘正负差错误: A=$a B=$b"
    }
}
Require (($positiveBase + $tuneCellsPerTune * 12) -eq 186 -and `
    (300 - ($positiveBase + $tuneCellsPerTune * 12)) -eq 114) `
    '实际Story在12次调律、0次校准时必须严格为186/114/0格'
Require (($positiveBase + $tuneCellsPerTune * 6) -eq 174 -and `
    (300 - ($positiveBase + $tuneCellsPerTune * 6) - ($calmCellsPerCorrection * 6)) -eq 102 -and `
    ($calmCellsPerCorrection * 6) -eq 24) `
    '实际Story在6次调律、6次校准时必须严格为174/102/24格'
Require ($positiveBase -eq 162 -and (300 - $positiveBase - ($calmCellsPerCorrection * 12)) -eq 90 -and `
    ($calmCellsPerCorrection * 12) -eq 48) `
    '实际Story在0次调律、12次校准时必须严格为162/90/48格'
Require (([regex]::Matches($enabledRollTrialBlock, 'Random\(300, _CategoryRoll\)').Count -eq 1) -and `
    $enabledRollTrialBlock.Contains('DB_COS_MasteryTuneCount(_Character, _TuneCount)') -and `
    $enabledRollTrialBlock.Contains('DB_COS_MasteryCorrectCount(_Character, _CorrectCount)') -and `
    $enabledRollTrialBlock.Contains('IntegerProduct(_TuneCount, 2, _TuneCells)') -and `
    $enabledRollTrialBlock.Contains('IntegerProduct(_CorrectCount, 4, _CalmCells)') -and `
    $rollTrialActions.Count -eq 1 -and `
    $rollTrialActions[0] -ceq 'PROC_COS_DispatchWoundCategory(_Character, _Damage, _PowerEligible, _Remaining, _HasBest, _BestOutcome, _BestRank, _CategoryRoll, _PositiveEnd, _CalmEnd);') `
    'Mastery=1 受击试炼必须读取路线计数、只生成一次300格类别随机并交给动态边界分类'
function Test-DisabledMasteryWoundBlock([string]$Block) {
    $normalizedBlock = Normalize-LineEndings $Block
    $actions = @(Get-MechanicsThenActions $normalizedBlock)
    return $normalizedBlock.Contains('DB_COS_ConfigMechanic((CHARACTER)_Character, "Mastery", 0)') -and
        ([regex]::Matches($normalizedBlock, 'Random\(300, _CategoryRoll\)').Count -eq 1) -and
        -not $normalizedBlock.Contains('DB_COS_MasteryTuneCount') -and
        -not $normalizedBlock.Contains('DB_COS_MasteryCorrectCount') -and
        -not $normalizedBlock.Contains('_TuneCells') -and
        -not $normalizedBlock.Contains('_CalmCells') -and
        $actions.Count -eq 1 -and
        $actions[0] -ceq 'PROC_COS_DispatchWoundCategory(_Character, _Damage, _PowerEligible, _Remaining, _HasBest, _BestOutcome, _BestRank, _CategoryRoll, 162, 162);'
}
Require (Test-DisabledMasteryWoundBlock $disabledRollTrialBlock) `
    'Mastery=0 受击试炼必须不读取路线账本，只随机一次并以固定162/162边界分类'
Require ([regex]::Matches(($rollTrialBlocks -join "`n"), 'Random\(300, _CategoryRoll\)').Count -eq 2 -and `
    [regex]::Matches($mechanicsGoal, 'Random\(300').Count -eq 2) `
    '受击机制全文必须且只能由两个 Mastery 互斥分支各调用一次 Random(300)'

$disabledWoundReadsCountsMutation = $disabledRollTrialBlock.Replace(
    "`nRandom(300, _CategoryRoll)",
    "`nDB_COS_MasteryTuneCount(_Character, _TuneCount)`nAND`nRandom(300, _CategoryRoll)")
Require (-not (Test-DisabledMasteryWoundBlock $disabledWoundReadsCountsMutation)) `
    'Mastery=0 轮盘 mutation probe 必须拒绝读取路线计数'
$disabledWoundBoundaryMutation = $disabledRollTrialBlock.Replace(', _CategoryRoll, 162, 162);', ', _CategoryRoll, 161, 162);')
Require (-not (Test-DisabledMasteryWoundBlock $disabledWoundBoundaryMutation)) `
    'Mastery=0 轮盘 mutation probe 必须拒绝非162/162固定边界'

$dispatchBlocks = @(Get-MechanicsProcBlocks 'PROC_COS_DispatchWoundCategory')
Require ($dispatchBlocks.Count -eq 3 -and -not (($dispatchBlocks -join "`n").Contains('Random('))) `
    '受击类别分类必须严格为三个无随机分支'
$positiveDispatch = @($dispatchBlocks | Where-Object { $_.Contains('_CategoryRoll < _PositiveEnd') -and -not $_.Contains('_CategoryRoll >= _PositiveEnd') })
$calmDispatch = @($dispatchBlocks | Where-Object { $_.Contains('_CategoryRoll >= _PositiveEnd') -and $_.Contains('_CategoryRoll < _CalmEnd') })
$negativeDispatch = @($dispatchBlocks | Where-Object { $_.Contains('_CategoryRoll >= _CalmEnd') })
$positiveDispatchActions = @(Get-MechanicsThenActions $positiveDispatch[0])
$calmDispatchActions = @(Get-MechanicsThenActions $calmDispatch[0])
$negativeDispatchActions = @(Get-MechanicsThenActions $negativeDispatch[0])
$expectedPositiveDispatchActions = @(
    'PROC_COS_RebuildPositiveWoundPool(_Character);',
    'PROC_COS_SelectWoundTrial(_Character, _Damage, _PowerEligible, _Remaining, _HasBest, _BestOutcome, _BestRank);'
)
$expectedCalmDispatchActions = @(
    'PROC_COS_ConsiderWoundTrial(_Character, _Damage, _PowerEligible, _Remaining, _HasBest, _BestOutcome, _BestRank, 38, _NextRank);'
)
$expectedNegativeDispatchActions = @(
    'PROC_COS_RebuildNegativeWoundPool(_Character);',
    'PROC_COS_SelectWoundTrial(_Character, _Damage, _PowerEligible, _Remaining, _HasBest, _BestOutcome, _BestRank);'
)
Require ($positiveDispatch.Count -eq 1 -and `
    (($positiveDispatchActions -join "`n") -ceq ($expectedPositiveDispatchActions -join "`n"))) `
    '正面类别必须按重建正面池、唯一抽取的顺序分派完整实参'
Require ($calmDispatch.Count -eq 1 -and $calmDispatch[0].Contains('DB_COS_WoundFateRank(38, _NextRank)') -and `
    (($calmDispatchActions -join "`n") -ceq ($expectedCalmDispatchActions -join "`n"))) `
    '平静类别必须以完整实参把结果38唯一交给评级比较'
Require ($negativeDispatch.Count -eq 1 -and `
    (($negativeDispatchActions -join "`n") -ceq ($expectedNegativeDispatchActions -join "`n"))) `
    '负面类别必须按重建负面池、唯一抽取的顺序分派完整实参'

$selectTrialBlocks = @(Get-MechanicsProcBlocks 'PROC_COS_SelectWoundTrial')
$selectTrialActions = @(Get-MechanicsThenActions $selectTrialBlocks[0])
Require ($selectTrialBlocks.Count -eq 1 -and $selectTrialBlocks[0].Contains('DB_COS_WoundPoolCount(_Character, _Count)') -and `
    $selectTrialBlocks[0].Contains('_Count > 0') -and $selectTrialBlocks[0].Contains('Random(_Count, _Slot)') -and `
    $selectTrialBlocks[0].Contains('DB_COS_WoundCandidate(_Character, _Slot, _NextOutcome)') -and `
    $selectTrialBlocks[0].Contains('DB_COS_WoundFateRank(_NextOutcome, _NextRank)') -and `
    $selectTrialActions.Count -eq 1 -and `
    $selectTrialActions[0] -ceq 'PROC_COS_ConsiderWoundTrial(_Character, _Damage, _PowerEligible, _Remaining, _HasBest, _BestOutcome, _BestRank, _NextOutcome, _NextRank);') `
    '池内抽取必须要求非空池并以完整实参和原剩余次数唯一进入评级比较'

$considerTrialBlocks = @(Get-MechanicsProcBlocks 'PROC_COS_ConsiderWoundTrial')
Require ($considerTrialBlocks.Count -eq 3) '受击试炼评级必须严格包含首次、保留和替换三个分支'
foreach ($considerBlock in $considerTrialBlocks) {
    Require ([regex]::Matches($considerBlock, 'IntegerSubtract\(_Remaining, 1, _NextRemaining\)').Count -eq 1) `
        '每个受击试炼评级分支必须恰好递减一次剩余次数'
    Require ([regex]::Matches($considerBlock, 'PROC_COS_ContinueWoundTrials\(').Count -eq 1) `
        '每个受击试炼评级分支必须恰好继续一次'
}
$firstConsider = @($considerTrialBlocks | Where-Object { $_.Contains('_HasBest == 0') })
$keepConsider = @($considerTrialBlocks | Where-Object { $_.Contains('_HasBest == 1') -and $_.Contains('_NextRank <= _BestRank') })
$replaceConsider = @($considerTrialBlocks | Where-Object { $_.Contains('_HasBest == 1') -and $_.Contains('_NextRank > _BestRank') })
Require ($firstConsider.Count -eq 1 -and $firstConsider[0].Contains('_NextOutcome, _NextRank);')) '首次试炼结果必须直接成为最佳结果'
Require ($keepConsider.Count -eq 1 -and $keepConsider[0].Contains('_BestOutcome, _BestRank);')) '同评级或更低评级必须保留首次最佳结果'
Require ($replaceConsider.Count -eq 1 -and $replaceConsider[0].Contains('_NextOutcome, _NextRank);')) '只有严格更高评级才能替换最佳结果'

$continueTrialBlocks = @(Get-MechanicsProcBlocks 'PROC_COS_ContinueWoundTrials')
Require ($continueTrialBlocks.Count -eq 2) '受击试炼继续过程必须严格包含继续和结束两个分支'
$continueRolling = @($continueTrialBlocks | Where-Object { $_.Contains('_Remaining > 0') })
$continueFinish = @($continueTrialBlocks | Where-Object { $_.Contains('_Remaining == 0') })
Require ($continueRolling.Count -eq 1 -and $continueRolling[0].Contains('PROC_COS_RollWoundTrial(_Character, _Damage, _PowerEligible, _Remaining, 1, _BestOutcome, _BestRank);')) `
    '仍有次数时必须带当前最佳结果重投完整受击试炼'
Require ($continueFinish.Count -eq 1 -and $continueFinish[0].Contains('PROC_COS_FinishWoundTrials(_Character, _Damage, _PowerEligible, _BestOutcome);')) `
    '次数耗尽时必须进入唯一结束过程'
$finishTrialBlocks = @(Get-MechanicsProcBlocks 'PROC_COS_FinishWoundTrials')
$finishTrialActions = @(Get-MechanicsThenActions $finishTrialBlocks[0])
$expectedFinishTrialActions = @(
    'PROC_COS_ResolveWound(_Character, _Damage, _BestOutcome, _PowerEligible);',
    'PROC_COS_ClearWoundPool(_Character);'
)
Require ($finishTrialBlocks.Count -eq 1 -and `
    (($finishTrialActions -join "`n") -ceq ($expectedFinishTrialActions -join "`n"))) `
    '受击试炼结束必须先以最佳结果唯一结算，再清空候选池'

$rollWoundBlocks = @(Get-MechanicsProcBlocks 'PROC_COS_RollWound')
$normalWoundRollActions = @(Get-MechanicsThenActions $rollWoundBlocks[0])
$expectedNormalWoundRollActions = @(
    'PROC_COS_BeginWoundTrials(_Character, _Damage, _PowerEligible, 1);'
)
Require ($rollWoundBlocks.Count -eq 1 -and `
    (($normalWoundRollActions -join "`n") -ceq ($expectedNormalWoundRollActions -join "`n"))) `
    '普通受击入口必须且只能开始一次单次完整试炼'
Require (-not ($rollWoundBlocks[0] -match 'FATE|FateRolls|_RollCount')) `
    '命运改签改为攻击触发后，受击轮盘不得再读取或消耗命运状态'

$resolveWoundBlocks = @(Get-MechanicsProcBlocks 'PROC_COS_ResolveWound')
$giftResolve = @($resolveWoundBlocks | Where-Object { $_.Contains('_Roll == 26') })
$calmResolve = @($resolveWoundBlocks | Where-Object { $_.Contains('_Roll == 38') })
$giftResolveActions = @($giftResolve | ForEach-Object { ($_ -split '(?m)^THEN\r?$', 2)[1] })
$calmResolveActions = @($calmResolve | ForEach-Object { ($_ -split '(?m)^THEN\r?$', 2)[1] })
Require ($giftResolve.Count -eq 1 -and $giftResolve[0].Contains('ApplyStatus(_Character, "COS_CHAOS_MASTERY_RESULT_L01", 12.0, 100, _Character);') -and `
    ([regex]::Matches($giftResolveActions[0], '(?m)^[A-Za-z][A-Za-z0-9_]+\(').Count -eq 1) -and `
    -not ($giftResolve[0] -match 'PROC_COS_(RecordWoundNegative|AddLost)|DB_COS_WoundStatus')) `
    '结果26必须只应用12秒一级掌控混沌礼物且不得串联普通正面结果'
Require ($calmResolve.Count -eq 1 -and $calmResolve[0].Contains('ApplyStatus(_Character, "COS_CHAOS_MASTERY_CALM_LOG", 0.1, 100, _Character);') -and `
    ([regex]::Matches($calmResolveActions[0], '(?m)^[A-Za-z][A-Za-z0-9_]+\(').Count -eq 1) -and `
    -not ($calmResolve[0] -match 'PROC_COS_(RecordWoundNegative|AddLost)|DB_COS_WoundStatus')) `
    '结果38必须只显示平静日志且不得记录负面或增加遗失'
Require (-not [regex]::IsMatch($mechanicsGoal, 'DB_COS_WoundStatus\([^\r\n]+"(MADNESS|FRIGHTENED|STUNNED|PRONE|SILENCED|BLINDED|SLOW|POISONED|BLEEDING|BURNING)"')) `
    '受击轮盘不得包含夺取控制或可能造成失控死亡的原版负面状态'
Require (-not [regex]::IsMatch($mechanicsGoal, '_Roll == (23|24)[\s\S]{0,700}(ApplyDamage|WOUND_VULNERABILITY)')) `
    '受击轮盘不得通过随机易伤或额外伤害制造突然死亡'
Require ([regex]::Matches($mechanicsGoal, 'NOT DB_COS_WoundConsumed\(\(CHARACTER\)_Character\);').Count -eq 3) `
    '受击轮盘锁必须在回合开始、进入战斗和离开战斗时清除'
Require (-not $mechanicsGoal.Contains('IsInCombat(_Target, 1)')) `
    '受击轮盘不得把非战斗状态下的角色攻击错误过滤掉'
$iconAtlasPath = Join-Path $root "Public\$module\Assets\Textures\Icons\Icons_ChaosOrigins.dds"
Require (Test-Path -LiteralPath $iconAtlasPath -PathType Leaf) '缺少技能图标 DDS 图集'
$iconTextureBytes = [IO.File]::ReadAllBytes($iconAtlasPath)
Require ($iconTextureBytes.Length -eq 349680 -and `
    [Text.Encoding]::ASCII.GetString($iconTextureBytes, 0, 4) -eq 'DDS ' -and `
    [BitConverter]::ToInt32($iconTextureBytes, 12) -eq 512 -and `
    [BitConverter]::ToInt32($iconTextureBytes, 16) -eq 512 -and `
    [BitConverter]::ToInt32($iconTextureBytes, 24) -eq 1 -and `
    [BitConverter]::ToInt32($iconTextureBytes, 28) -eq 10 -and `
    [Text.Encoding]::ASCII.GetString($iconTextureBytes, 84, 4) -eq 'DXT5') `
    '技能图集必须是512x512、10级mipmap的DXT5/BC3 DDS'
for ($reservedIndex = 32; $reservedIndex -le 75; $reservedIndex++) {
    Require ($iconTextureBytes[$reservedIndex] -eq 0) 'DDS 图集保留头必须为空'
}

$atlasCellCoordinates = @{
    COS_Identity = @(0, 0); COS_Status = @(1, 0); COS_Lost = @(2, 0); COS_Power = @(3, 0)
    COS_AllIn = @(0, 1); COS_Echo = @(1, 1); COS_Strike = @(2, 1); COS_Genesis = @(3, 1)
    COS_Finisher = @(0, 2); COS_Wound = @(1, 2); COS_Duality = @(2, 2); COS_FateRevision = @(3, 2)
    COS_Mastery = @(0, 3); COS_MasteryTune = @(1, 3); COS_MasteryCorrect = @(2, 3)
}
$generatedIconKeys = @(
    'COS_Power', 'COS_Lost', 'COS_Wound', 'COS_Duality',
    'COS_AllIn', 'COS_FateRevision', 'COS_Genesis', 'COS_Strike',
    'COS_Mastery', 'COS_MasteryTune', 'COS_MasteryCorrect', 'COS_Finisher'
)
$repositoryRoot = Split-Path $root -Parent
$baselineIconBytes = Get-GitBlobBytes $repositoryRoot `
    'ad3c4cc:story-src/Public/ChaosOriginsStory/Assets/Textures/Icons/Icons_ChaosOrigins.dds'
Require ($baselineIconBytes.Length -eq $iconTextureBytes.Length) `
    '当前技能图集必须保持 ad3c4cc 基线 DDS 的尺寸与布局'
for ($headerIndex = 0; $headerIndex -lt 128; $headerIndex++) {
    Require ($iconTextureBytes[$headerIndex] -eq $baselineIconBytes[$headerIndex]) `
        "技能图集头必须逐字节保留 ad3c4cc 基线: offset=$headerIndex"
}
$mipOffset = 128
for ($mip = 0; $mip -lt 10; $mip++) {
    $mipSize = [Math]::Max(1, 512 -shr $mip)
    $blocksWide = [Math]::Max(1, [int][Math]::Ceiling($mipSize / 4.0))
    $blocksHigh = $blocksWide
    $targetBlockStarts = [Collections.Generic.HashSet[int]]::new()
    if ($mip -le 4) {
        $cellSize = 64 -shr $mip
        $cellBlocks = $cellSize / 4
        foreach ($iconKey in $generatedIconKeys) {
            $cell = $atlasCellCoordinates[$iconKey]
            $firstBlockX = ([int]$cell[0] * $cellSize) / 4
            $firstBlockY = ([int]$cell[1] * $cellSize) / 4
            for ($blockY = 0; $blockY -lt $cellBlocks; $blockY++) {
                for ($blockX = 0; $blockX -lt $cellBlocks; $blockX++) {
                    $blockStart = $mipOffset + ((($firstBlockY + $blockY) * $blocksWide +
                        $firstBlockX + $blockX) * 16)
                    [void]$targetBlockStarts.Add($blockStart)
                }
            }
        }
    }
    for ($blockIndex = 0; $blockIndex -lt ($blocksWide * $blocksHigh); $blockIndex++) {
        $blockStart = $mipOffset + ($blockIndex * 16)
        if ($targetBlockStarts.Contains($blockStart)) { continue }
        for ($byteInBlock = 0; $byteInBlock -lt 16; $byteInBlock++) {
            if ($iconTextureBytes[$blockStart + $byteInBlock] -ne
                $baselineIconBytes[$blockStart + $byteInBlock]) {
                throw "DDS 未触及 BC3 block 偏离 ad3c4cc 基线: mip=$mip block=$blockIndex byte=$byteInBlock"
            }
        }
    }
    $mipOffset += $blocksWide * $blocksHigh * 16
}
Require ($mipOffset -eq $iconTextureBytes.Length) 'DDS mip 布局与文件长度不一致'

$magick = Get-Command magick -ErrorAction SilentlyContinue
Require ($null -ne $magick) '验证技能图标需要已安装的 ImageMagick magick'
$atlasIdentity = [string](& $magick.Source identify -quiet -format '%w|%h|%[channels]|%[opaque]' $iconAtlasPath)
Require ($LASTEXITCODE -eq 0) 'ImageMagick 无法解码技能图集'
$atlasIdentityParts = @($atlasIdentity -split '\|')
Require ($atlasIdentityParts.Count -eq 4 -and $atlasIdentityParts[0] -eq '512' -and `
    $atlasIdentityParts[1] -eq '512' -and $atlasIdentityParts[2] -match 'a' -and `
    $atlasIdentityParts[3] -eq 'False') '技能图集必须可解码为含真实透明度的512x512图像'

$artworkRoot = Join-Path (Split-Path $root -Parent) 'artwork\icons-v2'
$expectedArtworkFiles = @($generatedIconKeys | ForEach-Object { "$_.png" }) +
    @('preview-64px.png', 'README.md', 'rebuild-atlas.ps1')
$actualArtworkFiles = @(Get-ChildItem -LiteralPath $artworkRoot -File | ForEach-Object { $_.Name } | Sort-Object)
Require (-not (Compare-Object @($expectedArtworkFiles | Sort-Object) $actualArtworkFiles)) `
    '图标源目录必须只包含12枚透明PNG、64px预览和README'

$artworkReadme = Get-Content -LiteralPath (Join-Path $artworkRoot 'README.md') -Raw -Encoding UTF8
foreach ($readmeToken in @($generatedIconKeys + @(
    'imagegen', 'DXT5', 'mipmap', 'transparent', 'row0', 'row1', 'row2', 'row3',
    'COS_Origin', 'COS_Identity', 'ad3c4cc', 'mip0', 'mip4', 'mip5+', '#808080', 'rebuild-atlas.ps1'
))) {
    Require ($artworkReadme.Contains($readmeToken)) "图标README缺少生成、行映射或后处理记录: $readmeToken"
}
$rebuildAtlasScript = Get-Content -LiteralPath (Join-Path $artworkRoot 'rebuild-atlas.ps1') -Raw -Encoding UTF8
foreach ($scriptToken in @(
    '#requires -Version 7.0', "BaselineCommit = 'ad3c4cc'", '[byte[]]$patchedBytes = $baselineBytes.Clone()',
    '$mip -le 4', '64 -shr $mip', 'canvas:none', 'xc:#808080', 'Get-GitBlobBytes'
)) {
    Require ($rebuildAtlasScript.Contains($scriptToken)) "图标重建脚本缺少可复现基线block patch步骤: $scriptToken"
}
function ConvertFrom-InvariantDouble([string]$Value) {
    return [double]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture)
}
$previewIdentity = [string](& $magick.Source (Join-Path $artworkRoot 'preview-64px.png') -format `
    '%w|%h|%[opaque]|%[fx:p{0,0}.r]|%[fx:p{0,0}.g]|%[fx:p{0,0}.b]' info:)
$previewParts = @($previewIdentity -split '\|')
Require ($LASTEXITCODE -eq 0 -and $previewParts.Count -eq 6 -and $previewParts[0] -eq '320' -and `
    $previewParts[1] -eq '240' -and $previewParts[2] -eq 'True' -and `
    [Math]::Abs((ConvertFrom-InvariantDouble $previewParts[3]) - (128.0 / 255.0)) -lt 0.0001 -and `
    [Math]::Abs((ConvertFrom-InvariantDouble $previewParts[4]) - (128.0 / 255.0)) -lt 0.0001 -and `
    [Math]::Abs((ConvertFrom-InvariantDouble $previewParts[5]) - (128.0 / 255.0)) -lt 0.0001) `
    '64px图标预览必须是320x240且实际合成在#808080灰底'

$neutralMatteExpression = `
    '(a>0)&&(r<=0.156863)&&(g<=0.156863)&&(b<=0.156863)&&(abs(r-g)<=0.039216)&&(abs(r-b)<=0.039216)&&(abs(g-b)<=0.039216)?1:0'
foreach ($iconKey in $generatedIconKeys) {
    $sourcePng = Join-Path $artworkRoot "$iconKey.png"
    $sourceIdentity = [string](& $magick.Source identify -quiet -format '%w|%h|%[channels]|%[opaque]' $sourcePng)
    Require ($LASTEXITCODE -eq 0) "无法读取图标PNG: $iconKey"
    $sourceIdentityParts = @($sourceIdentity -split '\|')
    Require ($sourceIdentityParts.Count -eq 4 -and $sourceIdentityParts[0] -eq '256' -and `
        $sourceIdentityParts[1] -eq '256' -and $sourceIdentityParts[2] -match 'a' -and `
        $sourceIdentityParts[3] -eq 'False') "图标源必须是带透明背景的256x256 PNG: $iconKey"
    $mattePixels = [string](& $magick.Source $sourcePng -channel A -fx $neutralMatteExpression `
        -format '%[fx:mean*w*h]' info:)
    Require ($LASTEXITCODE -eq 0 -and (ConvertFrom-InvariantDouble $mattePixels) -lt 0.01) `
        "图标源仍含近黑中性不透明 matte: $iconKey / pixels=$mattePixels"
    $thumbnailMetrics = [string](& $magick.Source $sourcePng -filter Lanczos -resize '64x64!' -alpha extract `
        -format '%w|%h|%[fx:minima]|%[fx:maxima]|%[fx:mean]|%[fx:p{0,0}]|%[fx:p{63,0}]|%[fx:p{0,63}]|%[fx:p{63,63}]' info:)
    Require ($LASTEXITCODE -eq 0) "无法生成64px图标缩略图: $iconKey"
    $thumbnailParts = @($thumbnailMetrics -split '\|')
    Require ($thumbnailParts.Count -eq 9 -and $thumbnailParts[0] -eq '64' -and $thumbnailParts[1] -eq '64') `
        "图标缩略图尺寸错误: $iconKey"
    $alphaMinimum = ConvertFrom-InvariantDouble $thumbnailParts[2]
    $alphaMaximum = ConvertFrom-InvariantDouble $thumbnailParts[3]
    $alphaMean = ConvertFrom-InvariantDouble $thumbnailParts[4]
    $cornerAlpha = @(5..8 | ForEach-Object { ConvertFrom-InvariantDouble $thumbnailParts[$_] })
    Require ($alphaMinimum -le 0.001 -and $alphaMaximum -ge 0.99 -and `
        $alphaMean -gt 0.005 -and $alphaMean -lt 0.95 -and `
        -not ($cornerAlpha | Where-Object { $_ -gt 0.001 })) `
        "64px图标缩略图必须非空且四角透明: $iconKey"
}

function Get-ImageRmse([string]$ExpectedPath, [string]$ActualPath, [string]$Label) {
    $metricOutput = @(& $magick.Source compare -metric RMSE $ExpectedPath $ActualPath null: 2>&1)
    $metricExit = $LASTEXITCODE
    Require ($metricExit -in @(0, 1)) "ImageMagick RMSE比较失败: $Label"
    $metricText = $metricOutput -join ' '
    $metricMatch = [regex]::Match($metricText, '\(([0-9.eE+-]+)\)')
    Require ($metricMatch.Success) "ImageMagick RMSE输出无法解析: $Label / $metricText"
    return ConvertFrom-InvariantDouble $metricMatch.Groups[1].Value
}

$comparisonTemp = Join-Path ([IO.Path]::GetTempPath()) ('cos-icon-verify-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($comparisonTemp)
$comparisonFiles = [Collections.Generic.List[string]]::new()
try {
    foreach ($iconKey in $generatedIconKeys) {
        $cell = $atlasCellCoordinates[$iconKey]
        $crop = '64x64+{0}+{1}' -f ([int]$cell[0] * 64), ([int]$cell[1] * 64)
        $expectedThumbnail = Join-Path $comparisonTemp "$iconKey-expected.png"
        $actualCell = Join-Path $comparisonTemp "$iconKey-dds.png"
        $comparisonFiles.Add($expectedThumbnail)
        $comparisonFiles.Add($actualCell)
        & $magick.Source (Join-Path $artworkRoot "$iconKey.png") -filter Lanczos -resize '64x64!' `
            $expectedThumbnail
        Require ($LASTEXITCODE -eq 0) "无法生成图标比对缩略图: $iconKey"
        & $magick.Source ($iconAtlasPath + '[0]') -crop $crop +repage $actualCell
        Require ($LASTEXITCODE -eq 0) "无法提取DDS目标格: $iconKey"

        $alphaExpected = Join-Path $comparisonTemp "$iconKey-alpha-expected.png"
        $alphaActual = Join-Path $comparisonTemp "$iconKey-alpha-dds.png"
        $comparisonFiles.Add($alphaExpected)
        $comparisonFiles.Add($alphaActual)
        & $magick.Source $expectedThumbnail -alpha extract $alphaExpected
        Require ($LASTEXITCODE -eq 0) "无法提取源alpha: $iconKey"
        & $magick.Source $actualCell -alpha extract $alphaActual
        Require ($LASTEXITCODE -eq 0) "无法提取DDS alpha: $iconKey"
        $alphaRmse = Get-ImageRmse $alphaExpected $alphaActual "$iconKey alpha"
        Require ($alphaRmse -le 0.02) `
            "DDS目标格alpha偏离当前source: $iconKey / RMSE=$alphaRmse threshold=0.02"

        $pollutionExpression = '(u.a<=0.01)&&(v.a>0.08)?1:0'
        $pollutedPixels = [string](& $magick.Source $expectedThumbnail $actualCell -channel A `
            -fx $pollutionExpression -format '%[fx:mean*w*h]' info:)
        Require ($LASTEXITCODE -eq 0 -and (ConvertFrom-InvariantDouble $pollutedPixels) -lt 0.01) `
            "DDS透明源区出现旧像素或alpha污染: $iconKey / pixels=$pollutedPixels threshold=0"

        foreach ($background in @('#181818', '#808080', '#f0f0f0')) {
            $backgroundToken = $background.TrimStart('#')
            $expectedComposite = Join-Path $comparisonTemp "$iconKey-$backgroundToken-expected.png"
            $actualComposite = Join-Path $comparisonTemp "$iconKey-$backgroundToken-dds.png"
            $comparisonFiles.Add($expectedComposite)
            $comparisonFiles.Add($actualComposite)
            & $magick.Source -size '64x64' "xc:$background" $expectedThumbnail -compose over -composite `
                -alpha off $expectedComposite
            Require ($LASTEXITCODE -eq 0) "无法合成源图背景: $iconKey / $background"
            & $magick.Source -size '64x64' "xc:$background" $actualCell -compose over -composite `
                -alpha off $actualComposite
            Require ($LASTEXITCODE -eq 0) "无法合成DDS背景: $iconKey / $background"
            $compositeRmse = Get-ImageRmse $expectedComposite $actualComposite `
                "$iconKey composite $background"
            Require ($compositeRmse -le 0.085) `
                "DDS目标格在实际背景合成后偏离source: $iconKey / $background / RMSE=$compositeRmse threshold=0.085"
        }
    }
} finally {
    foreach ($comparisonFile in $comparisonFiles) {
        if ([IO.File]::Exists($comparisonFile)) { [IO.File]::Delete($comparisonFile) }
    }
    if ([IO.Directory]::Exists($comparisonTemp)) { [IO.Directory]::Delete($comparisonTemp) }
}

foreach ($iconKey in $atlasCellCoordinates.Keys) {
    $cell = $atlasCellCoordinates[$iconKey]
    $crop = '64x64+{0}+{1}' -f ([int]$cell[0] * 64), ([int]$cell[1] * 64)
    $cellMetrics = [string](& $magick.Source $iconAtlasPath -crop $crop +repage -alpha extract `
        -format '%[fx:minima]|%[fx:maxima]|%[fx:mean]' info:)
    Require ($LASTEXITCODE -eq 0) "无法解码DDS图标格: $iconKey"
    $cellParts = @($cellMetrics -split '\|')
    Require ($cellParts.Count -eq 3 -and (ConvertFrom-InvariantDouble $cellParts[0]) -le 0.05 -and `
        (ConvertFrom-InvariantDouble $cellParts[1]) -ge 0.5 -and `
        (ConvertFrom-InvariantDouble $cellParts[2]) -gt 0.001) `
        "DDS图标格必须非空且保留透明度: $iconKey"
}
$allStats = (Get-ChildItem -LiteralPath (Join-Path $root "Public\$module\Stats\Generated\Data") -File -Filter '*.txt' | `
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
Require (($registeredMasteryIcons -contains 'COS_Origin') -and `
    [regex]::Matches($allStats, '(?m)^data "Icon" "COS_Origin"\r?$').Count -eq 7) `
    'ChaosRuntime 的七个 COS_Origin 引用必须闭合到 COS_Identity 有意别名'
function Require-StatsIcon([string]$Entry, [string]$ExpectedIcon) {
    $entryPattern = '(?ms)^new entry "' + [regex]::Escape($Entry) + '".*?(?=^new entry |\z)'
    $entryMatches = @([regex]::Matches($allStats, $entryPattern))
    Require ($entryMatches.Count -eq 1) "Stats图标条目必须全局唯一: $Entry"
    $iconMatches = @([regex]::Matches($entryMatches[0].Value, '(?m)^data "Icon" "([^"]+)"\r?$'))
    Require ($iconMatches.Count -eq 1 -and $iconMatches[0].Groups[1].Value -eq $ExpectedIcon) `
        "Stats图标映射错误: $Entry -> $ExpectedIcon"
}
$expectedStatsIcons = @{
    COS_ChaosWound = 'COS_Wound'
    COS_ChaosDuality = 'COS_Duality'
    COS_FateRevision = 'COS_FateRevision'
    Shout_COS_FateRevision = 'COS_FateRevision'
    COS_CHAOS_FATE_READY = 'COS_FateRevision'
    COS_CHAOS_FATE_PENDING = 'COS_FateRevision'
    COS_CHAOS_FATE_ENABLED = 'COS_FateRevision'
    COS_ChaosMasteryGuide = 'COS_Mastery'
    COS_ChaosMasteryPointL01 = 'COS_Mastery'
    Shout_COS_ChaosMastery = 'COS_Mastery'
    Shout_COS_ChaosMasteryTune = 'COS_MasteryTune'
    COS_CHAOS_MASTERY_TUNE = 'COS_MasteryTune'
    COS_CHAOS_MASTERY_POSITIVE_INFO = 'COS_MasteryTune'
    Shout_COS_ChaosMasteryCorrect = 'COS_MasteryCorrect'
    COS_CHAOS_MASTERY_CORRECT = 'COS_MasteryCorrect'
    COS_CHAOS_MASTERY_NEGATIVE_INFO = 'COS_MasteryCorrect'
    COS_CHAOS_MASTERY_CALM_INFO = 'COS_Echo'
    COS_CHAOS_MASTERY_CALM_LOG = 'COS_Echo'
    COS_CHAOS_MASTERY_RESULT_L01 = 'COS_Echo'
    COS_ChaosPower = 'COS_Power'
    COS_ChaosLost = 'COS_Lost'
    COS_ChaosAllIn = 'COS_AllIn'
    COS_ChaosStrike = 'COS_Strike'
    Shout_COS_ChaosGenesis = 'COS_Genesis'
    COS_CHAOS_KILL = 'COS_Finisher'
}
foreach ($entry in $expectedStatsIcons.Keys) {
    Require-StatsIcon $entry $expectedStatsIcons[$entry]
}
foreach ($newIconCount in @{
    COS_Wound = 1
    COS_Duality = 1
    COS_FateRevision = 5
    COS_Mastery = 3
    COS_MasteryTune = 4
    COS_MasteryCorrect = 4
}.GetEnumerator()) {
    Require ([regex]::Matches($allStats, '(?m)^data "Icon" "' + [regex]::Escape($newIconCount.Key) + '"\r?$').Count -eq `
        $newIconCount.Value) "Stats新图标引用数量错误: $($newIconCount.Key)"
}
$boostFieldMatches = @([regex]::Matches($allStats, '(?m)^data "Boosts" "([^"]*)"\r?$'))
$skillCheckBoostTokens = @($boostFieldMatches | ForEach-Object {
    $_.Groups[1].Value -split ';' | Where-Object { $_ -ceq 'RollBonus(SkillCheck,5)' }
})
Require ($skillCheckBoostTokens.Count -eq 0) `
    '逐项技能加值不得叠加原有通用技能检定+5'
Require (-not ($allStats -match 'ProficiencyBonus\(Skill|ExpertiseBonus\(')) `
    '完整 Stats 不得额外授予任何技能熟练或专精'
Require ([regex]::Matches($mechanicsGoal, 'DB_COS_LifeSkillLevel\(\d+, \d+, "COS_CHAOS_LIFE_SKILL_BONUS_\d"\);').Count -eq 7) `
    '生活检定成长必须严格包含 5 至 30 级的 7 个阶段'
foreach ($lifeSkillBonus in 1..7) {
    $lifeSkillEntry = "COS_CHAOS_LIFE_SKILL_BONUS_$lifeSkillBonus"
    $lifeSkillPattern = '(?ms)^new entry "{0}".*?(?=^new entry |\z)' -f [regex]::Escape($lifeSkillEntry)
    $lifeSkillBlocks = @([regex]::Matches($allStats, $lifeSkillPattern))
    Require ($lifeSkillBlocks.Count -eq 1) "生活检定成长档位必须唯一声明: $lifeSkillEntry"
    $lifeSkillBlock = $lifeSkillBlocks[0].Value
    $lifeSkillBoosts = @([regex]::Matches($lifeSkillBlock, '(?m)^data "Boosts" "([^"]*)"\r?$'))
    Require ($lifeSkillBoosts.Count -eq 1 -and
        $lifeSkillBoosts[0].Groups[1].Value -ceq "RollBonus(RawAbility,$lifeSkillBonus)") `
        "生活检定成长必须只提供对应的纯属性检定档位: $lifeSkillEntry"
    Require (-not $lifeSkillBlock.Contains('RollBonus(SkillCheck,')) `
        "生活检定成长不得叠加固定技能检定+5: $lifeSkillEntry"
}
$lifeSkillDuplicateMutation = $allStats + "`nnew entry ""COS_CHAOS_LIFE_SKILL_BONUS_1""`ndata ""Boosts"" ""RollBonus(RawAbility,1)"""
$lifeSkillDuplicateBlocks = @([regex]::Matches(
    $lifeSkillDuplicateMutation,
    '(?ms)^new entry "COS_CHAOS_LIFE_SKILL_BONUS_1".*?(?=^new entry |\z)'
))
$lifeSkillDuplicateProbeKilled = $false
try {
    Require ($lifeSkillDuplicateBlocks.Count -eq 1) '生活检定重复条目变异应被拒绝'
} catch {
    $lifeSkillDuplicateProbeKilled = $true
}
Require $lifeSkillDuplicateProbeKilled '生活检定重复条目 mutation probe 必须被拒绝'
Write-Host 'MUTATION_LIFE_SKILL_DUPLICATE=KILLED'
$commentSkillCheckMutation = $allStats + "`n// RollBonus(SkillCheck,5)"
$commentBoostFieldMatches = @([regex]::Matches($commentSkillCheckMutation, '(?m)^data "Boosts" "([^"]*)"\r?$'))
$commentSkillCheckTokens = @($commentBoostFieldMatches | ForEach-Object {
    $_.Groups[1].Value -split ';' | Where-Object { $_ -ceq 'RollBonus(SkillCheck,5)' }
})
Require ($commentSkillCheckTokens.Count -eq $skillCheckBoostTokens.Count) `
    '完整 Stats 的注释 token mutation 不得改变固定技能检定统计'
Write-Host 'MUTATION_STATS_COMMENT_SKILL_CHECK=IGNORED'
Require ($mechanicsGoal.Contains('IntegerMin(_Level, 30, _CappedLevel)') -and `
    $mechanicsGoal.Contains('PROC_COS_ClearLifeSkillBonus(_Character);') -and `
    $mechanicsGoal.Contains('PROC_COS_ApplyLifeSkillBonus(_Character);')) `
    '生活检定成长必须封顶 30 级并在同步时替换旧档位'
Require (-not ($allStats -match 'COS_ChaosEcho|COS_CHAOS_ECHO_LOG_|COS_CHAOS_SENTINEL_ECHO_')) `
    '完整 Stats 不得保留混沌回响定义'
$featuresPath = Join-Path $root "Public\$module\Stats\Generated\Data\ChaosFeatures.txt"
$featuresText = Get-Content -LiteralPath $featuresPath -Raw -Encoding UTF8
Require (-not $featuresText.Contains('new entry "Shout_COS_TestPower100"') -and `
    -not $featuresText.Contains('new entry "Shout_COS_TestRestoreAllIn"') -and `
    -not $allStats.Contains('new entry "COS_CHAOS_RESTORE_ALLIN"')) `
    '发行版不得包含测试混沌之力、测试孤注充能技能或其专用状态'
Require (-not $goal.Contains('DB_COS_CoreSpell(1, "Shout_COS_TestPower100");') -and `
    -not $goal.Contains('DB_COS_CoreSpell(1, "Shout_COS_TestRestoreAllIn");')) `
    '基础同步不得再授予两个测试技能'
Require ($goal.Contains('HasSpell(_Character, "Shout_COS_TestPower100", 1)') -and `
    $goal.Contains('RemoveSpell(_Character, "Shout_COS_TestPower100", 0);') -and `
    $goal.Contains('HasSpell(_Character, "Shout_COS_TestRestoreAllIn", 1)') -and `
    $goal.Contains('RemoveSpell(_Character, "Shout_COS_TestRestoreAllIn", 0);')) `
    '基础同步必须清理旧存档已经获得的两个测试技能'
Require (-not $mechanicsGoal.Contains('UsingSpell(_Character, "Shout_COS_TestPower100"') -and `
    -not $mechanicsGoal.Contains('COS_CHAOS_RESTORE_ALLIN')) `
    '混沌机制不得保留测试技能处理规则'
Require ($featuresText.Contains('data "StackType" "Additive"') -and `
    $featuresText.Contains('StatusImmunity(COS_CHAOS_SENTINEL_POWER)') -and `
    $featuresText.Contains('IgnoreResting;FreezeDuration')) `
    '混沌之力必须使用可显示当前点数的冻结持续时间状态'
Require ($mechanicsGoal.Contains('IntegerProduct(_Power, 6, _DurationSeconds)') -and `
    $mechanicsGoal.Contains('IntegerToReal(_DurationSeconds, _Duration)') -and `
    $mechanicsGoal.Contains('ApplyStatus(_Character, "COS_CHAOS_POWER_STACK", _Duration, 100, _Character)')) `
    '混沌之力显示必须把当前点数换算成冻结的回合数字'
Require ($mechanicsGoal.Contains('_OldPower >= 10') -and `
    $mechanicsGoal.Contains('IntegerSubtract(_OldPower, 10, _NewPower)') -and `
    $mechanicsGoal.Contains('_Power >= 10')) `
    '混沌开天辟地必须需要并消耗 10 点混沌之力'
Require ($passive.Contains('new entry "COS_FateRevision"') -and `
    $passive.Contains('data "Properties" "IsToggled;ToggledDefaultOn"') -and `
    $featuresText.Contains('new entry "COS_CHAOS_FATE_ENABLED"')) `
    '命运改签必须是默认开启、可手动关闭的被动能力'
Require ($goal.Contains('DB_COS_CorePassive(1, "COS_FateRevision");') -and `
    -not $goal.Contains('DB_COS_CoreSpell(1, "Shout_COS_FateRevision");') -and `
    $goal.Contains('RemoveSpell(_Character, "Shout_COS_FateRevision", 0);')) `
    '命运改签必须授予新被动并清理旧主动技能及其挂起状态'
Require (-not ($mechanicsGoal -match 'COS_CHAOS_FATE_READY|Shout_COS_FateRevision')) `
    '命运改签攻击链不得继续依赖旧主动技能、待结算或资源就绪状态'
Require ([regex]::Matches($mechanicsGoal, 'COS_CHAOS_FATE_PENDING').Count -eq 8) `
    '旧命运改签待触发状态只能出现在四个互斥的一次性迁移分支中'
$legacyFateMigrationBlocks = @(Get-MechanicsProcBlocks 'PROC_COS_MigrateLegacyFatePending')
$legacyFateRefundBlocks = @($legacyFateMigrationBlocks | Where-Object {
    @(Get-MechanicsConditions $_) -contains 'DB_COS_Power(_Character, _OldPower)'
})
$legacyFatePowerOffBlocks = @($legacyFateMigrationBlocks | Where-Object {
    @(Get-MechanicsConditions $_) -contains 'DB_COS_ConfigMechanic(_Character, "Power", 0)'
})
$legacyFateMissingConfigBlocks = @($legacyFateMigrationBlocks | Where-Object {
    @(Get-MechanicsConditions $_) -contains 'NOT DB_COS_ConfigMechanic(_Character, "Power", _)'
})
$legacyFateMissingPowerBlocks = @($legacyFateMigrationBlocks | Where-Object {
    @(Get-MechanicsConditions $_) -contains 'NOT DB_COS_Power(_Character, _)'
})
Require ($legacyFateMigrationBlocks.Count -eq 4 -and $legacyFateRefundBlocks.Count -eq 1 -and `
    $legacyFatePowerOffBlocks.Count -eq 1 -and $legacyFateMissingConfigBlocks.Count -eq 1 -and `
    $legacyFateMissingPowerBlocks.Count -eq 1) `
    '旧命运改签迁移必须严格区分已扣款、Power关闭、配置缺失和数值缺失'
$expectedLegacyFateRefundConditions = @(
    'PROC_COS_MigrateLegacyFatePending((CHARACTER)_Character)',
    'HasActiveStatus(_Character, "COS_CHAOS_FATE_PENDING", 1)',
    'DB_COS_ConfigMechanic(_Character, "Power", 1)',
    'DB_COS_Power(_Character, _OldPower)',
    'IntegerSum(_OldPower, 1, _NewPower)'
)
$expectedLegacyFateRefundActions = @(
    'RemoveStatus(_Character, "COS_CHAOS_FATE_PENDING", _Character);',
    'NOT DB_COS_Power(_Character, _OldPower);',
    'DB_COS_Power(_Character, _NewPower);'
)
$expectedLegacyFateClearAction = @('RemoveStatus(_Character, "COS_CHAOS_FATE_PENDING", _Character);')
Require (((Get-MechanicsConditions $legacyFateRefundBlocks[0]) -join "`n") -ceq ($expectedLegacyFateRefundConditions -join "`n") -and `
    ((Get-MechanicsThenActions $legacyFateRefundBlocks[0]) -join "`n") -ceq ($expectedLegacyFateRefundActions -join "`n")) `
    '旧主动命运改签的预付1点必须在清除待触发状态时明确返还'
$expectedLegacyFatePowerOffConditions = @(
    'PROC_COS_MigrateLegacyFatePending((CHARACTER)_Character)',
    'HasActiveStatus(_Character, "COS_CHAOS_FATE_PENDING", 1)',
    'DB_COS_ConfigMechanic(_Character, "Power", 0)'
)
$expectedLegacyFateMissingConfigConditions = @(
    'PROC_COS_MigrateLegacyFatePending((CHARACTER)_Character)',
    'HasActiveStatus(_Character, "COS_CHAOS_FATE_PENDING", 1)',
    'NOT DB_COS_ConfigMechanic(_Character, "Power", _)'
)
$expectedLegacyFateMissingPowerConditions = @(
    'PROC_COS_MigrateLegacyFatePending((CHARACTER)_Character)',
    'HasActiveStatus(_Character, "COS_CHAOS_FATE_PENDING", 1)',
    'DB_COS_ConfigMechanic(_Character, "Power", 1)',
    'NOT DB_COS_Power(_Character, _)'
)
foreach ($legacyClearCase in @(
    @($legacyFatePowerOffBlocks[0], $expectedLegacyFatePowerOffConditions, 'Power关闭'),
    @($legacyFateMissingConfigBlocks[0], $expectedLegacyFateMissingConfigConditions, '配置缺失'),
    @($legacyFateMissingPowerBlocks[0], $expectedLegacyFateMissingPowerConditions, '数值缺失')
)) {
    Require (((Get-MechanicsConditions $legacyClearCase[0]) -join "`n") -ceq (@($legacyClearCase[1]) -join "`n") -and `
        ((Get-MechanicsThenActions $legacyClearCase[0]) -join "`n") -ceq ($expectedLegacyFateClearAction -join "`n")) `
        "旧主动命运改签在$($legacyClearCase[2])时只能清理待触发状态，不得赠送资源"
}
$mechanicsIfBlocks = @([regex]::Matches($mechanicsGoal.Replace("`r`n", "`n"), '(?ms)^IF$.*?(?=^IF$|^PROC$|\z)') | ForEach-Object { $_.Value })
$fateArmBlocks = @($mechanicsIfBlocks | Where-Object {
    $_.Contains('UsingSpell(_Character, _, _, _, _StoryActionID)') -and $_.Contains('COS_FateRevision')
})
$expectedFateArmConditions = @(
    'UsingSpell(_Character, _, _, _, _StoryActionID)',
    'DB_COS_Character((CHARACTER)_Character)',
    'DB_COS_ConfigMechanic((CHARACTER)_Character, "Fate", 1)',
    'HasPassive(_Character, "COS_FateRevision", 1)',
    'HasActiveStatus(_Character, "COS_CHAOS_FATE_ENABLED", 1)'
)
$expectedFateArmActions = @(
    'PROC_COS_ClearFateAction((CHARACTER)_Character);',
    'DB_COS_FateAction((CHARACTER)_Character, _StoryActionID);'
)
Require ($fateArmBlocks.Count -eq 1) '命运改签必须只有一个攻击行动记录入口'
Require (((Get-MechanicsConditions $fateArmBlocks[0]) -join "`n") -ceq ($expectedFateArmConditions -join "`n") -and `
    ((Get-MechanicsThenActions $fateArmBlocks[0]) -join "`n") -ceq ($expectedFateArmActions -join "`n")) `
    '命运改签开启后必须用本次攻击的 StoryActionID 建立唯一待处理记录'
$dualityAttackBlocks = @($mechanicsIfBlocks | Where-Object {
    $_.Contains('AttackedBy(') -and
    $_.Contains('DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Duality", 1)')
})
Require ($dualityAttackBlocks.Count -eq 6) '两仪入口必须严格包含 Fate 关闭、状态关闭、未记录、禁用资源、资源为0和命运改签六个互斥分支'
$fateDisabledBlocks = @($dualityAttackBlocks | Where-Object { @(Get-MechanicsConditions $_) -contains 'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Fate", 0)' })
$fateOffBlocks = @($dualityAttackBlocks | Where-Object { @(Get-MechanicsConditions $_) -contains 'HasActiveStatus(_AttackOwner, "COS_CHAOS_FATE_ENABLED", 0)' })
$fateUnarmedBlocks = @($dualityAttackBlocks | Where-Object { @(Get-MechanicsConditions $_) -contains 'NOT DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)' })
$fatePowerDisabledBlocks = @($dualityAttackBlocks | Where-Object { @(Get-MechanicsConditions $_) -contains 'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Power", 0)' })
$fatePowerZeroBlocks = @($dualityAttackBlocks | Where-Object { @(Get-MechanicsConditions $_) -contains 'DB_COS_Power((CHARACTER)_AttackOwner, 0)' })
$fateDualityBlock = @($dualityAttackBlocks | Where-Object { @(Get-MechanicsConditions $_) -contains 'DB_COS_Power((CHARACTER)_AttackOwner, _OldPower)' })
Require ($fateDisabledBlocks.Count -eq 1 -and $fateOffBlocks.Count -eq 1 -and $fateUnarmedBlocks.Count -eq 1 -and `
    $fatePowerDisabledBlocks.Count -eq 1 -and $fatePowerZeroBlocks.Count -eq 1 -and `
    $fateDualityBlock.Count -eq 1) `
    '两仪六个攻击分支必须各自唯一且可明确分类'
$dualityCommonConditions = @(
    'AttackedBy(_Target, _AttackOwner, _Attacker, _, _Damage, _, _StoryActionID)',
    '_AttackOwner == _Attacker',
    'DB_COS_Character((CHARACTER)_AttackOwner)',
    'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Duality", 1)'
)
$dualityFateEnabledConditions = @($dualityCommonConditions + @(
    'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Fate", 1)',
    'HasPassive(_AttackOwner, "COS_ChaosDuality", 1)'
))
$expectedFateDisabledConditions = @($dualityCommonConditions + @(
    'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Fate", 0)',
    'HasPassive(_AttackOwner, "COS_ChaosDuality", 1)',
    'IsCharacter(_Target, 1)', '_Damage > 0', 'Random(100, _DualityRoll)'
))
$expectedFateOffConditions = @($dualityCommonConditions + @(
    'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Fate", 1)',
    'HasPassive(_AttackOwner, "COS_ChaosDuality", 1)',
    'HasActiveStatus(_AttackOwner, "COS_CHAOS_FATE_ENABLED", 0)',
    'IsCharacter(_Target, 1)', '_Damage > 0', 'Random(100, _DualityRoll)'
))
$expectedFateUnarmedConditions = @($dualityFateEnabledConditions + @(
    'HasActiveStatus(_AttackOwner, "COS_CHAOS_FATE_ENABLED", 1)',
    'NOT DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)',
    'IsCharacter(_Target, 1)', '_Damage > 0', 'Random(100, _DualityRoll)'
))
$expectedFatePowerDisabledConditions = @($dualityFateEnabledConditions + @(
    'HasActiveStatus(_AttackOwner, "COS_CHAOS_FATE_ENABLED", 1)',
    'DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)',
    'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Power", 0)',
    'IsCharacter(_Target, 1)', '_Damage > 0', 'Random(100, _DualityRoll)'
))
$expectedFatePowerZeroConditions = @($dualityFateEnabledConditions + @(
    'HasActiveStatus(_AttackOwner, "COS_CHAOS_FATE_ENABLED", 1)',
    'DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)',
    'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Power", 1)',
    'DB_COS_Power((CHARACTER)_AttackOwner, 0)',
    'IsCharacter(_Target, 1)', '_Damage > 0', 'Random(100, _DualityRoll)'
))
$expectedFateDualityConditions = @($dualityFateEnabledConditions + @(
    'HasPassive(_AttackOwner, "COS_FateRevision", 1)',
    'HasActiveStatus(_AttackOwner, "COS_CHAOS_FATE_ENABLED", 1)',
    'DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)',
    'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Power", 1)',
    'DB_COS_Power((CHARACTER)_AttackOwner, _OldPower)',
    '_OldPower >= 1', 'IntegerSubtract(_OldPower, 1, _NewPower)',
    'IsCharacter(_Target, 1)', '_Damage > 0', 'GetLevel(_AttackOwner, _Level)',
    'IntegerMin(_Level, 30, _CappedLevel)',
    'DB_COS_FateRolls(_MinimumLevel, _MaximumLevel, _RollCount)',
    '_CappedLevel >= _MinimumLevel', '_CappedLevel < _MaximumLevel',
    'Random(100, _FirstDualityRoll)', 'IntegerSubtract(_RollCount, 1, _RemainingRolls)'
))
$expectedNormalDualityActions = @('PROC_COS_ResolveDuality((CHARACTER)_AttackOwner, (CHARACTER)_Target, _Damage, _DualityRoll);')
$expectedClearedNormalDualityActions = @(
    'NOT DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID);',
    'PROC_COS_ResolveDuality((CHARACTER)_AttackOwner, (CHARACTER)_Target, _Damage, _DualityRoll);'
)
Require (((Get-MechanicsConditions $fateDisabledBlocks[0]) -join "`n") -ceq ($expectedFateDisabledConditions -join "`n") -and `
    ((Get-MechanicsThenActions $fateDisabledBlocks[0]) -join "`n") -ceq ((@('PROC_COS_ClearFateAction((CHARACTER)_AttackOwner);') + $expectedNormalDualityActions) -join "`n")) `
    'Fate 配置关闭时必须不依赖 FATE_ENABLED、清除旧记录并执行一次普通两仪'
Require (((Get-MechanicsConditions $fateOffBlocks[0]) -join "`n") -ceq ($expectedFateOffConditions -join "`n") -and `
    ((Get-MechanicsThenActions $fateOffBlocks[0]) -join "`n") -ceq ((@('PROC_COS_ClearFateAction((CHARACTER)_AttackOwner);') + $expectedNormalDualityActions) -join "`n")) `
    'Fate 配置开启但命运改签状态关闭时必须清除旧记录并执行一次普通两仪'
Require (((Get-MechanicsConditions $fateUnarmedBlocks[0]) -join "`n") -ceq ($expectedFateUnarmedConditions -join "`n") -and `
    ((Get-MechanicsThenActions $fateUnarmedBlocks[0]) -join "`n") -ceq ($expectedNormalDualityActions -join "`n")) `
    '命运改签未记录本次攻击时必须执行一次普通两仪且不得消费资源'
Require (((Get-MechanicsConditions $fatePowerDisabledBlocks[0]) -join "`n") -ceq ($expectedFatePowerDisabledConditions -join "`n") -and `
    ((Get-MechanicsThenActions $fatePowerDisabledBlocks[0]) -join "`n") -ceq ($expectedClearedNormalDualityActions -join "`n")) `
    '混沌之力机制关闭时必须清除本次记录并执行一次普通两仪'
Require (((Get-MechanicsConditions $fatePowerZeroBlocks[0]) -join "`n") -ceq ($expectedFatePowerZeroConditions -join "`n") -and `
    ((Get-MechanicsThenActions $fatePowerZeroBlocks[0]) -join "`n") -ceq ($expectedClearedNormalDualityActions -join "`n")) `
    '混沌之力为0时必须清除本次记录并执行一次普通两仪'
$fateDualityActions = @(Get-MechanicsThenActions $fateDualityBlock[0])
$expectedFateDualityActions = @(
    'NOT DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID);',
    'NOT DB_COS_Power((CHARACTER)_AttackOwner, _OldPower);',
    'DB_COS_Power((CHARACTER)_AttackOwner, _NewPower);',
    'PROC_COS_SyncPowerDisplay((CHARACTER)_AttackOwner, _NewPower);',
    'PROC_COS_ContinueFateDuality((CHARACTER)_AttackOwner, (CHARACTER)_Target, _Damage, _RemainingRolls, _FirstDualityRoll);'
)
Require (((Get-MechanicsConditions $fateDualityBlock[0]) -join "`n") -ceq ($expectedFateDualityConditions -join "`n") -and `
    (($fateDualityActions -join "`n") -ceq ($expectedFateDualityActions -join "`n"))) `
    '命运改签必须只在同一攻击命中时消耗1点、移除本次记录并开始最优两仪判定'
$actualFateActionLines = @($mechanicsGoal.Replace("`r`n", "`n") -split "`n" | `
    ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^(?:NOT )?DB_COS_FateAction\(' } | Sort-Object)
$expectedFateActionLines = @(
    'DB_COS_FateAction(_Character, _StoryActionID)',
    'NOT DB_COS_FateAction(_Character, _StoryActionID);',
    'DB_COS_FateAction((CHARACTER)_Character, _StoryActionID);',
    'NOT DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)',
    'DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)',
    'DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)',
    'DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)',
    'NOT DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID);',
    'NOT DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID);',
    'NOT DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID);'
) | Sort-Object
Require (($actualFateActionLines -join "`n") -ceq ($expectedFateActionLines -join "`n")) `
    '命运改签行动记录的全部读写位置必须严格受限于清理、建立和六个结算分支'
Require (-not $mechanicsGoal.Contains('PROC_COS_BeginWoundTrials(_Character, _Damage, _PowerEligible, _RollCount);')) `
    '命运改签改为攻击触发后不得再重投受击轮盘'
Require ($mechanicsGoal.Contains('Random(100, _FirstDualityRoll)') -and `
    $mechanicsGoal.Contains('PROC_COS_ContinueFateDuality') -and `
    $mechanicsGoal.Contains('IntegerMax(_BestRoll, _NextRoll, _NextBestRoll)')) `
    '命运改签必须为两仪递归判定并保留更高的倍率结果'
$expectedFateTiers = @(
    'DB_COS_FateRolls(1, 5, 2);',
    'DB_COS_FateRolls(5, 9, 3);',
    'DB_COS_FateRolls(9, 13, 4);',
    'DB_COS_FateRolls(13, 17, 5);',
    'DB_COS_FateRolls(17, 21, 6);',
    'DB_COS_FateRolls(21, 25, 7);',
    'DB_COS_FateRolls(25, 100, 8);'
)
foreach ($fateTier in $expectedFateTiers) {
    Require ($mechanicsGoal.Contains($fateTier)) "命运改签等级判定次数缺少: $fateTier"
}
foreach ($powerChance in @(
    'DB_COS_LostChance(1, 15);',
    'DB_COS_LostChance(6, 100);',
    'DB_COS_KillChance(1, 10, 5);',
    'DB_COS_KillChance(31, 39, 35);',
    'DB_COS_KillChance(40, 40, 100);'
)) {
    Require ($mechanicsGoal.Contains($powerChance)) "混沌之力降低获取难度缺少: $powerChance"
}
Require (-not $mechanicsGoal.Contains('PROC_COS_ApplyPowerStacks')) `
    '混沌之力不得继续使用不可见数字的永久状态递归叠层'
Require ($featuresText.Contains('data "StatsFunctorContext" "OnCreate;OnShortRest"') -and `
    $featuresText.Contains('data "StatsFunctors" "RestoreResource(COS_ChaosAllInUse,100%,0)"')) `
    '混沌孤注必须在创建和短休时恢复当前等级的全部充能'
foreach ($allInPenalty in @('RollBonus(Attack,-8)', 'RollBonus(Attack,-6)', 'RollBonus(Attack,-4)')) {
    Require ($featuresText.Contains($allInPenalty)) "混沌孤注缺少命中惩罚: $allInPenalty"
}
foreach ($allInEntry in @('COS_CHAOS_ALLIN_L1', 'COS_CHAOS_ALLIN_L3', 'COS_CHAOS_ALLIN_L7')) {
    $allInPattern = 'new entry "{0}"[\s\S]*?(?=\r?\nnew entry|\z)' -f [regex]::Escape($allInEntry)
    $allInBlock = [regex]::Match($featuresText, $allInPattern).Value
    Require (-not $allInBlock.Contains('CriticalHit(')) "混沌孤注不得强制命中或暴击: $allInEntry"
}
$genesisBlock = [regex]::Match($featuresText, 'new entry "COS_CHAOS_GENESIS"[\s\S]*?(?=\r?\nnew entry|\z)').Value
Require (-not $genesisBlock.Contains('ActionResource(ActionPoint')) `
    '混沌开天辟地状态不得额外增加行动点'
Require ($featuresText.Contains('RestoreResource(ActionPoint,100%,0)')) `
    '混沌开天辟地施放时必须保留行动点恢复'
$coreMechanicKeys = @('Power', 'Wound', 'KillPower', 'Duality', 'AllIn', 'Fate', 'Genesis', 'Strike', 'Mastery')
$coreMechanicMirrors = @(
    'COS_CFG_MECH_POWER', 'COS_CFG_MECH_WOUND', 'COS_CFG_MECH_KILLPOWER',
    'COS_CFG_MECH_DUALITY', 'COS_CFG_MECH_ALLIN', 'COS_CFG_MECH_FATE',
    'COS_CFG_MECH_GENESIS', 'COS_CFG_MECH_STRIKE', 'COS_CFG_MECH_MASTERY'
)
function Get-StoryBlocks([string]$Story, [string]$Kind, [string]$Name) {
    $Story = Normalize-LineEndings $Story
    $pattern = '(?ms)^' + [regex]::Escape($Kind) + '\n' + [regex]::Escape($Name) +
        '\([^\n]*\)\n.*?(?=^(?:PROC|IF|EXITSECTION)\n|\z)'
    return @([regex]::Matches($Story, $pattern) | ForEach-Object { $_.Value })
}
function Get-AllStoryBlocks([string]$Story) {
    $Story = Normalize-LineEndings $Story
    return @([regex]::Matches($Story,
        '(?ms)^(?:PROC|IF)\n.*?(?=^(?:PROC|IF|EXITSECTION)\n|\z)') | ForEach-Object { $_.Value })
}
function Require-StoryGate([string]$Block, [string]$Gate, [string]$Message) {
    $normalizedBlock = Normalize-LineEndings $Block
    $thenIndex = $normalizedBlock.IndexOf("`nTHEN`n", [StringComparison]::Ordinal)
    Require ($thenIndex -ge 0) 'Story block 缺少 THEN 区'
    $conditions = $normalizedBlock.Substring(0, $thenIndex)
    Require ($conditions -match ('(?m)^' + $Gate + '$')) $Message
}
function Get-StoryThen([string]$Block) {
    $then = [regex]::Match($Block, '(?ms)^THEN\n(?<Actions>.*)$')
    Require $then.Success 'Story block 缺少 THEN 区'
    return $then.Groups['Actions'].Value
}

$storyBlockSources = [ordered]@{
    Base = $goal; Reward = $rewardGoal; Mechanics = $mechanicsGoal; Mastery = $masteryGoal; Config = $configGoal
}
foreach ($storyBlockSource in $storyBlockSources.GetEnumerator()) {
    Require ((Get-AllStoryBlocks $storyBlockSource.Value).Count -gt 0) `
        "Story block 解析不得为空: $($storyBlockSource.Key)"
}

$storyGateProbe = "IF`nDB_COS_ConfigMechanic((CHARACTER)_Character, ""Genesis"", 1)`nTHEN`nPROC_COS_Test(_Character);"
Require-StoryGate $storyGateProbe 'DB_COS_ConfigMechanic\(\(CHARACTER\)_Character, "Genesis", 1\)' `
    'Require-StoryGate 必须接受 THEN 前的完整条件行'
$storyGateThenOnlyProbe = "IF`nDB_COS_Character((CHARACTER)_Character)`nTHEN`nDB_COS_ConfigMechanic((CHARACTER)_Character, ""Genesis"", 1);"
$storyGateThenOnlyRejected = $false
try {
    Require-StoryGate $storyGateThenOnlyProbe 'DB_COS_ConfigMechanic\(\(CHARACTER\)_Character, "Genesis", 1\)' `
        'THEN 动作段中的同名门禁不得被接受'
} catch {
    $storyGateThenOnlyRejected = $true
}
Require $storyGateThenOnlyRejected 'Require-StoryGate 不得把 THEN 动作段误判为条件门禁'

$fateArmProbe = "IF`n" + ($expectedFateArmConditions -join "`nAND`n") + "`nTHEN`nPROC_COS_Test(_Character);"
Require (((Get-MechanicsConditions $fateArmProbe) -join "`n") -ceq ($expectedFateArmConditions -join "`n")) `
    '命运改签武装探针必须满足旧精确条件数组'
Require-StoryGate $fateArmProbe 'DB_COS_ConfigMechanic\(\(CHARACTER\)_Character, "Fate", 1\)' `
    '命运改签武装探针必须满足 _Character Fate=1 门禁'
$fateAttackProbe = "IF`n" + ($expectedFateUnarmedConditions -join "`nAND`n") + "`nTHEN`nPROC_COS_Test(_AttackOwner);"
Require (((Get-MechanicsConditions $fateAttackProbe) -join "`n") -ceq ($expectedFateUnarmedConditions -join "`n")) `
    '命运改签攻击探针必须满足旧精确条件数组'
Require-StoryGate $fateAttackProbe 'DB_COS_ConfigMechanic\(\(CHARACTER\)_AttackOwner, "Fate", 1\)' `
    '命运改签攻击探针必须满足 _AttackOwner Fate=1 门禁'

$expectedCoreMirrors = [ordered]@{
    Power = 'COS_CFG_MECH_POWER'; Wound = 'COS_CFG_MECH_WOUND'; KillPower = 'COS_CFG_MECH_KILLPOWER'
    Duality = 'COS_CFG_MECH_DUALITY'; AllIn = 'COS_CFG_MECH_ALLIN'; Fate = 'COS_CFG_MECH_FATE'
    Genesis = 'COS_CFG_MECH_GENESIS'; Strike = 'COS_CFG_MECH_STRIKE'; Mastery = 'COS_CFG_MECH_MASTERY'
}
$expectedRacialMirrors = [ordered]@{
    DeepGnome_StoneCamouflage = 'COS_CFG_RACE_DEEPGNOME_STONE'
    Drow_DrowWeaponTraining = 'COS_CFG_RACE_DROW_WEAPON'
    Duergar_DuergarResilience = 'COS_CFG_RACE_DUERGAR_RESILIENCE'
    Dwarf_DwarvenCombatTraining = 'COS_CFG_RACE_DWARF_WEAPON'
    Dwarf_DwarvenResilience = 'COS_CFG_RACE_DWARF_RESILIENCE'
    Elf_WeaponTraining = 'COS_CFG_RACE_ELF_WEAPON'
    FeyAncestry = 'COS_CFG_RACE_FEY_ANCESTRY'
    Gith_MartialProdigy = 'COS_CFG_RACE_GITH_MARTIAL'
    Gnome_Cunning = 'COS_CFG_RACE_GNOME_CUNNING'
    Halfling_Brave = 'COS_CFG_RACE_HALFLING_BRAVE'
    Halfling_LightfootStealth = 'COS_CFG_RACE_HALFLING_LIGHTFOOT'
    Halfling_Lucky = 'COS_CFG_RACE_HALFLING_LUCKY'
    Halfling_StoutResilience = 'COS_CFG_RACE_HALFLING_STOUT'
    HumanMilitia = 'COS_CFG_RACE_HUMAN_MILITIA'
    MountainDwarf_DwarvenArmorTraining = 'COS_CFG_RACE_MOUNTAIN_DWARF_ARMOR'
    RelentlessEndurance = 'COS_CFG_RACE_RELENTLESS'
    RockGnome_ArtificersLore = 'COS_CFG_RACE_ROCK_GNOME_LORE'
    SavageAttacks = 'COS_CFG_RACE_SAVAGE_ATTACKS'
    SuperiorDarkvision = 'COS_CFG_RACE_SUPERIOR_DARKVISION'
    Tiefling_HellishResistance = 'COS_CFG_RACE_TIEFLING_RESISTANCE'
}
$defaultMatches = @([regex]::Matches($configGoal,
    '(?m)^DB_COS_ConfigMechanicDefault\("(?<Key>[^"]+)", (?<Value>\d+)\);$'))
$defaultPairs = @($defaultMatches | ForEach-Object { "$($_.Groups['Key'].Value)=$($_.Groups['Value'].Value)" })
$expectedDefaultPairs = @($coreMechanicKeys | ForEach-Object { "$_=1" })
Require ($defaultMatches.Count -eq 9 -and @($defaultPairs | Sort-Object -Unique).Count -eq 9 -and
    -not (Compare-Object ($expectedDefaultPairs | Sort-Object) ($defaultPairs | Sort-Object))) `
    '核心设置默认值必须恰好是九个唯一键且全部为1'
foreach ($key in $coreMechanicKeys) {
    Require (-not $configGoal.Contains("DB_COS_ConfigMechanic(_Character, `"$key`", 1);")) `
        "核心设置不得绕过 EnsureMechanics 重复写入显式默认值: $key"
}

$mirrorMatches = @([regex]::Matches($configGoal,
    '(?m)^DB_COS_ConfigMechanicMirror\("(?<Key>[^"]+)", "(?<Mirror>COS_CFG_MECH_[A-Z]+)"\);$'))
$mirrorPairs = @($mirrorMatches | ForEach-Object { "$($_.Groups['Key'].Value)=$($_.Groups['Mirror'].Value)" })
$expectedMirrorPairs = @($expectedCoreMirrors.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" })
Require ($mirrorMatches.Count -eq 9 -and @($mirrorPairs | Sort-Object -Unique).Count -eq 9 -and
    -not (Compare-Object ($expectedMirrorPairs | Sort-Object) ($mirrorPairs | Sort-Object))) `
    '核心设置镜像必须恰好九个唯一键并一一映射到九个回显被动'

$expectedCoreEventMappings = [ordered]@{
    '7f818c10-3f23-49f8-838a-d161c57bb35d' = 'Power'
    '0574b4b8-549a-4b39-b810-6890c68642b1' = 'Wound'
    '71abdeef-69d2-4385-8885-4f9ebbd829ca' = 'KillPower'
    'aa88abcb-5f2e-452c-bdce-3ca6176db1e0' = 'Duality'
    '2dd4ef80-1686-4989-8773-3cf6f12b9a36' = 'AllIn'
    'aff82c28-d71a-4dad-837d-d41d8519051a' = 'Fate'
    '063cc1a5-fe65-43e5-8531-d6974a7b1dce' = 'Genesis'
    '78baf203-f60c-4dac-99ea-a7f5d1339d71' = 'Strike'
    '146d28dc-aa94-40e8-9bad-91b069055526' = 'Mastery'
}
$eventMappingMatches = @([regex]::Matches($configGoal,
    '(?m)^DB_COS_ConfigMechanicEvent\(\(TUTORIALEVENT\)[A-Z0-9_]+_(?<Event>[0-9a-f-]{36}), "(?<Key>[^"]+)"\);$'))
$eventMappingPairs = @($eventMappingMatches | ForEach-Object { "$($_.Groups['Event'].Value)=$($_.Groups['Key'].Value)" })
$expectedEventMappingPairs = @($expectedCoreEventMappings.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" })
Require ($eventMappingMatches.Count -eq 9 -and @($eventMappingPairs | Sort-Object -Unique).Count -eq 9 -and
    -not (Compare-Object ($expectedEventMappingPairs | Sort-Object) ($eventMappingPairs | Sort-Object))) `
    '核心设置必须把九个固定 TutorialEvent UUID 唯一映射到九个机制键'
Require ([regex]::Matches($configGoal,
    '(?m)^DB_COS_ConfigResetCoreEvent\(\(TUTORIALEVENT\)COS_CFG_RESET_CORE_08c8d67a-ace5-4830-8c2b-38b8c92bb470\);$').Count -eq 1) `
    '恢复默认必须只注册一个固定 TutorialEvent UUID'
Require ([regex]::Matches($configGoal,
    '(?m)^DB_COS_Config(?:MechanicEvent|UiOpenedEvent|ResetCoreEvent|LifeStepEvent|LifeResetEvent|RacialEvent|RacialBulkEvent)\(\(TUTORIALEVENT\)[A-Z0-9_]+_[0-9a-f-]{36}(?:, (?:"[^"]+"|-?\d+))?\);$').Count -eq 36) `
    '全部36个原生设置事件必须按游戏 Story 头声明为 TUTORIALEVENT，不能使用普通 STRING'

Require ([regex]::Matches($configGoal, '(?m)^DB_COS_ConfigLifeDefault\(5\);$').Count -eq 1) `
    '生活熟练项默认值必须唯一且为5'
$lifeMapMatches = @([regex]::Matches($configGoal,
    '(?m)^DB_COS_ConfigLifeBonusPassive\((?<Value>\d+), "COS_CFG_LIFE_SKILL_BONUS_(?<Suffix>\d{2})"\);$'))
Require ($lifeMapMatches.Count -eq 20) '生活熟练项Story映射必须恰好包含1至20'
foreach ($lifeMap in $lifeMapMatches) {
    Require ([int]$lifeMap.Groups['Value'].Value -eq [int]$lifeMap.Groups['Suffix'].Value) `
        '生活熟练项Story映射的数值和被动后缀必须一致'
}
$lifeStepMatches = @([regex]::Matches($configGoal,
    '(?m)^DB_COS_ConfigLifeStepEvent\(\(TUTORIALEVENT\)[A-Z0-9_]+_[0-9a-f-]{36}, (?<Delta>-?\d+)\);$'))
Require ($lifeStepMatches.Count -eq 2 -and
    -not (Compare-Object @(-1, 1) @($lifeStepMatches | ForEach-Object { [int]$_.Groups['Delta'].Value } | Sort-Object))) `
    '生活熟练项只能注册步长为-1和+1的两个固定事件'
Require ([regex]::Matches($configGoal,
    '(?m)^DB_COS_ConfigLifeResetEvent\(\(TUTORIALEVENT\)COS_CFG_LIFE_RESET_563ba5fe-c808-4a2f-80b5-a1b4feb54649\);$').Count -eq 1) `
    '生活熟练项必须注册唯一的恢复默认事件'

$racialDefaultMatches = @([regex]::Matches($configGoal,
    '(?m)^DB_COS_ConfigRacialDefault\("(?<Passive>[^"]+)", (?<Value>\d+)\);$'))
$racialDefaultPassives = @($racialDefaultMatches | ForEach-Object { $_.Groups['Passive'].Value } | Sort-Object)
Require ($racialDefaultMatches.Count -eq 20 -and
    @($racialDefaultPassives | Sort-Object -Unique).Count -eq 20 -and
    @($racialDefaultMatches | Where-Object { $_.Groups['Value'].Value -ne '0' }).Count -eq 0 -and
    -not (Compare-Object ($expectedRacialMirrors.Keys | Sort-Object) $racialDefaultPassives)) `
    '20个去重官方种族被动必须全部默认关闭'
$racialMirrorMatches = @([regex]::Matches($configGoal,
    '(?m)^DB_COS_ConfigRacialMirror\("(?<Passive>[^"]+)", "(?<Mirror>COS_CFG_RACE_[A-Z0-9_]+)"\);$'))
$racialMirrorPairs = @($racialMirrorMatches | ForEach-Object {
    "$($_.Groups['Passive'].Value)=$($_.Groups['Mirror'].Value)"
})
$expectedRacialMirrorPairs = @($expectedRacialMirrors.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" })
Require ($racialMirrorMatches.Count -eq 20 -and
    -not (Compare-Object ($expectedRacialMirrorPairs | Sort-Object) ($racialMirrorPairs | Sort-Object))) `
    '20个官方种族被动必须唯一映射到20个UI回显被动'
$racialEventMatches = @([regex]::Matches($configGoal,
    '(?m)^DB_COS_ConfigRacialEvent\(\(TUTORIALEVENT\)[A-Z0-9_]+_[0-9a-f-]{36}, "(?<Passive>[^"]+)"\);$'))
$racialEventPassives = @($racialEventMatches | ForEach-Object { $_.Groups['Passive'].Value } | Sort-Object)
Require ($racialEventMatches.Count -eq 20 -and
    -not (Compare-Object ($expectedRacialMirrors.Keys | Sort-Object) $racialEventPassives)) `
    '20个官方种族被动必须各自注册唯一固定事件'
Require ([regex]::Matches($configGoal,
    '(?m)^DB_COS_ConfigRacialBulkEvent\(\(TUTORIALEVENT\)[A-Z0-9_]+_[0-9a-f-]{36}, [01]\);$').Count -eq 2) `
    '种族被动必须只注册全选和全取消两个批量事件'

$configPassiveEntries = @([regex]::Matches($configStats, '(?m)^new entry "([^"]+)"$') |
    ForEach-Object { $_.Groups[1].Value })
$expectedConfigPassiveEntries = @($coreMechanicMirrors + $expectedRacialMirrors.Values)
Require ($configPassiveEntries.Count -eq 29 -and @($configPassiveEntries | Sort-Object -Unique).Count -eq 29 -and
    -not (Compare-Object ($expectedConfigPassiveEntries | Sort-Object) ($configPassiveEntries | Sort-Object))) `
    'ChaosConfig.txt 必须且只能定义九个核心机制与20个种族被动回显'
foreach ($mirror in $coreMechanicMirrors) {
    $mirrorBlock = [regex]::Match($configStats,
        '(?ms)^new entry "' + [regex]::Escape($mirror) + '".*?(?=^new entry |\z)').Value
    $displayNameMatch = [regex]::Match($mirrorBlock,
        '(?m)^data "DisplayName" "(?<Handle>h[^";]+)(?:;\d+)?"$')
    Require ($displayNameMatch.Success -and
        $displayNameMatch.Groups['Handle'].Value -ceq [string]$configMirrorDisplayHandles[$mirror]) `
        "核心设置回显被动必须使用只解析为内部标识的专用 DisplayName handle: $mirror"
    foreach ($requiredField in @('DisplayName', 'Description', 'Icon')) {
        Require ($mirrorBlock -match '(?m)^data "' + $requiredField + '" "[^"]+"$') `
            "核心设置回显被动必须提供 ${requiredField}: $mirror"
    }
    Require (-not $mirrorBlock.Contains('data "Properties" "IsHidden"')) `
        "核心设置回显被动必须能被 Stats.Passives 枚举，不能使用 IsHidden: $mirror"
}
foreach ($mirror in $expectedRacialMirrors.Values) {
    $mirrorBlock = [regex]::Match($configStats,
        '(?ms)^new entry "' + [regex]::Escape($mirror) + '".*?(?=^new entry |\z)').Value
    Require (-not $mirrorBlock.Contains('data "Properties" "IsHidden"') -and
        -not $mirrorBlock.Contains('data "Boosts" ')) `
        "种族被动回显必须可枚举且不得包含玩法Boost: $mirror"
}

$configAddMirrorBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigAddEnabledMechanicMirrors')
Require ($configAddMirrorBlocks.Count -eq 1 -and
    $configAddMirrorBlocks[0] -match 'DB_COS_ConfigMechanic\(_Character, _Key, 1\)' -and
    $configAddMirrorBlocks[0] -match 'DB_COS_ConfigMechanicMirror\(_Key, _Passive\)' -and
    -not $configAddMirrorBlocks[0].Contains('HasPassive(_Character, _Passive,') -and
    (Get-StoryThen $configAddMirrorBlocks[0]) -match '(?m)^AddPassive\(_Character, _Passive\);$') `
    '核心设置镜像同步必须为值为1的项目无条件重发回显被动，以刷新原生界面数据源'
$configRemoveMirrorBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigRemoveDisabledMechanicMirrors')
Require ($configRemoveMirrorBlocks.Count -eq 1 -and
    $configRemoveMirrorBlocks[0] -match 'DB_COS_ConfigMechanic\(_Character, _Key, 0\)' -and
    $configRemoveMirrorBlocks[0] -match 'DB_COS_ConfigMechanicMirror\(_Key, _Passive\)' -and
    -not $configRemoveMirrorBlocks[0].Contains('HasPassive(_Character, _Passive,') -and
    (Get-StoryThen $configRemoveMirrorBlocks[0]) -match '(?m)^RemovePassive\(_Character, _Passive\);$') `
    '核心设置镜像同步必须为值为0的项目无条件重发删除，以刷新原生界面数据源'
$configMirrorSyncBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigSyncMechanicMirrors')
Require ($configMirrorSyncBlocks.Count -eq 1 -and
    ((Get-StoryThen $configMirrorSyncBlocks[0]) -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join "`n" -ceq
        "PROC_COS_ConfigAddEnabledMechanicMirrors(_Character);`nPROC_COS_ConfigRemoveDisabledMechanicMirrors(_Character);") `
    '核心设置镜像同步必须按当前值分别补开启项、删关闭项，禁止先清空再重加'
Require (-not $configGoal.Contains('PROC_COS_ConfigRemoveMechanicMirrors') -and
    -not $configGoal.Contains('PROC_COS_ConfigAddMechanicMirrors')) `
    '核心设置不得保留会在同一同步周期清空全部回显的旧过程'

$configEnsureBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigEnsureMechanics')
Require ($configEnsureBlocks.Count -eq 1) '核心设置必须且只能定义一个 PROC_COS_ConfigEnsureMechanics'
$configEnsureBlock = $configEnsureBlocks[0]
Require ($configEnsureBlock -match 'DB_COS_ConfigMechanicDefault\(_Key, _Default\)' -and
    $configEnsureBlock -match 'NOT DB_COS_ConfigMechanic\(_Character, _Key, _\)' -and
    $configEnsureBlock -match 'THEN\nDB_COS_ConfigMechanic\(_Character, _Key, _Default\);') `
    '核心设置初始化必须在同一 EnsureMechanics PROC 内由默认表只补缺失值'
$configDefaultWriteBlocks = @(Get-AllStoryBlocks $configGoal | Where-Object {
    (Get-StoryThen $_) -match '(?m)^DB_COS_ConfigMechanic\(_Character, _Key, _Default\);$'
})
$configResetCoreBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigResetCore')
Require ($configDefaultWriteBlocks.Count -eq 2 -and $configResetCoreBlocks.Count -eq 1 -and
    $configDefaultWriteBlocks -contains $configEnsureBlock -and
    $configDefaultWriteBlocks -contains $configResetCoreBlocks[0]) `
    '核心设置 _Default 写入必须且只能来自 EnsureMechanics 与 ConfigResetCore'

$configIfBlocks = @([regex]::Matches($configGoal,
    '(?ms)^IF\n.*?(?=^IF\n|^PROC\n|^EXITSECTION\n|\z)') | ForEach-Object { $_.Value })
$mechanicToggleBlocks = @($configIfBlocks | Where-Object {
    $_.Contains('TutorialEvent(_Character, _Event)') -and $_.Contains('PROC_COS_ConfigToggleMechanic')
})
$resetBlocks = @($configIfBlocks | Where-Object {
    $_.Contains('TutorialEvent(_Character, _Event)') -and $_.Contains('PROC_COS_ConfigResetCore')
})
$configProcedureBlocks = @([regex]::Matches($configGoal,
    '(?ms)^PROC\n[A-Za-z0-9_]+\([^\n]*\)\n.*?(?=^(?:PROC|IF|EXITSECTION)\n|\z)') | ForEach-Object { $_.Value })
$configAllBlocks = @($configIfBlocks + $configProcedureBlocks)
$configSyncCharacterBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigSyncCharacter')
Require ($configSyncCharacterBlocks.Count -eq 1) '核心设置必须且只能定义一个 PROC_COS_ConfigSyncCharacter'
$configSyncCharacterBlock = $configSyncCharacterBlocks[0]
foreach ($syncAction in @(
    'PROC_COS_ConfigEnsureMechanics(_Character);',
    'PROC_COS_ConfigEnsureLifeSkill(_Character);',
    'PROC_COS_ConfigEnsureRacialPassives(_Character);',
    'PROC_COS_ConfigEnableEvents(_Character);',
    'PROC_COS_AccrueMastery(_Character);',
    'PROC_COS_SyncMastery(_Character);',
    'PROC_COS_ConfigSyncMechanicMirrors(_Character);',
    'PROC_COS_ConfigSyncLifeSkill(_Character);',
    'PROC_COS_ConfigSyncRacialPassives(_Character);'
)) {
    Require ((Get-StoryThen $configSyncCharacterBlock).Contains($syncAction)) `
        "ConfigSyncCharacter 必须同块调用: $syncAction"
}
$configEnsureCallBlocks = @($configAllBlocks | Where-Object {
    (Get-StoryThen $_).Contains('PROC_COS_ConfigEnsureMechanics(_Character);')
})
Require ($configEnsureCallBlocks.Count -eq 1 -and $configEnsureCallBlocks[0] -eq $configSyncCharacterBlock) `
    'Config Goal 内 EnsureMechanics 只能由 ConfigSyncCharacter 调用'
$mechanicsAllBlocksForConfig = @(Get-AllStoryBlocks $mechanicsGoal)
$registerBlocks = @(Get-StoryBlocks $mechanicsGoal 'PROC' 'PROC_COS_Register')
$mechanicsEnsureCallBlocks = @($mechanicsAllBlocksForConfig | Where-Object {
    (Get-StoryThen $_).Contains('PROC_COS_ConfigEnsureMechanics(_Character);')
})
Require ($registerBlocks.Count -eq 1 -and $registerBlocks[0].Contains('HasPassive(_Character, "COS_ChaosOriginMarker", 1)') -and
    $mechanicsEnsureCallBlocks.Count -eq 1 -and $mechanicsEnsureCallBlocks[0] -eq $registerBlocks[0]) `
    'Config Goal 外 EnsureMechanics 只能由带 OriginMarker 注册链的 COS_ChaosMechanics Register 调用'
foreach ($otherGoal in @($goal, $masteryGoal, $rewardGoal)) {
    Require (-not (@(Get-AllStoryBlocks $otherGoal | Where-Object {
        (Get-StoryThen $_).Contains('PROC_COS_ConfigEnsureMechanics(_Character);')
    }).Count)) '除 COS_ChaosMechanics Register 外，其他 Goal 不得调用 EnsureMechanics'
}
$configMechanicWritePattern = '(?m)^(?:NOT )?DB_COS_ConfigMechanic\('
foreach ($configIfBlock in $configIfBlocks) {
    Require (-not ((Get-StoryThen $configIfBlock) -match $configMechanicWritePattern)) `
        'IF 的 THEN 区不得直接增加或删除 DB_COS_ConfigMechanic，必须调用受白名单约束的 PROC'
}
$configMechanicWriteProcedures = @(
    'PROC_COS_ConfigEnsureMechanics', 'PROC_COS_ConfigToggleMechanic', 'PROC_COS_ConfigResetCore'
)
foreach ($configProcedureBlock in $configProcedureBlocks) {
    $procedureName = [regex]::Match($configProcedureBlock, '(?m)^PROC\n(?<Name>[A-Za-z0-9_]+)\(').Groups['Name'].Value
    if ((Get-StoryThen $configProcedureBlock) -match $configMechanicWritePattern) {
        Require ($configMechanicWriteProcedures -contains $procedureName) `
            "只有白名单配置 PROC 可以写 DB_COS_ConfigMechanic: $procedureName"
    }
}
$configWriteProcedureCalls = @('PROC_COS_ConfigToggleMechanic', 'PROC_COS_ConfigResetCore')
foreach ($writeProcedure in $configWriteProcedureCalls) {
    $externalCallIfBlocks = @($configIfBlocks | Where-Object { $_.Contains($writeProcedure) })
    $expectedExternalBlock = if ($writeProcedure -eq 'PROC_COS_ConfigToggleMechanic') {
        $mechanicToggleBlocks[0]
    } else {
        $resetBlocks[0]
    }
    Require ($externalCallIfBlocks.Count -eq 1 -and $externalCallIfBlocks[0] -eq $expectedExternalBlock) `
        "$writeProcedure 的外部调用必须且只能来自对应 TutorialEvent IF 块"
}
$whitelistedProcedurePattern = '^(?:PROC_COS_ConfigEnsureMechanics|PROC_COS_ConfigToggleMechanic|PROC_COS_ConfigResetCore)$'
foreach ($configProcedureBlock in $configProcedureBlocks) {
    $procedureName = [regex]::Match($configProcedureBlock, '(?m)^PROC\n(?<Name>[A-Za-z0-9_]+)\(').Groups['Name'].Value
    $calledWriteProcedures = @([regex]::Matches((Get-StoryThen $configProcedureBlock),
        '(?m)^PROC_COS_Config(?:ToggleMechanic|ResetCore)\(') | ForEach-Object {
            $_.Value.Split('(')[0]
        })
    Require ($calledWriteProcedures.Count -eq 0 -or $procedureName -match $whitelistedProcedurePattern) `
        "只有白名单配置 PROC 可以互调写入过程: $procedureName"
}
foreach ($eventWriteBlock in $mechanicToggleBlocks) {
    Require ($eventWriteBlock.Contains('DB_COS_ConfigMechanicEvent(_Event, _Key)')) `
        '机制切换 TutorialEvent 写入必须通过固定事件映射，不得接受任意字符串键'
    foreach ($writeGate in @(
        'HasPassive(_Character, "COS_ChaosOriginMarker", 1)', 'IsControlled(_Character, 1)', 'IsInCombat(_Character, 0)'
    )) {
        Require ($eventWriteBlock.Contains($writeGate)) "TutorialEvent 配置写入缺少同块门禁: $writeGate"
    }
}
foreach ($eventWriteBlock in $resetBlocks) {
    Require ($eventWriteBlock.Contains('DB_COS_ConfigResetCoreEvent(_Event)')) `
        '恢复默认 TutorialEvent 写入必须通过固定事件映射，不得接受任意字符串键'
    foreach ($writeGate in @(
        'HasPassive(_Character, "COS_ChaosOriginMarker", 1)', 'IsControlled(_Character, 1)', 'IsInCombat(_Character, 0)'
    )) {
        Require ($eventWriteBlock.Contains($writeGate)) "恢复默认 TutorialEvent 写入缺少同块门禁: $writeGate"
    }
}
Require ($mechanicToggleBlocks.Count -eq 1 -and $resetBlocks.Count -eq 1) `
    '核心设置必须各有一个带完整门禁的机制切换和恢复默认 TutorialEvent 写入块'
$uiOpenedBlocks = @($configIfBlocks | Where-Object {
    $_.Contains('TutorialEvent(_Character, _Event)') -and $_.Contains('DB_COS_ConfigUiOpenedEvent(_Event)')
})
Require ([regex]::Matches($configGoal,
    '(?m)^DB_COS_ConfigUiOpenedEvent\(\(TUTORIALEVENT\)COS_CFG_UI_OPENED_65247962-a3b0-417d-9044-85e4aad38079\);$').Count -eq 1 -and
    $uiOpenedBlocks.Count -eq 1) 'UI_OPENED 必须只用固定 TutorialEvent 映射到一个读取入口'
$uiOpenedActions = @((Get-StoryThen $uiOpenedBlocks[0]).Replace("`r`n", "`n") -split "`n" |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^PROC_' })
Require ($uiOpenedBlocks[0].Contains('HasPassive(_Character, "COS_ChaosOriginMarker", 1)') -and
    $uiOpenedBlocks[0].Contains('IsControlled(_Character, 1)') -and
    $uiOpenedActions.Count -eq 1 -and $uiOpenedActions[0] -eq 'PROC_COS_ConfigSyncCharacter(_Character);') `
    'UI_OPENED 只允许受控混沌角色通过 ConfigSyncCharacter 初始化和同步，不得直接写配置值'
$allStoryBlocksForConfigSync = @(
    @(Get-AllStoryBlocks $configGoal) + $mechanicsAllBlocksForConfig +
    @(Get-AllStoryBlocks $goal) + @(Get-AllStoryBlocks $masteryGoal) + @(Get-AllStoryBlocks $rewardGoal)
)
$allConfigSyncCallBlocks = @($allStoryBlocksForConfigSync | Where-Object {
    (Get-StoryThen $_).Contains('PROC_COS_ConfigSyncCharacter(_Character);')
})
$lifecycleSyncSpecs = @(
    'LevelGameplayStarted(_, _)', 'GainedControl(_Character)', 'LeveledUp(_Character)', 'RespecCompleted(_Character)'
)
foreach ($lifecycleEvent in $lifecycleSyncSpecs) {
    $lifecycleSyncBlocks = @($allConfigSyncCallBlocks | Where-Object {
        $_.StartsWith("IF`n") -and $_.Contains($lifecycleEvent) -and
        $_.Contains('HasPassive(_Character, "COS_ChaosOriginMarker", 1)')
    })
    Require ($lifecycleSyncBlocks.Count -eq 1) "ConfigSyncCharacter 必须只由带 OriginMarker 的生命周期事件调用: $lifecycleEvent"
}
Require ($allConfigSyncCallBlocks.Count -eq 5 -and $allConfigSyncCallBlocks -contains $uiOpenedBlocks[0]) `
    'ConfigSyncCharacter 的外部调用必须且只能是四个生命周期块和 UI_OPENED'
Require ((Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigResetCore').Count -eq 1 -and
    (Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigSyncMechanicMirrors').Count -ge 1) `
    '核心设置 Goal 必须实际定义 ResetCore 与 SyncMechanicMirrors PROC'

$ensureLifeBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigEnsureLifeSkill')
Require ($ensureLifeBlocks.Count -eq 1 -and
    $ensureLifeBlocks[0].Contains('DB_COS_ConfigLifeDefault(_Default)') -and
    $ensureLifeBlocks[0].Contains('NOT DB_COS_ConfigLifeSkill(_Character, _)') -and
    (Get-StoryThen $ensureLifeBlocks[0]).Contains('DB_COS_ConfigLifeSkill(_Character, _Default);')) `
    '生活熟练项初始化必须只在缺失时写入默认值5'
$stepLifeBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigStepLifeSkill')
Require ($stepLifeBlocks.Count -eq 1 -and
    $stepLifeBlocks[0].Contains('IntegerSum(_OldValue, _Delta, _RawValue)') -and
    $stepLifeBlocks[0].Contains('IntegerMax(_RawValue, 0, _FloorValue)') -and
    $stepLifeBlocks[0].Contains('IntegerMin(_FloorValue, 20, _Value)') -and
    (Get-StoryThen $stepLifeBlocks[0]).Contains('PROC_COS_ConfigSetLifeSkill(_Character, _Value);')) `
    '生活熟练项步进必须先计算再夹取到0至20并经唯一设置过程落地'
$setLifeBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigSetLifeSkill')
Require ($setLifeBlocks.Count -eq 1 -and
    (Get-StoryThen $setLifeBlocks[0]).Contains('NOT DB_COS_ConfigLifeSkill(_Character, _OldValue);') -and
    (Get-StoryThen $setLifeBlocks[0]).Contains('DB_COS_ConfigLifeSkill(_Character, _Value);') -and
    (Get-StoryThen $setLifeBlocks[0]).Contains('PROC_COS_ConfigSyncLifeSkill(_Character);')) `
    '生活熟练项设置必须原子替换存档值并立即同步玩法和UI'
$syncLifeBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigSyncLifeSkill')
Require ($configGoal.Contains('ApplyStatus(_Character, _Status, -1.0, 1, _Character);')) '生活技能必须通过常驻状态施加加值'
foreach ($lifeSyncAction in @(
    'AddPassive(_Character, "COS_CFG_LIFE_SKILL_CARRIER");',
    'PROC_COS_ConfigRemoveLifeSkillBonuses(_Character);',
    'PROC_COS_ConfigAddLifeSkillBonus(_Character);',
    'PROC_COS_ConfigSyncLifeSkillResource(_Character);'
)) {
    Require ($syncLifeBlocks.Count -eq 1 -and (Get-StoryThen $syncLifeBlocks[0]).Contains($lifeSyncAction)) `
        "生活熟练项同步缺少: $lifeSyncAction"
}
$lifeResourceBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigSyncLifeSkillResource')
Require ($lifeResourceBlocks.Count -eq 1 -and
    $lifeResourceBlocks[0].Contains('IntegerToReal(_Value, _ValueReal)') -and
    $lifeResourceBlocks[0].Contains('RealSubtract(0.0, 1000.0, _Reset)') -and
    [regex]::Matches((Get-StoryThen $lifeResourceBlocks[0]),
        '(?m)^PartyIncreaseActionResourceValue\(_Character, "COS_ConfigLifeSkill", _(?:Reset|ValueReal)\);$').Count -eq 2) `
    '生活熟练项UI镜像必须先清空组资源再写入当前值'

$racialApplyBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigApplyRacialPassive')
$racialEnableBlocks = @($racialApplyBlocks | Where-Object {
    $_.Contains('_Enabled == 1') -and $_.Contains('HasPassive(_Character, _Passive, 0)')
})
$racialDisableBlocks = @($racialApplyBlocks | Where-Object {
    $_.Contains('_Enabled == 0') -and $_.Contains('DB_COS_RacialPassiveGranted(_Character, _Passive)')
})
Require ($racialApplyBlocks.Count -eq 2 -and $racialEnableBlocks.Count -eq 1 -and
    (Get-StoryThen $racialEnableBlocks[0]).Contains('AddPassive(_Character, _Passive);') -and
    (Get-StoryThen $racialEnableBlocks[0]).Contains('DB_COS_RacialPassiveGranted(_Character, _Passive);')) `
    '开启种族被动只能在角色缺失时添加并记录模组归属'
Require ($racialDisableBlocks.Count -eq 1 -and
    (Get-StoryThen $racialDisableBlocks[0]).Contains('RemovePassive(_Character, _Passive);') -and
    (Get-StoryThen $racialDisableBlocks[0]).Contains('NOT DB_COS_RacialPassiveGranted(_Character, _Passive);')) `
    '关闭种族被动必须以模组授予账本为前置条件并同时清账'
$racialBulkBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigSetAllRacialPassives')
Require ($racialBulkBlocks.Count -eq 1 -and
    $racialBulkBlocks[0].Contains('DB_COS_ConfigRacial(_Character, _Passive, _Current)') -and
    (Get-StoryThen $racialBulkBlocks[0]).Contains('PROC_COS_ConfigApplyRacialPassive(_Character, _Passive, _Enabled);')) `
    '种族被动全选和全取消必须逐项复用同一归属保护过程'
$racialToggleBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigToggleRacialPassive')
Require ($racialToggleBlocks.Count -eq 1 -and
    $racialToggleBlocks[0].Contains('IntegerSubtract(1, _Enabled, _Next)') -and
    (Get-StoryThen $racialToggleBlocks[0]).Contains('PROC_COS_ConfigApplyRacialPassive(_Character, _Passive, _Next);')) `
    '种族被动单项切换必须从唯一当前值取反并复用归属保护过程'

foreach ($eventProcedure in @(
    'PROC_COS_ConfigStepLifeSkill', 'PROC_COS_ConfigSetLifeSkill',
    'PROC_COS_ConfigToggleRacialPassive', 'PROC_COS_ConfigSetAllRacialPassives'
)) {
    $eventBlocks = @($configIfBlocks | Where-Object {
        $_.Contains('TutorialEvent(_Character, _Event)') -and $_.Contains($eventProcedure)
    })
    Require ($eventBlocks.Count -eq 1) "设置写入必须由唯一固定TutorialEvent块调用: $eventProcedure"
    foreach ($gate in @(
        'HasPassive(_Character, "COS_ChaosOriginMarker", 1)',
        'IsControlled(_Character, 1)', 'IsInCombat(_Character, 0)'
    )) {
        Require ($eventBlocks[0].Contains($gate)) "设置写入缺少门禁 $gate : $eventProcedure"
    }
}

foreach ($forbiddenConfigPattern in @(
    '(?i)[A-Za-z0-9_]*Echo[A-Za-z0-9_]*',
    '(?i)Script\s*Extender', '(?i)\bNMCM\b', '(?i)\bMCM\b'
)) {
    Require (-not ($configGoal -match $forbiddenConfigPattern -or $configStats -match $forbiddenConfigPattern)) `
        "核心设置 Goal/Stats 禁止依赖: $forbiddenConfigPattern"
}

$genesisGatePattern = 'DB_COS_ConfigMechanic\((?:\(CHARACTER\))?_Character, "Genesis", 1\)'
$genesisReadyBlocks = @(Get-StoryBlocks $mechanicsGoal 'PROC' 'PROC_COS_ApplyGenesisReady')
$expectedGenesisReadyConditions = @(
    'PROC_COS_ApplyGenesisReady((CHARACTER)_Character, (INTEGER)_Power)',
    'DB_COS_ConfigMechanic((CHARACTER)_Character, "Genesis", 1)',
    'DB_COS_ConfigMechanic((CHARACTER)_Character, "Power", 1)',
    '_Power >= 10'
)
$expectedGenesisReadyActions = @(
    'ApplyStatus(_Character, "COS_CHAOS_GENESIS_READY", -1.0, 100, _Character);'
)
function Test-GenesisReadyContract([string]$Block) {
    return ((Get-MechanicsConditions $Block) -join "`n") -ceq ($expectedGenesisReadyConditions -join "`n") -and
        ((Get-MechanicsThenActions $Block) -join "`n") -ceq ($expectedGenesisReadyActions -join "`n")
}
Require ($genesisReadyBlocks.Count -eq 1 -and (Test-GenesisReadyContract $genesisReadyBlocks[0])) `
    'ApplyGenesisReady 必须且只能在 Genesis=1 且 Power>=10 时添加 READY'
$genesisReadyGenesisGateDeletionProbe = $genesisReadyBlocks[0].Replace(
    "`nDB_COS_ConfigMechanic((CHARACTER)_Character, `"Genesis`", 1)", '')
Require ($genesisReadyGenesisGateDeletionProbe -cne $genesisReadyBlocks[0] -and
    -not (Test-GenesisReadyContract $genesisReadyGenesisGateDeletionProbe)) `
    'GenesisReady Genesis gate deletion mutation probe 必须被拒绝'
$genesisReadyPowerConfigGateDeletionProbe = $genesisReadyBlocks[0].Replace(
    "`nDB_COS_ConfigMechanic((CHARACTER)_Character, `"Power`", 1)", '')
Require ($genesisReadyPowerConfigGateDeletionProbe -cne $genesisReadyBlocks[0] -and
    -not (Test-GenesisReadyContract $genesisReadyPowerConfigGateDeletionProbe)) `
    'GenesisReady Power config gate deletion mutation probe 必须被拒绝'
$genesisReadyPowerGateDeletionProbe = $genesisReadyBlocks[0].Replace(
    "`n_Power >= 10", '')
Require ($genesisReadyPowerGateDeletionProbe -cne $genesisReadyBlocks[0] -and
    -not (Test-GenesisReadyContract $genesisReadyPowerGateDeletionProbe)) `
    'GenesisReady Power gate deletion mutation probe 必须被拒绝'
$powerSyncBlocks = @(Get-StoryBlocks $mechanicsGoal 'PROC' 'PROC_COS_SyncPowerFromDatabase')
$expectedPowerSyncEnabledConditions = @(
    'PROC_COS_SyncPowerFromDatabase((CHARACTER)_Character)',
    'DB_COS_ConfigMechanic(_Character, "Power", 1)',
    'DB_COS_Power(_Character, _Power)'
)
$expectedPowerSyncDisabledConditions = @(
    'PROC_COS_SyncPowerFromDatabase((CHARACTER)_Character)',
    'DB_COS_ConfigMechanic(_Character, "Power", 0)'
)
$expectedPowerSyncDisabledActions = @(
    'RemoveStatus(_Character, "COS_CHAOS_POWER_STACK", _Character);',
    'RemoveStatus(_Character, "COS_CHAOS_GENESIS_READY", _Character);'
)
function Test-PowerSyncContract([string]$Story) {
    $blocks = @(Get-StoryBlocks $Story 'PROC' 'PROC_COS_SyncPowerFromDatabase')
    if ($blocks.Count -ne 2) { return $false }
    $enabled = @($blocks | Where-Object {
        ((Get-MechanicsConditions $_) -join "`n") -ceq ($expectedPowerSyncEnabledConditions -join "`n") -and
        ((Get-MechanicsThenActions $_) -join "`n") -ceq 'PROC_COS_SyncPowerDisplay(_Character, _Power);'
    })
    $disabled = @($blocks | Where-Object {
        ((Get-MechanicsConditions $_) -join "`n") -ceq ($expectedPowerSyncDisabledConditions -join "`n") -and
        ((Get-MechanicsThenActions $_) -join "`n") -ceq ($expectedPowerSyncDisabledActions -join "`n")
    })
    return $enabled.Count -eq 1 -and $disabled.Count -eq 1
}
Require (Test-PowerSyncContract $mechanicsGoal) `
    'SyncPowerFromDatabase 必须在 Power=1 时同步账本，在 Power=0 时只清 Power/Genesis 显示且保留账本'
$powerSyncEnabledGateMutation = $mechanicsGoal.Replace(
    "DB_COS_ConfigMechanic(_Character, `"Power`", 1)`nAND`nDB_COS_Power(_Character, _Power)",
    'DB_COS_Power(_Character, _Power)')
Require ($powerSyncEnabledGateMutation -cne $mechanicsGoal -and -not (Test-PowerSyncContract $powerSyncEnabledGateMutation)) `
    'SyncPowerFromDatabase mutation probe 必须拒绝启用分支缺失 Power=1'
$powerSyncLedgerDeletionMutation = $mechanicsGoal.Replace(
    'RemoveStatus(_Character, "COS_CHAOS_GENESIS_READY", _Character);',
    "RemoveStatus(_Character, `"COS_CHAOS_GENESIS_READY`", _Character);`nNOT DB_COS_Power(_Character, _Power);")
Require ($powerSyncLedgerDeletionMutation -cne $mechanicsGoal -and -not (Test-PowerSyncContract $powerSyncLedgerDeletionMutation)) `
    'SyncPowerFromDatabase mutation probe 必须拒绝 Power=0 删除账本'
$genesisUseBlocks = @($mechanicsIfBlocks | Where-Object {
    $_.Contains('UsingSpell(_Character, "Shout_COS_ChaosGenesis"')
})
Require ($genesisUseBlocks.Count -eq 1) '开天辟地必须只有一个 UsingSpell 触发块'
Require-StoryGate $genesisUseBlocks[0] $genesisGatePattern '开天辟地 UsingSpell 触发块必须要求 Genesis=1'

function Get-StatsEntryBlock([string]$Text, [string]$Name) {
    $pattern = '(?ms)^new entry "' + [regex]::Escape($Name) + '"\r?\n.*?(?=^new entry |\z)'
    $matches = @([regex]::Matches($Text, $pattern))
    Require ($matches.Count -eq 1) "Stats 条目必须全局唯一: $Name"
    return $matches[0].Value
}
function Test-StatsField([string]$Block, [string]$Field, [string]$Expected) {
    $matches = @([regex]::Matches($Block, '(?m)^data "' + [regex]::Escape($Field) + '" "([^"]*)"\r?$'))
    return $matches.Count -eq 1 -and $matches[0].Groups[1].Value -ceq $Expected
}
function Test-StatsUsing([string]$Block, [string]$Expected) {
    $matches = @([regex]::Matches(
        $Block,
        '(?m)^using "([^"]+)"\r?$'
    ))
    return $matches.Count -eq 1 -and $matches[0].Groups[1].Value -ceq $Expected
}

$globalCarryPassiveBlock = Get-StatsEntryBlock $passive 'COS_GlobalCarryCapacity50x'
$expectedGlobalCarryPassiveBlock = Normalize-LineEndings @'
new entry "COS_GlobalCarryCapacity50x"
type "PassiveData"
data "Properties" "IsHidden"
data "Boosts" "CarryCapacityMultiplier(50)"
'@
function Test-GlobalCarryPassiveContract([string]$Block) {
    return ((Normalize-LineEndings $Block).Trim() -ceq $expectedGlobalCarryPassiveBlock.Trim())
}
Require ((Test-StatsField $globalCarryPassiveBlock 'Properties' 'IsHidden') -and
    (Test-StatsField $globalCarryPassiveBlock 'Boosts' 'CarryCapacityMultiplier(50)')) `
    '全局负重被动必须隐藏并精确提供50倍负重'
Require ([regex]::Matches($globalCarryPassiveBlock, '(?m)^type "PassiveData"\r?$').Count -eq 1) `
    '全局负重被动必须唯一声明为 PassiveData'
Require (Test-GlobalCarryPassiveContract $globalCarryPassiveBlock) `
    '全局负重被动必须大小写敏感地只包含 entry、PassiveData、IsHidden 和 CarryCapacityMultiplier(50) 四行'

$globalCarryExtraTypeMutation = $globalCarryPassiveBlock.Replace(
    'type "PassiveData"',
    "type `"PassiveData`"`ntype `"StatusData`"")
Require ($globalCarryExtraTypeMutation -cne $globalCarryPassiveBlock -and
    -not (Test-GlobalCarryPassiveContract $globalCarryExtraTypeMutation)) `
    '全局负重被动变异探针必须拒绝额外 type'
$globalCarryUsingMutation = $globalCarryPassiveBlock.Replace(
    'type "PassiveData"',
    "type `"PassiveData`"`nusing `"SharedPassive`"")
Require ($globalCarryUsingMutation -cne $globalCarryPassiveBlock -and
    -not (Test-GlobalCarryPassiveContract $globalCarryUsingMutation)) `
    '全局负重被动变异探针必须拒绝 using 继承'
$globalCarryExtraDataMutation = $globalCarryPassiveBlock.Replace(
    'data "Boosts" "CarryCapacityMultiplier(50)"',
    "data `"Boosts`" `"CarryCapacityMultiplier(50)`"`ndata `"DisplayName`" `"hcarry;1`"")
Require ($globalCarryExtraDataMutation -cne $globalCarryPassiveBlock -and
    -not (Test-GlobalCarryPassiveContract $globalCarryExtraDataMutation)) `
    '全局负重被动变异探针必须拒绝任意额外 data'

$expectedCoreSpells = @(
    '1|Shout_COS_ChaosGenesis',
    '5|Target_COS_DraconicElementalWeapon',
    '5|Target_COS_Haste',
    '5|Target_COS_Knock'
) | Sort-Object
$actualCoreSpells = @([regex]::Matches(
    $goal,
    '(?m)^DB_COS_CoreSpell\(([0-9]+), "([^"]+)"\);\r?$'
) | ForEach-Object {
    "$($_.Groups[1].Value)|$($_.Groups[2].Value)"
} | Sort-Object)
Require ($actualCoreSpells.Count -eq 4 -and
    ($actualCoreSpells -join "`n") -ceq ($expectedCoreSpells -join "`n")) `
    '基础同步必须注册开天辟地和三个五级技能'

$coreSpellGrantPattern = '(?ms)PROC\r?\nPROC_COS_SyncBaseAfterCreation\(\(CHARACTER\)_Character\)\r?\n' +
    'AND\r?\nGetLevel\(_Character, _Level\)\r?\n' +
    'AND\r?\nDB_COS_CoreSpell\(_RequiredLevel, _CoreSpell\)\r?\n' +
    'AND\r?\n_Level >= _RequiredLevel\r?\n' +
    'AND\r?\nHasSpell\(_Character, _CoreSpell, 0\)\r?\n' +
    'THEN\r?\nAddSpell\(_Character, _CoreSpell, 0, 0\);'
Require ([regex]::Matches($goal, $coreSpellGrantPattern).Count -eq 1) `
    '基础同步必须在角色达到需求等级时授予 MOD 专用核心技能'

$coreSpellRemovalPattern = '(?ms)PROC\r?\nPROC_COS_SyncBaseAfterCreation\(\(CHARACTER\)_Character\)\r?\n' +
    'AND\r?\nGetLevel\(_Character, _Level\)\r?\n' +
    'AND\r?\nDB_COS_CoreSpell\(_RequiredLevel, _CoreSpell\)\r?\n' +
    'AND\r?\n_Level < _RequiredLevel\r?\n' +
    'AND\r?\nHasSpell\(_Character, _CoreSpell, 1\)\r?\n' +
    'THEN\r?\nRemoveSpell\(_Character, _CoreSpell, 0\);'
Require ([regex]::Matches($goal, $coreSpellRemovalPattern).Count -eq 1) `
    '基础同步必须在角色低于需求等级时移除 MOD 专用核心技能'

$baseSyncLifecycleSpecs = [ordered]@{
    'LevelGameplayStarted(_, _)' = @(
        'LevelGameplayStarted(_, _)',
        'DB_Avatars(_Character)',
        'HasPassive(_Character, "COS_ChaosOriginMarker", 1)'
    )
    'GainedControl(_Character)' = @(
        'GainedControl(_Character)',
        'HasPassive(_Character, "COS_ChaosOriginMarker", 1)'
    )
    'LeveledUp(_Character)' = @(
        'LeveledUp(_Character)',
        'HasPassive(_Character, "COS_ChaosOriginMarker", 1)'
    )
    'RespecCompleted(_Character)' = @(
        'RespecCompleted(_Character)',
        'HasPassive(_Character, "COS_ChaosOriginMarker", 1)'
    )
}
$baseSyncIfBlocks = @(Get-AllStoryBlocks $goal | Where-Object { $_.StartsWith("IF`n") })
foreach ($lifecycleEvent in $baseSyncLifecycleSpecs.Keys) {
    $eventBlocks = @($baseSyncIfBlocks | Where-Object {
        $conditions = @(Get-MechanicsConditions $_)
        $conditions.Count -gt 0 -and $conditions[0] -ceq $lifecycleEvent
    })
    Require ($eventBlocks.Count -eq 1) "基础同步生命周期事件必须唯一: $lifecycleEvent"
    $eventConditions = @(Get-MechanicsConditions $eventBlocks[0])
    $baseSyncCalls = @((Get-MechanicsThenActions $eventBlocks[0]) | Where-Object {
        $_ -ceq 'PROC_COS_SyncBaseAfterCreation(_Character);'
    })
    Require (($eventConditions -join "`n") -ceq ($baseSyncLifecycleSpecs[$lifecycleEvent] -join "`n") -and
        $baseSyncCalls.Count -eq 1) `
        "基础同步生命周期事件必须保留 OriginMarker 门禁并调用一次同步: $lifecycleEvent"
}

$draconicRoot = Get-StatsEntryBlock $featuresText 'Target_COS_DraconicElementalWeapon'
Require (Test-StatsUsing $draconicRoot 'Target_MAG_ElementalWeapon') `
    '龙族元素武器必须继承龙息长柄刀技能'
Require (Test-StatsField $draconicRoot 'ContainerSpells' `
    'Target_COS_DraconicElementalWeapon_Acid;Target_COS_DraconicElementalWeapon_Cold;Target_COS_DraconicElementalWeapon_Fire;Target_COS_DraconicElementalWeapon_Lightning;Target_COS_DraconicElementalWeapon_Thunder') `
    '龙族元素武器必须包含五个专用元素子技能'
Require ((Test-StatsField $draconicRoot 'UseCosts' '') -and
    (Test-StatsField $draconicRoot 'Cooldown' '')) `
    '龙族元素武器必须无动作、无资源且无冷却'

foreach ($element in @('Acid', 'Cold', 'Fire', 'Lightning', 'Thunder')) {
    $childName = "Target_COS_DraconicElementalWeapon_$element"
    $childBlock = Get-StatsEntryBlock $featuresText $childName
    Require (Test-StatsUsing $childBlock "Target_MAG_ElementalWeapon_$element") `
        "龙族元素子技能必须继承官方版本: $element"
    Require ((Test-StatsField $childBlock 'SpellContainerID' 'Target_COS_DraconicElementalWeapon') -and
        (Test-StatsField $childBlock 'UseCosts' '') -and
        (Test-StatsField $childBlock 'Cooldown' '')) `
        "龙族元素子技能必须绑定专用容器并移除成本: $element"
}

$hasteBlock = Get-StatsEntryBlock $featuresText 'Target_COS_Haste'
Require ((Test-StatsUsing $hasteBlock 'Target_Haste') -and
    (Test-StatsField $hasteBlock 'UseCosts' 'ActionPoint:1') -and
    (Test-StatsField $hasteBlock 'MemoryCost' '') -and
    -not ($hasteBlock -match '(?m)^data "SpellFlags" ')) `
    '加速术必须只消耗一个动作并继承原版专注规则'

$knockBlock = Get-StatsEntryBlock $featuresText 'Target_COS_Knock'
Require ((Test-StatsUsing $knockBlock 'Target_Knock') -and
    (Test-StatsField $knockBlock 'UseCosts' '') -and
    (Test-StatsField $knockBlock 'Cooldown' '') -and
    (Test-StatsField $knockBlock 'MemoryCost' '')) `
    '敲击术必须无动作、无资源且无冷却'

$genesisSpellBlock = Get-StatsEntryBlock $featuresText 'Shout_COS_ChaosGenesis'
$expectedGenesisRequirements = "HasStatus('COS_CHAOS_GENESIS_READY',context.Source) and HasPassive('COS_CFG_MECH_POWER',context.Source) and HasPassive('COS_CFG_MECH_GENESIS',context.Source)"
Require (Test-StatsField $genesisSpellBlock 'RequirementConditions' $expectedGenesisRequirements) `
    '开天辟地 Stats 必须同时要求 READY、Power 镜像和 Genesis 镜像'
foreach ($genesisPassiveGate in @('COS_CFG_MECH_POWER', 'COS_CFG_MECH_GENESIS')) {
    $mutation = $genesisSpellBlock.Replace(" and HasPassive('$genesisPassiveGate',context.Source)", '')
    Require ($mutation -cne $genesisSpellBlock -and
        -not (Test-StatsField $mutation 'RequirementConditions' $expectedGenesisRequirements)) `
        "开天辟地 Stats mutation probe 必须拒绝删除 $genesisPassiveGate"
}
$allInSpellBlock = Get-StatsEntryBlock $featuresText 'Shout_COS_ChaosAllIn'
$expectedAllInRequirements = "not HasStatus('COS_CHAOS_ALLIN_TOGGLE',context.Source) and HasPassive('COS_CFG_MECH_ALLIN',context.Source)"
Require (Test-StatsField $allInSpellBlock 'RequirementConditions' $expectedAllInRequirements) `
    '混沌孤注 Stats 必须保持未激活条件并要求 AllIn 镜像'
$allInGateMutation = $allInSpellBlock.Replace(" and HasPassive('COS_CFG_MECH_ALLIN',context.Source)", '')
Require ($allInGateMutation -cne $allInSpellBlock -and
    -not (Test-StatsField $allInGateMutation 'RequirementConditions' $expectedAllInRequirements)) `
    '混沌孤注 Stats mutation probe 必须拒绝删除 AllIn 镜像门禁'
$interruptText = Get-Content -LiteralPath (Join-Path $root "Public\$module\Stats\Generated\Data\Interrupt.txt") -Raw -Encoding UTF8
$strikeInterruptBlock = Get-StatsEntryBlock $interruptText 'Interrupt_COS_ChaosStrike'
$expectedStrikeConditions = "IsAbleToReact(context.Observer) and Self(context.Source,context.Observer) and ((HasInterruptedAttack() and (IsWeaponAttack() or IsSpell())) or (HasInterruptedSavingThrow() and IsSpell() and HasFunctor(StatsFunctorType.DealDamage))) and not HasStatus('COS_CHAOS_STRIKE_ACTIVE',context.Observer) and not AnyEntityIsItem() and HasPassive('COS_CFG_MECH_STRIKE',context.Observer)"
$expectedStrikeEnableCondition = "HasActionResource('COS_ChaosStrike',1,0,false,false,context.Source) and not HasStatus('COS_CHAOS_STRIKE_ACTIVE',context.Source) and HasPassive('COS_CFG_MECH_STRIKE',context.Source)"
Require (Test-StatsField $strikeInterruptBlock 'Conditions' $expectedStrikeConditions) `
    '混沌裁决 Interrupt Conditions 必须要求 Observer 的 Strike 镜像'
Require (Test-StatsField $strikeInterruptBlock 'EnableCondition' $expectedStrikeEnableCondition) `
    '混沌裁决 Interrupt EnableCondition 必须要求 Source 的 Strike 镜像'
Require (Test-StatsField $strikeInterruptBlock 'Properties' "IF(HasInterruptedAttack()):SetRoll(20);IF(HasInterruptedSavingThrow()):SetRoll(1);IF(HasInterruptedSavingThrow()):AdjustRoll(-99,All);ApplyStatus(OBSERVER_OBSERVER,COS_CHAOS_STRIKE_ACTIVE,100,1)") `
    '混沌裁决不得改写原 SetRoll/状态效果'
Require (Test-StatsField $strikeInterruptBlock 'Cost' 'ReactionActionPoint:1;COS_ChaosStrike:1') `
    '混沌裁决不得改写原 Cost'
foreach ($strikeGateSpec in @(
    @('Conditions', " and HasPassive('COS_CFG_MECH_STRIKE',context.Observer)", $expectedStrikeConditions),
    @('EnableCondition', " and HasPassive('COS_CFG_MECH_STRIKE',context.Source)", $expectedStrikeEnableCondition)
)) {
    $mutation = $strikeInterruptBlock.Replace($strikeGateSpec[1], '')
    Require ($mutation -cne $strikeInterruptBlock -and
        -not (Test-StatsField $mutation $strikeGateSpec[0] $strikeGateSpec[2])) `
        "混沌裁决 mutation probe 必须拒绝删除 $($strikeGateSpec[0]) 镜像门禁"
}

function Test-DualityOwnerPropagation([string]$Story) {
    $resolveBlocks = @(Get-StoryBlocks $Story 'PROC' 'PROC_COS_ResolveDuality')
    $outcomeBlocks = @(Get-StoryBlocks $Story 'PROC' 'PROC_COS_ResolveDualityOutcome')
    $typeBlocks = @(Get-StoryBlocks $Story 'PROC' 'PROC_COS_ResolveDualityType')
    $timingBlocks = @(Get-StoryBlocks $Story 'PROC' 'PROC_COS_ResolveDualityTiming')
    $queueBlocks = @(Get-StoryBlocks $Story 'PROC' 'PROC_COS_QueueDelayedDualityDamage')
    if ($resolveBlocks.Count -ne 2 -or $outcomeBlocks.Count -ne 1 -or $typeBlocks.Count -ne 2 -or
        $timingBlocks.Count -ne 3 -or $queueBlocks.Count -ne 1) { return $false }
    if (@($resolveBlocks | Where-Object {
        (Get-StoryThen $_).Contains('PROC_COS_ResolveDualityOutcome(_Owner, _Target,')
    }).Count -ne 2) { return $false }
    if (-not $outcomeBlocks[0].Contains('PROC_COS_ResolveDualityOutcome((CHARACTER)_Owner, (CHARACTER)_Target,') -or
        -not (Get-StoryThen $outcomeBlocks[0]).Contains('PROC_COS_ResolveDualityType(_Owner, _Target,')) { return $false }
    if (@($typeBlocks | Where-Object {
        $_.Contains('PROC_COS_ResolveDualityType((CHARACTER)_Owner, (CHARACTER)_Target,') -and
        (Get-StoryThen $_).Contains('PROC_COS_ResolveDualityTiming(_Owner, _Target,')
    }).Count -ne 2) { return $false }
    if (@($timingBlocks | Where-Object {
        $_.Contains('PROC_COS_ResolveDualityTiming((CHARACTER)_Owner, (CHARACTER)_Target,')
    }).Count -ne 3) { return $false }
    $delayedCalls = @([regex]::Matches(
        ($timingBlocks | ForEach-Object { Get-StoryThen $_ }) -join "`n",
        '(?m)^PROC_COS_QueueDelayedDualityDamage\(_Owner, _Target, [^\r\n]+\);$'))
    if ($delayedCalls.Count -ne 2) { return $false }
    $queueConditions = @(Get-MechanicsConditions $queueBlocks[0])
    $queueActions = @(Get-MechanicsThenActions $queueBlocks[0])
    $expectedQueueConditions = @(
        'PROC_COS_QueueDelayedDualityDamage((CHARACTER)_Owner, (CHARACTER)_Target, (INTEGER)_Amount, (STRING)_DamageType, (STRING)_LogStatus)',
        'DB_COS_DualityDelaySerial(_Serial)',
        'IntegerSum(_Serial, 1, _NextSerial)'
    )
    $expectedQueueActions = @(
        'NOT DB_COS_DualityDelaySerial(_Serial);',
        'DB_COS_DualityDelaySerial(_NextSerial);',
        'DB_COS_DualityDelayed(_Target, _NextSerial, _Amount, _DamageType, _LogStatus);',
        'DB_COS_DualityDelayedOwner(_Owner, _Target, _NextSerial);',
        'PROC_COS_AddDelayedTargetTotal(_Target, _Amount);',
        'PROC_COS_AddDelayedOwnerTotal(_Owner, _Target, _Amount);',
        'ApplyStatus(_Target, "COS_CHAOS_DUALITY_LOG_DEVOUR_40", -1.0, 100, _Target);'
    )
    return ($queueConditions -join "`n") -ceq ($expectedQueueConditions -join "`n") -and
        ($queueActions -join "`n") -ceq ($expectedQueueActions -join "`n")
}
Require (Test-DualityOwnerPropagation $mechanicsGoal) `
    '延迟两仪必须沿 ResolveDuality→Outcome→Type→Timing→Queue 传递 Owner，并同时写旧债务与 owner map'
$dualityOwnerPropagationMutation = $mechanicsGoal.Replace(
    'PROC_COS_ResolveDualityOutcome(_Owner, _Target,',
    'PROC_COS_ResolveDualityOutcome(_Target,')
Require ($dualityOwnerPropagationMutation -cne $mechanicsGoal -and
    -not (Test-DualityOwnerPropagation $dualityOwnerPropagationMutation)) `
    '延迟两仪 mutation probe 必须拒绝删除 Owner 传播'
$dualityOwnerMapDeletionMutation = $mechanicsGoal.Replace(
    "`nDB_COS_DualityDelayedOwner(_Owner, _Target, _NextSerial);", '')
Require ($dualityOwnerMapDeletionMutation -cne $mechanicsGoal -and
    -not (Test-DualityOwnerPropagation $dualityOwnerMapDeletionMutation)) `
    '延迟两仪 mutation probe 必须拒绝 Queue 缺失 owner map'

function Test-ExactDualityContracts([string]$Story, [string]$Kind, [string]$Name, [object[]]$Contracts) {
    $blocks = @(Get-StoryBlocks $Story $Kind $Name)
    if ($blocks.Count -ne $Contracts.Count) { return $false }
    foreach ($contract in $Contracts) {
        $matches = @($blocks | Where-Object {
            ((Get-MechanicsConditions $_) -join "`n") -ceq ($contract.Conditions -join "`n") -and
            ((Get-MechanicsThenActions $_) -join "`n") -ceq ($contract.Actions -join "`n")
        })
        if ($matches.Count -ne 1) { return $false }
    }
    return $true
}

$targetTotalContracts = @(
    @{
        Conditions = @(
            'PROC_COS_AddDelayedTargetTotal((CHARACTER)_Target, (INTEGER)_Amount)',
            'DB_COS_DualityDelayedTargetTotal(_Target, _OldAmount)',
            'IntegerSum(_OldAmount, _Amount, _NewAmount)'
        )
        Actions = @(
            'NOT DB_COS_DualityDelayedTargetTotal(_Target, _OldAmount);',
            'DB_COS_DualityDelayedTargetTotal(_Target, _NewAmount);'
        )
    },
    @{
        Conditions = @(
            'PROC_COS_AddDelayedTargetTotal((CHARACTER)_Target, (INTEGER)_Amount)',
            'NOT DB_COS_DualityDelayedTargetTotal(_Target, _)'
        )
        Actions = @('DB_COS_DualityDelayedTargetTotal(_Target, _Amount);')
    }
)
$ownerTotalContracts = @(
    @{
        Conditions = @(
            'PROC_COS_AddDelayedOwnerTotal((CHARACTER)_Owner, (CHARACTER)_Target, (INTEGER)_Amount)',
            'DB_COS_DualityDelayedOwnerTotal(_Owner, _Target, _OldAmount)',
            'IntegerSum(_OldAmount, _Amount, _NewAmount)'
        )
        Actions = @(
            'NOT DB_COS_DualityDelayedOwnerTotal(_Owner, _Target, _OldAmount);',
            'DB_COS_DualityDelayedOwnerTotal(_Owner, _Target, _NewAmount);'
        )
    },
    @{
        Conditions = @(
            'PROC_COS_AddDelayedOwnerTotal((CHARACTER)_Owner, (CHARACTER)_Target, (INTEGER)_Amount)',
            'NOT DB_COS_DualityDelayedOwnerTotal(_Owner, _Target, _)'
        )
        Actions = @('DB_COS_DualityDelayedOwnerTotal(_Owner, _Target, _Amount);')
    }
)
function Test-DualityAggregateWriteContract([string]$Story) {
    return (Test-ExactDualityContracts $Story 'PROC' 'PROC_COS_AddDelayedTargetTotal' $targetTotalContracts) -and
        (Test-ExactDualityContracts $Story 'PROC' 'PROC_COS_AddDelayedOwnerTotal' $ownerTotalContracts) -and
        (Test-DualityOwnerPropagation $Story)
}
Require (Test-DualityAggregateWriteContract $mechanicsGoal) `
    '延迟两仪 Queue 必须用互斥 helper 累加唯一 TargetTotal 与 OwnerTotal'
$targetTotalDeletionMutation = $mechanicsGoal.Replace('PROC_COS_AddDelayedTargetTotal(_Target, _Amount);', '')
Require ($targetTotalDeletionMutation -cne $mechanicsGoal -and
    -not (Test-DualityAggregateWriteContract $targetTotalDeletionMutation)) `
    '延迟两仪 mutation probe 必须拒绝 Queue 漏写 TargetTotal'
$ownerTotalDeletionMutation = $mechanicsGoal.Replace('PROC_COS_AddDelayedOwnerTotal(_Owner, _Target, _Amount);', '')
Require ($ownerTotalDeletionMutation -cne $mechanicsGoal -and
    -not (Test-DualityAggregateWriteContract $ownerTotalDeletionMutation)) `
    '延迟两仪 mutation probe 必须拒绝 Queue 漏写 OwnerTotal'
$totalAccumulationMutation = $mechanicsGoal.Replace(
    'IntegerSum(_OldAmount, _Amount, _NewAmount)',
    'IntegerSum(_OldAmount, 0, _NewAmount)')
Require ($totalAccumulationMutation -cne $mechanicsGoal -and
    -not (Test-DualityAggregateWriteContract $totalAccumulationMutation)) `
    '延迟两仪 mutation probe 必须拒绝 totals 漏累加 Amount'

$markerContracts = @(@{
    Conditions = @(
        'PROC_COS_SyncDualityDelayedMarker((CHARACTER)_Target)',
        'NOT DB_COS_DualityDelayed(_Target, _, _, _, _)'
    )
    Actions = @('RemoveStatus(_Target, "COS_CHAOS_DUALITY_LOG_DEVOUR_40", _Target);')
})
function Test-DualityMarkerContract([string]$Story) {
    $markerRemovalCount = [regex]::Matches($Story,
        '(?m)^RemoveStatus\(_Target, "COS_CHAOS_DUALITY_LOG_DEVOUR_40", _Target\);$').Count
    return $markerRemovalCount -eq 1 -and
        (Test-ExactDualityContracts $Story 'PROC' 'PROC_COS_SyncDualityDelayedMarker' $markerContracts)
}
Require (Test-DualityMarkerContract $mechanicsGoal) `
    '延迟两仪 marker 只能在不存在任何 individual debt 时由唯一 Sync PROC 移除'
$markerNotDeletionMutation = $mechanicsGoal.Replace(
    'NOT DB_COS_DualityDelayed(_Target, _, _, _, _)',
    'DB_COS_DualityDelayed(_Target, _, _, _, _)')
Require ($markerNotDeletionMutation -cne $mechanicsGoal -and
    -not (Test-DualityMarkerContract $markerNotDeletionMutation)) `
    '延迟两仪 marker mutation probe 必须拒绝 Sync 缺失 NOT'
$directMarkerRemovalMutation = $mechanicsGoal.Replace(
    'PROC_COS_SyncDualityDelayedMarker(_Target);',
    'RemoveStatus(_Target, "COS_CHAOS_DUALITY_LOG_DEVOUR_40", _Target);')
Require ($directMarkerRemovalMutation -cne $mechanicsGoal -and
    -not (Test-DualityMarkerContract $directMarkerRemovalMutation)) `
    '延迟两仪 marker mutation probe 必须拒绝清理流程直接无条件 RemoveStatus'

$clearOwnerContracts = @(
    @{
        Conditions = @(
            'PROC_COS_ClearDelayedDualityForOwner((CHARACTER)_Owner)',
            'DB_COS_DualityDelayedOwnerTotal(_Owner, _Target, _Contribution)',
            'DB_COS_DualityDelayedTargetTotal(_Target, _Total)',
            'IntegerSubtract(_Total, _Contribution, _Remaining)',
            '_Remaining != 0'
        )
        Actions = @(
            'NOT DB_COS_DualityDelayedOwnerTotal(_Owner, _Target, _Contribution);',
            'NOT DB_COS_DualityDelayedTargetTotal(_Target, _Total);',
            'DB_COS_DualityDelayedTargetTotal(_Target, _Remaining);',
            'PROC_COS_ClearDelayedDualityRowsForOwner(_Owner, _Target);'
        )
    },
    @{
        Conditions = @(
            'PROC_COS_ClearDelayedDualityForOwner((CHARACTER)_Owner)',
            'DB_COS_DualityDelayedOwnerTotal(_Owner, _Target, _Contribution)',
            'DB_COS_DualityDelayedTargetTotal(_Target, _Total)',
            'IntegerSubtract(_Total, _Contribution, _Remaining)',
            '_Remaining == 0'
        )
        Actions = @(
            'NOT DB_COS_DualityDelayedOwnerTotal(_Owner, _Target, _Contribution);',
            'NOT DB_COS_DualityDelayedTargetTotal(_Target, _Total);',
            'PROC_COS_ClearDelayedDualityRowsForOwner(_Owner, _Target);'
        )
    }
)
$clearOwnerRowsContracts = @(@{
    Conditions = @(
        'PROC_COS_ClearDelayedDualityRowsForOwner((CHARACTER)_Owner, (CHARACTER)_Target)',
        'DB_COS_DualityDelayedOwner(_Owner, _Target, _Serial)',
        'DB_COS_DualityDelayed(_Target, _Serial, _Amount, _DamageType, _LogStatus)'
    )
    Actions = @(
        'NOT DB_COS_DualityDelayed(_Target, _Serial, _Amount, _DamageType, _LogStatus);',
        'NOT DB_COS_DualityDelayedOwner(_Owner, _Target, _Serial);',
        'PROC_COS_SyncDualityDelayedMarker(_Target);'
    )
})
function Test-ClearDelayedOwnerContract([string]$Story) {
    return (Test-ExactDualityContracts $Story 'PROC' 'PROC_COS_ClearDelayedDualityForOwner' $clearOwnerContracts) -and
        (Test-ExactDualityContracts $Story 'PROC' 'PROC_COS_ClearDelayedDualityRowsForOwner' $clearOwnerRowsContracts)
}
Require (Test-ClearDelayedOwnerContract $mechanicsGoal) `
    '关闭两仪必须只减去该 Owner 对各 Target 的总贡献，并只清该 Owner 的 individual rows'
$clearOwnerTargetTotalMutation = $mechanicsGoal.Replace(
    'IntegerSubtract(_Total, _Contribution, _Remaining)',
    'IntegerSubtract(_Total, 0, _Remaining)')
Require ($clearOwnerTargetTotalMutation -cne $mechanicsGoal -and
    -not (Test-ClearDelayedOwnerContract $clearOwnerTargetTotalMutation)) `
    '延迟两仪 mutation probe 必须拒绝清 Owner 时未从 TargetTotal 减去贡献'
$globalDelayedClearMutation = $mechanicsGoal.Replace(
    'DB_COS_DualityDelayedOwner(_Owner, _Target, _Serial)',
    'DB_COS_DualityDelayedOwner(_OtherOwner, _Target, _Serial)')
Require ($globalDelayedClearMutation -cne $mechanicsGoal -and
    -not (Test-ClearDelayedOwnerContract $globalDelayedClearMutation)) `
    '双 Owner 静态合同必须拒绝关闭 A 时删除 B 的 individual rows'

$resolveRowsContracts = @(@{
    Conditions = @(
        'PROC_COS_ResolveDelayedDualityRows((CHARACTER)_Target)',
        'DB_COS_DualityDelayed(_Target, _Serial, _Amount, _DamageType, _LogStatus)',
        'DB_COS_DualityDelayedOwner(_Owner, _Target, _Serial)'
    )
    Actions = @(
        'NOT DB_COS_DualityDelayed(_Target, _Serial, _Amount, _DamageType, _LogStatus);',
        'NOT DB_COS_DualityDelayedOwner(_Owner, _Target, _Serial);',
        'ApplyStatus(_Target, _LogStatus, 0.1, 100, _Target);',
        'PROC_COS_SyncDualityDelayedMarker(_Target);'
    )
})
$clearTargetRowsContracts = @(@{
    Conditions = @(
        'PROC_COS_ClearDelayedDualityRowsForTarget((CHARACTER)_Target)',
        'DB_COS_DualityDelayed(_Target, _Serial, _Amount, _DamageType, _LogStatus)',
        'DB_COS_DualityDelayedOwner(_Owner, _Target, _Serial)'
    )
    Actions = @(
        'NOT DB_COS_DualityDelayed(_Target, _Serial, _Amount, _DamageType, _LogStatus);',
        'NOT DB_COS_DualityDelayedOwner(_Owner, _Target, _Serial);',
        'PROC_COS_SyncDualityDelayedMarker(_Target);'
    )
})
$clearTargetOwnerTotalsContracts = @(@{
    Conditions = @(
        'PROC_COS_ClearDelayedDualityOwnerTotalsForTarget((CHARACTER)_Target)',
        'DB_COS_DualityDelayedOwnerTotal(_Owner, _Target, _Contribution)'
    )
    Actions = @('NOT DB_COS_DualityDelayedOwnerTotal(_Owner, _Target, _Contribution);')
})
function Test-DualityDelayedLifecycleContract([string]$Story) {
    $blocks = @(Get-AllStoryBlocks $Story)
    $turnBlocks = @($blocks | Where-Object { $_.StartsWith("IF`nTurnStarted(_Target)") })
    $turnHpBlocks = @($turnBlocks | Where-Object { (Get-StoryThen $_).Contains('SetHitpoints(') })
    $diedBlocks = @($blocks | Where-Object {
        $_.StartsWith("IF`nDied(_Target)") -and $_.Contains('DB_COS_DualityDelayedTargetTotal(')
    })
    $migrationBlocks = @($blocks | Where-Object {
        $_.StartsWith("IF`nLevelGameplayStarted(_, _)") -and
        $_.Contains('DB_COS_DualityDelayed((CHARACTER)_Target,')
    })
    if ($turnHpBlocks.Count -ne 1 -or $diedBlocks.Count -ne 1 -or $migrationBlocks.Count -ne 1) { return $false }
    $expectedTurnConditions = @(
        'TurnStarted(_Target)',
        'DB_COS_DualityDelayedTargetTotal((CHARACTER)_Target, _Amount)',
        'GetHitpoints(_Target, _Hitpoints)',
        'IntegerSubtract(_Hitpoints, _Amount, _ReducedHitpoints)',
        'IntegerMax(_ReducedHitpoints, 0, _FinalHitpoints)'
    )
    $expectedTurnActions = @(
        'NOT DB_COS_DualityDelayedTargetTotal(_Target, _Amount);',
        'SetHitpoints(_Target, _FinalHitpoints, "Guaranteed");',
        'PROC_COS_ResolveDelayedDualityRows(_Target);',
        'PROC_COS_ClearDelayedDualityOwnerTotalsForTarget(_Target);',
        'PROC_COS_SyncDualityDelayedMarker(_Target);'
    )
    $expectedDiedConditions = @(
        'Died(_Target)',
        'DB_COS_DualityDelayedTargetTotal((CHARACTER)_Target, _Amount)'
    )
    $expectedDiedActions = @(
        'NOT DB_COS_DualityDelayedTargetTotal(_Target, _Amount);',
        'PROC_COS_ClearDelayedDualityRowsForTarget(_Target);',
        'PROC_COS_ClearDelayedDualityOwnerTotalsForTarget(_Target);',
        'PROC_COS_SyncDualityDelayedMarker(_Target);'
    )
    $expectedMigrationConditions = @(
        'LevelGameplayStarted(_, _)',
        'DB_COS_DualityDelayed((CHARACTER)_Target, _Serial, _Amount, _DamageType, _LogStatus)',
        'NOT DB_COS_DualityDelayedOwner(_, _Target, _Serial)'
    )
    $expectedMigrationActions = @(
        'NOT DB_COS_DualityDelayed(_Target, _Serial, _Amount, _DamageType, _LogStatus);',
        'PROC_COS_SyncDualityDelayedMarker(_Target);'
    )
    $individualHpBlocks = @($blocks | Where-Object {
        $_.Contains('DB_COS_DualityDelayed(') -and (Get-StoryThen $_).Contains('SetHitpoints(')
    })
    return $individualHpBlocks.Count -eq 0 -and
        ((Get-MechanicsConditions $turnHpBlocks[0]) -join "`n") -ceq ($expectedTurnConditions -join "`n") -and
        ((Get-MechanicsThenActions $turnHpBlocks[0]) -join "`n") -ceq ($expectedTurnActions -join "`n") -and
        ((Get-MechanicsConditions $diedBlocks[0]) -join "`n") -ceq ($expectedDiedConditions -join "`n") -and
        ((Get-MechanicsThenActions $diedBlocks[0]) -join "`n") -ceq ($expectedDiedActions -join "`n") -and
        ((Get-MechanicsConditions $migrationBlocks[0]) -join "`n") -ceq ($expectedMigrationConditions -join "`n") -and
        ((Get-MechanicsThenActions $migrationBlocks[0]) -join "`n") -ceq ($expectedMigrationActions -join "`n") -and
        (Test-ExactDualityContracts $Story 'PROC' 'PROC_COS_ResolveDelayedDualityRows' $resolveRowsContracts) -and
        (Test-ExactDualityContracts $Story 'PROC' 'PROC_COS_ClearDelayedDualityRowsForTarget' $clearTargetRowsContracts) -and
        (Test-ExactDualityContracts $Story 'PROC' 'PROC_COS_ClearDelayedDualityOwnerTotalsForTarget' $clearTargetOwnerTotalsContracts)
}
Require (Test-DualityDelayedLifecycleContract $mechanicsGoal) `
    '延迟两仪必须按 TargetTotal 只扣血一次，再逐 individual 清债/日志并清 totals；Died/legacy 必须安全清理'
$individualSetHpMutation = $mechanicsGoal.Replace(
    'PROC_COS_SyncDualityDelayedMarker(_Target);',
    "SetHitpoints(_Target, _FinalHitpoints, `"Guaranteed`" );`nPROC_COS_SyncDualityDelayedMarker(_Target);")
Require ($individualSetHpMutation -cne $mechanicsGoal -and
    -not (Test-DualityDelayedLifecycleContract $individualSetHpMutation)) `
    '同一 TurnStarted materialization mutation probe 必须拒绝 individual cleanup 再次 SetHitpoints'
$mappedDebtMigrationMutation = $mechanicsGoal.Replace(
    'NOT DB_COS_DualityDelayedOwner(_, _Target, _Serial)',
    'DB_COS_DualityDelayedOwner(_, _Target, _Serial)')
Require ($mappedDebtMigrationMutation -cne $mechanicsGoal -and
    -not (Test-DualityDelayedLifecycleContract $mappedDebtMigrationMutation)) `
    '旧债迁移 mutation probe 必须拒绝误清已有 owner map 的债务'

Require ((Test-DualityAggregateWriteContract $mechanicsGoal) -and
    (Test-ClearDelayedOwnerContract $mechanicsGoal) -and
    (Test-DualityDelayedLifecycleContract $mechanicsGoal) -and
    (Test-DualityMarkerContract $mechanicsGoal)) '两仪内存语义 probe 前必须先闭合源码聚合合同'
$semanticHp = 100
$semanticTargetTotal = 30
$semanticOwnerTotals = @{ A = 10; B = 20 }
$semanticDebts = @(@{ Owner = 'A'; Amount = 10 }, @{ Owner = 'B'; Amount = 20 })
$semanticMarker = $true
$semanticTargetTotal -= $semanticOwnerTotals.A
$semanticOwnerTotals.Remove('A')
$semanticDebts = @($semanticDebts | Where-Object { $_.Owner -ne 'A' })
$semanticMarker = $semanticDebts.Count -gt 0
Require ($semanticTargetTotal -eq 20 -and $semanticOwnerTotals.Count -eq 1 -and
    $semanticOwnerTotals.B -eq 20 -and $semanticDebts.Count -eq 1 -and $semanticMarker) `
    '两仪内存语义 probe：HP100、A10+B20 时清 A 后 TargetTotal 必须为20且 marker 保持'
$semanticHp = [Math]::Max(0, $semanticHp - $semanticTargetTotal)
$semanticTargetTotal = 0
$semanticOwnerTotals.Clear()
$semanticDebts = @()
$semanticMarker = $semanticDebts.Count -gt 0
Require ($semanticHp -eq 80 -and $semanticTargetTotal -eq 0 -and
    $semanticOwnerTotals.Count -eq 0 -and -not $semanticMarker) `
    '两仪内存语义 probe：结算 B 后必须只扣总额20到HP80并清 marker'

$fateArmGatePattern = 'DB_COS_ConfigMechanic\((?:\(CHARACTER\))?_Character, "Fate", 1\)'
$fateAttackGatePattern = 'DB_COS_ConfigMechanic\((?:\(CHARACTER\))?_AttackOwner, "Fate", 1\)'
$fateEffectAttackBlocks = @($dualityAttackBlocks | Where-Object {
    $_.Contains('HasActiveStatus(_AttackOwner, "COS_CHAOS_FATE_ENABLED", 1)') -and
    $_.Contains('DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)')
})
$fateRelevantBlocks = @($fateArmBlocks + $fateEffectAttackBlocks)
Require ($fateRelevantBlocks.Count -eq 5 -and $fateEffectAttackBlocks.Count -eq 4) `
    '命运改签必须保留一个武装和四个已启用/记录/多投相关攻击块'
Require-StoryGate $fateArmBlocks[0] $fateArmGatePattern '命运改签武装块必须用 _Character 要求 Fate=1'
foreach ($fateAttackBlock in $fateEffectAttackBlocks) {
    Require-StoryGate $fateAttackBlock $fateAttackGatePattern '命运改签攻击多投块必须用 _AttackOwner 要求 Fate=1'
}
Require-StoryGate $fateOffBlocks[0] $fateAttackGatePattern `
    'FATE_ENABLED=0 的普通单次 Duality 块必须要求 Fate=1，与 Fate=0 通路互斥'
Require (-not $fateDisabledBlocks[0].Contains('COS_CHAOS_FATE_ENABLED')) `
    'Fate=0 的普通单次 Duality 块不得依赖用户 FATE_ENABLED 状态'

function Test-FateEffectAttackBlock([string]$Block) {
    return $Block.Contains('AttackedBy(') -and
        $Block.Contains('HasActiveStatus(_AttackOwner, "COS_CHAOS_FATE_ENABLED", 1)') -and
        $Block.Contains('DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)')
}
function Get-FateDualityRouteBlocks([string]$StoryText) {
    $ifBlocks = @([regex]::Matches($StoryText.Replace("`r`n", "`n"), '(?ms)^IF$.*?(?=^IF$|^PROC$|\z)') | `
        ForEach-Object { $_.Value })
    return @($ifBlocks | Where-Object {
        $_.Contains('AttackedBy(_Target, _AttackOwner, _Attacker, _, _Damage, _, _StoryActionID)') -and
        $_.Contains('DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Duality", 1)')
    })
}

function Test-FateRouteMatchesState(
    [string]$Block,
    [int]$FateEnabled,
    [int]$StatusEnabled,
    [bool]$HasAction,
    [int]$PowerEnabled,
    [int]$Power
) {
    $conditions = @(Get-MechanicsConditions $Block)
    if ($conditions -contains 'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Fate", 0)' -and $FateEnabled -ne 0) { return $false }
    if ($conditions -contains 'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Fate", 1)' -and $FateEnabled -ne 1) { return $false }
    if ($conditions -contains 'HasActiveStatus(_AttackOwner, "COS_CHAOS_FATE_ENABLED", 0)' -and $StatusEnabled -ne 0) { return $false }
    if ($conditions -contains 'HasActiveStatus(_AttackOwner, "COS_CHAOS_FATE_ENABLED", 1)' -and $StatusEnabled -ne 1) { return $false }
    if ($conditions -contains 'NOT DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)' -and $HasAction) { return $false }
    if ($conditions -contains 'DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)' -and -not $HasAction) { return $false }
    if ($conditions -contains 'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Power", 0)' -and $PowerEnabled -ne 0) { return $false }
    if ($conditions -contains 'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Power", 1)' -and $PowerEnabled -ne 1) { return $false }
    if ($conditions -contains 'DB_COS_Power((CHARACTER)_AttackOwner, 0)' -and $Power -ne 0) { return $false }
    if ($conditions -contains '_OldPower >= 1' -and $Power -lt 1) { return $false }
    return $true
}

function Test-FateRouteTruthTable([string]$StoryText) {
    $routeBlocks = @(Get-FateDualityRouteBlocks $StoryText)
    if ($routeBlocks.Count -ne 6) { return $false }
    foreach ($fateEnabled in @(0, 1)) {
        foreach ($statusEnabled in @(0, 1)) {
            foreach ($hasAction in @($false, $true)) {
                foreach ($powerEnabled in @(0, 1)) {
                    foreach ($power in @(0, 1)) {
                        $matchCount = @($routeBlocks | Where-Object {
                            Test-FateRouteMatchesState $_ $fateEnabled $statusEnabled $hasAction $powerEnabled $power
                        }).Count
                        if ($matchCount -ne 1) { return $false }
                    }
                }
            }
        }
    }
    return $true
}
Require (Test-FateRouteTruthTable $mechanicsGoal) `
    'Fate 配置/用户状态/记录/资源的32个真值组合必须各自恰好匹配一个 Duality 攻击路径'
$fateDisabledDeletionMutation = $mechanicsGoal.Replace($fateDisabledBlocks[0], '')
Require ($fateDisabledDeletionMutation -cne $mechanicsGoal -and
    -not (Test-FateRouteTruthTable $fateDisabledDeletionMutation)) `
    'Fate=0 普通路径删除 mutation 必须被真值表拒绝'
$fateDisabledStatusMutationBlock = $fateDisabledBlocks[0].Replace(
    'HasPassive(_AttackOwner, "COS_ChaosDuality", 1)',
    "HasPassive(_AttackOwner, `"COS_ChaosDuality`", 1)`nAND`nHasActiveStatus(_AttackOwner, `"COS_CHAOS_FATE_ENABLED`", 0)")
$fateDisabledStatusMutation = $mechanicsGoal.Replace($fateDisabledBlocks[0], $fateDisabledStatusMutationBlock)
Require ($fateDisabledStatusMutation -cne $mechanicsGoal -and
    -not (Test-FateRouteTruthTable $fateDisabledStatusMutation)) `
    'Fate=0 普通路径错误依赖 FATE_ENABLED mutation 必须被真值表拒绝'
$fateGateRemovalProbe = $fateEffectAttackBlocks[0].Replace(
    "`nDB_COS_ConfigMechanic((CHARACTER)_AttackOwner, `"Fate`", 1)", '')
$fateGateRemovalRejected = $false
try {
    Require-StoryGate $fateGateRemovalProbe $fateAttackGatePattern '真实 Fate 效果块删除门禁后必须失败'
} catch {
    $fateGateRemovalRejected = $true
}
Require $fateGateRemovalRejected 'Fate mutation probe 必须拒绝真实效果块缺失 Fate=1'

$masteryEnabledGatePattern = 'DB_COS_ConfigMechanic\((?:\(CHARACTER\))?_Character, "Mastery", 1\)'
$masteryDisabledGatePattern = 'DB_COS_ConfigMechanic\((?:\(CHARACTER\))?_Character, "Mastery", 0\)'
$masteryIfBlocksForConfig = @([regex]::Matches($masteryGoal,
    '(?ms)^IF\n.*?(?=^IF\n|^PROC\n|^EXITSECTION\n|\z)') | ForEach-Object { $_.Value })
$masterySyncEffectBlocks = @(Get-StoryBlocks $masteryGoal 'PROC' 'PROC_COS_SyncMastery' | Where-Object {
    (Get-StoryThen $_).Contains('PROC_COS_SyncMasteryStatuses(_Character);')
})
$expectedMasterySyncEffectActions = @(
    'PROC_COS_SyncMasteryStatuses(_Character);',
    'PROC_COS_UpdateMasterySpell(_Character);'
)
function Test-MasterySyncEffectContract([string]$Block) {
    $actions = @((Get-StoryThen $Block).Replace("`r`n", "`n") -split "`n" |
        ForEach-Object { $_.Trim() } | Where-Object { $_ })
    return $actions.Count -eq 2 -and
        ($actions -join "`n") -ceq ($expectedMasterySyncEffectActions -join "`n")
}
$masteryApplyRouteBlocks = @(Get-StoryBlocks $masteryGoal 'PROC' 'PROC_COS_ApplyMasteryRouteStatus')
$masteryConsumeBlocks = @(Get-StoryBlocks $masteryGoal 'PROC' 'PROC_COS_ConsumeMasteryAvailable')
$masteryRelevantBlocks = @(
    $masterySyncEffectBlocks +
    (Get-StoryBlocks $masteryGoal 'PROC' 'PROC_COS_SyncMasteryStatuses') +
    $masteryApplyRouteBlocks +
    $masteryConsumeBlocks +
    (Get-StoryBlocks $masteryGoal 'PROC' 'PROC_COS_UpdateMasterySpell') +
    @($masteryIfBlocksForConfig | Where-Object {
        $_.Contains('CastedSpell(_Character, "Shout_COS_ChaosMasteryTune"') -or
        $_.Contains('CastedSpell(_Character, "Shout_COS_ChaosMasteryCorrect"')
    })
)
$masteryRelevantBlocks += $enabledRollTrialBlocks
$masteryRelevantBlocks += Get-StoryBlocks $mechanicsGoal 'PROC' 'PROC_COS_AddMasteryGiftWoundCandidates'
Require ($masterySyncEffectBlocks.Count -eq 1 -and `
    (Test-MasterySyncEffectContract $masterySyncEffectBlocks[0])) `
    'PROC_COS_SyncMastery 效果分支必须且只能依次同步路线状态和选择技能'
Require ($masteryApplyRouteBlocks.Count -eq 1 -and $masteryConsumeBlocks.Count -eq 1 -and `
    $masteryRelevantBlocks.Count -eq 10) `
    '掌控混沌必须严格覆盖状态 Sync、路线状态应用、可用点消费、选择技能显示、施放、轮盘和赠礼效果块'
foreach ($masteryEnabledBlock in $masteryRelevantBlocks) {
    Require-StoryGate $masteryEnabledBlock $masteryEnabledGatePattern `
        '掌控混沌显示、生效、轮盘和赠礼块必须精确具有 Mastery=1 开关门禁'
    Require (-not ($masteryEnabledBlock -match $masteryDisabledGatePattern)) `
        '掌控混沌显示、生效、轮盘和赠礼块不得出现 Mastery=0'
}
$masteryApplyRouteActions = @((Get-StoryThen $masteryApplyRouteBlocks[0]).Replace("`r`n", "`n") -split "`n" |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })
Require ($masteryApplyRouteActions.Count -eq 1 -and
    $masteryApplyRouteActions[0] -ceq 'ApplyStatus(_Character, _Status, _Duration, 100, _Character);' -and
    -not ($masteryApplyRouteBlocks[0] -match '(?m)^(?:NOT )?DB_COS_Mastery')) `
    'ApplyMasteryRouteStatus 只能在 Mastery=1 时应用计算后的路线状态，不得写账本'
$masteryConsumeActions = @((Get-StoryThen $masteryConsumeBlocks[0]).Replace("`r`n", "`n") -split "`n" |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })
$expectedMasteryConsumeActions = @(
    'NOT DB_COS_MasteryAvailableCount(_Character, _Count);',
    'DB_COS_MasteryAvailableCount(_Character, _Next);',
    'PROC_COS_UpdateMasterySpell(_Character);'
)
Require ($masteryConsumeBlocks[0].Contains('_Count > 0') -and
    $masteryConsumeBlocks[0].Contains('IntegerSubtract(_Count, 1, _Next)') -and
    $masteryConsumeActions.Count -eq 3 -and
    ($masteryConsumeActions -join "`n") -ceq ($expectedMasteryConsumeActions -join "`n")) `
    'ConsumeMasteryAvailable 只能在 Mastery=1 且可用点大于0时减一并同步选择技能'

$masterySyncUpdateRemovalProbe = $masterySyncEffectBlocks[0].Replace(
    "`nPROC_COS_UpdateMasterySpell(_Character);", '')
Require (-not (Test-MasterySyncEffectContract $masterySyncUpdateRemovalProbe)) `
    'SyncMastery UpdateMasterySpell deletion mutation probe 必须被拒绝'
$applyMasteryRouteGateRemovalProbe = $masteryApplyRouteBlocks[0].Replace(
    "`nDB_COS_ConfigMechanic((CHARACTER)_Character, `"Mastery`", 1)", '')
$applyMasteryRouteGateRemovalRejected = $false
try {
    Require-StoryGate $applyMasteryRouteGateRemovalProbe $masteryEnabledGatePattern `
        'ApplyMasteryRouteStatus 删除门禁后必须失败'
} catch {
    $applyMasteryRouteGateRemovalRejected = $true
}
Require $applyMasteryRouteGateRemovalRejected `
    'ApplyMasteryRouteStatus mutation probe 必须拒绝真实 Mastery=1 gate 被删除'
$consumeMasteryGateRemovalProbe = $masteryConsumeBlocks[0].Replace(
    "`nDB_COS_ConfigMechanic((CHARACTER)_Character, `"Mastery`", 1)", '')
$consumeMasteryGateRemovalRejected = $false
try {
    Require-StoryGate $consumeMasteryGateRemovalProbe $masteryEnabledGatePattern `
        'ConsumeMasteryAvailable 删除门禁后必须失败'
} catch {
    $consumeMasteryGateRemovalRejected = $true
}
Require $consumeMasteryGateRemovalRejected `
    'ConsumeMasteryAvailable mutation probe 必须拒绝真实 Mastery=1 gate 被删除'
$masteryAccountingProcedureNames = @(
    'PROC_COS_EnsureMasteryCounts', 'PROC_COS_AccrueMastery', 'PROC_COS_MigrateMasterySchema46To47',
    'PROC_COS_SyncMasteryAfterSchema47', 'PROC_COS_IncrementMasteryAvailable',
    'PROC_COS_GrantMasteryFrom', 'PROC_COS_ResetMastery', 'PROC_COS_ResetMasteryCarrier'
)
$masteryAccountingBlocks = @($masteryAccountingProcedureNames | ForEach-Object {
    Get-StoryBlocks $masteryGoal 'PROC' $_
})
Require ($masteryAccountingBlocks.Count -ge 12 -and `
    -not (($masteryAccountingBlocks -join "`n") -match $masteryEnabledGatePattern) -and `
    -not (($masteryAccountingBlocks -join "`n") -match $masteryDisabledGatePattern)) `
    '掌控混沌迁移、升级、Grant、可用点与Respec账本过程不得依赖 Mastery 开关'

$masteryAccountingProbe = (Get-StoryBlocks $masteryGoal 'PROC' 'PROC_COS_GrantMasteryFrom')[0]
Require (-not ($masteryAccountingProbe -match $masteryEnabledGatePattern)) `
    'Mastery accounting probe 必须允许 GrantMasteryFrom 无 Mastery=1 门禁'
$masteryGateRemovalProbe = $masteryRelevantBlocks[0].Replace(
    "`nDB_COS_ConfigMechanic((CHARACTER)_Character, `"Mastery`", 1)", '')
$masteryGateRemovalRejected = $false
try {
    Require-StoryGate $masteryGateRemovalProbe $masteryEnabledGatePattern 'Mastery 效果块删除门禁后必须失败'
} catch {
    $masteryGateRemovalRejected = $true
}
Require $masteryGateRemovalRejected 'Mastery mutation probe 必须拒绝效果块缺失 Mastery=1'
$enabledWoundGateRemovalProbe = $enabledRollTrialBlock.Replace(
    "`nDB_COS_ConfigMechanic((CHARACTER)_Character, `"Mastery`", 1)", '')
$enabledWoundGateRemovalRejected = $false
try {
    Require-StoryGate $enabledWoundGateRemovalProbe $masteryEnabledGatePattern 'Mastery=1 轮盘删除门禁后必须失败'
} catch {
    $enabledWoundGateRemovalRejected = $true
}
Require $enabledWoundGateRemovalRejected 'Mastery enabled wound mutation probe 必须拒绝缺失 Mastery=1'
$masterySuspendBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigSuspendMastery')
Require ($masterySuspendBlocks.Count -eq 1) '核心设置必须且只能定义一个 PROC_COS_ConfigSuspendMastery'
$masterySuspendBlock = $masterySuspendBlocks[0]
$masterySuspendActions = @((Get-StoryThen $masterySuspendBlock).Replace("`r`n", "`n") -split "`n" |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })
$expectedMasterySuspendActions = @(
    'RemoveStatus(_Character, "COS_CHAOS_MASTERY_TUNE", _Character);',
    'RemoveStatus(_Character, "COS_CHAOS_MASTERY_CORRECT", _Character);',
    'RemoveSpell(_Character, "Shout_COS_ChaosMastery", 1);'
)
Require ($masterySuspendActions.Count -eq 3 -and
    -not (Compare-Object ($expectedMasterySuspendActions | Sort-Object) ($masterySuspendActions | Sort-Object))) `
    'ConfigSuspendMastery 的 THEN 只能清理路线显示和掌控选择技能'
$masterySuspendCarrierMutation = $masterySuspendBlock.Replace(
    'RemoveSpell(_Character, "Shout_COS_ChaosMastery", 1);',
    "RemoveSpell(_Character, `"Shout_COS_ChaosMastery`", 1);`nRemovePassive(_Character, `"COS_ChaosMasteryGuide`");")
$masterySuspendCarrierMutationActions = @((Get-StoryThen $masterySuspendCarrierMutation).Replace("`r`n", "`n") -split "`n" |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })
Require ($masterySuspendCarrierMutation -cne $masterySuspendBlock -and
    ($masterySuspendCarrierMutationActions -join "`n") -cne ($expectedMasterySuspendActions -join "`n")) `
    'ConfigSuspendMastery mutation probe 必须拒绝移除 carriers 或 guide'
foreach ($forbiddenSuspendToken in @(
    'DB_COS_Mastery', 'Consume', 'ApplyStatus', 'AddSpell', 'CastedSpell',
    'RemovePassive', 'COS_ChaosMasteryPoint', 'COS_ChaosMasteryGuide'
)) {
    Require (-not $masterySuspendBlock.Contains($forbiddenSuspendToken)) `
        "ConfigSuspendMastery 禁止删除账本、消费、施加状态或施法: $forbiddenSuspendToken"
}
$applyMechanicBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigApplyMechanic')
function Test-ConfigStoryBlockExact([string]$Block, [string[]]$ExpectedConditions, [string[]]$ExpectedActions) {
    $actualConditions = @(Get-MechanicsConditions $Block)
    $actualActions = @((Get-StoryThen $Block).Replace("`r`n", "`n") -split "`n" |
        ForEach-Object { $_.Trim() } | Where-Object { $_ })
    return ($actualConditions -join "`n") -ceq ($ExpectedConditions -join "`n") -and
        ($actualActions -join "`n") -ceq ($ExpectedActions -join "`n")
}
$configApplySignature = 'PROC_COS_ConfigApplyMechanic((CHARACTER)_Character, (STRING)_Key, (INTEGER)_Enabled)'
$expectedConfigApplyContracts = @(
    @{
        Conditions = @($configApplySignature, '_Key == "Fate"', '_Enabled == 0')
        Actions = @('PROC_COS_ClearFateAction(_Character);')
    },
    @{
        Conditions = @($configApplySignature, '_Key == "Power"', '_Enabled == 0')
        Actions = @(
            'RemoveStatus(_Character, "COS_CHAOS_POWER_STACK", _Character);',
            'RemoveStatus(_Character, "COS_CHAOS_GENESIS_READY", _Character);'
        )
    },
    @{
        Conditions = @($configApplySignature, '_Key == "Power"', '_Enabled == 1', 'DB_COS_Power(_Character, _Power)')
        Actions = @('PROC_COS_SyncPowerDisplay(_Character, _Power);')
    },
    @{
        Conditions = @($configApplySignature, '_Key == "Genesis"', '_Enabled == 0')
        Actions = @('RemoveStatus(_Character, "COS_CHAOS_GENESIS_READY", _Character);')
    },
    @{
        Conditions = @(
            $configApplySignature, '_Key == "Genesis"', '_Enabled == 1',
            'DB_COS_ConfigMechanic(_Character, "Power", 1)', 'DB_COS_Power(_Character, _Power)'
        )
        Actions = @('PROC_COS_SyncPowerDisplay(_Character, _Power);')
    },
    @{
        Conditions = @($configApplySignature, '_Key == "AllIn"', '_Enabled == 0')
        Actions = @('PROC_COS_ClearAllIn(_Character);')
    },
    @{
        Conditions = @($configApplySignature, '_Key == "Duality"', '_Enabled == 0')
        Actions = @('PROC_COS_ClearDelayedDualityForOwner(_Character);')
    },
    @{
        Conditions = @($configApplySignature, '_Key == "Strike"', '_Enabled == 0')
        Actions = @('RemoveStatus(_Character, "COS_CHAOS_STRIKE_ACTIVE", _Character);')
    },
    @{
        Conditions = @($configApplySignature, '_Key == "Mastery"', '_Enabled == 0')
        Actions = @('PROC_COS_ConfigSuspendMastery(_Character);')
    },
    @{
        Conditions = @($configApplySignature, '_Key == "Mastery"', '_Enabled == 1')
        Actions = @('PROC_COS_SyncMastery(_Character);')
    }
)
function Test-ConfigApplyMechanicContract([string]$Story) {
    $blocks = @(Get-StoryBlocks $Story 'PROC' 'PROC_COS_ConfigApplyMechanic')
    if ($blocks.Count -ne $expectedConfigApplyContracts.Count) { return $false }
    foreach ($contract in $expectedConfigApplyContracts) {
        $matches = @($blocks | Where-Object {
            Test-ConfigStoryBlockExact $_ $contract.Conditions $contract.Actions
        })
        if ($matches.Count -ne 1) { return $false }
    }
    return $true
}
Require (Test-ConfigApplyMechanicContract $configGoal) `
    'ConfigApplyMechanic 必须严格只有 Fate0、Power0/1、Genesis0/1、AllIn0、Duality0、Strike0、Mastery0/1 十个具体副作用分支'
Require (-not (($applyMechanicBlocks -join "`n") -match 'COS_CHAOS_FATE_ENABLED') -and
    -not (($applyMechanicBlocks -join "`n") -match '(?m)^PROC_COS_ConfigSyncMechanicMirrors\(') -and
    -not (($applyMechanicBlocks -join "`n") -match '(?m)^(?:NOT )?DB_COS_Mastery')) `
    'ConfigApplyMechanic 不得删除用户 Fate 状态、逐键同步镜像或写 Mastery 账本'

$resetCoreBlocks = @(Get-StoryBlocks $configGoal 'PROC' 'PROC_COS_ConfigResetCore')
$resetCoreConditions = @(
    'PROC_COS_ConfigResetCore((CHARACTER)_Character)',
    'DB_COS_ConfigMechanicDefault(_Key, _Default)',
    'DB_COS_ConfigMechanic(_Character, _Key, _Enabled)'
)
$resetCoreActions = @(
    'NOT DB_COS_ConfigMechanic(_Character, _Key, _Enabled);',
    'DB_COS_ConfigMechanic(_Character, _Key, _Default);',
    'PROC_COS_ConfigApplyMechanic(_Character, _Key, _Default);'
)
$resetEventConditions = @(
    'TutorialEvent(_Character, _Event)',
    'DB_COS_ConfigResetCoreEvent(_Event)',
    'HasPassive(_Character, "COS_ChaosOriginMarker", 1)',
    'IsControlled(_Character, 1)',
    'IsInCombat(_Character, 0)'
)
$resetEventActions = @(
    'PROC_COS_ConfigResetCore(_Character);',
    'PROC_COS_ConfigSyncMechanicMirrors(_Character);'
)
function Test-ConfigResetStoryContract([string]$Story) {
    $procBlocks = @(Get-StoryBlocks $Story 'PROC' 'PROC_COS_ConfigResetCore')
    $eventBlocks = @(Get-AllStoryBlocks $Story | Where-Object {
        $_.StartsWith("IF`n") -and $_.Contains('DB_COS_ConfigResetCoreEvent(_Event)')
    })
    return $procBlocks.Count -eq 1 -and $eventBlocks.Count -eq 1 -and
        (Test-ConfigStoryBlockExact $procBlocks[0] $resetCoreConditions $resetCoreActions) -and
        (Test-ConfigStoryBlockExact $eventBlocks[0] $resetEventConditions $resetEventActions)
}
Require (Test-ConfigResetStoryContract $configGoal) `
    'ResetCore 必须逐键写默认值并 Apply，且固定事件返回后只同步一次镜像'

function Require-ConfigApplyMutationRejected([string]$Mutation, [string]$Message) {
    Require ($Mutation -cne $configGoal -and -not (Test-ConfigApplyMechanicContract $Mutation)) $Message
}
function Require-ConfigResetMutationRejected([string]$Mutation, [string]$Message) {
    Require ($Mutation -cne $configGoal -and -not (Test-ConfigResetStoryContract $Mutation)) $Message
}
$configApplyFateDeletionMutation = $configGoal.Replace(
    "THEN`nPROC_COS_ClearFateAction(_Character);",
    'THEN')
Require-ConfigApplyMutationRejected $configApplyFateDeletionMutation `
    'ConfigApplyMechanic mutation probe 必须拒绝 Fate0 缺失 ClearFateAction'
$configApplyFateStatusMutation = $configGoal.Replace(
    'PROC_COS_ClearFateAction(_Character);',
    "PROC_COS_ClearFateAction(_Character);`nRemoveStatus(_Character, `"COS_CHAOS_FATE_ENABLED`", _Character);")
Require-ConfigApplyMutationRejected $configApplyFateStatusMutation `
    'ConfigApplyMechanic mutation probe 必须拒绝 Fate0 删除用户 FATE_ENABLED 状态'
$configApplyPowerCleanupMutation = $configGoal.Replace(
    "RemoveStatus(_Character, `"COS_CHAOS_POWER_STACK`", _Character);`nRemoveStatus(_Character, `"COS_CHAOS_GENESIS_READY`", _Character);",
    'RemoveStatus(_Character, "COS_CHAOS_POWER_STACK", _Character);')
Require-ConfigApplyMutationRejected $configApplyPowerCleanupMutation `
    'ConfigApplyMechanic mutation probe 必须拒绝 Power0 未同时清理 Power 与 READY 显示'
$configApplyPowerSyncMutation = $configGoal.Replace(
    "_Key == `"Power`"`nAND`n_Enabled == 1`nAND`nDB_COS_Power(_Character, _Power)`nTHEN`nPROC_COS_SyncPowerDisplay(_Character, _Power);",
    "_Key == `"Power`"`nAND`n_Enabled == 1`nAND`nDB_COS_Power(_Character, _Power)`nTHEN")
Require-ConfigApplyMutationRejected $configApplyPowerSyncMutation `
    'ConfigApplyMechanic mutation probe 必须拒绝 Power1 缺失账本显示同步'
$configApplyGenesisPowerMutation = $configGoal.Replace(
    "AND`nDB_COS_Power(_Character, _Power)`nTHEN`nPROC_COS_SyncPowerDisplay(_Character, _Power);",
    "THEN`nPROC_COS_SyncPowerDisplay(_Character, _Power);")
Require-ConfigApplyMutationRejected $configApplyGenesisPowerMutation `
    'ConfigApplyMechanic mutation probe 必须拒绝 Genesis1 缺失当前 Power 条件'
$configApplyGenesisReadyDeletionMutation = $configGoal.Replace(
    "THEN`nRemoveStatus(_Character, `"COS_CHAOS_GENESIS_READY`", _Character);",
    'THEN')
Require-ConfigApplyMutationRejected $configApplyGenesisReadyDeletionMutation `
    'ConfigApplyMechanic mutation probe 必须拒绝 Genesis0 缺失 ready 清理'
$configApplyGenesisPowerConfigMutation = $configGoal.Replace(
    "_Key == `"Genesis`"`nAND`n_Enabled == 1`nAND`nDB_COS_ConfigMechanic(_Character, `"Power`", 1)",
    "_Key == `"Genesis`"`nAND`n_Enabled == 1")
Require-ConfigApplyMutationRejected $configApplyGenesisPowerConfigMutation `
    'ConfigApplyMechanic mutation probe 必须拒绝 Genesis1 缺失 Power=1'
$configApplyAllInCleanupMutation = $configGoal.Replace(
    "_Key == `"AllIn`"`nAND`n_Enabled == 0`nTHEN`nPROC_COS_ClearAllIn(_Character);",
    "_Key == `"AllIn`"`nAND`n_Enabled == 0`nTHEN")
Require-ConfigApplyMutationRejected $configApplyAllInCleanupMutation `
    'ConfigApplyMechanic mutation probe 必须拒绝 AllIn0 缺失当前孤注状态清理'
$configApplyDualityCleanupMutation = $configGoal.Replace(
    "_Key == `"Duality`"`nAND`n_Enabled == 0`nTHEN`nPROC_COS_ClearDelayedDualityForOwner(_Character);",
    "_Key == `"Duality`"`nAND`n_Enabled == 0`nTHEN")
Require-ConfigApplyMutationRejected $configApplyDualityCleanupMutation `
    'ConfigApplyMechanic mutation probe 必须拒绝 Duality0 缺失本角色延迟债务清理'
$configApplyStrikeCleanupMutation = $configGoal.Replace(
    "_Key == `"Strike`"`nAND`n_Enabled == 0`nTHEN`nRemoveStatus(_Character, `"COS_CHAOS_STRIKE_ACTIVE`", _Character);",
    "_Key == `"Strike`"`nAND`n_Enabled == 0`nTHEN")
Require-ConfigApplyMutationRejected $configApplyStrikeCleanupMutation `
    'ConfigApplyMechanic mutation probe 必须拒绝 Strike0 缺失当前裁决状态清理'
$configApplyMasteryLedgerMutation = $configGoal.Replace(
    'PROC_COS_ConfigSuspendMastery(_Character);',
    'NOT DB_COS_MasteryTuneCount(_Character, _Count);')
Require-ConfigApplyMutationRejected $configApplyMasteryLedgerMutation `
    'ConfigApplyMechanic mutation probe 必须拒绝 Mastery0 写路线账本'
$configApplyMasterySyncDeletionMutation = $configGoal.Replace(
    "_Key == `"Mastery`"`nAND`n_Enabled == 1`nTHEN`nPROC_COS_SyncMastery(_Character);",
    "_Key == `"Mastery`"`nAND`n_Enabled == 1`nTHEN")
Require-ConfigApplyMutationRejected $configApplyMasterySyncDeletionMutation `
    'ConfigApplyMechanic mutation probe 必须拒绝 Mastery1 缺失 SyncMastery'
$genericApplyMirrorBlock = @"
PROC
PROC_COS_ConfigApplyMechanic((CHARACTER)_Character, (STRING)_Key, (INTEGER)_Enabled)
THEN
PROC_COS_ConfigSyncMechanicMirrors(_Character);

"@
$configApplyGenericMirrorMutation = $configGoal.Replace(
    "PROC`nPROC_COS_ConfigToggleMechanic((CHARACTER)_Character, (STRING)_Key)",
    $genericApplyMirrorBlock + "PROC`nPROC_COS_ConfigToggleMechanic((CHARACTER)_Character, (STRING)_Key)")
Require-ConfigApplyMutationRejected $configApplyGenericMirrorMutation `
    'ConfigApplyMechanic mutation probe 必须拒绝恢复 generic per-key mirror 分支'

$resetApplyDeletionMutation = $configGoal.Replace(
    "`nPROC_COS_ConfigApplyMechanic(_Character, _Key, _Default);",
    '')
Require-ConfigResetMutationRejected $resetApplyDeletionMutation `
    'ResetCore mutation probe 必须拒绝逐键缺失 ApplyMechanic'
$resetPerKeyMirrorMutation = $configGoal.Replace(
    'PROC_COS_ConfigApplyMechanic(_Character, _Key, _Default);',
    "PROC_COS_ConfigApplyMechanic(_Character, _Key, _Default);`nPROC_COS_ConfigSyncMechanicMirrors(_Character);")
Require-ConfigResetMutationRejected $resetPerKeyMirrorMutation `
    'ResetCore mutation probe 必须拒绝逐键同步镜像'
$resetEventMirrorDeletionMutation = $configGoal.Replace(
    "PROC_COS_ConfigResetCore(_Character);`nPROC_COS_ConfigSyncMechanicMirrors(_Character);",
    'PROC_COS_ConfigResetCore(_Character);')
Require-ConfigResetMutationRejected $resetEventMirrorDeletionMutation `
    'Reset event mutation probe 必须拒绝返回后缺失唯一镜像同步'
[xml]$tutorialEventsDocument = Get-Content -LiteralPath $tutorialEventsPath -Raw -Encoding UTF8
$tutorialEventNodes = @($tutorialEventsDocument.SelectNodes('//node[@id="TutorialEvent"]'))
$expectedTutorialEvents = [ordered]@{
    COS_CFG_UI_OPENED = '65247962-a3b0-417d-9044-85e4aad38079'
    COS_CFG_MECH_POWER = '7f818c10-3f23-49f8-838a-d161c57bb35d'
    COS_CFG_MECH_WOUND = '0574b4b8-549a-4b39-b810-6890c68642b1'
    COS_CFG_MECH_KILLPOWER = '71abdeef-69d2-4385-8885-4f9ebbd829ca'
    COS_CFG_MECH_DUALITY = 'aa88abcb-5f2e-452c-bdce-3ca6176db1e0'
    COS_CFG_MECH_ALLIN = '2dd4ef80-1686-4989-8773-3cf6f12b9a36'
    COS_CFG_MECH_FATE = 'aff82c28-d71a-4dad-837d-d41d8519051a'
    COS_CFG_MECH_GENESIS = '063cc1a5-fe65-43e5-8531-d6974a7b1dce'
    COS_CFG_MECH_STRIKE = '78baf203-f60c-4dac-99ea-a7f5d1339d71'
    COS_CFG_MECH_MASTERY = '146d28dc-aa94-40e8-9bad-91b069055526'
    COS_CFG_RESET_CORE = '08c8d67a-ace5-4830-8c2b-38b8c92bb470'
    COS_CFG_LIFE_MINUS = 'e438f411-6a7e-4060-9e0b-c7f6c26e751a'
    COS_CFG_LIFE_PLUS = 'ddcf4293-e7d1-4154-a9c4-19fa24a35f38'
    COS_CFG_LIFE_RESET = '563ba5fe-c808-4a2f-80b5-a1b4feb54649'
    COS_CFG_RACE_ALL = 'e0927578-b7bd-42d8-b497-4f6fa2d57053'
    COS_CFG_RACE_NONE = '8d98892a-4cc3-4fb3-88b0-7bcbff3d7abe'
    COS_CFG_RACE_DEEPGNOME_STONE = '2535def3-de94-4a94-b5be-b7e08e143709'
    COS_CFG_RACE_DROW_WEAPON = '712d9a0d-7d5f-4f42-a808-cd2dfb9e3685'
    COS_CFG_RACE_DUERGAR_RESILIENCE = 'd523163f-95a3-459b-92f4-59b9dc499b75'
    COS_CFG_RACE_DWARF_WEAPON = 'dd78b5d4-1cab-48eb-91b6-583b00eede31'
    COS_CFG_RACE_DWARF_RESILIENCE = '6394ac5c-d9ae-4fe8-94bb-88900fc50d46'
    COS_CFG_RACE_ELF_WEAPON = '0aab1270-5408-4fc2-a473-9f6c893f018a'
    COS_CFG_RACE_FEY_ANCESTRY = '342a9ee6-2aec-4448-885c-8724af4d6c6b'
    COS_CFG_RACE_GITH_MARTIAL = '8a7fb402-80c6-424e-a90c-a627bf6187e8'
    COS_CFG_RACE_GNOME_CUNNING = '50b71015-0ed0-4b12-8f46-322e5c9de3fe'
    COS_CFG_RACE_HALFLING_BRAVE = '7937b010-b9cb-4a6b-b732-33e12a5e08a3'
    COS_CFG_RACE_HALFLING_LIGHTFOOT = 'aa96a380-d8a4-475e-ac9e-b24502b914aa'
    COS_CFG_RACE_HALFLING_LUCKY = 'ed99bd77-fd4e-4bbc-80d1-de2b125ce4ce'
    COS_CFG_RACE_HALFLING_STOUT = '69bf2c6d-7e8c-4dc6-91cd-8ef359b8bcd1'
    COS_CFG_RACE_HUMAN_MILITIA = 'a18a929b-1faa-44ac-b364-b03858bd6504'
    COS_CFG_RACE_MOUNTAIN_DWARF_ARMOR = 'a99eb828-5907-489d-8492-81e833c25e68'
    COS_CFG_RACE_RELENTLESS = '8ddf3765-2814-4085-a0e1-376aaf9d984c'
    COS_CFG_RACE_ROCK_GNOME_LORE = 'b227b0fd-026e-4931-af70-dd436277ddc0'
    COS_CFG_RACE_SAVAGE_ATTACKS = '108ff1c7-b025-46cc-8b10-e9729e3fb4c3'
    COS_CFG_RACE_SUPERIOR_DARKVISION = 'c0888d3b-4c97-4c50-95b9-34620ba1fdef'
    COS_CFG_RACE_TIEFLING_RESISTANCE = '022d736c-8b4b-4599-9e51-e584a0e1c05d'
}
Require ($tutorialEventNodes.Count -eq 36) 'TutorialEvents 必须且只能包含36个 TutorialEvent node'
foreach ($tutorialEvent in $expectedTutorialEvents.GetEnumerator()) {
    $matches = @($tutorialEventNodes | Where-Object {
        $_.SelectSingleNode('./attribute[@id="Name"]').value -eq $tutorialEvent.Key -and
        $_.SelectSingleNode('./attribute[@id="UUID"]').value -eq $tutorialEvent.Value -and
        $_.SelectSingleNode('./attribute[@id="EventType"]').value -eq '8'
    })
    Require ($matches.Count -eq 1) "TutorialEvent Name/UUID/EventType 不匹配: $($tutorialEvent.Key)"
}
$formalFiles = @(
    (Join-Path $root "Mods\$module\meta.lsx"),
    $goalPath,
    $masteryGoalPath,
    $mechanicsGoalPath,
    $rewardGoalPath,
    (Join-Path $root "Public\$module\Origins\Origins.lsx"),
    $masteryStatsPath,
    (Join-Path $root "Public\$module\Stats\Generated\Data\Passive.txt"),
    (Join-Path $root "Public\$module\Stats\Generated\Data\Status_BOOST.txt")
) | ForEach-Object { Get-Item -LiteralPath $_ }
foreach ($file in $formalFiles) {
    $text = [IO.File]::ReadAllText($file.FullName)
    Require (-not ($text -match 'ScriptExtender|MCM|TutorialEvent|COS_ChaosIdentity|COS_ChaosStatus')) `
        "创建后同步源夹带了后续系统: $($file.FullName)"
}

$textureBankSourcePath = Join-Path $root 'resource-src\Public\ChaosOriginsStory\Content\UI\[PAK]_ChaosOriginsStory\_merged.lsf.lsx'
$resourceSources = @(Get-ChildItem -LiteralPath (Join-Path $root 'resource-src') -Recurse -File -Filter '*.lsx')
$guiRoot = Join-Path $root "Mods\$module\GUI"
$guiRelativePaths = @(
    'Pages/COS_ConfigEscButton.xaml',
    'Pages/COS_ConfigEscButton_c.xaml',
    'Pages/COS_ConfigMenu.xaml',
    'Pages/COS_ConfigMenu_c.xaml',
    'StateMachines/Keyboard.xaml',
    'StateMachines/Controller.xaml'
)
foreach ($relative in $guiRelativePaths) {
    $path = Join-Path $guiRoot $relative
    Require (Test-Path -LiteralPath $path -PathType Leaf) "缺少原生菜单空壳: $relative"
    $guiText = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    [void][xml]$guiText
}

$stateMachineSpecs = @(
    @{ Path = 'StateMachines\Keyboard.xaml'; Entry = 'COS_ConfigEscButton.xaml'; Page = 'COS_ConfigMenu.xaml' },
    @{ Path = 'StateMachines\Controller.xaml'; Entry = 'COS_ConfigEscButton_c.xaml'; Page = 'COS_ConfigMenu_c.xaml' }
)
foreach ($stateMachineSpec in $stateMachineSpecs) {
    $stateMachinePath = Join-Path $guiRoot $stateMachineSpec.Path
    $stateText = [IO.File]::ReadAllText($stateMachinePath)
    [xml]$stateMachineDocument = $stateText
    $states = @($stateMachineDocument.SelectNodes('//*[local-name()="State"]'))
    $actualStateNames = @($states | ForEach-Object { $_.GetAttribute('Name') } | Sort-Object)
    $expectedStateNames = @('COS_CFG_MENU', 'Paused', 'SystemUIs')
    Require ($states.Count -eq 3 -and -not (Compare-Object $expectedStateNames $actualStateNames)) `
        "状态机必须且只能定义 Paused、SystemUIs 和 COS_CFG_MENU: $($stateMachineSpec.Path)"
    $pausedState = @($states | Where-Object { $_.GetAttribute('Name') -eq 'Paused' })
    $systemUisState = @($states | Where-Object { $_.GetAttribute('Name') -eq 'SystemUIs' })
    $configMenuState = @($states | Where-Object { $_.GetAttribute('Name') -eq 'COS_CFG_MENU' })
    Require ($pausedState.Count -eq 1 -and $pausedState[0].GetAttribute('ModType') -eq 'Extend' -and
        $systemUisState.Count -eq 1 -and $systemUisState[0].GetAttribute('ModType') -eq 'Extend') `
        "Paused 和 SystemUIs 必须使用 ModType=Extend: $($stateMachineSpec.Path)"
    $extendedStateNames = @($states | Where-Object { $_.GetAttribute('ModType') -eq 'Extend' } | ForEach-Object { $_.GetAttribute('Name') } | Sort-Object)
    Require ($extendedStateNames.Count -eq 2 -and -not (Compare-Object @('Paused', 'SystemUIs') $extendedStateNames)) `
        "只有 Paused 和 SystemUIs 可以使用 ModType=Extend: $($stateMachineSpec.Path)"
    Require ($configMenuState.Count -eq 1 -and $configMenuState[0].GetAttribute('ModType') -ne 'Extend' -and
        $configMenuState[0].GetAttribute('Layout') -eq 'Common' -and
        $configMenuState[0].GetAttribute('Owner') -eq 'All' -and
        $configMenuState[0].GetAttribute('DisableStatesBelow') -eq 'True' -and
        $configMenuState[0].GetAttribute('IsModal') -eq 'True' -and
        $configMenuState[0].GetAttribute('HideStatesBelow') -eq 'True') `
        "COS_CFG_MENU 必须是独立 Common/All 模态状态: $($stateMachineSpec.Path)"
    $entryWidgets = @($pausedState[0].SelectNodes('.//*[local-name()="StateWidget"]') |
        Where-Object { $_.GetAttribute('Filename') -eq $stateMachineSpec.Entry })
    Require ($entryWidgets.Count -eq 1) "暂停状态未引用正确入口: $($stateMachineSpec.Path)"
    $pageWidgets = @($configMenuState[0].SelectNodes('.//*[local-name()="StateWidget"]') |
        Where-Object { $_.GetAttribute('Filename') -eq $stateMachineSpec.Page })
    Require ($pageWidgets.Count -eq 1) "COS_CFG_MENU 未引用正确空壳页: $($stateMachineSpec.Path)"
    $openConfigEvents = @($systemUisState[0].SelectNodes('.//*[local-name()="StateEvent"]') |
        Where-Object { $_.GetAttribute('Name') -eq 'OpenCOSConfig' })
    Require ($openConfigEvents.Count -eq 1) "SystemUIs 必须定义唯一 OpenCOSConfig 事件: $($stateMachineSpec.Path)"
    $openConfigSubstates = @($openConfigEvents[0].SelectNodes('.//*[local-name()="AddSubstate"]'))
    Require ($openConfigSubstates.Count -eq 1 -and
        $openConfigSubstates[0].GetAttribute('Name') -eq 'COS_CFG_MENU') `
        "OpenCOSConfig 必须只打开 COS_CFG_MENU: $($stateMachineSpec.Path)"
    $closeEvents = @($configMenuState[0].SelectNodes('./*[local-name()="State.Events"]/*[local-name()="StateEvent"]') |
        Where-Object { $_.GetAttribute('Name') -in @('CloseWidget', 'CloseAll') })
    foreach ($closeEventName in @('CloseWidget', 'CloseAll')) {
        $closeEvent = @($closeEvents | Where-Object { $_.GetAttribute('Name') -eq $closeEventName })
        Require ($closeEvent.Count -eq 1) `
            "COS_CFG_MENU 必须定义唯一 $closeEventName 关闭事件: $($stateMachineSpec.Path)"
        $closeActions = @($closeEvent[0].SelectNodes('./*[local-name()="StateEvent.Actions"]/*'))
        Require ($closeActions.Count -eq 1 -and $closeActions[0].LocalName -eq 'RemoveState') `
            "COS_CFG_MENU 的 $closeEventName 必须只有一个直接 RemoveState 动作: $($stateMachineSpec.Path)"
    }
}

$entrySpecs = @(
    @{ Path = 'Pages\COS_ConfigEscButton.xaml'; IsController = $false },
    @{ Path = 'Pages\COS_ConfigEscButton_c.xaml'; IsController = $true }
)
foreach ($entrySpec in $entrySpecs) {
    [xml]$entryDocument = Get-Content -LiteralPath (Join-Path $guiRoot $entrySpec.Path) -Raw -Encoding UTF8
    $openConfigButtons = @($entryDocument.SelectNodes('//*[local-name()="LSButton"]') |
        Where-Object { $_.GetAttribute('CommandParameter') -eq 'OpenCOSConfig' })
    Require ($openConfigButtons.Count -eq 1) `
        "暂停菜单入口必须由唯一 LSButton 发送 OpenCOSConfig: $($entrySpec.Path)"
    Require ($openConfigButtons[0].GetAttribute('Command') -eq '{Binding CustomEvent}') `
        "暂停菜单入口必须由 LSButton 绑定 CustomEvent: $($entrySpec.Path)"
    $entryTitleBinding = $openConfigButtons[0].GetAttribute('Content') + $openConfigButtons[0].GetAttribute('Tag')
    Require ($entryTitleBinding.Contains('hc05fd001g0000g4000g8000g000000000000')) `
        "暂停菜单入口必须绑定既有四语标题: $($entrySpec.Path)"
    if ($entrySpec.IsController) {
        Require ($openConfigButtons[0].GetAttribute('BoundEvent') -eq 'UIShowInfo') `
            '手柄入口必须由实际 LSButton 绑定 UIShowInfo'
    }
}

$xamlNamespace = 'http://schemas.microsoft.com/winfx/2006/xaml'
$tutorialEventCommandBinding = '{Binding DataContext.TutorialEvent, RelativeSource={RelativeSource AncestorType={x:Type ls:UIWidget}}}'
$expectedConfigRows = [ordered]@{
    Power = @{ Uuid = '7f818c10-3f23-49f8-838a-d161c57bb35d'; Mirror = 'COS_CFG_MECH_POWER' }
    Wound = @{ Uuid = '0574b4b8-549a-4b39-b810-6890c68642b1'; Mirror = 'COS_CFG_MECH_WOUND' }
    KillPower = @{ Uuid = '71abdeef-69d2-4385-8885-4f9ebbd829ca'; Mirror = 'COS_CFG_MECH_KILLPOWER' }
    Duality = @{ Uuid = 'aa88abcb-5f2e-452c-bdce-3ca6176db1e0'; Mirror = 'COS_CFG_MECH_DUALITY' }
    AllIn = @{ Uuid = '2dd4ef80-1686-4989-8773-3cf6f12b9a36'; Mirror = 'COS_CFG_MECH_ALLIN' }
    Fate = @{ Uuid = 'aff82c28-d71a-4dad-837d-d41d8519051a'; Mirror = 'COS_CFG_MECH_FATE' }
    Genesis = @{ Uuid = '063cc1a5-fe65-43e5-8531-d6974a7b1dce'; Mirror = 'COS_CFG_MECH_GENESIS' }
    Strike = @{ Uuid = '78baf203-f60c-4dac-99ea-a7f5d1339d71'; Mirror = 'COS_CFG_MECH_STRIKE' }
    Mastery = @{ Uuid = '146d28dc-aa94-40e8-9bad-91b069055526'; Mirror = 'COS_CFG_MECH_MASTERY' }
}
$expectedRacialConfigRows = [ordered]@{
    DeepGnomeStone = @{ Uuid = '2535def3-de94-4a94-b5be-b7e08e143709'; Mirror = 'COS_CFG_RACE_DEEPGNOME_STONE' }
    DrowWeapon = @{ Uuid = '712d9a0d-7d5f-4f42-a808-cd2dfb9e3685'; Mirror = 'COS_CFG_RACE_DROW_WEAPON' }
    DuergarResilience = @{ Uuid = 'd523163f-95a3-459b-92f4-59b9dc499b75'; Mirror = 'COS_CFG_RACE_DUERGAR_RESILIENCE' }
    DwarfWeapon = @{ Uuid = 'dd78b5d4-1cab-48eb-91b6-583b00eede31'; Mirror = 'COS_CFG_RACE_DWARF_WEAPON' }
    DwarfResilience = @{ Uuid = '6394ac5c-d9ae-4fe8-94bb-88900fc50d46'; Mirror = 'COS_CFG_RACE_DWARF_RESILIENCE' }
    ElfWeapon = @{ Uuid = '0aab1270-5408-4fc2-a473-9f6c893f018a'; Mirror = 'COS_CFG_RACE_ELF_WEAPON' }
    FeyAncestry = @{ Uuid = '342a9ee6-2aec-4448-885c-8724af4d6c6b'; Mirror = 'COS_CFG_RACE_FEY_ANCESTRY' }
    GithMartial = @{ Uuid = '8a7fb402-80c6-424e-a90c-a627bf6187e8'; Mirror = 'COS_CFG_RACE_GITH_MARTIAL' }
    GnomeCunning = @{ Uuid = '50b71015-0ed0-4b12-8f46-322e5c9de3fe'; Mirror = 'COS_CFG_RACE_GNOME_CUNNING' }
    HalflingBrave = @{ Uuid = '7937b010-b9cb-4a6b-b732-33e12a5e08a3'; Mirror = 'COS_CFG_RACE_HALFLING_BRAVE' }
    HalflingLightfoot = @{ Uuid = 'aa96a380-d8a4-475e-ac9e-b24502b914aa'; Mirror = 'COS_CFG_RACE_HALFLING_LIGHTFOOT' }
    HalflingLucky = @{ Uuid = 'ed99bd77-fd4e-4bbc-80d1-de2b125ce4ce'; Mirror = 'COS_CFG_RACE_HALFLING_LUCKY' }
    HalflingStout = @{ Uuid = '69bf2c6d-7e8c-4dc6-91cd-8ef359b8bcd1'; Mirror = 'COS_CFG_RACE_HALFLING_STOUT' }
    HumanMilitia = @{ Uuid = 'a18a929b-1faa-44ac-b364-b03858bd6504'; Mirror = 'COS_CFG_RACE_HUMAN_MILITIA' }
    MountainDwarfArmor = @{ Uuid = 'a99eb828-5907-489d-8492-81e833c25e68'; Mirror = 'COS_CFG_RACE_MOUNTAIN_DWARF_ARMOR' }
    Relentless = @{ Uuid = '8ddf3765-2814-4085-a0e1-376aaf9d984c'; Mirror = 'COS_CFG_RACE_RELENTLESS' }
    RockGnomeLore = @{ Uuid = 'b227b0fd-026e-4931-af70-dd436277ddc0'; Mirror = 'COS_CFG_RACE_ROCK_GNOME_LORE' }
    SavageAttacks = @{ Uuid = '108ff1c7-b025-46cc-8b10-e9729e3fb4c3'; Mirror = 'COS_CFG_RACE_SAVAGE_ATTACKS' }
    SuperiorDarkvision = @{ Uuid = 'c0888d3b-4c97-4c50-95b9-34620ba1fdef'; Mirror = 'COS_CFG_RACE_SUPERIOR_DARKVISION' }
    TieflingResistance = @{ Uuid = '022d736c-8b4b-4599-9e51-e584a0e1c05d'; Mirror = 'COS_CFG_RACE_TIEFLING_RESISTANCE' }
}
function Get-XamlNamedNodes([xml]$Document, [string]$Name) {
    return @($Document.SelectNodes('//*') | Where-Object {
        $_.GetAttribute('Name', $xamlNamespace) -eq $Name
    })
}
function Require-TutorialEventAction([System.Xml.XmlElement]$Action, [string]$Uuid, [string]$Message) {
    Require ($Action.GetAttribute('CommandParameter') -eq $Uuid -and
        $Action.GetAttribute('Command') -eq $tutorialEventCommandBinding) $Message
}
function Test-ConfigResetContract([xml]$Document, [string]$PageName) {
    $resetButtons = @(Get-XamlNamedNodes $Document 'COSConfigResetCore')
    Require ($resetButtons.Count -eq 1 -and $resetButtons[0].LocalName -eq 'LSButton') `
        "核心设置重置控件必须是唯一命名的 LSButton: $PageName"
    $resetButton = $resetButtons[0]
    $resetTriggers = @($resetButton.SelectNodes('.//*[local-name()="EventTrigger"]'))
    Require ($resetTriggers.Count -eq 1 -and $resetTriggers[0].GetAttribute('EventName') -eq 'Click') `
        "核心设置重置 LSButton 必须只用 Click EventTrigger: $PageName"
    $resetActions = @($resetTriggers[0].SelectNodes('.//*[local-name()="InvokeCommandAction"]'))
    Require ($resetActions.Count -eq 1) "核心设置重置 Click EventTrigger 必须恰好一个 InvokeCommandAction: $PageName"
    Require-TutorialEventAction $resetActions[0] $expectedTutorialEvents.COS_CFG_RESET_CORE `
        "核心设置重置按钮必须发送 COS_CFG_RESET_CORE: $PageName"
    if ($PageName -eq 'COS_ConfigMenu_c.xaml') {
        $resetRows = @(Get-XamlNamedNodes $Document 'COSConfigResetRow')
        Require ($resetRows.Count -eq 1 -and $resetRows[0].LocalName -eq 'ContentControl' -and
            [object]::ReferenceEquals($resetRows[0], $resetButton.ParentNode)) `
            "手柄核心设置重置必须由唯一命名的父 ContentControl 承载: $PageName"
        Require ($resetRows[0].GetAttribute('Focusable') -eq 'True' -and
            $resetRows[0].GetAttribute('ls:MoveFocus.Focusable') -eq 'True') `
            "手柄核心设置重置父行必须参与焦点移动: $PageName"
        Require ($resetButton.GetAttribute('BoundEvent') -eq 'UIAccept') `
            "手柄核心设置重置 LSButton 必须绑定 UIAccept: $PageName"
        Require ($resetButton.GetAttribute('Focusable') -eq 'False' -and
            $resetButton.GetAttribute('ls:MoveFocus.Focusable') -eq 'False') `
            "手柄核心设置重置子按钮不得参与焦点移动: $PageName"
        Require ($resetButton.GetAttribute('IsEnabled') -eq
            '{Binding Path=(ls:MoveFocus.IsFocused), ElementName=COSConfigResetRow}') `
            "手柄核心设置重置子按钮必须只在父行聚焦时启用: $PageName"
    } else {
        Require (-not $resetButton.HasAttribute('BoundEvent')) `
            "键鼠核心设置重置 LSButton 不得伪造 BoundEvent 激活: $PageName"
    }
}
function Test-ConfigRowContract([xml]$Document, [string]$Key, [string]$Uuid, [string]$Mirror, [string]$PageName) {
    $rowNodes = @(Get-XamlNamedNodes $Document "COSConfigRow$Key")
    Require ($rowNodes.Count -eq 1) "核心设置行必须唯一命名为 COSConfigRow${Key}: $PageName"
    $row = $rowNodes[0]
    if ($PageName -eq 'COS_ConfigMenu_c.xaml') {
        Require ($row.LocalName -eq 'ContentControl' -and
            $row.GetAttribute('Focusable') -eq 'True' -and
            $row.GetAttribute('ls:MoveFocus.Focusable') -eq 'True') `
            "手柄核心设置父行必须是可聚焦 ContentControl: COSConfigRow$Key/$PageName"
    }
    $rowActions = @($row.SelectNodes('.//*[local-name()="InvokeCommandAction"]'))
    Require ($rowActions.Count -eq 1) "核心设置行必须恰好一个 InvokeCommandAction: COSConfigRow$Key/$PageName"
    Require-TutorialEventAction $rowActions[0] $Uuid "核心设置行必须绑定固定 TutorialEvent UUID: COSConfigRow$Key/$PageName"

    $buttonNodes = @($row.SelectNodes('.//*') | Where-Object {
        $_.GetAttribute('Name', $xamlNamespace) -eq "COSConfigToggle$Key"
    })
    Require ($buttonNodes.Count -eq 1 -and $buttonNodes[0].LocalName -eq 'LSToggleButton') `
        "核心设置事件控件必须是唯一命名的原生 LSToggleButton: COSConfigToggle${Key}: $PageName"
    $button = $buttonNodes[0]
    Require ($button.GetAttribute('Width') -ne '160' -and
        $button.GetAttribute('Style') -notmatch 'BrownButtonStyle') `
        "核心设置切换框不得使用会被裁切的160宽 BrownButton: COSConfigToggle$Key/$PageName"
    $boxImages = @($button.SelectNodes('.//*[local-name()="Image"]') | Where-Object {
        $_.GetAttribute('Source') -eq 'pack://application:,,,/Core;component/Assets/Options/checkBox_d.png'
    })
    Require ($boxImages.Count -eq 1) `
        "核心设置 LSToggleButton 必须显示原生未勾选框: COSConfigToggle$Key/$PageName"
    $hoverSetters = @($button.SelectNodes('.//*[local-name()="Trigger"]/*[local-name()="Setter"]') | Where-Object {
        $_.GetAttribute('TargetName') -eq 'ToggleBox' -and
        $_.GetAttribute('Property') -eq 'Source' -and
        $_.GetAttribute('Value') -eq 'pack://application:,,,/Core;component/Assets/Options/checkBox_h.png'
    })
    Require ($hoverSetters.Count -eq 1) `
        "核心设置 LSToggleButton 悬停时必须使用原生高亮框: COSConfigToggle$Key/$PageName"
    $buttonTriggers = @($button.SelectNodes('.//*[local-name()="EventTrigger"]'))
    Require ($buttonTriggers.Count -eq 1 -and $buttonTriggers[0].GetAttribute('EventName') -eq 'Click') `
        "核心设置 LSButton 必须只用 Click EventTrigger: COSConfigToggle$Key/$PageName"
    $buttonActions = @($buttonTriggers[0].SelectNodes('.//*[local-name()="InvokeCommandAction"]'))
    Require ($buttonActions.Count -eq 1 -and [object]::ReferenceEquals($rowActions[0], $buttonActions[0])) `
        "核心设置 LSButton 的 Click EventTrigger 必须承载本行唯一 InvokeCommandAction: COSConfigToggle$Key/$PageName"
    if ($PageName -eq 'COS_ConfigMenu_c.xaml') {
        Require ($button.GetAttribute('BoundEvent') -eq 'UIAccept') `
            "手柄核心设置 LSToggleButton 必须绑定 UIAccept: COSConfigToggle$Key/$PageName"
        Require ($button.GetAttribute('Focusable') -eq 'False' -and
            $button.GetAttribute('ls:MoveFocus.Focusable') -eq 'False') `
            "手柄核心设置子 LSToggleButton 不得参与焦点移动: COSConfigToggle$Key/$PageName"
        Require ($button.GetAttribute('IsEnabled') -eq
            "{Binding Path=(ls:MoveFocus.IsFocused), ElementName=COSConfigRow$Key}") `
            "手柄核心设置子 LSToggleButton 必须只在对应父行聚焦时启用: COSConfigToggle$Key/$PageName"
    } else {
        Require (-not $button.HasAttribute('BoundEvent')) `
            "键鼠核心设置 LSToggleButton 不得伪造 BoundEvent 激活: COSConfigToggle$Key/$PageName"
    }

    $rowItemsControls = @($row.SelectNodes('.//*[local-name()="ItemsControl"]'))
    Require ($rowItemsControls.Count -eq 1) "核心设置行必须恰好一个镜像 ItemsControl: COSConfigRow$Key/$PageName"
    $mirrorNodes = @($rowItemsControls | Where-Object {
        $_.GetAttribute('Name', $xamlNamespace) -eq "COSConfigMirror$Key"
    })
    Require ($mirrorNodes.Count -eq 1) "核心设置镜像必须唯一命名为 COSConfigMirror${Key}: $PageName"
    $mirrorNode = $mirrorNodes[0]
    Require ($mirrorNode.GetAttribute('ItemsSource') -eq '{Binding CurrentPlayer.SelectedCharacter.Stats.Passives}') `
        "核心设置镜像必须精确绑定 SelectedCharacter Passives: COSConfigMirror$Key/$PageName"
    $itemTemplateNodes = @($mirrorNode.SelectNodes('./*[local-name()="ItemsControl.ItemTemplate"]'))
    Require ($itemTemplateNodes.Count -eq 1) `
        "核心设置镜像必须有唯一 ItemsControl.ItemTemplate: COSConfigMirror$Key/$PageName"
    $dataTemplateNodes = @($itemTemplateNodes[0].SelectNodes('./*[local-name()="DataTemplate"]'))
    Require ($dataTemplateNodes.Count -eq 1) `
        "核心设置镜像 ItemTemplate 必须有唯一 DataTemplate: COSConfigMirror$Key/$PageName"
    $enabledStateNodes = @($dataTemplateNodes[0].SelectNodes('.//*') | Where-Object {
        $_.GetAttribute('Name', $xamlNamespace) -eq 'EnabledState'
    })
    Require ($enabledStateNodes.Count -eq 1 -and
        $enabledStateNodes[0].LocalName -eq 'Image' -and
        $enabledStateNodes[0].GetAttribute('Visibility') -eq 'Collapsed' -and
        $enabledStateNodes[0].GetAttribute('Source') -eq 'pack://application:,,,/Core;component/Assets/Options/ico_check_h.png') `
        "核心设置开启回显必须使用原生勾选图标: COSConfigMirror$Key/$PageName"
    $dataTemplateTriggersNodes = @($dataTemplateNodes[0].SelectNodes('./*[local-name()="DataTemplate.Triggers"]'))
    Require ($dataTemplateTriggersNodes.Count -eq 1) `
        "核心设置镜像 DataTemplate 必须有唯一 DataTemplate.Triggers: COSConfigMirror$Key/$PageName"
    $mirrorTriggers = @($dataTemplateTriggersNodes[0].SelectNodes('./*[local-name()="DataTrigger"]'))
    $allMirrorTriggers = @($mirrorNode.SelectNodes('.//*[local-name()="DataTrigger"]'))
    Require ($mirrorTriggers.Count -eq 1 -and $allMirrorTriggers.Count -eq 1 -and
        $mirrorTriggers[0].GetAttribute('Value') -eq $Mirror -and
        $mirrorTriggers[0].GetAttribute('Binding') -eq '{Binding Name.Str}') `
        "核心设置镜像必须只在 DataTemplate.Triggers 中用 Name.Str DataTrigger 回显 ${Mirror}: COSConfigMirror$Key/$PageName"
    $triggerSetters = @($mirrorTriggers[0].SelectNodes('.//*[local-name()="Setter"]'))
    Require ($triggerSetters.Count -eq 1 -and
        $triggerSetters[0].GetAttribute('TargetName') -eq 'EnabledState' -and
        $triggerSetters[0].GetAttribute('Property') -eq 'Visibility' -and
        $triggerSetters[0].GetAttribute('Value') -eq 'Visible') `
        "核心设置镜像 DataTrigger 必须唯一显示 EnabledState: COSConfigMirror$Key/$PageName"
}
function Test-ControllerPageContract([xml]$Document, [string]$PageText, [string]$PageName) {
    $rootNodes = @(Get-XamlNamedNodes $Document 'COS_ConfigMenu_c')
    Require ($rootNodes.Count -eq 1 -and $rootNodes[0].LocalName -eq 'UIWidget') `
        "手柄核心设置页必须保留唯一命名根控件: $PageName"
    Require ($rootNodes[0].GetAttribute('FocusDown') -eq 'UIDown' -and
        $rootNodes[0].GetAttribute('FocusUp') -eq 'UIUp' -and
        $rootNodes[0].GetAttribute('ls:MoveFocus.FocusMovementMode') -eq 'MainAxisTunnel') `
        "手柄核心设置根控件必须保留上下导航和 MainAxisTunnel: $PageName"
    $setFocusActions = @($Document.SelectNodes('//*[local-name()="SetMoveFocusAction"]'))
    $loadedTriggers = @($Document.SelectNodes('//*[local-name()="EventTrigger"]') |
        Where-Object { $_.GetAttribute('EventName') -eq 'Loaded' })
    $loadedFocusActions = if ($loadedTriggers.Count -eq 1) {
        @($loadedTriggers[0].SelectNodes('.//*[local-name()="SetMoveFocusAction"]'))
    } else { @() }
    Require ($setFocusActions.Count -eq 1 -and $loadedFocusActions.Count -eq 1 -and
        $setFocusActions[0].GetAttribute('TargetName') -eq 'COS_ConfigMenu_c') `
        "手柄核心设置页 Loaded 必须唯一把初始焦点交给根控件: $PageName"
    foreach ($forbiddenResource in @('PageHeaderHeight', 'PageHeader', 'BrownButtonStyle', 'BigBrownButtonStyle')) {
        Require (-not $PageText.Contains("{StaticResource $forbiddenResource}")) `
            "手柄核心设置页不得引用键鼠专属资源 ${forbiddenResource}: $PageName"
    }
}
$legacyAcceptNames = @($expectedConfigRows.Keys | ForEach-Object { "COSConfigToggle$_" }) +
    @('COSConfigResetCore')
$racialControlIds = @(
    'DeepGnomeStone','DrowWeapon','DuergarResilience','DwarfWeapon','DwarfResilience',
    'ElfWeapon','FeyAncestry','GithMartial','GnomeCunning','HalflingBrave',
    'HalflingLightfoot','HalflingLucky','HalflingStout','HumanMilitia','MountainDwarfArmor',
    'Relentless','RockGnomeLore','SavageAttacks','SuperiorDarkvision','TieflingResistance'
)
$expandedAcceptNames = @($legacyAcceptNames + @('COSConfigLifeReset','COSConfigRaceAll','COSConfigRaceNone') +
    @($racialControlIds | ForEach-Object { "COSConfigRaceToggle$_" }))
function Test-ControllerAcceptContract([xml]$Document, [string]$PageName, [string[]]$ExpectedAcceptNames = $expandedAcceptNames) {
    $acceptButtons = @($Document.SelectNodes('//*') | Where-Object {
        ($_.LocalName -eq 'LSButton' -or $_.LocalName -eq 'LSToggleButton') -and
        $_.GetAttribute('BoundEvent') -eq 'UIAccept'
    })
    $acceptNames = @($acceptButtons | ForEach-Object {
        $_.GetAttribute('Name', $xamlNamespace)
    })
    Require ($acceptButtons.Count -eq $ExpectedAcceptNames.Count -and
        @($acceptNames | Select-Object -Unique).Count -eq $ExpectedAcceptNames.Count -and
        -not (Compare-Object ($ExpectedAcceptNames | Sort-Object) ($acceptNames | Sort-Object))) `
        "手柄设置页消费 UIAccept 的控件必须与批准清单完全一致: $PageName"
}
function Require-ConfigRowMutationRejected([string]$Markup, [string]$Message, [string]$PageName = 'COS_ConfigMenu.xaml') {
    [xml]$mutationDocument = $Markup
    $rejected = $false
    try {
        Test-ConfigRowContract $mutationDocument 'Power' '7f818c10-3f23-49f8-838a-d161c57bb35d' 'COS_CFG_MECH_POWER' $PageName
    } catch {
        $rejected = $true
    }
    Require $rejected $Message
}
function Require-ConfigResetMutationRejected([string]$Markup, [string]$Message, [string]$PageName = 'COS_ConfigMenu.xaml') {
    [xml]$mutationDocument = $Markup
    $rejected = $false
    try {
        Test-ConfigResetContract $mutationDocument $PageName
    } catch {
        $rejected = $true
    }
    Require $rejected $Message
}
function Require-ControllerPageMutationRejected([string]$Markup, [string]$Message) {
    [xml]$mutationDocument = $Markup
    $rejected = $false
    try {
        Test-ControllerPageContract $mutationDocument $Markup 'COS_ConfigMenu_c.xaml'
    } catch {
        $rejected = $true
    }
    Require $rejected $Message
}
function Require-ControllerAcceptMutationRejected([string]$Markup, [string]$Message) {
    [xml]$mutationDocument = $Markup
    $rejected = $false
    try {
        Test-ControllerAcceptContract $mutationDocument 'COS_ConfigMenu_c.xaml' $legacyAcceptNames
    } catch {
        $rejected = $true
    }
    Require $rejected $Message
}
$configRowProbe = '<Root xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:ls="urn:test-ls" xmlns:b="urn:test-behaviors"><Grid x:Name="COSConfigRowPower"><ls:LSToggleButton x:Name="COSConfigTogglePower"><ls:LSToggleButton.Template><ControlTemplate><Grid><Image x:Name="ToggleBox" Source="pack://application:,,,/Core;component/Assets/Options/checkBox_d.png" /></Grid><ControlTemplate.Triggers><Trigger><Setter TargetName="ToggleBox" Property="Source" Value="pack://application:,,,/Core;component/Assets/Options/checkBox_h.png" /></Trigger></ControlTemplate.Triggers></ControlTemplate></ls:LSToggleButton.Template><b:Interaction.Triggers><b:EventTrigger EventName="Click"><b:InvokeCommandAction Command="{Binding DataContext.TutorialEvent, RelativeSource={RelativeSource AncestorType={x:Type ls:UIWidget}}}" CommandParameter="7f818c10-3f23-49f8-838a-d161c57bb35d" /></b:EventTrigger></b:Interaction.Triggers></ls:LSToggleButton><ItemsControl x:Name="COSConfigMirrorPower" ItemsSource="{Binding CurrentPlayer.SelectedCharacter.Stats.Passives}"><ItemsControl.ItemTemplate><DataTemplate><Image x:Name="EnabledState" Source="pack://application:,,,/Core;component/Assets/Options/ico_check_h.png" Visibility="Collapsed" /><DataTemplate.Triggers><DataTrigger Binding="{Binding Name.Str}" Value="COS_CFG_MECH_POWER"><DataTrigger.Setters><Setter TargetName="EnabledState" Property="Visibility" Value="Visible" /></DataTrigger.Setters></DataTrigger></DataTemplate.Triggers></DataTemplate></ItemsControl.ItemTemplate></ItemsControl></Grid></Root>'
[xml]$configRowProbeDocument = $configRowProbe
Test-ConfigRowContract $configRowProbeDocument 'Power' '7f818c10-3f23-49f8-838a-d161c57bb35d' 'COS_CFG_MECH_POWER' '内存正向探针'
Require-ConfigRowMutationRejected ($configRowProbe -replace 'EventName="Click"', 'EventName="MouseEnter"') `
    'MouseEnter 不得替代 LSToggleButton 的 Click 激活'
Require-ConfigRowMutationRejected ($configRowProbe -replace 'ls:LSToggleButton', 'Button') `
    '普通 Button 不得替代命名 LSToggleButton'
Require-ConfigRowMutationRejected ($configRowProbe -replace 'CurrentPlayer\.SelectedCharacter\.Stats\.Passives', 'CurrentPlayer\.Stats\.Passives') `
    '错误的镜像 ItemsSource 必须被拒绝'
Require-ConfigRowMutationRejected ($configRowProbe -replace '\{Binding Name\.Str\}', '{Binding DisplayName}') `
    '错误的镜像 DataTrigger Binding 必须被拒绝'
Require-ConfigRowMutationRejected (($configRowProbe -replace '<ItemsControl.ItemTemplate><DataTemplate>', '') `
    -replace '</DataTemplate></ItemsControl.ItemTemplate>', '') `
    '裸放在 ItemsControl 下的 DataTrigger 必须被拒绝'
Require-ConfigRowMutationRejected ($configRowProbe -replace 'TargetName="EnabledState"', 'TargetName="WrongState"') `
    '错误 Setter 必须被拒绝'
Require-ConfigRowMutationRejected ($configRowProbe -replace '<DataTrigger.Setters><Setter TargetName="EnabledState" Property="Visibility" Value="Visible" /></DataTrigger.Setters>', '') `
    '缺失 Setter 必须被拒绝'
Require-ConfigRowMutationRejected ($configRowProbe -replace 'ico_check_h.png', 'checkBox_d.png') `
    '错误的开启回显图标必须被拒绝'
$configControllerRowProbe = '<Root xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:ls="urn:test-ls" xmlns:b="urn:test-behaviors"><ContentControl x:Name="COSConfigRowPower" Focusable="True" ls:MoveFocus.Focusable="True"><Grid><ls:LSToggleButton x:Name="COSConfigTogglePower" Focusable="False" ls:MoveFocus.Focusable="False" BoundEvent="UIAccept" IsEnabled="{Binding Path=(ls:MoveFocus.IsFocused), ElementName=COSConfigRowPower}"><ls:LSToggleButton.Template><ControlTemplate><Grid><Image x:Name="ToggleBox" Source="pack://application:,,,/Core;component/Assets/Options/checkBox_d.png" /></Grid><ControlTemplate.Triggers><Trigger><Setter TargetName="ToggleBox" Property="Source" Value="pack://application:,,,/Core;component/Assets/Options/checkBox_h.png" /></Trigger></ControlTemplate.Triggers></ControlTemplate></ls:LSToggleButton.Template><b:Interaction.Triggers><b:EventTrigger EventName="Click"><b:InvokeCommandAction Command="{Binding DataContext.TutorialEvent, RelativeSource={RelativeSource AncestorType={x:Type ls:UIWidget}}}" CommandParameter="7f818c10-3f23-49f8-838a-d161c57bb35d" /></b:EventTrigger></b:Interaction.Triggers></ls:LSToggleButton><ItemsControl x:Name="COSConfigMirrorPower" ItemsSource="{Binding CurrentPlayer.SelectedCharacter.Stats.Passives}"><ItemsControl.ItemTemplate><DataTemplate><Image x:Name="EnabledState" Source="pack://application:,,,/Core;component/Assets/Options/ico_check_h.png" Visibility="Collapsed" /><DataTemplate.Triggers><DataTrigger Binding="{Binding Name.Str}" Value="COS_CFG_MECH_POWER"><DataTrigger.Setters><Setter TargetName="EnabledState" Property="Visibility" Value="Visible" /></DataTrigger.Setters></DataTrigger></DataTemplate.Triggers></DataTemplate></ItemsControl.ItemTemplate></ItemsControl></Grid></ContentControl></Root>'
[xml]$configControllerRowProbeDocument = $configControllerRowProbe
Test-ConfigRowContract $configControllerRowProbeDocument 'Power' '7f818c10-3f23-49f8-838a-d161c57bb35d' 'COS_CFG_MECH_POWER' 'COS_ConfigMenu_c.xaml'
Require-ConfigRowMutationRejected $configRowProbe '手柄 LSToggleButton 缺失 UIAccept 必须被拒绝' 'COS_ConfigMenu_c.xaml'
Require-ConfigRowMutationRejected ($configControllerRowProbe -replace ' IsEnabled="\{Binding Path=\(ls:MoveFocus.IsFocused\), ElementName=COSConfigRowPower\}"', '') `
    '手柄子按钮缺失父焦点启用门控必须被拒绝' 'COS_ConfigMenu_c.xaml'
Require-ConfigRowMutationRejected ($configControllerRowProbe -replace 'ElementName=COSConfigRowPower', 'ElementName=COSConfigRowWound') `
    '手柄子按钮绑定错误父行必须被拒绝' 'COS_ConfigMenu_c.xaml'
Require-ConfigRowMutationRejected ($configControllerRowProbe -replace 'Focusable="False" ls:MoveFocus.Focusable="False" BoundEvent', 'Focusable="True" ls:MoveFocus.Focusable="False" BoundEvent') `
    '手柄子按钮不得重新参与标准焦点' 'COS_ConfigMenu_c.xaml'
Require-ConfigRowMutationRejected ($configControllerRowProbe -replace 'Focusable="False" BoundEvent', 'Focusable="True" BoundEvent') `
    '手柄子按钮不得重新参与 MoveFocus' 'COS_ConfigMenu_c.xaml'
$configResetProbe = '<Root xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:ls="urn:test-ls" xmlns:b="urn:test-behaviors"><ls:LSButton x:Name="COSConfigResetCore"><b:Interaction.Triggers><b:EventTrigger EventName="Click"><b:InvokeCommandAction Command="{Binding DataContext.TutorialEvent, RelativeSource={RelativeSource AncestorType={x:Type ls:UIWidget}}}" CommandParameter="08c8d67a-ace5-4830-8c2b-38b8c92bb470" /></b:EventTrigger></b:Interaction.Triggers></ls:LSButton></Root>'
[xml]$configResetProbeDocument = $configResetProbe
Test-ConfigResetContract $configResetProbeDocument 'COS_ConfigMenu.xaml'
$configControllerResetProbe = '<Root xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:ls="urn:test-ls" xmlns:b="urn:test-behaviors"><ContentControl x:Name="COSConfigResetRow" Focusable="True" ls:MoveFocus.Focusable="True"><ls:LSButton x:Name="COSConfigResetCore" Focusable="False" ls:MoveFocus.Focusable="False" BoundEvent="UIAccept" IsEnabled="{Binding Path=(ls:MoveFocus.IsFocused), ElementName=COSConfigResetRow}"><b:Interaction.Triggers><b:EventTrigger EventName="Click"><b:InvokeCommandAction Command="{Binding DataContext.TutorialEvent, RelativeSource={RelativeSource AncestorType={x:Type ls:UIWidget}}}" CommandParameter="08c8d67a-ace5-4830-8c2b-38b8c92bb470" /></b:EventTrigger></b:Interaction.Triggers></ls:LSButton></ContentControl></Root>'
[xml]$configControllerResetProbeDocument = $configControllerResetProbe
Test-ConfigResetContract $configControllerResetProbeDocument 'COS_ConfigMenu_c.xaml'
Require-ConfigResetMutationRejected ($configResetProbe -replace 'ls:LSButton', 'Grid') `
    'Grid 不得替代命名重置 LSButton'
Require-ConfigResetMutationRejected ($configResetProbe -replace 'EventName="Click"', 'EventName="MouseEnter"') `
    'MouseEnter 不得替代重置 LSButton 的 Click 激活'
Require-ConfigResetMutationRejected $configResetProbe '手柄重置 LSButton 缺失 UIAccept 必须被拒绝' 'COS_ConfigMenu_c.xaml'
Require-ConfigResetMutationRejected ($configControllerResetProbe -replace ' IsEnabled="\{Binding Path=\(ls:MoveFocus.IsFocused\), ElementName=COSConfigResetRow\}"', '') `
    '手柄重置子按钮缺失父焦点启用门控必须被拒绝' 'COS_ConfigMenu_c.xaml'
Require-ConfigResetMutationRejected ($configControllerResetProbe -replace 'ElementName=COSConfigResetRow', 'ElementName=COSConfigRowPower') `
    '手柄重置子按钮绑定错误父行必须被拒绝' 'COS_ConfigMenu_c.xaml'
Require-ConfigResetMutationRejected ($configControllerResetProbe -replace 'Focusable="False" ls:MoveFocus.Focusable="False" BoundEvent', 'Focusable="True" ls:MoveFocus.Focusable="False" BoundEvent') `
    '手柄重置子按钮不得重新参与标准焦点' 'COS_ConfigMenu_c.xaml'
$configControllerPageProbe = '<ls:UIWidget x:Name="COS_ConfigMenu_c" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:ls="clr-namespace:ls;assembly=Code" xmlns:b="http://schemas.microsoft.com/xaml/behaviors" FocusDown="UIDown" FocusUp="UIUp" ls:MoveFocus.FocusMovementMode="MainAxisTunnel"><b:Interaction.Triggers><b:EventTrigger EventName="Loaded"><b:InvokeCommandAction/><ls:SetMoveFocusAction TargetName="COS_ConfigMenu_c"/></b:EventTrigger></b:Interaction.Triggers><ls:UIWidget.Template><ControlTemplate><Grid/></ControlTemplate></ls:UIWidget.Template></ls:UIWidget>'
[xml]$configControllerPageProbeDocument = $configControllerPageProbe
Test-ControllerPageContract $configControllerPageProbeDocument $configControllerPageProbe 'COS_ConfigMenu_c.xaml'
Require-ControllerPageMutationRejected ($configControllerPageProbe -replace '<ls:SetMoveFocusAction TargetName="COS_ConfigMenu_c"/>', '') `
    '手柄页缺失 Loaded 初始焦点动作必须被拒绝'
Require-ControllerPageMutationRejected ($configControllerPageProbe -replace 'TargetName="COS_ConfigMenu_c"', 'TargetName="WrongRoot"') `
    '手柄页初始焦点指向错误根控件必须被拒绝'
Require-ControllerPageMutationRejected ($configControllerPageProbe -replace '<Grid/>', '<Grid Height="{StaticResource PageHeaderHeight}"/>') `
    '手柄页重新引用 PageHeaderHeight 必须被拒绝'
Require-ControllerPageMutationRejected ($configControllerPageProbe -replace '<Grid/>', '<Grid Tag="{StaticResource PageHeader}"/>') `
    '手柄页重新引用 PageHeader 必须被拒绝'
Require-ControllerPageMutationRejected ($configControllerPageProbe -replace ' FocusDown="UIDown"', '') `
    '手柄页缺失 FocusDown 必须被拒绝'
Require-ControllerPageMutationRejected ($configControllerPageProbe -replace 'FocusDown="UIDown"', 'FocusDown="WrongDown"') `
    '手柄页错误 FocusDown 必须被拒绝'
Require-ControllerPageMutationRejected ($configControllerPageProbe -replace ' FocusUp="UIUp"', '') `
    '手柄页缺失 FocusUp 必须被拒绝'
Require-ControllerPageMutationRejected ($configControllerPageProbe -replace 'FocusUp="UIUp"', 'FocusUp="WrongUp"') `
    '手柄页错误 FocusUp 必须被拒绝'
Require-ControllerPageMutationRejected ($configControllerPageProbe -replace ' ls:MoveFocus.FocusMovementMode="MainAxisTunnel"', '') `
    '手柄页缺失 FocusMovementMode 必须被拒绝'
Require-ControllerPageMutationRejected ($configControllerPageProbe -replace 'FocusMovementMode="MainAxisTunnel"', 'FocusMovementMode="Cycle"') `
    '手柄页错误 FocusMovementMode 必须被拒绝'
$configControllerAcceptProbe = '<Root xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:ls="urn:test-ls"><ls:LSButton x:Name="COSConfigTogglePower" BoundEvent="UIAccept"/><ls:LSButton x:Name="COSConfigToggleWound" BoundEvent="UIAccept"/><ls:LSButton x:Name="COSConfigToggleKillPower" BoundEvent="UIAccept"/><ls:LSButton x:Name="COSConfigToggleDuality" BoundEvent="UIAccept"/><ls:LSButton x:Name="COSConfigToggleAllIn" BoundEvent="UIAccept"/><ls:LSButton x:Name="COSConfigToggleFate" BoundEvent="UIAccept"/><ls:LSButton x:Name="COSConfigToggleGenesis" BoundEvent="UIAccept"/><ls:LSButton x:Name="COSConfigToggleStrike" BoundEvent="UIAccept"/><ls:LSButton x:Name="COSConfigToggleMastery" BoundEvent="UIAccept"/><ls:LSButton x:Name="COSConfigResetCore" BoundEvent="UIAccept"/><ls:LSButton x:Name="COSConfigCloseCore"/></Root>'
[xml]$configControllerAcceptProbeDocument = $configControllerAcceptProbe
Test-ControllerAcceptContract $configControllerAcceptProbeDocument '内存正向探针' $legacyAcceptNames
Require-ControllerAcceptMutationRejected ($configControllerAcceptProbe -replace '</Root>', '<ls:LSButton x:Name="AlwaysOn" BoundEvent="UIAccept" IsEnabled="True"/></Root>') `
    '手柄页注入第十一个始终启用 UIAccept 必须被拒绝'
Require-ControllerAcceptMutationRejected ($configControllerAcceptProbe -replace 'x:Name="COSConfigCloseCore"', 'x:Name="COSConfigCloseCore" BoundEvent="UIAccept"') `
    '手柄关闭或任意额外控件不得消费 UIAccept'

foreach ($pageName in @('COS_ConfigMenu.xaml', 'COS_ConfigMenu_c.xaml')) {
    $page = [IO.File]::ReadAllText((Join-Path $guiRoot "Pages\$pageName"))
    [xml]$pageDocument = $page
    if ($pageName -eq 'COS_ConfigMenu_c.xaml') {
        Test-ControllerPageContract $pageDocument $page $pageName
        Test-ControllerAcceptContract $pageDocument $pageName
        $expectedControllerFocusOrder = @(
            'COSConfigRowPower', 'COSConfigRowWound', 'COSConfigRowKillPower',
            'COSConfigRowDuality', 'COSConfigRowAllIn', 'COSConfigRowFate',
            'COSConfigRowGenesis', 'COSConfigRowStrike', 'COSConfigRowMastery',
            'COSConfigLifeRow', 'COSConfigLifeResetRow', 'COSConfigRaceAllRow', 'COSConfigRaceNoneRow'
        ) + @($racialControlIds | ForEach-Object { "COSConfigRaceRow$_" }) + @(
            'COSConfigResetRow', 'COSConfigCloseCore'
        )
        $controllerFocusableNodes = @($pageDocument.SelectNodes('//*') | Where-Object {
            $_.GetAttribute('Focusable') -eq 'True' -and
            $_.GetAttribute('ls:MoveFocus.Focusable') -eq 'True'
        })
        $controllerFocusOrder = @($controllerFocusableNodes | ForEach-Object {
            $_.GetAttribute('Name', $xamlNamespace)
        })
        Require (($controllerFocusOrder -join '|') -eq ($expectedControllerFocusOrder -join '|')) `
            "手柄焦点顺序必须覆盖核心、生活熟练项、种族被动、重置与关闭，且不得存在额外焦点消费者: $pageName"
        $closeButtons = @(Get-XamlNamedNodes $pageDocument 'COSConfigCloseCore')
        Require ($closeButtons.Count -eq 1 -and $closeButtons[0].LocalName -eq 'LSButton' -and
            $closeButtons[0].GetAttribute('Command') -eq '{Binding CustomEvent}' -and
            $closeButtons[0].GetAttribute('CommandParameter') -eq 'CloseWidget') `
            "手柄关闭控件必须是焦点序列最后的原生 LSButton: $pageName"
    } else {
        $keyboardBoundButtons = @($pageDocument.SelectNodes('//*[local-name()="LSButton"]') |
            Where-Object { $_.HasAttribute('BoundEvent') })
        Require ($keyboardBoundButtons.Count -eq 0) `
            "键鼠核心设置页的 LSButton 不得绑定手柄 BoundEvent: $pageName"
    }
    $optionsBackgrounds = @($pageDocument.SelectNodes('//*[local-name()="Image"]') |
        Where-Object { $_.GetAttribute('Source') -eq '{StaticResource OptionsBackground}' })
    Require ($optionsBackgrounds.Count -eq 1) "空壳页必须使用 OptionsBackground: $pageName"
    $rowsViewports = @(Get-XamlNamedNodes $pageDocument 'COSConfigRowsViewport')
    Require ($rowsViewports.Count -eq 1 -and $rowsViewports[0].LocalName -eq 'ScrollViewer' -and
        $rowsViewports[0].GetAttribute('Grid.Row') -eq '2' -and
        $rowsViewports[0].GetAttribute('VerticalScrollBarVisibility') -eq 'Auto' -and
        $rowsViewports[0].GetAttribute('HorizontalScrollBarVisibility') -eq 'Disabled') `
        "扩展设置必须放在唯一的垂直滚动容器中: $pageName"
    Require (-not $page.Contains('Margin="180,80"') -and -not $page.Contains('Width="1180"')) `
        "核心设置页不得保留导致低分辨率越界的固定外边距或1180宽度: $pageName"
    $cancelBindings = @($pageDocument.SelectNodes('//*[local-name()="LSInputBinding"]') |
        Where-Object { $_.GetAttribute('BoundEvent') -eq 'UICancel' -and $_.GetAttribute('CommandParameter') -eq 'CloseWidget' })
    Require ($cancelBindings.Count -eq 1) "空壳页必须用 UICancel 发送 CloseWidget: $pageName"
    Require ($cancelBindings[0].GetAttribute('Command') -eq '{Binding CustomEvent}') `
        "空壳页的 UICancel 必须绑定 CustomEvent: $pageName"
    $returnButtons = @($pageDocument.SelectNodes('//*[local-name()="LSButton"]') |
        Where-Object { $_.GetAttribute('Content').Contains('hc05fd010g0000g4000g8000g000000000000') -and
            $_.GetAttribute('CommandParameter') -eq 'CloseWidget' })
    Require ($returnButtons.Count -eq 1) "空壳页返回按钮必须发送 CloseWidget: $pageName"
    Require ($returnButtons[0].GetAttribute('Command') -eq '{Binding CustomEvent}') `
        "空壳页返回按钮必须绑定 CustomEvent: $pageName"
    $tutorialActions = @($pageDocument.SelectNodes('//*[local-name()="InvokeCommandAction"]'))
    $tutorialCommandParameters = @($tutorialActions | ForEach-Object { $_.GetAttribute('CommandParameter') })
    $expectedTutorialUuids = @($expectedTutorialEvents.Values)
    Require ($tutorialActions.Count -eq 36 -and @($tutorialCommandParameters | Sort-Object -Unique).Count -eq 36 -and
        -not (Compare-Object ($expectedTutorialUuids | Sort-Object) ($tutorialCommandParameters | Sort-Object))) `
        "设置页必须恰好调用36个唯一固定 TutorialEvent UUID: $pageName"
    foreach ($tutorialAction in $tutorialActions) {
        Require ($tutorialAction.GetAttribute('Command') -eq $tutorialEventCommandBinding) `
            "核心设置页 InvokeCommandAction 必须精确绑定 DataContext.TutorialEvent: $pageName"
    }
    foreach ($configRow in $expectedConfigRows.GetEnumerator()) {
        Test-ConfigRowContract $pageDocument $configRow.Key $configRow.Value.Uuid $configRow.Value.Mirror $pageName
    }
    foreach ($racialRow in $expectedRacialConfigRows.GetEnumerator()) {
        $rowName = "COSConfigRaceRow$($racialRow.Key)"
        $toggleName = "COSConfigRaceToggle$($racialRow.Key)"
        $mirrorName = "COSConfigRaceMirror$($racialRow.Key)"
        $rows = @(Get-XamlNamedNodes $pageDocument $rowName)
        $toggles = @(Get-XamlNamedNodes $pageDocument $toggleName)
        $mirrors = @(Get-XamlNamedNodes $pageDocument $mirrorName)
        Require ($rows.Count -eq 1 -and $toggles.Count -eq 1 -and $mirrors.Count -eq 1) `
            "种族被动行、开关和镜像必须各自唯一: $($racialRow.Key)/$pageName"
        Require ($toggles[0].LocalName -eq 'LSToggleButton' -and
            $mirrors[0].GetAttribute('ItemsSource') -eq '{Binding CurrentPlayer.SelectedCharacter.Stats.Passives}') `
            "种族被动必须使用原生开关和当前角色Passives镜像: $($racialRow.Key)/$pageName"
        $actions = @($toggles[0].SelectNodes('.//*[local-name()="InvokeCommandAction"]'))
        Require ($actions.Count -eq 1) "种族被动开关必须只有一个固定事件: $($racialRow.Key)/$pageName"
        Require-TutorialEventAction $actions[0] $racialRow.Value.Uuid `
            "种族被动开关UUID错误: $($racialRow.Key)/$pageName"
        $dataTriggers = @($mirrors[0].SelectNodes('.//*[local-name()="DataTrigger"]'))
        Require ($dataTriggers.Count -eq 1 -and
            $dataTriggers[0].GetAttribute('Binding') -eq '{Binding Name.Str}' -and
            $dataTriggers[0].GetAttribute('Value') -eq $racialRow.Value.Mirror) `
            "种族被动镜像必须绑定唯一批准标识: $($racialRow.Key)/$pageName"
        if ($pageName -eq 'COS_ConfigMenu_c.xaml') {
            Require ($rows[0].LocalName -eq 'ContentControl' -and
                $rows[0].GetAttribute('Focusable') -eq 'True' -and
                $rows[0].GetAttribute('ls:MoveFocus.Focusable') -eq 'True' -and
                $toggles[0].GetAttribute('BoundEvent') -eq 'UIAccept' -and
                $toggles[0].GetAttribute('IsEnabled') -eq
                    "{Binding Path=(ls:MoveFocus.IsFocused), ElementName=$rowName}") `
                "手柄种族被动行必须独占焦点并门控子开关: $($racialRow.Key)/$pageName"
        } else {
            Require ($rows[0].LocalName -eq 'Grid' -and -not $toggles[0].HasAttribute('BoundEvent')) `
                "键鼠种族被动行不得伪造手柄激活: $($racialRow.Key)/$pageName"
        }
    }
    $lifeValueControls = @(Get-XamlNamedNodes $pageDocument 'COSConfigLifeValue')
    Require ($lifeValueControls.Count -eq 1 -and
        $lifeValueControls[0].GetAttribute('ItemsSource') -eq
            '{Binding CurrentPlayer.SelectedCharacter.Stats.ActionResources}') `
        "生活熟练项必须唯一绑定当前角色ActionResources: $pageName"
    $lifeTypeTriggers = @($lifeValueControls[0].SelectNodes('.//*[local-name()="DataTrigger"]') |
        Where-Object { $_.GetAttribute('Binding') -eq '{Binding TypeId}' })
    $lifeProgressBars = @($lifeValueControls[0].SelectNodes('.//*[local-name()="LSProgressBar"]'))
    Require ($lifeTypeTriggers.Count -eq 1 -and
        $lifeTypeTriggers[0].GetAttribute('Value') -eq 'COS_ConfigLifeSkill' -and
        $lifeProgressBars.Count -eq 1 -and
        $lifeProgressBars[0].GetAttribute('Minimum') -eq '0' -and
        $lifeProgressBars[0].GetAttribute('Maximum') -eq '20') `
        "生活熟练项显示必须绑定COS_ConfigLifeSkill并固定为0至20: $pageName"
    foreach ($lifeButton in @(
        @{ Name = 'COSConfigLifeMinus'; Uuid = $expectedTutorialEvents.COS_CFG_LIFE_MINUS },
        @{ Name = 'COSConfigLifePlus'; Uuid = $expectedTutorialEvents.COS_CFG_LIFE_PLUS },
        @{ Name = 'COSConfigLifeReset'; Uuid = $expectedTutorialEvents.COS_CFG_LIFE_RESET },
        @{ Name = 'COSConfigRaceAll'; Uuid = $expectedTutorialEvents.COS_CFG_RACE_ALL },
        @{ Name = 'COSConfigRaceNone'; Uuid = $expectedTutorialEvents.COS_CFG_RACE_NONE }
    )) {
        $buttons = @(Get-XamlNamedNodes $pageDocument $lifeButton.Name)
        Require ($buttons.Count -eq 1) "设置控制按钮必须唯一: $($lifeButton.Name)/$pageName"
        $actions = @($buttons[0].SelectNodes('.//*[local-name()="InvokeCommandAction"]'))
        Require ($actions.Count -eq 1) "设置控制按钮必须只有一个固定事件: $($lifeButton.Name)/$pageName"
        Require-TutorialEventAction $actions[0] $lifeButton.Uuid `
            "设置控制按钮UUID错误: $($lifeButton.Name)/$pageName"
    }
    if ($pageName -eq 'COS_ConfigMenu_c.xaml') {
        $lifeMinusNodes = @(Get-XamlNamedNodes $pageDocument 'COSConfigLifeMinus')
        $lifePlusNodes = @(Get-XamlNamedNodes $pageDocument 'COSConfigLifePlus')
        Require ($lifeMinusNodes[0].GetAttribute('BoundEvent') -eq 'UILeft' -and
            $lifePlusNodes[0].GetAttribute('BoundEvent') -eq 'UIRight') `
            '手柄生活熟练项必须由左右方向逐点调整'
    }
    $loadedTriggers = @($pageDocument.SelectNodes('//*[local-name()="EventTrigger"]') |
        Where-Object { $_.GetAttribute('EventName') -eq 'Loaded' })
    Require ($loadedTriggers.Count -eq 1) "核心设置页必须恰好一个 Loaded 事件: $pageName"
    $loadedActions = @($loadedTriggers[0].SelectNodes('.//*[local-name()="InvokeCommandAction"]'))
    $namedLoadedActions = @($loadedActions | Where-Object {
        $_.GetAttribute('Name', $xamlNamespace) -eq 'COSConfigOpenOnLoaded'
    })
    Require ($loadedActions.Count -eq 1 -and $namedLoadedActions.Count -eq 1) `
        "核心设置页 Loaded 打开事件必须唯一命名为 COSConfigOpenOnLoaded: $pageName"
    Require-TutorialEventAction $namedLoadedActions[0] $expectedTutorialEvents.COS_CFG_UI_OPENED `
        "核心设置页 Loaded 打开事件必须发送 COS_CFG_UI_OPENED: $pageName"
    Test-ConfigResetContract $pageDocument $pageName
    Require ($page.Contains('CurrentPlayer.SelectedCharacter.Stats.Passives')) `
        "核心设置页必须绑定 CurrentPlayer.SelectedCharacter.Stats.Passives: $pageName"
    $mirrorTriggers = @($pageDocument.SelectNodes('//*[local-name()="DataTrigger"]') | Where-Object {
        $_.GetAttribute('Value') -match '^COS_CFG_MECH_'
    })
    $mirrorTriggerValues = @($mirrorTriggers | ForEach-Object { $_.GetAttribute('Value') })
    Require ($mirrorTriggers.Count -eq 9 -and @($mirrorTriggerValues | Sort-Object -Unique).Count -eq 9 -and
        -not (Compare-Object ($coreMechanicMirrors | Sort-Object) ($mirrorTriggerValues | Sort-Object))) `
        "核心设置页必须恰好有九个唯一机制回显 DataTrigger，且不得夹带额外 COS_CFG_MECH_*: $pageName"
    Require ($page.Contains('hc05fd001g0000g4000g8000g000000000000') -and
        $page.Contains('hc05fd002g0000g4000g8000g000000000000') -and
        $page.Contains('hc05fd010g0000g4000g8000g000000000000')) `
        "空壳页缺少标题、说明或返回文本: $pageName"
}

$guiMetadataSourcePath = Join-Path $root 'resource-src\Mods\ChaosOriginsStory\GUI\metadata.lsf.lsx'
$raspberryTemplateSourcePath = Join-Path $root 'resource-src\Public\ChaosOriginsStory\RootTemplates\COS_Raspberry.lsf.lsx'
Require (Test-Path -LiteralPath $guiMetadataSourcePath -PathType Leaf) '缺少 GUI metadata 源文件'
[xml]$guiMetadataDocument = Get-Content -LiteralPath $guiMetadataSourcePath -Raw -Encoding UTF8
$guiMetadataVersion = $guiMetadataDocument.SelectSingleNode('/save/version')
Require ($null -ne $guiMetadataVersion -and
    $guiMetadataVersion.GetAttribute('major') -eq '4' -and
    $guiMetadataVersion.GetAttribute('minor') -eq '8' -and
    $guiMetadataVersion.GetAttribute('revision') -eq '0' -and
    $guiMetadataVersion.GetAttribute('build') -eq '500') `
    'GUI metadata 必须使用 v4.8.0.500'
$guiConfigRegions = @($guiMetadataDocument.SelectNodes('/save/region[@id="config"]'))
$guiConfigNodes = @($guiMetadataDocument.SelectNodes('/save/region[@id="config"]/node[@id="config"]'))
$guiEntriesNodes = @($guiMetadataDocument.SelectNodes('/save/region[@id="config"]/node[@id="config"]/children/node[@id="entries"]'))
Require ($guiConfigRegions.Count -eq 1 -and $guiConfigNodes.Count -eq 1 -and $guiEntriesNodes.Count -eq 1) `
    'GUI metadata 必须包含 config/entries 空配置节点'
$guiEntriesChildren = @($guiEntriesNodes[0].SelectNodes('./children'))
Require ($guiEntriesChildren.Count -eq 1 -and $guiEntriesChildren[0].SelectNodes('./*').Count -eq 0) `
    'GUI metadata 的 entries children 必须为空'
Require ($resourceSources.Count -eq 4 -and
    $resourceSources.FullName -contains $tagPath -and
    $resourceSources.FullName -contains $textureBankSourcePath -and
    $resourceSources.FullName -contains $guiMetadataSourcePath -and
    $resourceSources.FullName -contains $raspberryTemplateSourcePath) `
    '资源源目录必须只包含起源标签、技能图标 TextureBank、GUI metadata 和山莓模板'
Require (Test-Path -LiteralPath $raspberryTemplateSourcePath -PathType Leaf) '缺少山莓 RootTemplate 覆盖源'
[xml]$raspberryTemplate = Get-Content -LiteralPath $raspberryTemplateSourcePath -Raw -Encoding UTF8
$raspberryNodes = @($raspberryTemplate.SelectNodes('//node[@id="GameObjects"]'))
Require ($raspberryNodes.Count -eq 1) '山莓 RootTemplate 必须只有一个 GameObjects 节点'
$raspberryNode = $raspberryNodes[0]
Require ([string]$raspberryNode.SelectSingleNode('./attribute[@id="MapKey"]').value -eq
    'b0943b65-5766-414a-903d-28de8790370a') '山莓 RootTemplate MapKey 错误'
Require ([string]$raspberryNode.SelectSingleNode('./attribute[@id="Name"]').value -eq 'GEN_CONS_Berry' -and
    [string]$raspberryNode.SelectSingleNode('./attribute[@id="Stats"]').value -eq 'CONS_Berry') `
    '山莓覆盖必须保留官方 Name 和 Stats'
$raspberryActions = @($raspberryNode.SelectNodes('./children/node[@id="OnUsePeaceActions"]/children/node[@id="Action"]'))
Require ($raspberryActions.Count -eq 1) '山莓必须只有一个和平使用动作'
$raspberryAction = $raspberryActions[0]
Require ([string]$raspberryAction.SelectSingleNode('./attribute[@id="ActionType"]').value -eq '7') `
    '山莓必须继续使用官方 ApplyStatus 动作'
$raspberryActionAttributes = $raspberryAction.SelectSingleNode('./children/node[@id="Attributes"]')
Require ([string]$raspberryActionAttributes.SelectSingleNode('./attribute[@id="Consume"]').value -eq 'False' -and
    [string]$raspberryActionAttributes.SelectSingleNode('./attribute[@id="StatsId"]').value -eq 'COS_RASPBERRY_ZERO_HEAL' -and
    [string]$raspberryActionAttributes.SelectSingleNode('./attribute[@id="StatusDuration"]').value -eq '1') `
    '山莓必须不消耗并套用一回合零治疗状态'
[xml]$textureBank = Get-Content -LiteralPath $textureBankSourcePath -Raw -Encoding UTF8
$atlasUuid = [string]([xml](Get-Content -LiteralPath (Join-Path $root "Public\$module\GUI\Icons_ChaosOrigins.lsx") -Raw -Encoding UTF8)).SelectSingleNode('//node[@id="TextureAtlasPath"]/attribute[@id="UUID"]').value
$textureResource = $textureBank.SelectSingleNode('//region[@id="TextureBank"]//node[@id="Resource"]')
Require ($null -ne $textureResource -and `
    [string]$textureResource.SelectSingleNode('./attribute[@id="ID"]').value -eq $atlasUuid -and `
    [string]$textureResource.SelectSingleNode('./attribute[@id="SourceFile"]').value -eq `
        'Public/ChaosOriginsStory/Assets/Textures/Icons/Icons_ChaosOrigins.dds') `
    '技能图集必须有 UUID 和 DDS 路径一致的 TextureBank 注册'

$statusPath = Join-Path $root "Public\$module\Stats\Generated\Data\Status_BOOST.txt"
$statusText = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8
$statusEntries = @([regex]::Matches($statusText, 'new entry "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
$expectedStatusEntries = @(
    @($expectedOriginToggleMappings | ForEach-Object { $_.Split('|')[1] }) +
    'COS_RASPBERRY_ZERO_HEAL'
    'COS_FIXED_GUIDANCE_30'
    @(1..20 | ForEach-Object { 'COS_CFG_LIFE_SKILL_STATUS_{0:D2}' -f $_ })
)
Require ($statusEntries.Count -eq 29 -and -not (Compare-Object $expectedStatusEntries $statusEntries)) `
    '必须定义七个起源身份隐藏状态和一个山莓1点治疗状态'
$raspberryStatusBlock = Get-StatsEntryBlock $statusText 'COS_RASPBERRY_ZERO_HEAL'
$raspberryStatusTypes = @([regex]::Matches($raspberryStatusBlock, '(?m)^type "([^"]+)"\r?$'))
Require ($raspberryStatusTypes.Count -eq 1 -and $raspberryStatusTypes[0].Groups[1].Value -ceq 'StatusData') `
    '山莓1点治疗状态必须唯一声明为 StatusData'
Require (Test-StatsField $raspberryStatusBlock 'StatusType' 'BOOST') `
    '山莓1点治疗状态的 StatusType 必须唯一且为 BOOST'
Require ((Test-StatsUsing $raspberryStatusBlock 'FOOD') -and
    (Test-StatsField $raspberryStatusBlock 'Icon' 'Spell_Transmutation_Goodberry') -and
    (Test-StatsField $raspberryStatusBlock 'StackId' 'FOOD')) `
    '山莓1点治疗状态必须继承官方 FOOD 的治疗表现'
Require (Test-StatsField $raspberryStatusBlock 'OnApplyFunctors' 'RegainHitPoints(1)') `
    '山莓1点治疗状态必须唯一执行 RegainHitPoints(1)'
Require (-not ($raspberryStatusBlock -match 'RegainHitPoints\((?!1\))')) `
    '山莓1点治疗状态不得恢复 1 点以外的生命值'
$expectedRaspberryOneHealBlock = Normalize-LineEndings @'
new entry "COS_RASPBERRY_ZERO_HEAL"
type "StatusData"
data "StatusType" "BOOST"
using "FOOD"
data "Icon" "Spell_Transmutation_Goodberry"
data "StackId" "FOOD"
data "OnApplyFunctors" "RegainHitPoints(1)"
'@
function Test-RaspberryOneHealContract([string]$Block) {
    return (Normalize-LineEndings $Block).Trim() -ceq $expectedRaspberryOneHealBlock.Trim()
}
Require (Test-RaspberryOneHealContract $raspberryStatusBlock) `
    '山莓1点治疗状态必须满足完整七行精确契约'
$raspberryFunctorNeedle = 'data "OnApplyFunctors" "RegainHitPoints(1)"'
$raspberryZeroHealMutation = $raspberryStatusBlock.Replace(
    $raspberryFunctorNeedle,
    'data "OnApplyFunctors" "RegainHitPoints(0)"'
)
Require ($raspberryZeroHealMutation -cne $raspberryStatusBlock -and
    -not (Test-RaspberryOneHealContract $raspberryZeroHealMutation)) `
    '山莓1点治疗契约变异探针必须拒绝 RegainHitPoints(0)'
$raspberryWhitespaceDuplicateMutation = $raspberryStatusBlock.Replace(
    $raspberryFunctorNeedle,
    "$raspberryFunctorNeedle`n $raspberryFunctorNeedle"
)
Require ($raspberryWhitespaceDuplicateMutation -cne $raspberryStatusBlock -and
    -not (Test-RaspberryOneHealContract $raspberryWhitespaceDuplicateMutation)) `
    '山莓1点治疗契约变异探针必须拒绝带前导空白的重复 OnApplyFunctors'
$raspberryOnRemoveMutation = $raspberryStatusBlock.Replace(
    $raspberryFunctorNeedle,
    "$raspberryFunctorNeedle`ndata `"OnRemoveFunctors`" `"RegainHitPoints(1)`""
)
Require ($raspberryOnRemoveMutation -cne $raspberryStatusBlock -and
    -not (Test-RaspberryOneHealContract $raspberryOnRemoveMutation)) `
    '山莓1点治疗契约变异探针必须拒绝 OnRemoveFunctors'
$raspberryExtraDataMutation = $raspberryStatusBlock.Replace(
    $raspberryFunctorNeedle,
    "$raspberryFunctorNeedle`ndata `"Boosts`" `"ArmorClass(1)`""
)
Require ($raspberryExtraDataMutation -cne $raspberryStatusBlock -and
    -not (Test-RaspberryOneHealContract $raspberryExtraDataMutation)) `
    '山莓1点治疗契约变异探针必须拒绝任意额外 data 字段'
Require (-not $raspberryTemplate.OuterXml.Contains('FOOD_FRUIT_GOODBERRY') -and
    -not $statusText.Contains('new entry "FOOD_FRUIT_GOODBERRY"')) `
    '山莓覆盖不得修改神莓术生成物的模板或官方状态'
Require ([regex]::Matches($statusText, 'DisableOverhead;DisablePortraitIndicator;IgnoreResting;ApplyToDead').Count -eq 1) `
    '起源身份状态基类必须隐藏头顶和肖像提示并跨休息保留'

Write-Host 'ChaosOriginsStory final native Story source verification: ok'
