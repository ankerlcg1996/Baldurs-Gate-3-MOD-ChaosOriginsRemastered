#requires -Version 7.0

param(
    [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

function Require {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Read-Required {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Require (Test-Path -LiteralPath $Path -PathType Leaf) "缺少文件: $Path"
    Get-Content -Raw -LiteralPath $Path -Encoding UTF8
}

function Test-ExactOrdinalSet {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Actual,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Expected
    )

    if ($Actual.Count -ne $Expected.Count) {
        return $false
    }

    $actualSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($value in $Actual) {
        if (-not $actualSet.Add($value)) {
            return $false
        }
    }

    $expectedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($value in $Expected) {
        if (-not $expectedSet.Add($value)) {
            return $false
        }
    }

    $actualSet.SetEquals($expectedSet)
}

function Test-ExactOrdinalSequence {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Actual,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Expected
    )

    if ($Actual.Count -ne $Expected.Count) {
        return $false
    }

    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ($Actual[$index] -cne $Expected[$index]) {
            return $false
        }
    }

    return $true
}

function Get-OsirisRuleBlocks {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    @(
        [regex]::Matches(
            $Content,
            '(?ms)^(?:IF|PROC)\r?\n.*?(?=^(?:IF|PROC|EXITSECTION)\r?$|\z)'
        ) | ForEach-Object { $_.Value }
    )
}

function Get-ProcedureBlocks {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $escapedName = [regex]::Escape($Name)
    @(
        Get-OsirisRuleBlocks -Content $Content |
            Where-Object { [regex]::IsMatch($_, "(?s)\APROC\r?\n$escapedName\(") }
    )
}

function Get-ThenBody {
    param(
        [Parameter(Mandatory)]
        [string]$Block
    )

    $parts = [regex]::Split($Block, '(?m)^THEN\s*$', 2)
    Require ($parts.Count -eq 2) 'Osiris 规则缺少 THEN'
    $parts[1]
}

function Assert-MutationRejected {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Probe
    )

    $rejected = $false
    try {
        & $Probe
    }
    catch {
        $rejected = $true
    }

    Require $rejected "变异探针未被拒绝: $Name"
}

function Replace-FirstLiteral {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$OldValue,

        [Parameter(Mandatory)]
        [string]$NewValue,

        [Parameter(Mandatory)]
        [string]$ProbeName
    )

    $index = $Content.IndexOf($OldValue, [System.StringComparison]::Ordinal)
    Require ($index -ge 0) "变异探针缺少真实锚点: $ProbeName"
    $Content.Substring(0, $index) + $NewValue + $Content.Substring($index + $OldValue.Length)
}

function Replace-RuleBlock {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$OldBlock,

        [Parameter(Mandatory)]
        [string]$NewBlock,

        [Parameter(Mandatory)]
        [string]$ProbeName
    )

    $index = $Content.IndexOf($OldBlock, [System.StringComparison]::Ordinal)
    Require ($index -ge 0) "变异探针无法定位规则: $ProbeName"
    $Content.Substring(0, $index) + $NewBlock + $Content.Substring($index + $OldBlock.Length)
}

function Get-StatsEntries {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $matches = [regex]::Matches(
        $Content,
        '(?ms)^new entry "([^"]+)"\r?\n(.*?)(?=^new entry |\z)'
    )
    @(
        foreach ($match in $matches) {
            [pscustomobject]@{
                Name = $match.Groups[1].Value
                Body = $match.Groups[2].Value
                Source = $match.Value
            }
        }
    )
}

function Get-StatsDataFields {
    param(
        [Parameter(Mandatory)]
        [psobject]$Entry
    )

    $fields = [ordered]@{}
    foreach ($match in [regex]::Matches($Entry.Body, '(?m)^data "([^"]+)" "([^"]*)"\s*$')) {
        $name = $match.Groups[1].Value
        Require (-not $fields.Contains($name)) "Stats entry 包含重复字段: $($Entry.Name).$name"
        $fields[$name] = $match.Groups[2].Value
    }
    $fields
}

function Get-HandleWithoutVersion {
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$Context
    )

    $match = [regex]::Match($Value, '^([^;\s]+)(?:;1)?$')
    Require $match.Success "本地化 handle 格式错误: $Context"
    $match.Groups[1].Value
}

function Get-XamlNamedNodes {
    param(
        [Parameter(Mandatory)]
        [xml]$Document,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $namespaceManager = [System.Xml.XmlNamespaceManager]::new($Document.NameTable)
    $namespaceManager.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
    @($Document.SelectNodes("//*[@x:Name='$Name']", $namespaceManager))
}

function Get-XamlName {
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlElement]$Node
    )

    $Node.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
}

function Get-NamedNodeOrder {
    param(
        [Parameter(Mandatory)]
        [xml]$Document
    )

    @(
        $Document.SelectNodes('//*') |
            ForEach-Object { Get-XamlName -Node $_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Assert-OrderedSubset {
    param(
        [Parameter(Mandatory)]
        [string[]]$Actual,

        [Parameter(Mandatory)]
        [string[]]$Expected,

        [Parameter(Mandatory)]
        [string]$Context
    )

    $lastIndex = -1
    foreach ($value in $Expected) {
        $matches = @($Actual | Where-Object { $_ -ceq $value })
        Require ($matches.Count -eq 1) "$Context 命名节点必须唯一: $value"
        $index = [Array]::IndexOf($Actual, $value)
        Require ($index -gt $lastIndex) "$Context 节点顺序错误: $value"
        $lastIndex = $index
    }
}

function Assert-CategoryMappingContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ExpectedCategories
    )

    $matches = @([regex]::Matches(
        $Content,
        '(?m)^\s*DB_COS_ConfigCategoryMirror\("([^"]+)", "([^"]+)"\);\s*$'
    ))

    foreach ($category in $ExpectedCategories.Keys) {
        $categoryMatches = @($matches | Where-Object { $_.Groups[1].Value -ceq $category })
        Require ($categoryMatches.Count -ge 1) "缺少分类映射: $category"
        Require ($categoryMatches.Count -eq 1) "分类映射不唯一: $category"
        Require ($categoryMatches[0].Groups[2].Value -ceq $ExpectedCategories[$category]) "分类镜像错误: $category"
    }

    $actualPairs = @($matches | ForEach-Object { '{0}|{1}' -f $_.Groups[1].Value, $_.Groups[2].Value })
    $expectedPairs = @($ExpectedCategories.Keys | ForEach-Object { '{0}|{1}' -f $_, $ExpectedCategories[$_] })
    Require (Test-ExactOrdinalSet -Actual $actualPairs -Expected $expectedPairs) '分类映射集合不精确'
}

function Assert-LegacyDetectionContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string[]]$ExpectedTables
    )

    $matches = @([regex]::Matches(
        $Content,
        '(?m)^\s*DB_COS_ConfigLegacyTable\("([^"]+)"\);\s*$'
    ))
    $actualTables = @($matches | ForEach-Object { $_.Groups[1].Value })
    Require (Test-ExactOrdinalSet -Actual $actualTables -Expected $ExpectedTables) '旧档识别表集合不精确'

    foreach ($table in $ExpectedTables) {
        Require ([regex]::Matches($Content, [regex]::Escape($table)).Count -ge 2) "旧档识别未实际检查: $table"
    }
}

function Assert-PresetDetectionOrderContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string[]]$ExpectedOrder
    )

    $blocks = @(Get-ProcedureBlocks -Content $Content -Name 'PROC_COS_PresetDetectCurrent')
    Require ($blocks.Count -eq 1) '预设检测过程必须恰好有一个规则'
    $block = $blocks[0]
    $positions = [System.Collections.Generic.List[int]]::new()
    foreach ($preset in $ExpectedOrder) {
        $token = if ($preset -ceq 'Custom') {
            'PROC_COS_PresetDetectCustom(_Character);'
        }
        else {
            "PROC_COS_PresetDetectCandidate(_Character, `"$preset`");"
        }
        Require ([regex]::Matches($block, [regex]::Escape($token)).Count -eq 1) "预设检测步骤不唯一或缺失: $preset"
        $positions.Add($block.IndexOf($token, [System.StringComparison]::Ordinal))
    }

    for ($index = 1; $index -lt $positions.Count; $index++) {
        Require ($positions[$index] -gt $positions[$index - 1]) "预设检测顺序错误: $($ExpectedOrder[$index])"
    }
}

function Assert-PresetMatrixContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ExpectedMatrix,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ExpectedLife
    )

    $categoryMatches = @([regex]::Matches(
        $Content,
        '(?m)^\s*DB_COS_PresetCategory\("([^"]+)", "([^"]+)", (-?\d+)\);\s*$'
    ))
    $actualRows = @(
        $categoryMatches | ForEach-Object {
            '{0}|{1}|{2}' -f $_.Groups[1].Value, $_.Groups[2].Value, $_.Groups[3].Value
        }
    )
    $expectedRows = @(
        foreach ($preset in $ExpectedMatrix.Keys) {
            foreach ($category in $ExpectedMatrix[$preset].Keys) {
                '{0}|{1}|{2}' -f $preset, $category, $ExpectedMatrix[$preset][$category]
            }
        }
    )
    Require ($actualRows.Count -eq 28) "预设分类矩阵行数错误: 期望 28，实际 $($actualRows.Count)"
    Require (Test-ExactOrdinalSet -Actual $actualRows -Expected $expectedRows) '预设分类矩阵不精确'

    $lifeMatches = @([regex]::Matches(
        $Content,
        '(?m)^\s*DB_COS_PresetLife\("([^"]+)", (\d+)\);\s*$'
    ))
    $actualLifeRows = @($lifeMatches | ForEach-Object { '{0}|{1}' -f $_.Groups[1].Value, $_.Groups[2].Value })
    $expectedLifeRows = @($ExpectedLife.Keys | ForEach-Object { '{0}|{1}' -f $_, $ExpectedLife[$_] })
    Require ($actualLifeRows.Count -eq 4) "预设生活加值矩阵行数错误: 期望 4，实际 $($actualLifeRows.Count)"
    Require (Test-ExactOrdinalSet -Actual $actualLifeRows -Expected $expectedLifeRows) '预设生活加值矩阵不精确'
}

function Assert-EventMapContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ExpectedCategoryEvents,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ExpectedPresetEvents
    )

    $categoryMatches = @([regex]::Matches(
        $Content,
        '(?m)^\s*DB_COS_ConfigCategoryEvent\(\(TUTORIALEVENT\)[A-Za-z0-9_]*([0-9a-f]{8}-[0-9a-f-]{27}), "([^"]+)"\);\s*$'
    ))
    $actualCategoryRows = @($categoryMatches | ForEach-Object { '{0}|{1}' -f $_.Groups[2].Value, $_.Groups[1].Value })
    $expectedCategoryRows = @($ExpectedCategoryEvents.Keys | ForEach-Object { '{0}|{1}' -f $_, $ExpectedCategoryEvents[$_] })
    Require (Test-ExactOrdinalSet -Actual $actualCategoryRows -Expected $expectedCategoryRows) '分类事件 UUID 映射不精确'

    $selectMatches = @([regex]::Matches(
        $Content,
        '(?m)^\s*DB_COS_PresetSelectEvent\(\(TUTORIALEVENT\)[A-Za-z0-9_]*([0-9a-f]{8}-[0-9a-f-]{27}), "([^"]+)"\);\s*$'
    ))
    $actualPresetRows = @($selectMatches | ForEach-Object { '{0}|{1}' -f $_.Groups[2].Value, $_.Groups[1].Value })
    foreach ($action in @('Apply', 'Cancel')) {
        $tableName = "DB_COS_Preset${action}Event"
        $matches = @([regex]::Matches(
            $Content,
            "(?m)^\s*$tableName\(\(TUTORIALEVENT\)[A-Za-z0-9_]*([0-9a-f]{8}-[0-9a-f-]{27})\);\s*$"
        ))
        Require ($matches.Count -eq 1) "预设事件映射缺失或重复: $action"
        $actualPresetRows += '{0}|{1}' -f $action, $matches[0].Groups[1].Value
    }
    $expectedPresetRows = @($ExpectedPresetEvents.Keys | ForEach-Object { '{0}|{1}' -f $_, $ExpectedPresetEvents[$_] })
    Require (Test-ExactOrdinalSet -Actual $actualPresetRows -Expected $expectedPresetRows) '预设事件 UUID 映射不精确'
}

function Assert-CategoryInitializationContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string[]]$Categories
    )

    $ensureBlocks = @(Get-ProcedureBlocks -Content $Content -Name 'PROC_COS_ConfigEnsureCategories')
    Require ($ensureBlocks.Count -eq 1) '分类统一初始化入口必须恰好有一个规则'
    foreach ($token in @(
        'NOT DB_COS_ConfigCategorySchema(_Character)',
        'PROC_COS_ConfigDetectLegacy(_Character);',
        'PROC_COS_ConfigInitCategoriesNew(_Character);',
        'PROC_COS_ConfigInitCategoriesLegacy(_Character);'
    )) {
        Require ($ensureBlocks[0].Contains($token)) "分类初始化入口缺少: $token"
    }

    $initializerBlocks = [ordered]@{
        New = @(Get-ProcedureBlocks -Content $Content -Name 'PROC_COS_ConfigInitCategoriesNew')
        Legacy = @(Get-ProcedureBlocks -Content $Content -Name 'PROC_COS_ConfigInitCategoriesLegacy')
    }
    foreach ($kind in $initializerBlocks.Keys) {
        $blocks = @($initializerBlocks[$kind])
        Require ($blocks.Count -eq 1) "$kind 分类初始化规则必须唯一"
        $block = $blocks[0]
        Require ($block.Contains('NOT DB_COS_ConfigCategorySchema(_Character)')) "$kind 分类初始化缺少 schema 幂等门控"
        $legacyToken = if ($kind -ceq 'Legacy') {
            'DB_COS_ConfigLegacyDetected(_Character)'
        }
        else {
            'NOT DB_COS_ConfigLegacyDetected(_Character)'
        }
        Require ($block.Contains($legacyToken)) "$kind 分类初始化分支门控错误"
        foreach ($category in $Categories) {
            Require ([regex]::Matches($block, "PROC_COS_ConfigInitCategory\(_Character, `"$category`", -?\d+\);").Count -eq 1) "$kind 分类初始化行缺失或重复: $category"
        }
        Require ([regex]::Matches($block, 'PROC_COS_ConfigCommitCategorySchema\(_Character\);').Count -eq 1) "$kind 分类 schema 提交调用缺失或重复"
        $commitIndex = $block.IndexOf('PROC_COS_ConfigCommitCategorySchema(_Character);', [System.StringComparison]::Ordinal)
        foreach ($category in $Categories) {
            Require ($block.IndexOf("`"$category`"", [System.StringComparison]::Ordinal) -lt $commitIndex) "$kind 分类 schema 在七行之前提交"
        }
    }

    $rowBlocks = @(Get-ProcedureBlocks -Content $Content -Name 'PROC_COS_ConfigInitCategory')
    Require ($rowBlocks.Count -eq 1) '分类单行初始化规则必须唯一'
    Require ($rowBlocks[0].Contains('NOT DB_COS_ConfigCategory(_Character, _Category, _)')) '分类单行初始化缺少幂等门控'
    Require ([regex]::Matches((Get-ThenBody -Block $rowBlocks[0]), '(?m)^\s*DB_COS_ConfigCategory\(_Character, _Category, _Value\);\s*$').Count -eq 1) '分类单行初始化写入不精确'

    $commitBlocks = @(Get-ProcedureBlocks -Content $Content -Name 'PROC_COS_ConfigCommitCategorySchema')
    Require ($commitBlocks.Count -eq 1) '分类 schema 提交规则必须唯一'
    $commitBlock = $commitBlocks[0]
    foreach ($category in $Categories) {
        Require ([regex]::Matches($commitBlock, "(?m)^\s*DB_COS_ConfigCategory\(_Character, `"$category`", _[A-Za-z0-9]+\)\s*$").Count -eq 1) "分类 schema 提交未检查: $category"
    }
    Require ($commitBlock.Contains('NOT DB_COS_ConfigCategorySchema(_Character)')) '分类 schema 提交缺少幂等门控'
    $commitBody = Get-ThenBody -Block $commitBlock
    Require ([regex]::Matches($commitBody, '(?m)^\s*DB_COS_ConfigCategorySchema\(_Character\);\s*$').Count -eq 1) '分类 schema 必须且只能提交一次'

    $syncBlocks = @(Get-ProcedureBlocks -Content $Content -Name 'PROC_COS_ConfigSyncCharacter')
    Require ($syncBlocks.Count -eq 1) '统一角色同步入口必须唯一'
    $syncActions = @(
        (Get-ThenBody -Block $syncBlocks[0]) -split '\r?\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('//') }
    )
    Require ($syncActions.Count -gt 0 -and $syncActions[0] -ceq 'PROC_COS_ConfigEnsureCategories(_Character);') '首次分类初始化不是统一角色同步第一步'
}

function Assert-EventGuardContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $families = [ordered]@{
        Category = 'DB_COS_ConfigCategoryEvent\(_Event,'
        PresetSelect = 'DB_COS_PresetSelectEvent\(_Event,'
        PresetApply = 'DB_COS_PresetApplyEvent\(_Event\)'
        PresetCancel = 'DB_COS_PresetCancelEvent\(_Event\)'
    }
    foreach ($family in $families.Keys) {
        $blocks = @(
            Get-OsirisRuleBlocks -Content $Content |
                Where-Object {
                    $_.StartsWith("IF`n", [System.StringComparison]::Ordinal) -or
                    $_.StartsWith("IF`r`n", [System.StringComparison]::Ordinal)
                } |
                Where-Object { [regex]::IsMatch($_, $families[$family]) }
        )
        Require ($blocks.Count -eq 1) "修改事件处理规则缺失或重复: $family"
        foreach ($guard in @(
            'HasPassive(_Character, "COS_ChaosOriginMarker", 1)',
            'IsControlled(_Character, 1)',
            'IsInCombat(_Character, 0)'
        )) {
            Require ($blocks[0].Contains($guard)) "修改事件缺少门控: $family $guard"
        }
    }
}

function Assert-PresetWorkflowContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $selectionBlocks = @(
        Get-OsirisRuleBlocks -Content $Content |
            Where-Object { $_.Contains('DB_COS_PresetSelectEvent(_Event, _Preset)') }
    )
    Require ($selectionBlocks.Count -eq 1) '预设选择事件规则必须唯一'
    Require ($selectionBlocks[0].Contains('PROC_COS_PresetPreview(_Character, _Preset);')) '预设选择必须生成预览'
    Require (-not $selectionBlocks[0].Contains('PROC_COS_PresetApply(')) '预设选择不得直接应用'

    $applyBlocks = @(Get-ProcedureBlocks -Content $Content -Name 'PROC_COS_PresetApply')
    Require ($applyBlocks.Count -eq 1) '预设应用过程必须唯一'
    Require ($applyBlocks[0].Contains('DB_COS_PresetPending(_Character, _Preset)')) '预设应用缺少 pending 选择'
    Require ($applyBlocks[0].Contains('DB_COS_PresetPreviewReady(_Character, _Preset)')) '预设应用绕过预览'
    Require ($applyBlocks[0].Contains('PROC_COS_PresetApplyCategories(_Character, _Preset);')) '预设应用未连接分类矩阵'
    Require ($applyBlocks[0].Contains('PROC_COS_PresetApplyLife(_Character, _Preset);')) '预设应用未连接生活加值矩阵'

    $categoryLoopBlocks = @(Get-ProcedureBlocks -Content $Content -Name 'PROC_COS_PresetApplyCategories')
    Require ($categoryLoopBlocks.Count -eq 1) '预设分类矩阵应用规则必须唯一'
    Require ($categoryLoopBlocks[0].Contains('DB_COS_PresetCategory(_Preset, _Category, _Value)')) '预设分类应用未读取矩阵'
    Require ((Get-ThenBody -Block $categoryLoopBlocks[0]).Contains('PROC_COS_PresetApplyCategory(_Character, _Category, _Value);')) '预设分类矩阵未连接单行应用'

    $categoryApplyBlocks = @(Get-ProcedureBlocks -Content $Content -Name 'PROC_COS_PresetApplyCategory')
    Require ($categoryApplyBlocks.Count -eq 1) '预设分类应用规则必须唯一'
    Require ($categoryApplyBlocks[0].Contains('_Value >= 0')) '预设分类应用缺少 -1 通配保护'
    Require ([regex]::IsMatch((Get-ThenBody -Block $categoryApplyBlocks[0]), '(?m)^\s*(?:NOT\s+)?DB_COS_ConfigCategory\(')) '预设分类应用没有写入分类记录'

    $lifeApplyBlocks = @(Get-ProcedureBlocks -Content $Content -Name 'PROC_COS_PresetApplyLife')
    Require ($lifeApplyBlocks.Count -eq 1) '预设生活加值应用规则必须唯一'
    Require ($lifeApplyBlocks[0].Contains('DB_COS_PresetLife(_Preset, _Value)')) '预设生活加值应用未读取矩阵'
    Require ((Get-ThenBody -Block $lifeApplyBlocks[0]).Contains('PROC_COS_ConfigSetLifeSkill(_Character, _Value);')) '预设生活加值未写入批准配置'

    foreach ($presetBlock in @($applyBlocks) + @($categoryLoopBlocks) + @($categoryApplyBlocks) + @($lifeApplyBlocks)) {
        Require (-not [regex]::IsMatch((Get-ThenBody -Block $presetBlock), 'DB_COS_ConfigCategory\([^;\r\n]*"Origin"')) 'PureChaos Origin 通配被直接写入'
    }

    $cancelBlocks = @(Get-ProcedureBlocks -Content $Content -Name 'PROC_COS_PresetCancel')
    Require ($cancelBlocks.Count -ge 1) '预设取消过程缺失'
    Require (($cancelBlocks -join "`n").Contains('DB_COS_PresetPending')) '预设取消没有清理 pending 状态'
}

function Assert-PresetWriteContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $forbiddenTables = @(
        'DB_COS_ConfigMechanic',
        'DB_COS_ConfigRacial',
        'DB_COS_GrantSetting',
        'DB_COS_TagSpellsSetting',
        'DB_COS_VoloEyeSetting',
        'DB_COS_CarrySetting',
        'DB_COS_ConfigCost'
    )
    $applyBlocks = @(
        Get-OsirisRuleBlocks -Content $Content |
            Where-Object { [regex]::IsMatch($_, '(?m)^PROC_COS_PresetApply[A-Za-z0-9_]*\(') }
    )
    Require ($applyBlocks.Count -ge 2) '预设应用规则集合不完整'

    foreach ($block in $applyBlocks) {
        $body = Get-ThenBody -Block $block
        $writes = @([regex]::Matches($body, '(?m)^\s*(?:NOT\s+)?(DB_COS_[A-Za-z0-9_]+)\s*\('))
        foreach ($write in $writes) {
            $table = $write.Groups[1].Value
            $allowed = (
                $table -ceq 'DB_COS_ConfigCategory' -or
                $table -ceq 'DB_COS_ConfigLifeSkill' -or
                $table.StartsWith('DB_COS_Preset', [System.StringComparison]::Ordinal) -or
                $table.StartsWith('DB_COS_CategoryActual', [System.StringComparison]::Ordinal) -or
                $table.StartsWith('DB_COS_RuntimeDiagnostic', [System.StringComparison]::Ordinal)
            )
            Require $allowed "预设应用写入未批准表: $table"
        }

        foreach ($table in $forbiddenTables) {
            Require (-not [regex]::IsMatch($body, "(?m)^\s*(?:NOT\s+)?$table\s*\(")) "预设应用写入子配置/消耗表: $table"
        }
    }
}

function Assert-StatsStatusContract {
    param(
        [Parameter(Mandatory)]
        [psobject]$Entry,

        [Parameter(Mandatory)]
        [string]$ExpectedStackId
    )

    $nonEmptyLines = @(
        $Entry.Body -split '\r?\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('//') }
    )
    Require (@($nonEmptyLines | Where-Object { $_ -ceq 'type "StatusData"' }).Count -eq 1) "状态类型错误: $($Entry.Name)"
    Require (-not $Entry.Body.Contains('data "Boosts"')) "状态不得包含 Boosts: $($Entry.Name)"
    Require (-not [regex]::IsMatch($Entry.Body, '(?m)^using ')) "状态不得继承 using: $($Entry.Name)"

    $fields = Get-StatsDataFields -Entry $Entry
    $allowedFields = @('StatusType', 'DisplayName', 'Description', 'Icon', 'StackId', 'StackType', 'StatusPropertyFlags')
    Require (Test-ExactOrdinalSet -Actual @($fields.Keys) -Expected $allowedFields) "状态字段集合错误: $($Entry.Name)"
    Require ($fields.StatusType -ceq 'BOOST') "状态 StatusType 错误: $($Entry.Name)"
    Require ($fields.StackId -ceq $ExpectedStackId) "状态 StackId 错误: $($Entry.Name)"
    Require ($fields.StackType -ceq 'Overwrite') "状态 StackType 错误: $($Entry.Name)"
    $actualFlags = @($fields.StatusPropertyFlags -split ';')
    $expectedFlags = @('DisableOverhead', 'DisableCombatlog', 'DisablePortraitIndicator', 'IgnoreResting')
    Require (Test-ExactOrdinalSet -Actual $actualFlags -Expected $expectedFlags) "状态隐藏 flags 错误: $($Entry.Name)"
    foreach ($field in @('DisplayName', 'Description', 'Icon')) {
        Require (-not [string]::IsNullOrWhiteSpace($fields[$field])) "状态字段为空: $($Entry.Name).$field"
    }
}

function Assert-MirrorPassiveContract {
    param(
        [Parameter(Mandatory)]
        [psobject]$Entry
    )

    Require ([regex]::Matches($Entry.Body, '(?m)^type "PassiveData"\s*$').Count -eq 1) "分类镜像不是 PassiveData: $($Entry.Name)"
    Require (-not [regex]::IsMatch($Entry.Body, '(?i)Boosts|Spell|ActionResource|Interrupt')) "分类镜像包含玩法效果: $($Entry.Name)"
    Require (-not [regex]::IsMatch($Entry.Body, '(?m)^using ')) "分类镜像不得继承 using: $($Entry.Name)"
    $fields = Get-StatsDataFields -Entry $Entry
    Require (Test-ExactOrdinalSet -Actual @($fields.Keys) -Expected @('DisplayName', 'Description', 'Icon')) "分类镜像字段集合错误: $($Entry.Name)"
}

function Assert-StatsContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string[]]$ExpectedMirrors,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$StatusGroups
    )

    $entries = @(Get-StatsEntries -Content $Content)
    $mirrorEntries = @($entries | Where-Object { $_.Name.StartsWith('COS_CFG_CATEGORY_', [System.StringComparison]::Ordinal) })
    Require (Test-ExactOrdinalSet -Actual @($mirrorEntries.Name) -Expected $ExpectedMirrors) '分类 mirror Stats 集合不精确'
    foreach ($entry in $mirrorEntries) {
        Assert-MirrorPassiveContract -Entry $entry
    }

    $statusPrefixes = @(
        'COS_PRESET_CURRENT_',
        'COS_PRESET_PENDING_',
        'COS_PRESET_PREVIEW_',
        'COS_CATEGORY_ACTUAL_',
        'COS_PRESET_ERROR_'
    )
    $statusEntries = @(
        $entries | Where-Object {
            $entryName = $_.Name
            @($statusPrefixes | Where-Object { $entryName.StartsWith($_, [System.StringComparison]::Ordinal) }).Count -gt 0
        }
    )
    $expectedStatuses = @($StatusGroups.Values | ForEach-Object { $_.Keys })
    Require (Test-ExactOrdinalSet -Actual @($statusEntries.Name) -Expected $expectedStatuses) '分类/预设状态批准集合不精确'

    foreach ($groupName in $StatusGroups.Keys) {
        foreach ($statusName in $StatusGroups[$groupName].Keys) {
            $matchingEntries = @($statusEntries | Where-Object { $_.Name -ceq $statusName })
            Require ($matchingEntries.Count -eq 1) "状态 entry 缺失或重复: $statusName"
            Assert-StatsStatusContract -Entry $matchingEntries[0] -ExpectedStackId $StatusGroups[$groupName][$statusName]
        }
    }

    [pscustomobject]@{
        Entries = $entries
        Mirrors = $mirrorEntries
        Statuses = $statusEntries
    }
}

function Get-UiButtonEvent {
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlElement]$Node,

        [Parameter(Mandatory)]
        [string]$Context
    )

    $actions = @($Node.SelectNodes('.//*[local-name()="InvokeCommandAction" and @CommandParameter]'))
    Require ($actions.Count -eq 1) "$Context 事件动作缺失或重复"
    $actions[0].GetAttribute('CommandParameter')
}

function Assert-UiPageContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$PageName,

        [Parameter(Mandatory)]
        [bool]$Controller,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ButtonEvents,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$StatusNodeSets,

        [Parameter(Mandatory)]
        [string[]]$PanelOrder,

        [Parameter(Mandatory)]
        [string[]]$ButtonOrder
    )

    [xml]$document = $Content
    $allNames = @(Get-NamedNodeOrder -Document $document)
    Assert-OrderedSubset -Actual $allNames -Expected $PanelOrder -Context $PageName
    Assert-OrderedSubset -Actual $allNames -Expected $ButtonOrder -Context "$PageName 按钮"

    $eventMap = [ordered]@{}
    foreach ($buttonName in $ButtonEvents.Keys) {
        $nodes = @(Get-XamlNamedNodes -Document $document -Name $buttonName)
        Require ($nodes.Count -eq 1) "$PageName 按钮命名节点缺失或重复: $buttonName"
        $event = Get-UiButtonEvent -Node $nodes[0] -Context "$PageName $buttonName"
        Require ($event -ceq $ButtonEvents[$buttonName]) "$PageName 按钮事件错误: $buttonName"
        $eventMap[$buttonName] = $event

        if ($Controller) {
            Require ($nodes[0].GetAttribute('BoundEvent') -ceq 'UIAccept') "$PageName 手柄按钮缺少 UIAccept: $buttonName"
            Require ($nodes[0].GetAttribute('Focusable') -ceq 'False') "$PageName 手柄按钮自身不应取得焦点: $buttonName"
            Require ($nodes[0].GetAttribute('MoveFocus.Focusable', 'clr-namespace:ls;assembly=Code') -ceq 'False') "$PageName 手柄按钮 MoveFocus 语义错误: $buttonName"
            Require ($nodes[0].GetAttribute('IsEnabled').Contains('IsFocused')) "$PageName 手柄按钮未绑定焦点行: $buttonName"
        }
    }

    $statusMap = [ordered]@{}
    foreach ($nodeName in $StatusNodeSets.Keys) {
        $nodes = @(Get-XamlNamedNodes -Document $document -Name $nodeName)
        Require ($nodes.Count -eq 1) "$PageName 状态节点缺失或重复: $nodeName"
        Require ($nodes[0].GetAttribute('IsHitTestVisible') -ceq 'False') "$PageName 状态节点必须只读: $nodeName"
        Require ($nodes[0].GetAttribute('Focusable') -ceq 'False') "$PageName 状态节点必须不可聚焦: $nodeName"
        $actualValues = @(
            $nodes[0].SelectNodes('.//*[local-name()="DataTrigger" and @Value]') |
                ForEach-Object { $_.GetAttribute('Value') }
        )
        Require (Test-ExactOrdinalSet -Actual $actualValues -Expected $StatusNodeSets[$nodeName]) "$PageName 状态过滤集合错误: $nodeName"
        $statusMap[$nodeName] = $actualValues
    }

    $panelNodes = @(Get-XamlNamedNodes -Document $document -Name 'COSCategoryPresetPanel')
    Require ($panelNodes.Count -eq 1) "$PageName 分类/预设面板缺失或重复"
    $uiHandleReferences = @(
        [regex]::Matches($panelNodes[0].OuterXml, '\bSource=[''"](h[^''"]+)[''"]') |
            ForEach-Object { $_.Groups[1].Value }
    )
    Require ($uiHandleReferences.Count -gt 0) "$PageName 分类/预设面板没有本地化 handle"
    $uiHandles = @($uiHandleReferences | Sort-Object -Unique)

    $mirrorValues = @(
        $panelNodes[0].SelectNodes('.//*[local-name()="DataTrigger" and @Binding="{Binding Name.Str}" and @Value]') |
            ForEach-Object { $_.GetAttribute('Value') } |
            Where-Object { $_.StartsWith('COS_CFG_CATEGORY_', [System.StringComparison]::Ordinal) }
    )
    Require (Test-ExactOrdinalSet -Actual $mirrorValues -Expected @(
        'COS_CFG_CATEGORY_CORE',
        'COS_CFG_CATEGORY_ORIGIN',
        'COS_CFG_CATEGORY_RACETAGS',
        'COS_CFG_CATEGORY_WEAPON',
        'COS_CFG_CATEGORY_ARMOR',
        'COS_CFG_CATEGORY_RACIAL',
        'COS_CFG_CATEGORY_CONVENIENCE'
    )) "$PageName 分类 mirror 过滤集合错误"

    [pscustomobject]@{
        Document = $document
        Events = $eventMap
        Statuses = $statusMap
        Handles = $uiHandles
        Mirrors = $mirrorValues
    }
}

function Assert-UiParityContract {
    param(
        [Parameter(Mandatory)]
        [psobject]$Keyboard,

        [Parameter(Mandatory)]
        [psobject]$Controller
    )

    Require (Test-ExactOrdinalSequence -Actual @($Keyboard.Events.Keys) -Expected @($Controller.Events.Keys)) '键鼠/手柄按钮命名语义不对称'
    foreach ($name in $Keyboard.Events.Keys) {
        Require ($Keyboard.Events[$name] -ceq $Controller.Events[$name]) "键鼠/手柄事件语义不对称: $name"
    }
    Require (Test-ExactOrdinalSequence -Actual @($Keyboard.Statuses.Keys) -Expected @($Controller.Statuses.Keys)) '键鼠/手柄状态节点不对称'
    foreach ($name in $Keyboard.Statuses.Keys) {
        Require (Test-ExactOrdinalSet -Actual $Keyboard.Statuses[$name] -Expected $Controller.Statuses[$name]) "键鼠/手柄状态集合不对称: $name"
    }
    Require (Test-ExactOrdinalSet -Actual $Keyboard.Handles -Expected $Controller.Handles) '键鼠/手柄本地化语义不对称'
    Require (Test-ExactOrdinalSet -Actual $Keyboard.Mirrors -Expected $Controller.Mirrors) '键鼠/手柄分类 mirror 语义不对称'
}

function Assert-LocalizationContract {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ContentByLanguage,

        [Parameter(Mandatory)]
        [string[]]$RequiredHandles
    )

    $nodesByLanguage = [ordered]@{}
    $handlesByLanguage = [ordered]@{}
    foreach ($language in $ContentByLanguage.Keys) {
        [xml]$document = $ContentByLanguage[$language]
        $nodes = @($document.SelectNodes('/contentList/content'))
        $nodesByLanguage[$language] = $nodes
        $handlesByLanguage[$language] = @($nodes | ForEach-Object { $_.GetAttribute('contentuid') })
        Require (Test-ExactOrdinalSet -Actual $handlesByLanguage[$language] -Expected $handlesByLanguage[$language]) "本地化 handle 重复: $language"
    }

    $referenceHandles = $handlesByLanguage.Chinese
    foreach ($language in $ContentByLanguage.Keys) {
        Require (Test-ExactOrdinalSet -Actual $handlesByLanguage[$language] -Expected $referenceHandles) "四语 handle 集合不一致: $language"
    }

    foreach ($handle in $RequiredHandles) {
        $texts = [ordered]@{}
        foreach ($language in $ContentByLanguage.Keys) {
            $nodes = @($nodesByLanguage[$language] | Where-Object { $_.GetAttribute('contentuid') -ceq $handle })
            Require ($nodes.Count -eq 1) "本地化 handle 未唯一覆盖: $language $handle"
            $text = $nodes[0].InnerText
            Require (-not [string]::IsNullOrWhiteSpace($text)) "本地化文本为空: $language $handle"
            Require (-not [regex]::IsMatch($text, '(?i)\bNot Found\b')) "本地化包含 Not Found: $language $handle"
            $texts[$language] = $text
        }

        Require ([regex]::IsMatch($texts.Chinese, '\p{IsCJKUnifiedIdeographs}')) "中文语义不完整: $handle"
        Require ([regex]::IsMatch($texts.English, '[A-Za-z]')) "英文语义不完整: $handle"
        Require ([regex]::IsMatch($texts.Japanese, '[A-Za-z\p{IsHiragana}\p{IsKatakana}\p{IsCJKUnifiedIdeographs}]')) "日文语义不完整: $handle"
        Require ([regex]::IsMatch($texts.Korean, '[A-Za-z\p{IsHangulSyllables}]')) "韩文语义不完整: $handle"
        foreach ($language in @('English', 'Japanese', 'Korean')) {
            Require ($texts[$language] -cne $texts.Chinese) "$language 直接复制中文: $handle"
        }
    }
}

function Assert-PackageContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string[]]$ExpectedPaths,

        [Parameter(Mandatory)]
        [string[]]$ExpectedGoals
    )

    $manifest = $Content | ConvertFrom-Json
    Require ($manifest.schema -eq 1) 'package-files.json schema 必须为 1'
    $actualPaths = @($manifest.files)
    Require ($actualPaths.Count -eq 38) "正式包路径数错误: 期望 38，实际 $($actualPaths.Count)"
    Require (Test-ExactOrdinalSet -Actual $actualPaths -Expected $ExpectedPaths) '正式包 38 路径集合发生漂移'
    $actualGoals = @($actualPaths | Where-Object { $_ -match '^Mods/ChaosOriginsStory/Story/RawFiles/Goals/[^/]+\.txt$' })
    Require ($actualGoals.Count -eq 6) "正式包 Goal 数错误: 期望 6，实际 $($actualGoals.Count)"
    Require (Test-ExactOrdinalSet -Actual $actualGoals -Expected $ExpectedGoals) '正式包六个 Goal 集合发生漂移'
}

$paths = [ordered]@{
    Config = Join-Path $Root 'Mods\ChaosOriginsStory\Story\RawFiles\Goals\COS_Config.txt'
    Mechanics = Join-Path $Root 'Mods\ChaosOriginsStory\Story\RawFiles\Goals\COS_ChaosMechanics.txt'
    Mastery = Join-Path $Root 'Mods\ChaosOriginsStory\Story\RawFiles\Goals\COS_ChaosMastery.txt'
    Stats = Join-Path $Root 'Public\ChaosOriginsStory\Stats\Generated\Data\ChaosConfig.txt'
    Keyboard = Join-Path $Root 'Mods\ChaosOriginsStory\GUI\Pages\COS_ConfigMenu.xaml'
    Controller = Join-Path $Root 'Mods\ChaosOriginsStory\GUI\Pages\COS_ConfigMenu_c.xaml'
    Package = Join-Path $Root 'package-files.json'
}

$config = Read-Required $paths.Config
$mechanics = Read-Required $paths.Mechanics
$mastery = Read-Required $paths.Mastery
$stats = Read-Required $paths.Stats
$keyboardXaml = Read-Required $paths.Keyboard
$controllerXaml = Read-Required $paths.Controller
$packageJson = Read-Required $paths.Package
$localization = [ordered]@{}
foreach ($language in @('Chinese', 'English', 'Japanese', 'Korean')) {
    $localization[$language] = Read-Required (Join-Path $Root "Localization\$language\ChaosOriginsStory.xml")
}

$categories = [ordered]@{
    Core = 'COS_CFG_CATEGORY_CORE'
    Origin = 'COS_CFG_CATEGORY_ORIGIN'
    RaceTags = 'COS_CFG_CATEGORY_RACETAGS'
    WeaponProficiencies = 'COS_CFG_CATEGORY_WEAPON'
    ArmorProficiencies = 'COS_CFG_CATEGORY_ARMOR'
    RacialAbilities = 'COS_CFG_CATEGORY_RACIAL'
    Convenience = 'COS_CFG_CATEGORY_CONVENIENCE'
}

# Fail first here on the .98 baseline. Later contracts must not mask a missing category implementation.
Assert-CategoryMappingContract -Content $config -ExpectedCategories $categories

$legacyTables = @(
    'DB_COS_ConfigMechanic',
    'DB_COS_ConfigLifeSkill',
    'DB_COS_ConfigCost',
    'DB_COS_ConfigRacial',
    'DB_COS_GrantSetting',
    'DB_COS_TagSpellsSetting',
    'DB_COS_VoloEyeSetting',
    'DB_COS_CarrySetting'
)
Assert-LegacyDetectionContract -Content $config -ExpectedTables $legacyTables

$presetOrder = @('AllConvenience', 'Balanced', 'NearVanilla', 'PureChaos', 'Custom')
Assert-PresetDetectionOrderContract -Content $config -ExpectedOrder $presetOrder

$presetMatrix = [ordered]@{
    NearVanilla = [ordered]@{ Core = 0; Origin = 1; RaceTags = 0; WeaponProficiencies = 0; ArmorProficiencies = 0; RacialAbilities = 0; Convenience = 0 }
    PureChaos = [ordered]@{ Core = 1; Origin = -1; RaceTags = 0; WeaponProficiencies = 0; ArmorProficiencies = 0; RacialAbilities = 0; Convenience = 0 }
    Balanced = [ordered]@{ Core = 1; Origin = 1; RaceTags = 0; WeaponProficiencies = 0; ArmorProficiencies = 0; RacialAbilities = 0; Convenience = 0 }
    AllConvenience = [ordered]@{ Core = 1; Origin = 1; RaceTags = 1; WeaponProficiencies = 1; ArmorProficiencies = 1; RacialAbilities = 1; Convenience = 1 }
}
$presetLife = [ordered]@{ NearVanilla = 0; PureChaos = 0; Balanced = 5; AllConvenience = 20 }
Assert-PresetMatrixContract -Content $config -ExpectedMatrix $presetMatrix -ExpectedLife $presetLife

$categoryEvents = [ordered]@{
    Core = '7e990000-0000-4000-8000-000000000001'
    Origin = '7e990000-0000-4000-8000-000000000002'
    RaceTags = '7e990000-0000-4000-8000-000000000003'
    WeaponProficiencies = '7e990000-0000-4000-8000-000000000004'
    ArmorProficiencies = '7e990000-0000-4000-8000-000000000005'
    RacialAbilities = '7e990000-0000-4000-8000-000000000006'
    Convenience = '7e990000-0000-4000-8000-000000000007'
}
$presetEvents = [ordered]@{
    NearVanilla = '7e990000-0000-4000-8000-000000000011'
    PureChaos = '7e990000-0000-4000-8000-000000000012'
    Balanced = '7e990000-0000-4000-8000-000000000013'
    AllConvenience = '7e990000-0000-4000-8000-000000000014'
    Apply = '7e990000-0000-4000-8000-000000000015'
    Cancel = '7e990000-0000-4000-8000-000000000016'
}
Assert-EventMapContract -Content $config -ExpectedCategoryEvents $categoryEvents -ExpectedPresetEvents $presetEvents

Assert-CategoryInitializationContract -Content $config -Categories @($categories.Keys)
Assert-EventGuardContract -Content $config
Assert-PresetWorkflowContract -Content $config
Assert-PresetWriteContract -Content $config

Require (-not [regex]::IsMatch($mechanics, '(?m)^\s*(?:NOT\s+)?DB_COS_ConfigCategory\(')) 'COS_ChaosMechanics 不得写分类配置'
Require (-not [regex]::IsMatch($mastery, '(?m)^\s*(?:NOT\s+)?DB_COS_ConfigCategory\(')) 'COS_ChaosMastery 不得写分类配置'

$currentStatuses = @(
    'COS_PRESET_CURRENT_NEAR_VANILLA',
    'COS_PRESET_CURRENT_PURE_CHAOS',
    'COS_PRESET_CURRENT_BALANCED',
    'COS_PRESET_CURRENT_ALL_CONVENIENCE',
    'COS_PRESET_CURRENT_CUSTOM'
)
$pendingStatuses = @(
    'COS_PRESET_PENDING_NEAR_VANILLA',
    'COS_PRESET_PENDING_PURE_CHAOS',
    'COS_PRESET_PENDING_BALANCED',
    'COS_PRESET_PENDING_ALL_CONVENIENCE'
)
$previewStatuses = @(
    foreach ($category in $categories.Keys) {
        $token = switch ($category) {
            RaceTags { 'RACETAGS' }
            WeaponProficiencies { 'WEAPON' }
            ArmorProficiencies { 'ARMOR' }
            RacialAbilities { 'RACIAL' }
            default { $category.ToUpperInvariant() }
        }
        "COS_PRESET_PREVIEW_${token}_ON"
        "COS_PRESET_PREVIEW_${token}_OFF"
    }
    'COS_PRESET_PREVIEW_LIFE_0'
    'COS_PRESET_PREVIEW_LIFE_5'
    'COS_PRESET_PREVIEW_LIFE_20'
)
$actualStatuses = @(
    foreach ($category in $categories.Keys) {
        $token = switch ($category) {
            RaceTags { 'RACETAGS' }
            WeaponProficiencies { 'WEAPON' }
            ArmorProficiencies { 'ARMOR' }
            RacialAbilities { 'RACIAL' }
            default { $category.ToUpperInvariant() }
        }
        foreach ($state in @('ACTIVE', 'PAUSED', 'WAITING_CONDITION', 'MISSING_CONFIG', 'SYNC_FAILED')) {
            "COS_CATEGORY_ACTUAL_${token}_${state}"
        }
    }
)
$errorStatuses = @(
    'COS_PRESET_ERROR_NO_SELECTION',
    'COS_PRESET_ERROR_COMBAT_READONLY',
    'COS_PRESET_ERROR_CONFIG_INCOMPLETE',
    'COS_PRESET_ERROR_SYNC_FAILED'
)

$statusGroups = [ordered]@{
    Current = [ordered]@{}
    Pending = [ordered]@{}
    Preview = [ordered]@{}
    Actual = [ordered]@{}
    Error = [ordered]@{}
}
foreach ($status in $currentStatuses) { $statusGroups.Current[$status] = 'COS_PRESET_CURRENT' }
foreach ($status in $pendingStatuses) { $statusGroups.Pending[$status] = 'COS_PRESET_PENDING' }
foreach ($status in $previewStatuses) {
    $suffix = $status.Substring('COS_PRESET_PREVIEW_'.Length)
    $channel = if ($suffix.StartsWith('LIFE_', [System.StringComparison]::Ordinal)) { 'LIFE' } else { $suffix.Substring(0, $suffix.LastIndexOf('_')) }
    $statusGroups.Preview[$status] = "COS_PRESET_PREVIEW_$channel"
}
foreach ($status in $actualStatuses) {
    $suffix = $status.Substring('COS_CATEGORY_ACTUAL_'.Length)
    $channel = $suffix
    foreach ($state in @('_WAITING_CONDITION', '_MISSING_CONFIG', '_SYNC_FAILED', '_ACTIVE', '_PAUSED')) {
        if ($channel.EndsWith($state, [System.StringComparison]::Ordinal)) {
            $channel = $channel.Substring(0, $channel.Length - $state.Length)
            break
        }
    }
    $statusGroups.Actual[$status] = "COS_CATEGORY_ACTUAL_$channel"
}
foreach ($status in $errorStatuses) { $statusGroups.Error[$status] = 'COS_PRESET_ERROR' }

$statsContract = Assert-StatsContract -Content $stats -ExpectedMirrors @($categories.Values) -StatusGroups $statusGroups
foreach ($status in @($statusGroups.Values | ForEach-Object { $_.Keys })) {
    Require ($config.Contains($status)) "Story 未使用分类/预设状态: $status"
}

$buttonEvents = [ordered]@{
    COSCategoryToggleCore = $categoryEvents.Core
    COSCategoryToggleOrigin = $categoryEvents.Origin
    COSCategoryToggleRaceTags = $categoryEvents.RaceTags
    COSCategoryToggleWeaponProficiencies = $categoryEvents.WeaponProficiencies
    COSCategoryToggleArmorProficiencies = $categoryEvents.ArmorProficiencies
    COSCategoryToggleRacialAbilities = $categoryEvents.RacialAbilities
    COSCategoryToggleConvenience = $categoryEvents.Convenience
    COSPresetNearVanilla = $presetEvents.NearVanilla
    COSPresetPureChaos = $presetEvents.PureChaos
    COSPresetBalanced = $presetEvents.Balanced
    COSPresetAllConvenience = $presetEvents.AllConvenience
    COSPresetApply = $presetEvents.Apply
    COSPresetCancel = $presetEvents.Cancel
}
$statusNodeSets = [ordered]@{
    COSPresetCurrent = $currentStatuses
    COSPresetPending = $pendingStatuses
    COSPresetPreview = $previewStatuses
    COSCategoryActual = $actualStatuses
    COSPresetError = $errorStatuses
}
$panelOrder = @(
    'COSRuntimeDiagnosticPanel',
    'COSCategoryPresetPanel',
    'COSPresetCurrent',
    'COSPresetPending',
    'COSPresetButtons',
    'COSPresetPreview',
    'COSCategoryButtons',
    'COSCategoryActual',
    'COSPresetError',
    'COSPresetActions',
    'COSConfigOverview'
)
$buttonOrder = @(
    'COSPresetNearVanilla',
    'COSPresetPureChaos',
    'COSPresetBalanced',
    'COSPresetAllConvenience',
    'COSCategoryToggleCore',
    'COSCategoryToggleOrigin',
    'COSCategoryToggleRaceTags',
    'COSCategoryToggleWeaponProficiencies',
    'COSCategoryToggleArmorProficiencies',
    'COSCategoryToggleRacialAbilities',
    'COSCategoryToggleConvenience',
    'COSPresetApply',
    'COSPresetCancel'
)

$keyboardContract = Assert-UiPageContract -Content $keyboardXaml -PageName 'COS_ConfigMenu.xaml' -Controller $false -ButtonEvents $buttonEvents -StatusNodeSets $statusNodeSets -PanelOrder $panelOrder -ButtonOrder $buttonOrder
$controllerContract = Assert-UiPageContract -Content $controllerXaml -PageName 'COS_ConfigMenu_c.xaml' -Controller $true -ButtonEvents $buttonEvents -StatusNodeSets $statusNodeSets -PanelOrder $panelOrder -ButtonOrder $buttonOrder
Assert-UiParityContract -Keyboard $keyboardContract -Controller $controllerContract

$requiredHandles = [System.Collections.Generic.List[string]]::new()
foreach ($entry in @($statsContract.Mirrors) + @($statsContract.Statuses)) {
    $fields = Get-StatsDataFields -Entry $entry
    foreach ($fieldName in @('DisplayName', 'Description')) {
        $requiredHandles.Add((Get-HandleWithoutVersion -Value $fields[$fieldName] -Context "$($entry.Name).$fieldName"))
    }
}
foreach ($handle in $keyboardContract.Handles) { $requiredHandles.Add($handle) }
$requiredHandles = @($requiredHandles.ToArray() | Sort-Object -Unique)
Assert-LocalizationContract -ContentByLanguage $localization -RequiredHandles $requiredHandles

$expectedPackagePaths = @(
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
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosConfig.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosDamage.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosFeatures.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosMastery.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/ChaosRuntime.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/Interrupt.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/Passive.txt',
    'Public/ChaosOriginsStory/Stats/Generated/Data/Status_BOOST.txt',
    'Public/ChaosOriginsStory/Tags/2c237035-d1a9-4469-91de-d74d8464c8d5.lsf',
    'Public/ChaosOriginsStory/Tutorials/TutorialEvents.lsx'
)
$expectedGoals = @(
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_BaseAfterCreation.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMastery.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosMechanics.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_GlobalPlayerBenefits.txt',
    'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_OriginStoryRewards.txt'
)
Assert-PackageContract -Content $packageJson -ExpectedPaths $expectedPackagePaths -ExpectedGoals $expectedGoals

# In-memory mutation probes: each mutation must alter real source and be rejected by the matching assertion.
$coreMapLine = 'DB_COS_ConfigCategoryMirror("Core", "COS_CFG_CATEGORY_CORE");'
$missingCategoryMutation = Replace-FirstLiteral -Content $config -OldValue $coreMapLine -NewValue '// mutation: removed Core category' -ProbeName 'missing-category'
Assert-MutationRejected -Name 'missing-category' -Probe {
    Assert-CategoryMappingContract -Content $missingCategoryMutation -ExpectedCategories $categories
}

$balancedCoreLine = 'DB_COS_PresetCategory("Balanced", "Core", 1);'
$wrongPresetMutation = Replace-FirstLiteral -Content $config -OldValue $balancedCoreLine -NewValue 'DB_COS_PresetCategory("Balanced", "Core", 0);' -ProbeName 'wrong-preset-value'
Assert-MutationRejected -Name 'wrong-preset-value' -Probe {
    Assert-PresetMatrixContract -Content $wrongPresetMutation -ExpectedMatrix $presetMatrix -ExpectedLife $presetLife
}

$presetApplyBlock = @(Get-ProcedureBlocks -Content $config -Name 'PROC_COS_PresetApply')[0]
$injectedApplyBlock = Replace-FirstLiteral -Content $presetApplyBlock -OldValue 'THEN' -NewValue "THEN`nDB_COS_ConfigCost(_Character, `"Fate`", 999);" -ProbeName 'preset-subconfig-write'
$presetWriteMutation = Replace-RuleBlock -Content $config -OldBlock $presetApplyBlock -NewBlock $injectedApplyBlock -ProbeName 'preset-subconfig-write'
Assert-MutationRejected -Name 'preset-subconfig-write' -Probe {
    Assert-PresetWriteContract -Content $presetWriteMutation
}

$legacyLine = 'DB_COS_ConfigLegacyTable("DB_COS_ConfigMechanic");'
$legacyMutation = Replace-FirstLiteral -Content $config -OldValue $legacyLine -NewValue '// mutation: removed legacy mechanic check' -ProbeName 'missing-legacy-table'
Assert-MutationRejected -Name 'missing-legacy-table' -Probe {
    Assert-LegacyDetectionContract -Content $legacyMutation -ExpectedTables $legacyTables
}

$categoryEventBlock = @(
    Get-OsirisRuleBlocks -Content $config |
        Where-Object { $_.Contains('DB_COS_ConfigCategoryEvent(_Event, _Category)') }
)[0]
$unguardedCategoryBlock = Replace-FirstLiteral -Content $categoryEventBlock -OldValue 'IsInCombat(_Character, 0)' -NewValue 'IsInCombat(_Character, 1)' -ProbeName 'missing-combat-guard'
$combatMutation = Replace-RuleBlock -Content $config -OldBlock $categoryEventBlock -NewBlock $unguardedCategoryBlock -ProbeName 'missing-combat-guard'
Assert-MutationRejected -Name 'missing-combat-guard' -Probe {
    Assert-EventGuardContract -Content $combatMutation
}

$previewBypassBlock = Replace-FirstLiteral -Content $presetApplyBlock -OldValue 'DB_COS_PresetPreviewReady(_Character, _Preset)' -NewValue 'DB_COS_PresetMutationBypass(_Character, _Preset)' -ProbeName 'preview-bypass'
$previewBypassMutation = Replace-RuleBlock -Content $config -OldBlock $presetApplyBlock -NewBlock $previewBypassBlock -ProbeName 'preview-bypass'
Assert-MutationRejected -Name 'preview-bypass' -Probe {
    Assert-PresetWorkflowContract -Content $previewBypassMutation
}

$commitBlock = @(Get-ProcedureBlocks -Content $config -Name 'PROC_COS_ConfigCommitCategorySchema')[0]
$duplicateCommitBlock = Replace-FirstLiteral -Content $commitBlock -OldValue 'DB_COS_ConfigCategorySchema(_Character);' -NewValue "DB_COS_ConfigCategorySchema(_Character);`nDB_COS_ConfigCategorySchema(_Character);" -ProbeName 'duplicate-schema-commit'
$duplicateCommitMutation = Replace-RuleBlock -Content $config -OldBlock $commitBlock -NewBlock $duplicateCommitBlock -ProbeName 'duplicate-schema-commit'
Assert-MutationRejected -Name 'duplicate-schema-commit' -Probe {
    Assert-CategoryInitializationContract -Content $duplicateCommitMutation -Categories @($categories.Keys)
}

[xml]$controllerEventMutationDocument = $controllerXaml
$controllerPresetButton = @(Get-XamlNamedNodes -Document $controllerEventMutationDocument -Name 'COSPresetNearVanilla')[0]
$controllerPresetAction = @($controllerPresetButton.SelectNodes('.//*[local-name()="InvokeCommandAction" and @CommandParameter]'))[0]
$controllerPresetAction.SetAttribute('CommandParameter', $presetEvents.PureChaos)
$controllerEventMutation = $controllerEventMutationDocument.OuterXml
Assert-MutationRejected -Name 'controller-event-drift' -Probe {
    [void](Assert-UiPageContract -Content $controllerEventMutation -PageName 'controller-event-probe' -Controller $true -ButtonEvents $buttonEvents -StatusNodeSets $statusNodeSets -PanelOrder $panelOrder -ButtonOrder $buttonOrder)
}

$languageMutation = [ordered]@{}
foreach ($language in $localization.Keys) { $languageMutation[$language] = $localization[$language] }
[xml]$chineseDocument = $localization.Chinese
[xml]$koreanDocument = $localization.Korean
$mutationHandle = $requiredHandles[0]
$chineseNode = @($chineseDocument.SelectNodes('/contentList/content') | Where-Object { $_.GetAttribute('contentuid') -ceq $mutationHandle })[0]
$koreanNode = @($koreanDocument.SelectNodes('/contentList/content') | Where-Object { $_.GetAttribute('contentuid') -ceq $mutationHandle })[0]
Require ($null -ne $chineseNode -and $null -ne $koreanNode) '本地化复制中文探针缺少真实节点'
$koreanNode.InnerText = $chineseNode.InnerText
$languageMutation.Korean = $koreanDocument.OuterXml
Assert-MutationRejected -Name 'korean-copies-chinese' -Probe {
    Assert-LocalizationContract -ContentByLanguage $languageMutation -RequiredHandles $requiredHandles
}

Write-Output 'Category/preset contract counts: categories=7; preset-category-rows=28; preset-life-rows=4; events=13'
Write-Output 'Category/preset mutation probes: category=PASS; matrix=PASS; write-allowlist=PASS; legacy=PASS; combat=PASS; preview=PASS; schema=PASS; controller=PASS; localization=PASS'
Write-Output 'ChaosOriginsStory category/preset verification: ok'
