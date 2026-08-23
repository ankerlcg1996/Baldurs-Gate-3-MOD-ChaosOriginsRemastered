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

$expectedPackageFiles = @(
    'Localization/Chinese/ChaosOriginsStory.loca',
    'Localization/English/ChaosOriginsStory.loca',
    'Localization/Japanese/ChaosOriginsStory.loca',
    'Localization/Korean/ChaosOriginsStory.loca',
    'Mods/ChaosOriginsStory/meta.lsx',
    'Public/ChaosOriginsStory/Origins/Origins.lsx',
    'Public/ChaosOriginsStory/Stats/Generated/Data/Passive.txt',
    'Public/ChaosOriginsStory/Tags/2c237035-d1a9-4469-91de-d74d8464c8d5.lsf'
) | Sort-Object

$manifestPath = Join-Path $root 'package-files.json'
Require (Test-Path -LiteralPath $manifestPath -PathType Leaf) '缺少 package-files.json'
$manifestDocument = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Require ($manifestDocument.schema -eq 1) '不支持的打包清单格式'
$manifest = @($manifestDocument.files | Sort-Object)
Require ($manifest.Count -eq 8 -and @($manifest | Select-Object -Unique).Count -eq 8) `
    '最小起源打包清单必须恰好包含 8 个唯一文件'
Require (-not (Compare-Object $expectedPackageFiles $manifest)) '最小起源打包清单内容错误'

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
$dependencies = @($meta.SelectNodes('//node[@id="Dependencies"]/children/node[@id="ModuleShortDesc"]'))
Require ($dependencies.Count -eq 1) '最小起源必须只声明 GustavDev 依赖'
$dependencyAttributes = @{}
foreach ($attribute in @($dependencies[0].SelectNodes('attribute'))) { $dependencyAttributes[[string]$attribute.id] = [string]$attribute.value }
Require ($dependencyAttributes.Folder -eq 'GustavDev') '最小起源依赖目录必须为 GustavDev'
Require ($dependencyAttributes.UUID -eq '28ac9ce2-2aba-8cda-b3b5-6e922f71b6b8') 'GustavDev UUID 错误'
Require (@($moduleInfo.SelectNodes('children/node[@id="Scripts"]/children/node')).Count -eq 0) `
    '最小起源不得声明额外脚本模块'
Require (@($moduleInfo.SelectNodes('children/node[@id="TargetModes"]/children/node[@id="Target"]/attribute[@id="Object" and @value="Story"]')).Count -eq 1) `
    '模块必须声明 Story TargetMode'

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
    Passives = 'DeathSavingThrows;COS_ChaosOriginMarker'
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

$passivePath = Join-Path $root "Public\$module\Stats\Generated\Data\Passive.txt"
$passive = (Get-Content -LiteralPath $passivePath -Raw -Encoding UTF8).Trim()
$passiveEntries = @([regex]::Matches($passive, 'new entry "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
Require ($passiveEntries.Count -eq 1 -and $passiveEntries[0] -eq 'COS_ChaosOriginMarker') `
    '最小包只能定义 COS_ChaosOriginMarker'
Require ($passive.Contains('data "Properties" "IsHidden"')) '起源标记必须隐藏'
Require (-not ($passive -match 'Boosts|UnlockSpell|Toggle')) '起源标记不得附带玩法效果'

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

$expectedHandles = @($descriptionHandle, $displayHandle) | Sort-Object
foreach ($language in @('Chinese', 'English', 'Japanese', 'Korean')) {
    $path = Join-Path $root "Localization\$language\ChaosOriginsStory.xml"
    Require (Test-Path -LiteralPath $path -PathType Leaf) "缺少本地化源: $language"
    [xml]$localization = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $contents = @($localization.contentList.content)
    $handles = @($contents | ForEach-Object { [string]$_.contentuid } | Sort-Object)
    Require ($handles.Count -eq 2 -and -not (Compare-Object $expectedHandles $handles)) `
        "最小本地化必须只包含名称和说明: $language"
    foreach ($content in $contents) {
        Require (-not [string]::IsNullOrWhiteSpace([string]$content.InnerText)) "本地化包含空文本: $language"
    }
}

$storyPath = Join-Path $root "Mods\$module\Story"
Require (-not (Test-Path -LiteralPath $storyPath)) '最小起源阶段不得包含 Story Goals 或编译 Story'
$formalFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'Mods') -Recurse -File) + `
    @(Get-ChildItem -LiteralPath (Join-Path $root 'Public') -Recurse -File)
Require ($formalFiles.Count -eq 3) '最小正式源必须只有 meta、Origins 和 Passive 三个文件'
foreach ($file in $formalFiles) {
    $text = [IO.File]::ReadAllText($file.FullName)
    Require (-not ($text -match 'ScriptExtender|MCM|TutorialEvent|COS_ChaosIdentity|COS_ChaosStatus')) `
        "最小正式源夹带了后续系统: $($file.FullName)"
}

$resourceSources = @(Get-ChildItem -LiteralPath (Join-Path $root 'resource-src') -Recurse -File -Filter '*.lsx')
Require ($resourceSources.Count -eq 1 -and $resourceSources[0].FullName -eq $tagPath) `
    '最小资源源目录只能包含起源标签'

Write-Host 'ChaosOriginsStory minimal origin source verification: ok'
