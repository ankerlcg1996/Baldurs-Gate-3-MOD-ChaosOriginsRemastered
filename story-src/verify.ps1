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
    Require ($readmeText.Contains('version.json') -and $readmeText.Contains('26') -and `
        $readmeText.Contains('四个 Goal')) "工程说明必须以version.json为准并记录26文件/4 Goals: $readmePath"
}

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
    'Mods/ChaosOriginsStory/meta.lsx',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_BaseAfterCreation.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMastery.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMechanics.txt',
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
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosDamage.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosFeatures.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosMastery.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosRuntime.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/Interrupt.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/Passive.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/Status_BOOST.txt',
    'Public/ChaosOriginsStory/Tags/2c237035-d1a9-4469-91de-d74d8464c8d5.lsf'
) | Sort-Object

$manifestPath = Join-Path $root 'package-files.json'
Require (Test-Path -LiteralPath $manifestPath -PathType Leaf) '缺少 package-files.json'
$manifestDocument = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Require ($manifestDocument.schema -eq 1) '不支持的打包清单格式'
$manifest = @($manifestDocument.files | Sort-Object)
Require ($manifest.Count -eq 26 -and @($manifest | Select-Object -Unique).Count -eq 26) `
    '原生 Story 打包清单必须恰好包含 26 个唯一文件'
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
$expectedMasteryEntries = @(
    'COS_ChaosMasteryGuide',
    'COS_ChaosMasteryPointL01',
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
Require ($masteryEntryNames.Count -eq 12 -and -not (Compare-Object $expectedMasteryEntries $masteryEntryNames)) `
    '一级 ChaosMastery.txt 必须且只能包含掌控资源、母子技能、路线状态和结果状态'
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

$masteryRequiredLines = @{
    COS_ChaosMasteryGuide = @('type "PassiveData"', 'data "DisplayName" "h1253cd25g6db6g4704g90e7gadf6ad0df3ed;1"', 'data "Description" "h11f157e4g81c1g4dc8gbd3eg20fbb820812f;1"', 'data "Icon" "COS_Mastery"', 'data "Properties" "Highlighted"', 'data "Boosts" ""')
    COS_ChaosMasteryPointL01 = @('type "PassiveData"', 'data "Icon" "COS_Mastery"', 'data "Properties" "IsHidden"', 'data "Boosts" "ActionResource(COS_ChaosMasteryPoint,1,0)"', 'data "StatsFunctorContext" "OnCreate"', 'data "StatsFunctors" "RestoreResource(COS_ChaosMasteryPoint,100%,0)"')
    Shout_COS_ChaosMastery = @('type "SpellData"', 'using "Shout_ActionSurge"', 'data "SpellType" "Shout"', 'data "Level" "0"', 'data "ContainerSpells" "Shout_COS_ChaosMasteryTune;Shout_COS_ChaosMasteryCorrect"', 'data "AIFlags" "CanNotUse"', 'data "TargetConditions" "Self()"', 'data "Icon" "COS_Mastery"', 'data "DisplayName" "h1253cd25g6db6g4704g90e7gadf6ad0df3ed;1"', 'data "Description" "h11f157e4g81c1g4dc8gbd3eg20fbb820812f;1"', 'data "UseCosts" ""', 'data "SpellFlags" "IsLinkedSpellContainer"', 'data "SpellProperties" ""', 'data "TooltipStatusApply" ""', 'data "Requirements" ""', 'data "Cooldown" ""')
    Shout_COS_ChaosMasteryTune = @('type "SpellData"', 'using "Shout_COS_ChaosMastery"', 'data "SpellContainerID" "Shout_COS_ChaosMastery"', 'data "ContainerSpells" ""', 'data "Icon" "COS_MasteryTune"', 'data "DisplayName" "hbfabec61g3070g4e70g8e71gc20633da5d52;1"', 'data "Description" "h0cf72805gf1e4g4f89gbc8fgb4eb4561d859;1"', 'data "UseCosts" "COS_ChaosMasteryPoint:1"', 'data "SpellProperties" "ApplyStatus(SELF,COS_CHAOS_MASTERY_TUNE,100,-1)"', 'data "TooltipStatusApply" "ApplyStatus(COS_CHAOS_MASTERY_TUNE,100,-1)"', 'data "SpellFlags" ""', 'data "AIFlags" ""', 'data "Requirements" ""', 'data "Cooldown" ""', 'data "TargetConditions" "Self()"')
    Shout_COS_ChaosMasteryCorrect = @('type "SpellData"', 'using "Shout_COS_ChaosMastery"', 'data "SpellContainerID" "Shout_COS_ChaosMastery"', 'data "ContainerSpells" ""', 'data "Icon" "COS_MasteryCorrect"', 'data "DisplayName" "h03a4fec8gb0efg45f9g8c5fgfd91d085f127;1"', 'data "Description" "h0a9761a0g8ebeg4517ga88bgc9605641ea43;1"', 'data "UseCosts" "COS_ChaosMasteryPoint:1"', 'data "SpellProperties" "ApplyStatus(SELF,COS_CHAOS_MASTERY_CORRECT,100,-1)"', 'data "TooltipStatusApply" "ApplyStatus(COS_CHAOS_MASTERY_CORRECT,100,-1)"', 'data "SpellFlags" ""', 'data "AIFlags" ""', 'data "Requirements" ""', 'data "Cooldown" ""', 'data "TargetConditions" "Self()"')
    COS_CHAOS_MASTERY_TUNE = @('type "StatusData"', 'using "COS_CHAOS_RACE_TEMPLATE"', 'data "DisplayName" "hbfabec61g3070g4e70g8e71gc20633da5d52;1"', 'data "Description" "h46000001g0001g4001g8001g000000000001;1"', 'data "Icon" "COS_MasteryTune"', 'data "StackId" "COS_CHAOS_MASTERY_TUNE"', 'data "StackType" "Additive"', 'data "StatusPropertyFlags" "DisableOverhead;DisableCombatlog;IgnoreResting;FreezeDuration"')
    COS_CHAOS_MASTERY_CORRECT = @('type "StatusData"', 'using "COS_CHAOS_RACE_TEMPLATE"', 'data "DisplayName" "h03a4fec8gb0efg45f9g8c5fgfd91d085f127;1"', 'data "Description" "h46000002g0002g4002g8002g000000000002;1"', 'data "Icon" "COS_MasteryCorrect"', 'data "StackId" "COS_CHAOS_MASTERY_CORRECT"', 'data "StackType" "Additive"', 'data "StatusPropertyFlags" "DisableOverhead;DisableCombatlog;IgnoreResting;FreezeDuration"')
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
    'COS_ChaosOriginMarker',
    'COS_BaseProficiencies',
    'COS_BaseStarterSpells',
    'COS_Origin_Astarion',
    'COS_Origin_Gale',
    'COS_Origin_Laezel',
    'COS_Origin_Shadowheart',
    'COS_Origin_Wyll',
    'COS_Origin_Karlach',
    'COS_Origin_DarkUrge',
    'COS_FateRevision',
    'COS_ChaosTooltipTemplate'
) + $tooltipPassiveEntries
Require ($passiveEntries.Count -eq $expectedPassiveEntries.Count -and -not (Compare-Object $expectedPassiveEntries $passiveEntries)) `
    'Passive.txt 必须且只能定义基础、身份、命运改签与黄色词条代理被动'
Require ([regex]::Matches($passive, 'data "Properties" "IsHidden"').Count -eq 3) '三项基础被动必须全部隐藏'
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
Require ($passive.Contains('Proficiency(LightArmor);Proficiency(MediumArmor);Proficiency(HeavyArmor);Proficiency(Shields);Proficiency(SimpleWeapons);Proficiency(MartialWeapons);Proficiency(MusicalInstrument)')) `
    '基础熟练清单未与 ChaosOriginsRemastered 1.0.25 对齐'
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
$expectedHandles = (@($descriptionHandle, $displayHandle) + $identityHandles + $masteryLocalizationHandles) | Sort-Object
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
        h11f157e4g81c1g4dc8gbd3eg20fbb820812f = '消耗1点掌控混沌，选择增加1层调律或厄兆纠偏。洗点会清空路线并返还该点。'
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
        h46000001g0001g4001g8001g000000000001 = '当前1层。受击轮盘：正面164/300（54.7%），负面136/300（45.3%），平息0/300。已将2个负面格改为正面格。'
        h46000002g0002g4002g8002g000000000002 = '当前1层。受击轮盘：正面162/300（54.0%），负面134/300（44.7%），平息4/300（1.3%）。已将4个负面格改为平息格。'
    }
    English = @{
        h0d010313gb67fg4c89ga5b9g30c58d4fb2f9 = 'Chaos Mastery Point'
        hf1437f68g6231g4f22gb12ega9bcfc6189d8 = 'Hidden resource. Chaos Origin gains 1 point per level, up to 12 points; resting does not restore it.'
        h1253cd25g6db6g4704g90e7gadf6ad0df3ed = 'Chaos Mastery'
        h11f157e4g81c1g4dc8gbd3eg20fbb820812f = 'Spend 1 Chaos Mastery point to gain 1 Attunement or Omen Correction stack. Respeccing clears the route and returns that point.'
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
        h46000001g0001g4001g8001g000000000001 = 'Current: 1 stack. Wound wheel: Positive 164/300 (54.7%), Negative 136/300 (45.3%), Calm 0/300. Two negative cells have become positive.'
        h46000002g0002g4002g8002g000000000002 = 'Current: 1 stack. Wound wheel: Positive 162/300 (54.0%), Negative 134/300 (44.7%), Calm 4/300 (1.3%). Four negative cells have become calm.'
    }
    Japanese = @{
        h0d010313gb67fg4c89ga5b9g30c58d4fb2f9 = '混沌掌握ポイント'
        hf1437f68g6231g4f22gb12ega9bcfc6189d8 = '非表示のリソース。混沌の起源はレベルごとに1ポイントを獲得し、最大12ポイント。休息では回復しない。'
        h1253cd25g6db6g4704g90e7gadf6ad0df3ed = '混沌掌握'
        h11f157e4g81c1g4dc8gbd3eg20fbb820812f = '混沌掌握ポイントを1消費し、調律または凶兆補正を1スタック得る。再訓練するとルートを消去し、そのポイントを返還する。'
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
        h46000001g0001g4001g8001g000000000001 = '現在1スタック。被撃ルーレット：正効果164/300（54.7%）、負効果136/300（45.3%）、鎮静0/300。負効果2マスを正効果へ変更済み。'
        h46000002g0002g4002g8002g000000000002 = '現在1スタック。被撃ルーレット：正効果162/300（54.0%）、負効果134/300（44.7%）、鎮静4/300（1.3%）。負効果4マスを鎮静へ変更済み。'
    }
    Korean = @{
        h0d010313gb67fg4c89ga5b9g30c58d4fb2f9 = '혼돈 통제 점수'
        hf1437f68g6231g4f22gb12ega9bcfc6189d8 = '숨겨진 자원입니다. 혼돈 기원은 레벨마다 1점을 얻으며 최대 12점까지 보유합니다. 휴식으로 회복되지 않습니다.'
        h1253cd25g6db6g4704g90e7gadf6ad0df3ed = '혼돈 통제'
        h11f157e4g81c1g4dc8gbd3eg20fbb820812f = '혼돈 통제 점수 1을 소모해 조율 또는 흉조 교정 1중첩을 얻습니다. 재분배하면 경로를 초기화하고 해당 점수를 돌려받습니다.'
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
        h46000001g0001g4001g8001g000000000001 = '현재 1중첩. 피격 룰렛: 긍정 164/300(54.7%), 부정 136/300(45.3%), 진정 0/300. 부정 2칸을 긍정으로 전환했습니다.'
        h46000002g0002g4002g8002g000000000002 = '현재 1중첩. 피격 룰렛: 긍정 162/300(54.0%), 부정 134/300(44.7%), 진정 4/300(1.3%). 부정 4칸을 진정으로 전환했습니다.'
    }
}
$referenceLocalizationHandles = $null
$referenceProxyTooltipKeys = $null
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
    $tuneDescription = [string]$contentsByHandle['h0cf72805gf1e4g4f89gbc8fgb4eb4561d859'].InnerText
    Require (-not [regex]::IsMatch($tuneDescription, '(?:\+1%|-1%)')) `
        "调律说明仍使用旧百分比: $language"
    Require ($handles.Count -eq 648 -and @($handles | Select-Object -Unique).Count -eq 648) `
        "完整本地化必须包含 648 个唯一文本: $language"
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

$storyPath = Join-Path $root "Mods\$module\Story"
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
$goals = @(Get-ChildItem -LiteralPath (Split-Path $goalPath -Parent) -File -Filter '*.txt')
Require ($goals.Count -eq 4 -and ($goals.FullName -contains $goalPath) -and `
    ($goals.FullName -contains $masteryGoalPath) -and ($goals.FullName -contains $rewardGoalPath) -and `
    ($goals.FullName -contains $mechanicsGoalPath)) `
    '当前 Story 必须且只能包含基础同步、掌控混沌、混沌机制和起源剧情奖励四个 Goal'
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

function Test-COSMasteryLedgerSemantics([string]$Story) {
    if ($Story -match 'GetActionResourceValuePersonal|TimerLaunch|SetEntityEvent|ParentTargetEdge|ApplyStatus\(') { return $false }
    if ($Story -match 'COS_ChaosMasteryPointL(?:0[2-9]|1[0-2])') { return $false }
    if ([regex]::Matches($Story, '(?m)^DB_COS_MasteryCarrier\(1, "COS_ChaosMasteryPointL01"\);$').Count -ne 1) { return $false }
    if ($Story -notmatch 'DB_COS_MasteryUnspent\(' -or $Story -notmatch 'DB_COS_MasterySchema44To45\(') { return $false }
    if ($Story -match '(?m)^NOT DB_COS_MasteryEarned\([^\n]+\);$') { return $false }

    $syncBlocks = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_SyncMastery')
    if ($syncBlocks.Count -ne 3) { return $false }
    $guideSync = @($syncBlocks | Where-Object {
        $_.Contains('HasPassive(_Character, "COS_ChaosMasteryGuide", 0)')
    })
    $migratedSync = @($syncBlocks | Where-Object {
        $_.Contains('DB_COS_MasterySchema44To45(_Character)') -and
        -not $_.Contains('NOT DB_COS_MasterySchema44To45(_Character)')
    })
    $unmigratedSync = @($syncBlocks | Where-Object {
        $_.Contains('NOT DB_COS_MasterySchema44To45(_Character)')
    })
    if ($guideSync.Count -ne 1 -or $migratedSync.Count -ne 1 -or $unmigratedSync.Count -ne 1) { return $false }
    foreach ($block in $syncBlocks) {
        if (-not $block.Contains('HasPassive(_Character, "COS_ChaosOriginMarker", 1)')) { return $false }
    }
    if (-not (Test-MasteryActions $guideSync[0] @('AddPassive(_Character, "COS_ChaosMasteryGuide");'))) { return $false }
    if (-not (Test-MasteryActions $migratedSync[0] @('PROC_COS_SyncMasteryAfterSchema45(_Character);'))) { return $false }
    if (-not (Test-MasteryActions $unmigratedSync[0] @('PROC_COS_MigrateMasterySchema44To45(_Character);'))) { return $false }

    $migrationBlocks = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_MigrateMasterySchema44To45')
    if ($migrationBlocks.Count -ne 3) { return $false }
    foreach ($block in $migrationBlocks) {
        if (-not $block.Contains('NOT DB_COS_MasterySchema44To45(_Character)')) { return $false }
    }
    $recoverMigration = @($migrationBlocks | Where-Object {
        $_.Contains('DB_COS_MasteryEarned(_Character, 1)') -and
        $_.Contains('HasPassive(_Character, _Carrier, 1)')
    })
    $spentMigration = @($migrationBlocks | Where-Object {
        $_.Contains('DB_COS_MasteryEarned(_Character, 1)') -and
        $_.Contains('HasPassive(_Character, _Carrier, 0)')
    })
    $freshMigration = @($migrationBlocks | Where-Object {
        $_.Contains('NOT DB_COS_MasteryEarned(_Character, 1)')
    })
    if ($recoverMigration.Count -ne 1 -or $spentMigration.Count -ne 1 -or $freshMigration.Count -ne 1) { return $false }
    if (-not $recoverMigration[0].Contains('DB_COS_MasteryCarrier(1, _Carrier)') -or
        -not $recoverMigration[0].Contains('NOT DB_COS_MasteryUnspent(_Character, 1)')) { return $false }
    if (-not (Test-MasteryActions $recoverMigration[0] @(
        'DB_COS_MasteryUnspent(_Character, 1);',
        'DB_COS_MasterySchema44To45(_Character);',
        'PROC_COS_SyncMasteryAfterSchema45(_Character);'
    ))) { return $false }
    if (-not $spentMigration[0].Contains('DB_COS_MasteryCarrier(1, _Carrier)') -or
        $spentMigration[0].Contains('DB_COS_MasteryUnspent(') -or
        -not (Test-MasteryActions $spentMigration[0] @(
            'DB_COS_MasterySchema44To45(_Character);',
            'PROC_COS_SyncMasteryAfterSchema45(_Character);'
        ))) { return $false }
    if ($freshMigration[0].Contains('DB_COS_MasteryUnspent(') -or
        -not (Test-MasteryActions $freshMigration[0] @(
            'DB_COS_MasterySchema44To45(_Character);',
            'PROC_COS_SyncMasteryAfterSchema45(_Character);'
        ))) { return $false }

    $afterMigrationBlocks = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_SyncMasteryAfterSchema45')
    if ($afterMigrationBlocks.Count -ne 1 -or
        -not $afterMigrationBlocks[0].Contains('GetLevel(_Character, _Level)') -or
        -not $afterMigrationBlocks[0].Contains('IntegerMin(_Level, 1, _Cap)') -or
        -not (Test-MasteryActions $afterMigrationBlocks[0] @(
            'PROC_COS_EnsureMasteryCounts(_Character);',
            'PROC_COS_GrantMasteryFrom(_Character, 1, _Cap);'
        ))) { return $false }

    $grantBlocks = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_GrantMasteryFrom')
    if ($grantBlocks.Count -ne 3) { return $false }
    $freshGrant = @($grantBlocks | Where-Object { $_.Contains('NOT DB_COS_MasteryEarned(_Character, _Cursor)') })
    $knownGrant = @($grantBlocks | Where-Object {
        $_.Contains('DB_COS_MasteryEarned(_Character, _Cursor)') -and
        -not $_.Contains('NOT DB_COS_MasteryEarned(_Character, _Cursor)')
    })
    $grantEnd = @($grantBlocks | Where-Object { $_.Contains('_Cursor > _Cap') })
    if ($freshGrant.Count -ne 1 -or $knownGrant.Count -ne 1 -or $grantEnd.Count -ne 1) { return $false }
    if (-not $freshGrant[0].Contains('DB_COS_MasteryCarrier(_Cursor, _Carrier)') -or
        -not $freshGrant[0].Contains('HasPassive(_Character, _Carrier, 0)') -or
        -not (Test-MasteryActions $freshGrant[0] @(
            'AddPassive(_Character, _Carrier);',
            'DB_COS_MasteryEarned(_Character, _Cursor);',
            'DB_COS_MasteryUnspent(_Character, _Cursor);',
            'PROC_COS_GrantMasteryFrom(_Character, _Next, _Cap);'
        ))) { return $false }
    if (-not (Test-MasteryActions $knownGrant[0] @('PROC_COS_GrantMasteryFrom(_Character, _Next, _Cap);'))) { return $false }
    if (-not (Test-MasteryActions $grantEnd[0] @('PROC_COS_UpdateMasterySpell(_Character);'))) { return $false }

    $updateBlocks = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_UpdateMasterySpell')
    if ($updateBlocks.Count -ne 2) { return $false }
    $showMastery = @($updateBlocks | Where-Object { $_.Contains('DB_COS_MasteryUnspent(_Character, 1)') -and -not $_.Contains('NOT DB_COS_MasteryUnspent(_Character, 1)') })
    $hideMastery = @($updateBlocks | Where-Object { $_.Contains('NOT DB_COS_MasteryUnspent(_Character, 1)') })
    if ($showMastery.Count -ne 1 -or $hideMastery.Count -ne 1) { return $false }
    if (-not $showMastery[0].Contains('HasSpell(_Character, "Shout_COS_ChaosMastery", 0)') -or
        -not (Test-MasteryActions $showMastery[0] @('AddSpell(_Character, "Shout_COS_ChaosMastery", 0, 1);'))) { return $false }
    if (-not $hideMastery[0].Contains('HasSpell(_Character, "Shout_COS_ChaosMastery", 1)') -or
        -not (Test-MasteryActions $hideMastery[0] @('RemoveSpell(_Character, "Shout_COS_ChaosMastery", 1);'))) { return $false }

    $consumeBlocks = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_ConsumeMasteryCarrier')
    if ($consumeBlocks.Count -ne 1 -or
        -not $consumeBlocks[0].Contains('DB_COS_MasteryUnspent(_Character, _Level)') -or
        -not $consumeBlocks[0].Contains('DB_COS_MasteryCarrier(_Level, _Carrier)') -or
        -not $consumeBlocks[0].Contains('HasPassive(_Character, _Carrier, 1)') -or
        -not (Test-MasteryActions $consumeBlocks[0] @(
            'NOT DB_COS_MasteryUnspent(_Character, _Level);',
            'RemovePassive(_Character, _Carrier);',
            'PROC_COS_UpdateMasterySpell(_Character);'
        ))) { return $false }

    foreach ($clearSpec in @(
        @{ Proc = 'PROC_COS_ClearMasteryUnspent'; Fact = 'DB_COS_MasteryUnspent'; Variable = '_Level' },
        @{ Proc = 'PROC_COS_ClearMasteryTuneCount'; Fact = 'DB_COS_MasteryTuneCount'; Variable = '_Count' },
        @{ Proc = 'PROC_COS_ClearMasteryCorrectCount'; Fact = 'DB_COS_MasteryCorrectCount'; Variable = '_Count' }
    )) {
        $clearBlocks = @(Get-MasteryStoryBlocks $Story 'PROC' $clearSpec.Proc)
        $fact = $clearSpec.Fact + '(_Character, ' + $clearSpec.Variable + ')'
        if ($clearBlocks.Count -ne 1 -or -not $clearBlocks[0].Contains($fact) -or
            -not (Test-MasteryActions $clearBlocks[0] @(('NOT ' + $fact + ';')))) { return $false }
    }

    $resetBlocks = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_ResetMastery')
    if ($resetBlocks.Count -ne 1 -or -not (Test-MasteryActions $resetBlocks[0] @(
        'DB_COS_MasterySchema44To45(_Character);',
        'DB_COS_MasteryEarned(_Character, 1);',
        'RemoveStatus(_Character, "COS_CHAOS_MASTERY_TUNE", _Character);',
        'RemoveStatus(_Character, "COS_CHAOS_MASTERY_CORRECT", _Character);',
        'PROC_COS_ClearMasteryUnspent(_Character);',
        'PROC_COS_ClearMasteryTuneCount(_Character);',
        'PROC_COS_ClearMasteryCorrectCount(_Character);',
        'DB_COS_MasteryTuneCount(_Character, 0);',
        'DB_COS_MasteryCorrectCount(_Character, 0);',
        'PROC_COS_RebuildMasteryAfterRespec(_Character);'
    ))) { return $false }
    if ($resetBlocks[0].Contains('RemovePassive(') -or
        [regex]::Matches($resetBlocks[0], '(?m)^DB_COS_MasteryEarned\(_Character, 1\);$').Count -ne 1) { return $false }

    $respecBlocks = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_RebuildMasteryAfterRespec')
    if ($respecBlocks.Count -ne 2) { return $false }
    $keepCarrier = @($respecBlocks | Where-Object { $_.Contains('HasPassive(_Character, _Carrier, 1)') })
    $restoreCarrier = @($respecBlocks | Where-Object { $_.Contains('HasPassive(_Character, _Carrier, 0)') })
    if ($keepCarrier.Count -ne 1 -or $restoreCarrier.Count -ne 1) { return $false }
    foreach ($block in $respecBlocks) {
        if (-not $block.Contains('DB_COS_MasteryEarned(_Character, 1)') -or
            -not $block.Contains('DB_COS_MasteryCarrier(1, _Carrier)') -or
            -not $block.Contains('NOT DB_COS_MasteryUnspent(_Character, 1)') -or
            $block.Contains('RemovePassive(')) { return $false }
    }
    if (-not (Test-MasteryActions $keepCarrier[0] @(
        'DB_COS_MasteryUnspent(_Character, 1);',
        'PROC_COS_UpdateMasterySpell(_Character);'
    ))) { return $false }
    if (-not (Test-MasteryActions $restoreCarrier[0] @(
        'AddPassive(_Character, _Carrier);',
        'DB_COS_MasteryUnspent(_Character, 1);',
        'PROC_COS_UpdateMasterySpell(_Character);'
    ))) { return $false }

    foreach ($route in @(
        @{ Spell = 'Shout_COS_ChaosMasteryTune'; Count = 'DB_COS_MasteryTuneCount' },
        @{ Spell = 'Shout_COS_ChaosMasteryCorrect'; Count = 'DB_COS_MasteryCorrectCount' }
    )) {
        $blocks = @(@(Get-MasteryStoryBlocks $Story 'IF' 'CastedSpell') | Where-Object {
            $_.Contains('CastedSpell(_Character, "' + $route.Spell + '", _, _, _)')
        })
        if ($blocks.Count -ne 1) { return $false }
        $block = $blocks[0]
        if (-not $block.Contains('HasPassive(_Character, "COS_ChaosOriginMarker", 1)') -or
            -not $block.Contains('DB_COS_MasteryUnspent((CHARACTER)_Character, 1)') -or
            -not $block.Contains('DB_COS_MasteryCarrier(1, _Carrier)') -or
            -not $block.Contains('HasPassive(_Character, _Carrier, 1)') -or
            -not $block.Contains($route.Count + '((CHARACTER)_Character, _Count)') -or
            -not $block.Contains('IntegerSum(_Count, 1, _Next)') -or
            -not (Test-MasteryActions $block @(
                ('NOT ' + $route.Count + '((CHARACTER)_Character, _Count);'),
                ($route.Count + '((CHARACTER)_Character, _Next);'),
                'PROC_COS_ConsumeMasteryCarrier((CHARACTER)_Character, 1);'
            ))) { return $false }
    }

    return $true
}

function Invoke-COSMasteryRespecModel(
    [string[]]$Actions,
    [bool]$InitialSchema,
    [bool]$InitialEarned,
    [int]$InitialCarrierCount,
    [int]$InitialUnspentCount
) {
    $state = [ordered]@{
        Schema = $InitialSchema
        Earned = $InitialEarned
        CarrierCount = $InitialCarrierCount
        UnspentCount = $InitialUnspentCount
        TuneCount = 1
        CorrectCount = 1
    }
    foreach ($action in $Actions) {
        switch -CaseSensitive ($action) {
            'DB_COS_MasterySchema44To45(_Character);' { $state.Schema = $true }
            'DB_COS_MasteryEarned(_Character, 1);' { $state.Earned = $true }
            'RemoveStatus(_Character, "COS_CHAOS_MASTERY_TUNE", _Character);' { }
            'RemoveStatus(_Character, "COS_CHAOS_MASTERY_CORRECT", _Character);' { }
            'PROC_COS_ClearMasteryUnspent(_Character);' { $state.UnspentCount = 0 }
            'PROC_COS_ClearMasteryTuneCount(_Character);' { $state.TuneCount = 0 }
            'PROC_COS_ClearMasteryCorrectCount(_Character);' { $state.CorrectCount = 0 }
            'DB_COS_MasteryTuneCount(_Character, 0);' { $state.TuneCount = 0 }
            'DB_COS_MasteryCorrectCount(_Character, 0);' { $state.CorrectCount = 0 }
            'PROC_COS_RebuildMasteryAfterRespec(_Character);' {
                if (-not $state.Schema -or -not $state.Earned) { return $null }
                if ($state.CarrierCount -eq 0) { $state.CarrierCount = 1 }
                if ($state.CarrierCount -ne 1) { return $null }
                $state.UnspentCount = 1
            }
            default { return $null }
        }
    }
    return [pscustomobject]$state
}

function Test-COSMasteryFirstRespecStateMachine([string]$Story) {
    $resetBlocks = @(Get-MasteryStoryBlocks $Story 'PROC' 'PROC_COS_ResetMastery')
    if ($resetBlocks.Count -ne 1) { return $false }
    $actions = @(Get-MasteryThenActions $resetBlocks[0])
    if ($actions.Count -ne 10 -or
        $actions[0] -cne 'DB_COS_MasterySchema44To45(_Character);' -or
        $actions[1] -cne 'DB_COS_MasteryEarned(_Character, 1);') { return $false }
    foreach ($initialSchema in @($false, $true)) {
        foreach ($initialEarned in @($false, $true)) {
            foreach ($initialCarrier in @(0, 1)) {
                foreach ($initialUnspent in @(0, 1)) {
                    $result = Invoke-COSMasteryRespecModel `
                        $actions $initialSchema $initialEarned $initialCarrier $initialUnspent
                    if ($null -eq $result -or -not $result.Schema -or -not $result.Earned -or
                        $result.CarrierCount -ne 1 -or $result.UnspentCount -ne 1 -or
                        $result.TuneCount -ne 0 -or $result.CorrectCount -ne 0) { return $false }
                    # 下一次 Sync 必须走 Schema1 分支，不能再次进入 .44 -> .45 迁移。
                    if (-not $result.Schema) { return $false }
                }
            }
        }
    }
    # 两个化身分别执行同一角色键控序列；第二个化身在自己的事件前保持原态。
    $first = Invoke-COSMasteryRespecModel $actions $false $false 0 0
    $secondBefore = [pscustomobject]@{ Schema = $false; Earned = $false; CarrierCount = 1; UnspentCount = 0 }
    if (-not $first.Schema -or -not $first.Earned -or $secondBefore.Schema -or $secondBefore.Earned -or
        $secondBefore.CarrierCount -ne 1 -or $secondBefore.UnspentCount -ne 0) { return $false }
    $second = Invoke-COSMasteryRespecModel $actions $secondBefore.Schema $secondBefore.Earned `
        $secondBefore.CarrierCount $secondBefore.UnspentCount
    if (-not $second.Schema -or -not $second.Earned -or $second.CarrierCount -ne 1 -or
        $second.UnspentCount -ne 1 -or $first.CarrierCount -ne 1 -or $first.UnspentCount -ne 1) { return $false }
    return $true
}

Require (Test-COSMasteryFirstRespecStateMachine $masteryGoal) `
    'Respec 必须先按角色写入 Schema1/Earned1，再把全部合法L1状态唯一归一为 Carrier1/Unspent1'
Require (Test-COSMasteryLedgerSemantics $masteryGoal) `
    '掌控混沌 Story 必须以角色级 Unspent 账本授予/消费/洗点并完成 .44 到 .45 一次性迁移'

$masteryRespecWithoutSchemaMutant = $masteryGoal.Replace(
    "PROC_COS_ResetMastery((CHARACTER)_Character)`nTHEN`nDB_COS_MasterySchema44To45(_Character);",
    "PROC_COS_ResetMastery((CHARACTER)_Character)`nTHEN"
)
Require ($masteryRespecWithoutSchemaMutant -cne $masteryGoal -and `
    -not (Test-COSMasteryFirstRespecStateMachine $masteryRespecWithoutSchemaMutant)) `
    '首次 Respec 静态状态机变异未拒绝 Reset 漏写 Schema1'

$masteryRespecLateSchemaMutant = $masteryGoal.Replace(
    "PROC_COS_ResetMastery((CHARACTER)_Character)`nTHEN`nDB_COS_MasterySchema44To45(_Character);",
    "PROC_COS_ResetMastery((CHARACTER)_Character)`nTHEN"
).Replace(
    "DB_COS_MasteryCorrectCount(_Character, 0);`nPROC_COS_RebuildMasteryAfterRespec(_Character);",
    "DB_COS_MasteryCorrectCount(_Character, 0);`nPROC_COS_RebuildMasteryAfterRespec(_Character);`nDB_COS_MasterySchema44To45(_Character);"
)
Require ($masteryRespecLateSchemaMutant -cne $masteryGoal -and `
    -not (Test-COSMasteryFirstRespecStateMachine $masteryRespecLateSchemaMutant)) `
    '首次 Respec 静态状态机变异未拒绝 Schema1 晚于重建动作'

$masteryRespecWithoutEarnedMutant = $masteryGoal.Replace(
    "DB_COS_MasterySchema44To45(_Character);`nDB_COS_MasteryEarned(_Character, 1);",
    'DB_COS_MasterySchema44To45(_Character);'
)
Require ($masteryRespecWithoutEarnedMutant -cne $masteryGoal -and `
    -not (Test-COSMasteryFirstRespecStateMachine $masteryRespecWithoutEarnedMutant)) `
    'Respec 静态状态机变异未拒绝 Earned=false 无法归一'

$masteryRespecLateEarnedMutant = $masteryGoal.Replace(
    "DB_COS_MasterySchema44To45(_Character);`nDB_COS_MasteryEarned(_Character, 1);",
    'DB_COS_MasterySchema44To45(_Character);'
).Replace(
    "PROC_COS_RebuildMasteryAfterRespec(_Character);",
    "PROC_COS_RebuildMasteryAfterRespec(_Character);`nDB_COS_MasteryEarned(_Character, 1);"
)
Require ($masteryRespecLateEarnedMutant -cne $masteryGoal -and `
    -not (Test-COSMasteryFirstRespecStateMachine $masteryRespecLateEarnedMutant)) `
    'Respec 静态状态机变异未拒绝 Earned1 晚于重建动作'

$masteryRaceMutant = $masteryGoal.Replace(
    "AND`nDB_COS_MasteryUnspent(_Character, 1)`nAND`nHasSpell(_Character, `"Shout_COS_ChaosMastery`", 0)",
    "AND`nGetActionResourceValuePersonal(_Character, `"COS_ChaosMasteryPoint`", 0, _Points)`nAND`n_Points > 0.0`nAND`nHasSpell(_Character, `"Shout_COS_ChaosMastery`", 0)"
)
Require ($masteryRaceMutant -cne $masteryGoal -and -not (Test-COSMasteryLedgerSemantics $masteryRaceMutant)) `
    '掌控混沌静态变异检查未拒绝 AddPassive 后同帧资源查询竞态'

$masteryRepeatMigrationMutant = $masteryGoal.Replace(
    "DB_COS_MasteryUnspent(_Character, 1);`nDB_COS_MasterySchema44To45(_Character);`nPROC_COS_SyncMasteryAfterSchema45(_Character);",
    "DB_COS_MasteryUnspent(_Character, 1);`nPROC_COS_SyncMasteryAfterSchema45(_Character);"
)
Require ($masteryRepeatMigrationMutant -cne $masteryGoal -and -not (Test-COSMasteryLedgerSemantics $masteryRepeatMigrationMutant)) `
    '掌控混沌静态变异检查未拒绝可重复执行的迁移'

$masteryShowWithoutUnspentMutant = $masteryGoal.Replace(
    "PROC_COS_UpdateMasterySpell((CHARACTER)_Character)`nAND`nDB_COS_MasteryUnspent(_Character, 1)`nAND`nHasSpell(_Character, `"Shout_COS_ChaosMastery`", 0)",
    "PROC_COS_UpdateMasterySpell((CHARACTER)_Character)`nAND`nDB_COS_MasteryEarned(_Character, 1)`nAND`nHasSpell(_Character, `"Shout_COS_ChaosMastery`", 0)"
)
Require ($masteryShowWithoutUnspentMutant -cne $masteryGoal -and -not (Test-COSMasteryLedgerSemantics $masteryShowWithoutUnspentMutant)) `
    '掌控混沌静态变异检查未拒绝无 Unspent 仍显示母技能'

$masteryRegrantSpentMutant = $masteryGoal.Replace(
    "HasPassive(_Character, _Carrier, 0)`nTHEN`nDB_COS_MasterySchema44To45(_Character);",
    "HasPassive(_Character, _Carrier, 0)`nTHEN`nDB_COS_MasteryUnspent(_Character, 1);`nDB_COS_MasterySchema44To45(_Character);"
)
Require ($masteryRegrantSpentMutant -cne $masteryGoal -and -not (Test-COSMasteryLedgerSemantics $masteryRegrantSpentMutant)) `
    '掌控混沌静态变异检查未拒绝已消费旧存档被迁移重补'

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
    '(?i)Dialog(?:ue)?', '(?i)Default', 'ApplyStatus\('
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
$mechanicsGoal = Get-Content -LiteralPath $mechanicsGoalPath -Raw -Encoding UTF8
Require (-not $mechanicsGoal.Contains('COS_ChaosMastery')) `
    '一级原生选择切片不得提前修改两仪或受击轮盘逻辑'
foreach ($requiredMechanicsText in @(
    'PROC_COS_RollWound', 'PROC_COS_ResolveDuality', 'PROC_COS_AddPower', 'PROC_COS_AddLost',
    'Shout_COS_ChaosGenesis', 'AttackedBy(', 'TurnStarted(', 'EnteredCombat(', 'LeftCombat(',
    'UsingSpell(_Character, "Shout_COS_TestPower100"', 'PROC_COS_AddPower((CHARACTER)_Character, 100)',
    'RestorePartyFinished()', 'COS_CHAOS_RESTORE_ALLIN', 'Random(100, _DualityRoll)',
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
    $giftCandidateBlocks[0].Contains('DB_COS_MasteryGift(_MinimumLevel, _Outcome, _Weight, _Rank)') -and `
    $giftCandidateBlocks[0].Contains('_Level >= _MinimumLevel') -and $giftCandidateBlocks[0].Contains('_Layer <= _Weight')) `
    '掌控混沌礼物候选必须按等级和权重加入'
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
$rollTrialActions = @(Get-MechanicsThenActions $rollTrialBlocks[0])
$tuneCellMatches = @([regex]::Matches($rollTrialBlocks[0], '(?m)^IntegerProduct\(_TuneCount, (\d+), _TuneCells\)$'))
$calmCellMatches = @([regex]::Matches($rollTrialBlocks[0], '(?m)^IntegerProduct\(_CorrectCount, (\d+), _CalmCells\)$'))
$positiveBaseMatches = @([regex]::Matches($rollTrialBlocks[0], '(?m)^IntegerSum\((\d+), _TuneCells, _PositiveEnd\)$'))
$calmEndMatches = @([regex]::Matches($rollTrialBlocks[0], '(?m)^IntegerSum\(_PositiveEnd, _CalmCells, _CalmEnd\)$'))
Require ($tuneCellMatches.Count -eq 1 -and [int]$tuneCellMatches[0].Groups[1].Value -eq 2) `
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
Require ($rollTrialBlocks.Count -eq 1 -and ([regex]::Matches($rollTrialBlocks[0], 'Random\(300, _CategoryRoll\)').Count -eq 1) -and `
    $rollTrialBlocks[0].Contains('DB_COS_MasteryTuneCount(_Character, _TuneCount)') -and `
    $rollTrialBlocks[0].Contains('DB_COS_MasteryCorrectCount(_Character, _CorrectCount)') -and `
    $rollTrialBlocks[0].Contains('IntegerProduct(_TuneCount, 2, _TuneCells)') -and `
    $rollTrialBlocks[0].Contains('IntegerProduct(_CorrectCount, 4, _CalmCells)') -and `
    $rollTrialActions.Count -eq 1 -and `
    $rollTrialActions[0] -ceq 'PROC_COS_DispatchWoundCategory(_Character, _Damage, _PowerEligible, _Remaining, _HasBest, _BestOutcome, _BestRank, _CategoryRoll, _PositiveEnd, _CalmEnd);') `
    '每次受击试炼必须只生成一次300格类别随机并交给分类过程'
Require ([regex]::Matches($mechanicsGoal, 'Random\(300').Count -eq 1) '受击机制全文必须且只能有一次Random(300)调用'

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
Require (-not ($allStats -match 'ProficiencyBonus\(Skill|ExpertiseBonus\(')) `
    '完整 Stats 不得额外授予任何技能熟练或专精'
Require ([regex]::Matches($mechanicsGoal, 'DB_COS_LifeSkillLevel\(\d+, \d+, "COS_CHAOS_LIFE_SKILL_BONUS_\d"\);').Count -eq 7) `
    '生活检定成长必须严格包含 5 至 30 级的 7 个阶段'
foreach ($lifeSkillBonus in 1..7) {
    $lifeSkillEntry = "COS_CHAOS_LIFE_SKILL_BONUS_$lifeSkillBonus"
    $lifeSkillPattern = 'new entry "{0}"[\s\S]*?(?=\r?\nnew entry|\z)' -f [regex]::Escape($lifeSkillEntry)
    $lifeSkillBlock = [regex]::Match($allStats, $lifeSkillPattern).Value
    Require ($lifeSkillBlock.Contains("RollBonus(SkillCheck,$lifeSkillBonus);RollBonus(RawAbility,$lifeSkillBonus)")) `
        "生活检定成长档位错误: $lifeSkillEntry"
}
Require ($mechanicsGoal.Contains('IntegerMin(_Level, 30, _CappedLevel)') -and `
    $mechanicsGoal.Contains('PROC_COS_ClearLifeSkillBonus(_Character);') -and `
    $mechanicsGoal.Contains('PROC_COS_ApplyLifeSkillBonus(_Character);')) `
    '生活检定成长必须封顶 30 级并在同步时替换旧档位'
Require (-not ($allStats -match 'COS_ChaosEcho|COS_CHAOS_ECHO_LOG_|COS_CHAOS_SENTINEL_ECHO_')) `
    '完整 Stats 不得保留混沌回响定义'
$featuresPath = Join-Path $root "Public\$module\Stats\Generated\Data\ChaosFeatures.txt"
$featuresText = Get-Content -LiteralPath $featuresPath -Raw -Encoding UTF8
Require ($featuresText.Contains('new entry "Shout_COS_TestPower100"') -and `
    $featuresText.Contains('data "UseCosts" ""')) `
    '测试阶段必须提供无消耗的100点混沌之力技能'
Require ($featuresText.Contains('new entry "Shout_COS_TestRestoreAllIn"') -and `
    $featuresText.Contains('ApplyStatus(SELF,COS_CHAOS_RESTORE_ALLIN,100,0.1)')) `
    '测试阶段必须提供恢复全部孤注充能的技能'
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
    $_.Contains('DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Duality", 1)') -and
    $_.Contains('COS_CHAOS_FATE_ENABLED')
})
Require ($dualityAttackBlocks.Count -eq 5) '两仪入口必须严格包含关闭、未记录、禁用资源、资源为0和命运改签五个互斥分支'
$fateOffBlocks = @($dualityAttackBlocks | Where-Object { @(Get-MechanicsConditions $_) -contains 'HasActiveStatus(_AttackOwner, "COS_CHAOS_FATE_ENABLED", 0)' })
$fateUnarmedBlocks = @($dualityAttackBlocks | Where-Object { @(Get-MechanicsConditions $_) -contains 'NOT DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)' })
$fatePowerDisabledBlocks = @($dualityAttackBlocks | Where-Object { @(Get-MechanicsConditions $_) -contains 'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Power", 0)' })
$fatePowerZeroBlocks = @($dualityAttackBlocks | Where-Object { @(Get-MechanicsConditions $_) -contains 'DB_COS_Power((CHARACTER)_AttackOwner, 0)' })
$fateDualityBlock = @($dualityAttackBlocks | Where-Object { @(Get-MechanicsConditions $_) -contains 'DB_COS_Power((CHARACTER)_AttackOwner, _OldPower)' })
Require ($fateOffBlocks.Count -eq 1 -and $fateUnarmedBlocks.Count -eq 1 -and `
    $fatePowerDisabledBlocks.Count -eq 1 -and $fatePowerZeroBlocks.Count -eq 1 -and `
    $fateDualityBlock.Count -eq 1) `
    '两仪五个攻击分支必须各自唯一且可明确分类'
$dualityCommonConditions = @(
    'AttackedBy(_Target, _AttackOwner, _Attacker, _, _Damage, _, _StoryActionID)',
    '_AttackOwner == _Attacker',
    'DB_COS_Character((CHARACTER)_AttackOwner)',
    'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Duality", 1)',
    'HasPassive(_AttackOwner, "COS_ChaosDuality", 1)'
)
$expectedFateOffConditions = @($dualityCommonConditions + @(
    'HasActiveStatus(_AttackOwner, "COS_CHAOS_FATE_ENABLED", 0)',
    'IsCharacter(_Target, 1)', '_Damage > 0', 'Random(100, _DualityRoll)'
))
$expectedFateUnarmedConditions = @($dualityCommonConditions + @(
    'HasActiveStatus(_AttackOwner, "COS_CHAOS_FATE_ENABLED", 1)',
    'NOT DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)',
    'IsCharacter(_Target, 1)', '_Damage > 0', 'Random(100, _DualityRoll)'
))
$expectedFatePowerDisabledConditions = @($dualityCommonConditions + @(
    'HasActiveStatus(_AttackOwner, "COS_CHAOS_FATE_ENABLED", 1)',
    'DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)',
    'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Power", 0)',
    'IsCharacter(_Target, 1)', '_Damage > 0', 'Random(100, _DualityRoll)'
))
$expectedFatePowerZeroConditions = @($dualityCommonConditions + @(
    'HasActiveStatus(_AttackOwner, "COS_CHAOS_FATE_ENABLED", 1)',
    'DB_COS_FateAction((CHARACTER)_AttackOwner, _StoryActionID)',
    'DB_COS_ConfigMechanic((CHARACTER)_AttackOwner, "Power", 1)',
    'DB_COS_Power((CHARACTER)_AttackOwner, 0)',
    'IsCharacter(_Target, 1)', '_Damage > 0', 'Random(100, _DualityRoll)'
))
$expectedFateDualityConditions = @($dualityCommonConditions + @(
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
Require (((Get-MechanicsConditions $fateOffBlocks[0]) -join "`n") -ceq ($expectedFateOffConditions -join "`n") -and `
    ((Get-MechanicsThenActions $fateOffBlocks[0]) -join "`n") -ceq ((@('PROC_COS_ClearFateAction((CHARACTER)_AttackOwner);') + $expectedNormalDualityActions) -join "`n")) `
    '命运改签关闭分支必须清除旧记录并执行一次普通两仪'
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
    '命运改签行动记录的全部读写位置必须严格受限于清理、建立和五个结算分支'
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
Require ($resourceSources.Count -eq 2 -and $resourceSources.FullName -contains $tagPath -and `
    $resourceSources.FullName -contains $textureBankSourcePath) `
    '资源源目录必须只包含起源标签和技能图标 TextureBank'
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
$expectedStatusEntries = @($expectedOriginToggleMappings | ForEach-Object { $_.Split('|')[1] })
Require ($statusEntries.Count -eq 7 -and -not (Compare-Object $expectedStatusEntries $statusEntries)) `
    '必须且只能定义七个起源身份隐藏状态'
Require ([regex]::Matches($statusText, 'DisableOverhead;DisablePortraitIndicator;IgnoreResting;ApplyToDead').Count -eq 1) `
    '起源身份状态基类必须隐藏头顶和肖像提示并跨休息保留'

Write-Host 'ChaosOriginsStory final native Story source verification: ok'
