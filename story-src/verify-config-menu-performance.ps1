#requires -Version 7.0
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$categories = @('Core', 'Origin', 'RaceTags', 'Weapon', 'Armor', 'Racial', 'Convenience')
$pagePaths = @(
    'Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu.xaml',
    'Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu_c.xaml'
)

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Required([string]$RelativePath) {
    $path = Join-Path $root $RelativePath
    Require (Test-Path -LiteralPath $path -PathType Leaf) "缺少文件: $RelativePath"
    Get-Content -LiteralPath $path -Raw -Encoding UTF8
}

function Get-XamlNames([string]$Text) {
    @([regex]::Matches($Text, 'x:Name="([^"]+)"') | ForEach-Object {
        $_.Groups[1].Value
    } | Sort-Object -Unique)
}

function Get-ProcedureBlock([string]$Story, [string]$Signature) {
    $escaped = [regex]::Escape($Signature)
    $match = [regex]::Match(
        $Story,
        "(?ms)^PROC\r?\n$escaped.*?(?=^(?:PROC|IF|QRY|EXITSECTION|KBSECTION)\r?$|\z)"
    )
    Require $match.Success "缺少过程: $Signature"
    $match.Value
}

function Get-IfBlock([string]$Story, [string]$ConditionMarker) {
    $blocks = @([regex]::Matches(
        $Story,
        '(?ms)^IF\r?\n.*?(?=^(?:PROC|IF|QRY|EXITSECTION|KBSECTION)\r?$|\z)'
    ) | ForEach-Object { $_.Value })
    $matches = @($blocks | Where-Object { $_.Contains($ConditionMarker) })
    Require ($matches.Count -eq 1) "事件规则数量错误: $ConditionMarker ($($matches.Count))"
    $matches[0]
}

foreach ($relativePath in $pagePaths) {
    $text = Read-Required $relativePath
    try {
        [xml]$null = $text
    }
    catch {
        throw "XAML 不是有效 XML: $relativePath`n$($_.Exception.Message)"
    }

    foreach ($category in $categories) {
        Require (-not $text.Contains("COSCategory${category}ChildMutation")) "仍存在动态分类模板: $relativePath / $category"
        Require (-not $text.Contains("COSCategory${category}PausedOverlay")) "仍存在分类遮罩: $relativePath / $category"
        Require $text.Contains("COSCategory${category}Section") "缺少分类区: $relativePath / $category"
        Require $text.Contains("COSCategory${category}Toggle") "缺少分类总开关: $relativePath / $category"
    }

    Require (-not $text.Contains('COSRuntimeDiagnosticPanel')) "主页面仍渲染大型运行诊断框: $relativePath"
    $statusBindingCount = [regex]::Matches($text, 'CurrentPlayer\.SelectedCharacter\.StatusEffects').Count
    Require ($statusBindingCount -le 2) "状态列表绑定仍会重建页面: $relativePath ($statusBindingCount)"

    $gitPath = $relativePath.Replace('\\', '/')
    $baseline = (& git -C (Split-Path $root -Parent) show "54c1f8c^:story-src/$gitPath" 2>&1) -join "`n"
    Require ($LASTEXITCODE -eq 0) "无法读取旧版完整控件基线: $gitPath"
    $currentNames = Get-XamlNames $text
    $baselineNames = Get-XamlNames $baseline
    $missingNames = @(Compare-Object $currentNames $baselineNames | Where-Object SideIndicator -eq '=>' | ForEach-Object InputObject)
    Require ($missingNames.Count -eq 0) "细分控件缺失: $relativePath / $($missingNames -join ', ')"

    foreach ($name in @(
        'COSPresetNearVanillaButton', 'COSPresetPureChaosButton',
        'COSPresetBalancedButton', 'COSPresetAllConvenienceButton',
        'COSPresetApplyButton', 'COSPresetCancelButton'
    )) {
        Require ($currentNames -contains $name) "缺少预设控件: $relativePath / $name"
    }
}

$story = Read-Required 'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt'
$forbiddenClickCalls = @(
    'PROC_COS_ConfigSyncCharacter(',
    'PROC_COS_ConfigSyncCategoryActual(',
    'PROC_COS_RuntimeDiagnosticUpdate('
)

foreach ($marker in @(
    'DB_COS_ConfigLifeStepEvent(_Event, _Delta)',
    'DB_COS_ConfigLifeResetEvent(_Event)',
    'DB_COS_ConfigRacialEvent(_Event, _Passive)',
    'DB_COS_ConfigRacialBulkEvent(_Event, _Enabled)',
    'DB_COS_ConfigMechanicEvent(_Event, _Key)',
    'DB_COS_ConfigCostStepEvent(_Event, _Key, _Delta)',
    'DB_COS_ConfigCostResetEvent(_Event, _Key)'
)) {
    $block = Get-IfBlock $story $marker
    foreach ($forbidden in $forbiddenClickCalls) {
        Require (-not $block.Contains($forbidden)) "单项点击触发全量刷新: $marker / $forbidden"
    }
}

$categoryToggle = Get-ProcedureBlock $story 'PROC_COS_ConfigToggleCategory((CHARACTER)_Character, (STRING)_Key)'
Require ([regex]::Matches($categoryToggle, 'PROC_COS_ConfigSyncCharacter\(').Count -eq 1) '分类总开关必须且只能执行一次统一同步'

$presetApply = Get-ProcedureBlock $story 'PROC_COS_PresetApply((CHARACTER)_Character)'
Require ([regex]::Matches($presetApply, 'PROC_COS_ConfigSyncCharacter\(').Count -eq 1) '应用预设必须且只能执行一次统一同步'

'CONFIG_MENU_PERFORMANCE=PASS; IN_GAME=PENDING'
