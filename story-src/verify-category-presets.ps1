#requires -Version 7.0

param(
    [string]$Root = $PSScriptRoot,

    [ValidateSet('All', 'Task3')]
    [string]$Focus = 'All'
)

class CategoryPresetContractException : System.Exception {
    CategoryPresetContractException([string]$message) : base($message) {}
}

$ErrorActionPreference = 'Stop'

function Require {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw [CategoryPresetContractException]::new($Message)
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

function Remove-OsirisLineComment {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Line
    )

    $inString = $false
    for ($index = 0; $index -lt $Line.Length; $index++) {
        $character = $Line[$index]
        if ($character -eq '"') {
            $precedingSlashes = 0
            for ($slashIndex = $index - 1; $slashIndex -ge 0 -and $Line[$slashIndex] -eq '\'; $slashIndex--) {
                $precedingSlashes++
            }
            if (($precedingSlashes % 2) -eq 0) {
                $inString = -not $inString
            }
            continue
        }
        if (-not $inString -and $character -eq '/' -and $index + 1 -lt $Line.Length -and $Line[$index + 1] -eq '/') {
            return $Line.Substring(0, $index)
        }
    }
    $Line
}

function Get-OsirisRuleBlocks {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $blocks = [System.Collections.Generic.List[string]]::new()
    $blockStart = -1
    foreach ($lineMatch in @([regex]::Matches($Content, '(?m)^.*(?:\r?\n|\z)'))) {
        if ($lineMatch.Length -eq 0) { continue }
        $rawLine = $lineMatch.Value.TrimEnd([char[]]@("`r", "`n"))
        $codeLine = (Remove-OsirisLineComment -Line $rawLine).Trim()
        $isRuleHeader = $codeLine -ceq 'IF' -or $codeLine -ceq 'PROC'
        $isSectionEnd = $codeLine -ceq 'EXITSECTION'
        if ($isRuleHeader -or $isSectionEnd) {
            if ($blockStart -ge 0) {
                $blocks.Add($Content.Substring($blockStart, $lineMatch.Index - $blockStart))
                $blockStart = -1
            }
            if ($isRuleHeader) {
                $blockStart = $lineMatch.Index
            }
        }
    }
    if ($blockStart -ge 0) {
        $blocks.Add($Content.Substring($blockStart))
    }
    @($blocks.ToArray())
}

function Get-OsirisCodeLines {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    @(
        foreach ($sourceLine in @($Content -split '\r?\n')) {
            $line = (Remove-OsirisLineComment -Line $sourceLine).Trim()
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $line
            }
        }
    )
}

function Get-OsirisRuleModel {
    param(
        [Parameter(Mandatory)]
        [string]$Block
    )

    $lines = @(Get-OsirisCodeLines -Content $Block)
    Require ($lines.Count -ge 3) 'Osiris 规则结构不完整'
    $thenIndex = [Array]::IndexOf($lines, 'THEN')
    Require ($thenIndex -ge 2) 'Osiris 规则缺少真实 THEN'

    $kind = $lines[0]
    Require ($kind -ceq 'PROC' -or $kind -ceq 'IF') "未知 Osiris 规则类型: $kind"
    $head = $lines[1]
    $conditionStart = if ($kind -ceq 'PROC') { 2 } else { 1 }
    $conditions = @()
    if ($thenIndex -gt $conditionStart) {
        $conditions = @(
            $lines[$conditionStart..($thenIndex - 1)] |
                Where-Object { $_ -cne 'AND' }
        )
    }
    $actions = @()
    if ($thenIndex -lt $lines.Count - 1) {
        $actions = @($lines[($thenIndex + 1)..($lines.Count - 1)])
    }

    [pscustomobject]@{
        Kind = $kind
        Head = $head
        Conditions = $conditions
        Actions = $actions
        Block = $Block
    }
}

function Get-OsirisRuleModels {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    @(Get-OsirisRuleBlocks -Content $Content | ForEach-Object { Get-OsirisRuleModel -Block $_ })
}

function Get-ProcedureModels {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $headPattern = '^' + [regex]::Escape($Name) + '\('
    @(
        Get-OsirisRuleModels -Content $Content |
            Where-Object { $_.Kind -ceq 'PROC' -and $_.Head -match $headPattern }
    )
}

function Assert-OsirisParserContract {
    $quotedLine = 'DB_COS_Test("https://example.invalid/a//b", _Value); // trailing comment'
    $codeLines = @(Get-OsirisCodeLines -Content $quotedLine)
    Require ($codeLines.Count -eq 1 -and $codeLines[0] -ceq 'DB_COS_Test("https://example.invalid/a//b", _Value);') 'Osiris parser 破坏引号内双斜线'

    $commentedRule = @'
PROC   // rule header comment
PROC_COS_ParserProbe()
THEN // then comment
DB_COS_Test("https://example.invalid/a//b", _Value); // action comment
'@
    $models = @(Get-OsirisRuleModels -Content $commentedRule)
    Require ($models.Count -eq 1) 'Osiris parser 未捕获带尾空白/注释的规则头'
    Require ($models[0].Kind -ceq 'PROC' -and $models[0].Head -ceq 'PROC_COS_ParserProbe()') 'Osiris parser 注释规则结构错误'
    Require-ExactConditions -Model $models[0] -Expected @() -Context 'Osiris parser 注释规则'
    Require-ExactActions -Model $models[0] -Expected @(
        'DB_COS_Test("https://example.invalid/a//b", _Value);'
    ) -Context 'Osiris parser 注释规则'
}

function Require-Condition {
    param(
        [Parameter(Mandatory)]
        [psobject]$Model,

        [Parameter(Mandatory)]
        [string]$Condition,

        [Parameter(Mandatory)]
        [string]$Context
    )

    Require (@($Model.Conditions | Where-Object { $_ -ceq $Condition }).Count -eq 1) "$Context 缺少或重复真实条件: $Condition"
}

function Require-ExactConditions {
    param(
        [Parameter(Mandatory)]
        [psobject]$Model,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Expected,

        [Parameter(Mandatory)]
        [string]$Context
    )

    Require (Test-ExactOrdinalSet -Actual @($Model.Conditions) -Expected $Expected) "$Context 条件集合不精确"
}

function Require-ExactActions {
    param(
        [Parameter(Mandatory)]
        [psobject]$Model,

        [Parameter(Mandatory)]
        [string[]]$Expected,

        [Parameter(Mandatory)]
        [string]$Context
    )

    Require (Test-ExactOrdinalSequence -Actual @($Model.Actions) -Expected $Expected) "$Context THEN 动作序列不精确"
}

function Assert-MutationRejected {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$ExpectedMessagePattern,

        [Parameter(Mandatory)]
        [scriptblock]$Probe
    )

    $rejected = $false
    try {
        & $Probe
    }
    catch [CategoryPresetContractException] {
        if (-not [regex]::IsMatch($_.Exception.Message, $ExpectedMessagePattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
            throw
        }
        $rejected = $true
    }

    Require $rejected "变异探针未被拒绝: $Name"
}

function Assert-MutationHarnessContract {
    $missingCommandEscaped = $false
    try {
        Assert-MutationRejected -Name 'harness-command-not-found' -ExpectedMessagePattern '^never matches$' -Probe {
            Invoke-COSDefinitelyMissingCommand
        }
    }
    catch [System.Management.Automation.CommandNotFoundException] {
        $missingCommandEscaped = $true
    }
    Require $missingCommandEscaped 'mutation harness 吞掉 CommandNotFoundException'

    $nullReferenceEscaped = $false
    try {
        $nullTarget = $null
        Assert-MutationRejected -Name 'harness-null-reference' -ExpectedMessagePattern '^never matches$' -Probe {
            $nullTarget.ToString()
        }
    }
    catch [System.Management.Automation.RuntimeException] {
        $nullReferenceEscaped = $true
    }
    Require $nullReferenceEscaped 'mutation harness 吞掉空引用异常'

    $emptyStatsRejected = $false
    $emptyStatusGroups = [ordered]@{ Current = [ordered]@{ COS_PRESET_CURRENT_CUSTOM = 'COS_PRESET_CURRENT' } }
    $emptyMirrorHandles = [ordered]@{
        COS_CFG_CATEGORY_CORE = [pscustomobject]@{
            DisplayName = 'h7e990000g0000g4000g8000g000000000101'
            Description = 'h7e990000g0000g4000g8000g000000000102'
        }
    }
    try {
        [void](Assert-StatsContract -Content '' -ExpectedMirrors @('COS_CFG_CATEGORY_CORE') -StatusGroups $emptyStatusGroups -ExpectedMirrorHandles $emptyMirrorHandles)
    }
    catch [CategoryPresetContractException] {
        Require ($_.Exception.Message -ceq '分类 mirror Stats 集合不精确') "空 Stats 合同错误不精确: $($_.Exception.Message)"
        $emptyStatsRejected = $true
    }
    Require $emptyStatsRejected '空 Stats 未以合同异常拒绝'

    $emptyLocalizationRejected = $false
    $emptyLocalization = [ordered]@{
        Chinese = '<contentList />'
        English = '<contentList />'
        Japanese = '<contentList />'
        Korean = '<contentList />'
    }
    $missingHandle = 'h7e990000g0000g4000g8000g000000000101'
    try {
        Assert-LocalizationContract -ContentByLanguage $emptyLocalization -SemanticByHandle ([ordered]@{ $missingHandle = 'COS_CFG_CATEGORY_CORE' })
    }
    catch [CategoryPresetContractException] {
        Require ($_.Exception.Message -ceq "分类/预设批准 handle 缺失或重复: Chinese $missingHandle") "空本地化 handle 合同错误不精确: $($_.Exception.Message)"
        $emptyLocalizationRejected = $true
    }
    Require $emptyLocalizationRejected '空本地化 handle 未以合同异常拒绝'
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
        [AllowEmptyString()]
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

    $codeLines = @(Get-OsirisCodeLines -Content $Content)
    $code = $codeLines -join "`n"
    $matches = @([regex]::Matches(
        $code,
        '(?m)^\s*DB_COS_ConfigCategoryMap\("([^"]+)", "([^"]+)"\);\s*$'
    ))
    $mappingRows = @($codeLines | Where-Object {
        $_.StartsWith('DB_COS_ConfigCategoryMap(', [System.StringComparison]::Ordinal) -and $_.EndsWith(';', [System.StringComparison]::Ordinal)
    })
    Require ($matches.Count -eq $mappingRows.Count) '分类映射包含无法解析的活动行'

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
        [System.Collections.IDictionary]$ExpectedProbes
    )

    $codeLines = @(Get-OsirisCodeLines -Content $Content)
    $code = $codeLines -join "`n"
    $matches = @([regex]::Matches(
        $code,
        '(?m)^\s*DB_COS_ConfigLegacyTable\("([^"]+)"\);\s*$'
    ))
    $mappingRows = @($codeLines | Where-Object {
        $_.StartsWith('DB_COS_ConfigLegacyTable(', [System.StringComparison]::Ordinal) -and $_.EndsWith(';', [System.StringComparison]::Ordinal)
    })
    Require ($matches.Count -eq $mappingRows.Count) '旧档识别表包含无法解析的活动行'
    $actualTables = @($matches | ForEach-Object { $_.Groups[1].Value })
    Require (Test-ExactOrdinalSet -Actual $actualTables -Expected @($ExpectedProbes.Keys)) '旧档识别表集合不精确'

    $allProbeModels = @(
        Get-OsirisRuleModels -Content $Content |
            Where-Object { $_.Kind -ceq 'PROC' -and $_.Head.StartsWith('PROC_COS_ConfigProbeLegacy', [System.StringComparison]::Ordinal) }
    )
    Require ($allProbeModels.Count -eq 8) "旧档专用 probe 数量错误: 期望 8，实际 $($allProbeModels.Count)"

    $actualProbeTables = [System.Collections.Generic.List[string]]::new()
    foreach ($table in $ExpectedProbes.Keys) {
        $procedure = $ExpectedProbes[$table].Procedure
        $arity = $ExpectedProbes[$table].Arity
        $models = @(Get-ProcedureModels -Content $Content -Name $procedure)
        Require ($models.Count -eq 1) "旧档专用 probe 缺失或重复: $procedure"
        $tailPattern = if ($arity -gt 1) { '(?:,\s*_(?:[A-Za-z][A-Za-z0-9_]*)?){' + ($arity - 1) + '}' } else { '' }
        $tablePattern = '^' + [regex]::Escape($table) + '\(_Character' + $tailPattern + '\)$'
        $tableConditions = @($models[0].Conditions | Where-Object { $_ -match $tablePattern })
        Require ($tableConditions.Count -eq 1) "旧档 probe 条件签名或 arity 错误: $table"
        Require ($models[0].Conditions.Count -eq 2) "旧档 probe 条件集合不精确: $table"
        Require-Condition -Model $models[0] -Condition 'NOT DB_COS_ConfigPreexisting(_Character)' -Context "旧档 probe $table"
        foreach ($condition in $models[0].Conditions) {
            $queriedTableMatch = [regex]::Match($condition, '^(DB_COS_[A-Za-z0-9_]+)\(_Character(?:,.*)?\)$')
            if ($queriedTableMatch.Success -and $ExpectedProbes.Contains($queriedTableMatch.Groups[1].Value)) {
                $actualProbeTables.Add($queriedTableMatch.Groups[1].Value)
            }
        }
        Require-ExactActions -Model $models[0] -Expected @(
            'DB_COS_ConfigPreexisting(_Character);'
        ) -Context "旧档 probe $table"
    }

    Require (Test-ExactOrdinalSet -Actual @($actualProbeTables.ToArray()) -Expected @($ExpectedProbes.Keys)) '旧档专用 probe 查询集合不精确'

    $detectModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_ConfigDetectPreexisting')
    Require ($detectModels.Count -eq 1) '旧档检测调度过程必须唯一'
    Require-ExactConditions -Model $detectModels[0] -Expected @() -Context '旧档检测调度'
    $expectedDetectActions = @(
        'NOT DB_COS_ConfigPreexisting(_Character);'
        foreach ($table in $ExpectedProbes.Keys) {
            "$($ExpectedProbes[$table].Procedure)(_Character);"
        }
    )
    Require-ExactActions -Model $detectModels[0] -Expected $expectedDetectActions -Context '旧档检测调度'
}

function Assert-PresetDetectionOrderContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string[]]$ExpectedOrder
    )

    $models = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_PresetDetect')
    Require ($models.Count -eq 1) '预设检测调度规则必须唯一'
    Require-ExactConditions -Model $models[0] -Expected @() -Context '预设检测调度'
    $expectedActions = @(
        'NOT DB_COS_PresetMismatch(_Character, _, _, 2);'
        foreach ($preset in @($ExpectedOrder | Where-Object { $_ -cne 'Custom' })) {
            "PROC_COS_PresetValidate(_Character, `"$preset`", 2);"
        }
        'PROC_COS_PresetSetCurrent(_Character);'
    )
    Require-ExactActions -Model $models[0] -Expected $expectedActions -Context '预设检测调度'
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

    $codeLines = @(Get-OsirisCodeLines -Content $Content)
    $code = $codeLines -join "`n"
    $categoryMatches = @([regex]::Matches(
        $code,
        '(?m)^\s*DB_COS_PresetCategory\("([^"]+)", "([^"]+)", (-?\d+)\);\s*$'
    ))
    $categoryRows = @($codeLines | Where-Object {
        $_.StartsWith('DB_COS_PresetCategory(', [System.StringComparison]::Ordinal) -and $_.EndsWith(';', [System.StringComparison]::Ordinal)
    })
    Require ($categoryMatches.Count -eq $categoryRows.Count) '预设分类矩阵包含无法解析的活动行'
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
        $code,
        '(?m)^\s*DB_COS_PresetLife\("([^"]+)", (\d+)\);\s*$'
    ))
    $lifeRows = @($codeLines | Where-Object {
        $_.StartsWith('DB_COS_PresetLife(', [System.StringComparison]::Ordinal) -and $_.EndsWith(';', [System.StringComparison]::Ordinal)
    })
    Require ($lifeMatches.Count -eq $lifeRows.Count) '预设生活加值矩阵包含无法解析的活动行'
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

    $codeLines = @(Get-OsirisCodeLines -Content $Content)
    $code = $codeLines -join "`n"
    $categoryMatches = @([regex]::Matches(
        $code,
        '(?m)^\s*DB_COS_ConfigCategoryEvent\(\(TUTORIALEVENT\)[A-Za-z0-9_]*([0-9a-f]{8}-[0-9a-f-]{27}), "([^"]+)"\);\s*$'
    ))
    $categoryRows = @($codeLines | Where-Object {
        $_.StartsWith('DB_COS_ConfigCategoryEvent(', [System.StringComparison]::Ordinal) -and $_.EndsWith(';', [System.StringComparison]::Ordinal)
    })
    Require ($categoryMatches.Count -eq $categoryRows.Count) '分类事件映射包含无法解析的活动行'
    $actualCategoryRows = @($categoryMatches | ForEach-Object { '{0}|{1}' -f $_.Groups[2].Value, $_.Groups[1].Value })
    $expectedCategoryRows = @($ExpectedCategoryEvents.Keys | ForEach-Object { '{0}|{1}' -f $_, $ExpectedCategoryEvents[$_] })
    Require (Test-ExactOrdinalSet -Actual $actualCategoryRows -Expected $expectedCategoryRows) '分类事件 UUID 映射不精确'

    $selectMatches = @([regex]::Matches(
        $code,
        '(?m)^\s*DB_COS_PresetSelectEvent\(\(TUTORIALEVENT\)[A-Za-z0-9_]*([0-9a-f]{8}-[0-9a-f-]{27}), "([^"]+)"\);\s*$'
    ))
    $selectRows = @($codeLines | Where-Object {
        $_.StartsWith('DB_COS_PresetSelectEvent(', [System.StringComparison]::Ordinal) -and $_.EndsWith(';', [System.StringComparison]::Ordinal)
    })
    Require ($selectMatches.Count -eq $selectRows.Count) '预设选择事件映射包含无法解析的活动行'
    $actualPresetRows = @($selectMatches | ForEach-Object { '{0}|{1}' -f $_.Groups[2].Value, $_.Groups[1].Value })
    foreach ($action in @('Apply', 'Cancel')) {
        $tableName = "DB_COS_Preset${action}Event"
        $matches = @([regex]::Matches(
            $code,
            "(?m)^\s*$tableName\(\(TUTORIALEVENT\)[A-Za-z0-9_]*([0-9a-f]{8}-[0-9a-f-]{27})\);\s*$"
        ))
        $actionRows = @($codeLines | Where-Object {
            $_.StartsWith("$tableName(", [System.StringComparison]::Ordinal) -and $_.EndsWith(';', [System.StringComparison]::Ordinal)
        })
        Require ($matches.Count -eq $actionRows.Count) "预设事件映射包含无法解析的活动行: $action"
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
        [System.Collections.IDictionary]$NewCategories,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$LegacyCategories,

        [Parameter(Mandatory)]
        [int]$NewLife
    )

    Require (Test-ExactOrdinalSequence -Actual @($NewCategories.Keys) -Expected @($LegacyCategories.Keys)) '新旧分类键顺序不一致'
    $categoryKeys = @($NewCategories.Keys)

    $initializeModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_ConfigInitializeCategories')
    Require ($initializeModels.Count -eq 1) '分类统一初始化入口必须恰好有一个规则'
    Require-ExactConditions -Model $initializeModels[0] -Expected @(
        'HasPassive(_Character, "COS_ChaosOriginMarker", 1)',
        'NOT DB_COS_ConfigCategorySchema(_Character, _)'
    ) -Context '分类统一初始化入口'
    Require-ExactActions -Model $initializeModels[0] -Expected @(
        'PROC_COS_ConfigDetectPreexisting(_Character);',
        'PROC_COS_ConfigInitializeNew(_Character);',
        'PROC_COS_ConfigInitializeLegacy(_Character);',
        'PROC_COS_ConfigCommitCategorySchema(_Character);'
    ) -Context '分类统一初始化入口'

    $newModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_ConfigInitializeNew')
    Require ($newModels.Count -eq 1) '新角色分类初始化规则必须唯一'
    Require-ExactConditions -Model $newModels[0] -Expected @(
        'NOT DB_COS_ConfigPreexisting(_Character)'
    ) -Context '新角色分类初始化'
    $expectedNewActions = @(
        foreach ($category in $categoryKeys) {
            "PROC_COS_ConfigInitCategory(_Character, `"$category`", $($NewCategories[$category]));"
        }
        "DB_COS_ConfigLifeSkill(_Character, $NewLife);"
    )
    Require ($expectedNewActions.Count -eq 8) '验证器内部错误: 新角色分支必须定义八个数据动作'
    Require-ExactActions -Model $newModels[0] -Expected $expectedNewActions -Context '新角色分类初始化'

    $legacyModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_ConfigInitializeLegacy')
    Require ($legacyModels.Count -eq 1) '旧角色分类初始化规则必须唯一'
    Require-ExactConditions -Model $legacyModels[0] -Expected @(
        'DB_COS_ConfigPreexisting(_Character)'
    ) -Context '旧角色分类初始化'
    $expectedLegacyActions = @(
        foreach ($category in $categoryKeys) {
            "PROC_COS_ConfigInitCategory(_Character, `"$category`", $($LegacyCategories[$category]));"
        }
    )
    Require ($expectedLegacyActions.Count -eq 7) '验证器内部错误: 旧角色分支必须定义七个数据动作'
    Require-ExactActions -Model $legacyModels[0] -Expected $expectedLegacyActions -Context '旧角色分类初始化'

    $forbiddenLegacyWrites = @(
        'DB_COS_ConfigLifeSkill',
        'DB_COS_ConfigMechanic',
        'DB_COS_ConfigCost',
        'DB_COS_ConfigRacial',
        'DB_COS_GrantSetting',
        'DB_COS_TagSpellsSetting',
        'DB_COS_VoloEyeSetting',
        'DB_COS_CarryEnabled'
    )
    foreach ($action in $legacyModels[0].Actions) {
        foreach ($table in $forbiddenLegacyWrites) {
            Require (-not $action.StartsWith("$table(", [System.StringComparison]::Ordinal) -and -not $action.StartsWith("NOT $table(", [System.StringComparison]::Ordinal)) "旧角色初始化不得写入 child config: $table"
        }
    }

    $rowModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_ConfigInitCategory')
    Require ($rowModels.Count -eq 1) '分类单行初始化规则必须唯一'
    Require-ExactConditions -Model $rowModels[0] -Expected @(
        'NOT DB_COS_ConfigCategory(_Character, _Category, _)'
    ) -Context '分类单行初始化'
    Require-ExactActions -Model $rowModels[0] -Expected @(
        'DB_COS_ConfigCategory(_Character, _Category, _Value);'
    ) -Context '分类单行初始化'

    $commitModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_ConfigCommitCategorySchema')
    Require ($commitModels.Count -eq 1) '分类 schema 提交规则必须唯一'
    Require ($commitModels[0].Conditions.Count -eq 8) "分类 schema 提交条件行数错误: 期望 8，实际 $($commitModels[0].Conditions.Count)"
    Require-Condition -Model $commitModels[0] -Condition 'NOT DB_COS_ConfigCategorySchema(_Character, _)' -Context '分类 schema 提交'
    $commitCategories = @(
        foreach ($condition in $commitModels[0].Conditions) {
            $match = [regex]::Match($condition, '^DB_COS_ConfigCategory\(_Character, "([^"]+)", _[A-Za-z0-9_]+\)$')
            if ($match.Success) {
                $match.Groups[1].Value
            }
        }
    )
    Require (Test-ExactOrdinalSet -Actual $commitCategories -Expected $categoryKeys) '分类 schema 提交绑定键集合不精确'
    Require-ExactActions -Model $commitModels[0] -Expected @(
        'DB_COS_ConfigCategorySchema(_Character, 1);'
    ) -Context '分类 schema 提交'
    $schemaWriteSites = @(
        Get-OsirisRuleModels -Content $Content |
            ForEach-Object {
                $model = $_
                foreach ($action in $model.Actions) {
                    if ($action.StartsWith('DB_COS_ConfigCategorySchema(', [System.StringComparison]::Ordinal)) {
                        [pscustomobject]@{ Head = $model.Head; Action = $action }
                    }
                }
            }
    )
    Require ($schemaWriteSites.Count -eq 1) "分类 schema 全局提交次数错误: 期望 1，实际 $($schemaWriteSites.Count)"
    Require ($schemaWriteSites[0].Head -ceq $commitModels[0].Head -and $schemaWriteSites[0].Action -ceq 'DB_COS_ConfigCategorySchema(_Character, 1);') '分类 schema 只能由完整七行检查过程提交'

    $syncModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_ConfigSyncCharacter')
    Require ($syncModels.Count -eq 1) '统一角色同步入口必须唯一'
    Require ($syncModels[0].Actions.Count -gt 0 -and $syncModels[0].Actions[0] -ceq 'PROC_COS_ConfigInitializeCategories(_Character);') '首次分类初始化不是统一角色同步第一步'
}

function Assert-LegacyWriterInitializationContract {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Entrypoints
    )

    $expectedNames = @(
        'ConfigSyncCharacter',
        'MechanicsSync',
        'GlobalPlayerBenefitsSync',
        'GrantSync',
        'VoloEyeSync'
    )
    Require (Test-ExactOrdinalSequence -Actual @($Entrypoints.Keys) -Expected $expectedNames) '生命周期 legacy-writer 入口集合不精确'

    foreach ($name in $Entrypoints.Keys) {
        $entry = $Entrypoints[$name]
        $models = @(Get-ProcedureModels -Content $entry.Content -Name $entry.Procedure)
        if (-not [string]::IsNullOrWhiteSpace($entry.SelectorAction)) {
            $models = @($models | Where-Object { $_.Actions -ccontains $entry.SelectorAction })
        }
        Require ($models.Count -eq 1) "生命周期 legacy-writer 入口缺失或重复: $name"
        Require ($models[0].Actions.Count -gt 0) "生命周期 legacy-writer 入口没有动作: $name"
        Require ($models[0].Actions[0] -ceq 'PROC_COS_ConfigInitializeCategories(_Character);') "生命周期 legacy-writer 入口未先初始化分类: $name"
    }
}

function Assert-EventGuardContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $families = [ordered]@{
        Category = [pscustomobject]@{ Table = 'DB_COS_ConfigCategoryEvent'; Condition = 'DB_COS_ConfigCategoryEvent(_Event, _Key)' }
        PresetSelect = [pscustomobject]@{ Table = 'DB_COS_PresetSelectEvent'; Condition = 'DB_COS_PresetSelectEvent(_Event, _Preset)' }
        PresetApply = [pscustomobject]@{ Table = 'DB_COS_PresetApplyEvent'; Condition = 'DB_COS_PresetApplyEvent(_Event)' }
        PresetCancel = [pscustomobject]@{ Table = 'DB_COS_PresetCancelEvent'; Condition = 'DB_COS_PresetCancelEvent(_Event)' }
    }
    foreach ($family in $families.Keys) {
        $tablePrefix = $families[$family].Table + '('
        $models = @(
            Get-OsirisRuleModels -Content $Content |
                Where-Object {
                    $_.Kind -ceq 'IF' -and
                    @($_.Conditions | Where-Object { $_.StartsWith($tablePrefix, [System.StringComparison]::Ordinal) }).Count -gt 0
                }
        )
        Require ($models.Count -eq 1) "修改事件处理规则缺失或重复: $family"
        Require (@($models[0].Conditions | Where-Object { $_.StartsWith($tablePrefix, [System.StringComparison]::Ordinal) }).Count -eq 1) "修改事件映射条件不精确: $family"
        $expectedConditions = @(
            'TutorialEvent(_Character, _Event)',
            $families[$family].Condition,
            'HasPassive(_Character, "COS_ChaosOriginMarker", 1)',
            'IsControlled(_Character, 1)',
            'IsInCombat(_Character, 0)',
            'DB_COS_ConfigCategorySchema(_Character, 1)'
        )
        Require-ExactConditions -Model $models[0] -Expected $expectedConditions -Context "修改事件 $family"
        switch ($family) {
            Category {
                Require-ExactActions -Model $models[0] -Expected @(
                    'PROC_COS_ConfigToggleCategory(_Character, _Key);'
                ) -Context '分类切换事件'
            }
            PresetSelect {
                Require-ExactActions -Model $models[0] -Expected @(
                    'PROC_COS_PresetSelect(_Character, _Preset);'
                ) -Context '预设选择事件'
            }
            PresetApply {
                Require-ExactActions -Model $models[0] -Expected @(
                    'PROC_COS_PresetValidate(_Character, 0);',
                    'PROC_COS_PresetApply(_Character);'
                ) -Context '预设应用事件'
            }
            PresetCancel {
                Require-ExactActions -Model $models[0] -Expected @(
                    'PROC_COS_PresetClearPreview(_Character);',
                    'PROC_COS_PresetDetect(_Character);',
                    'PROC_COS_ConfigSyncCategoryActual(_Character);',
                    'PROC_COS_RuntimeDiagnosticUpdate(_Character);'
                ) -Context '预设取消事件'
            }
        }
    }
}

function Assert-CategoryToggleContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [switch]$Task3Stage
    )

    $models = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_ConfigToggleCategory')
    Require ($models.Count -eq 1) '分类切换过程必须唯一'
    Require-ExactConditions -Model $models[0] -Expected @(
        'DB_COS_ConfigCategory(_Character, _Key, _Current)',
        'IntegerSubtract(1, _Current, _Next)'
    ) -Context '分类切换过程'
    $expectedActions = @(
        'NOT DB_COS_ConfigCategory(_Character, _Key, _Current);',
        'DB_COS_ConfigCategory(_Character, _Key, _Next);',
        'PROC_COS_ConfigSyncCharacter(_Character);'
    )
    if (-not $Task3Stage) {
        $expectedActions += @(
            'PROC_COS_PresetDetect(_Character);',
            'PROC_COS_ConfigSyncCategoryActual(_Character);'
        )
    }
    $expectedActions += 'PROC_COS_RuntimeDiagnosticUpdate(_Character);'
    Require-ExactActions -Model $models[0] -Expected $expectedActions -Context '分类切换过程'
}

function Assert-CategorySeedContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ExpectedCategories,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ExpectedEvents,

        [Parameter(Mandatory)]
        [string[]]$ExpectedLegacyTables
    )

    $expectedRows = @(
        foreach ($category in $ExpectedCategories.Keys) {
            "DB_COS_ConfigCategoryMap(`"$category`", `"$($ExpectedCategories[$category])`")"
        }
        foreach ($category in $ExpectedEvents.Keys) {
            "DB_COS_ConfigCategoryEvent((TUTORIALEVENT)$($ExpectedEvents[$category]), `"$category`")"
        }
        foreach ($table in $ExpectedLegacyTables) {
            "DB_COS_ConfigLegacyTable(`"$table`")"
        }
    )

    $models = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_ConfigSeedCategories')
    Require ($models.Count -eq $expectedRows.Count) "分类 seed 规则数量错误: 期望 $($expectedRows.Count)，实际 $($models.Count)"
    $actualRows = [System.Collections.Generic.List[string]]::new()
    foreach ($model in $models) {
        Require ($model.Conditions.Count -eq 1) '分类 seed 每条规则必须只有一个幂等条件'
        Require ($model.Actions.Count -eq 1) '分类 seed 每条规则必须只有一个数据动作'
        $action = $model.Actions[0]
        Require ($action.EndsWith(';', [System.StringComparison]::Ordinal)) '分类 seed 动作缺少分号'
        $row = $action.Substring(0, $action.Length - 1)
        Require ($model.Conditions[0] -ceq "NOT $row") "分类 seed 幂等条件与数据动作不匹配: $row"
        $actualRows.Add($row)
    }
    Require (Test-ExactOrdinalSet -Actual @($actualRows.ToArray()) -Expected $expectedRows) '分类 seed 数据集合不精确'
}

function Assert-CategoryMirrorContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $enabledModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_ConfigAddEnabledCategoryMirrors')
    Require ($enabledModels.Count -eq 1) '开启分类镜像规则必须唯一'
    Require-ExactConditions -Model $enabledModels[0] -Expected @(
        'DB_COS_ConfigCategory(_Character, _Category, 1)',
        'DB_COS_ConfigCategoryMap(_Category, _Passive)'
    ) -Context '开启分类镜像'
    Require-ExactActions -Model $enabledModels[0] -Expected @(
        'AddPassive(_Character, _Passive);'
    ) -Context '开启分类镜像'

    $disabledModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_ConfigRemoveDisabledCategoryMirrors')
    Require ($disabledModels.Count -eq 1) '关闭分类镜像规则必须唯一'
    Require-ExactConditions -Model $disabledModels[0] -Expected @(
        'DB_COS_ConfigCategory(_Character, _Category, 0)',
        'DB_COS_ConfigCategoryMap(_Category, _Passive)'
    ) -Context '关闭分类镜像'
    Require-ExactActions -Model $disabledModels[0] -Expected @(
        'RemovePassive(_Character, _Passive);'
    ) -Context '关闭分类镜像'

    $syncModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_ConfigSyncCategoryMirrors')
    Require ($syncModels.Count -eq 1) '分类镜像同步过程必须唯一'
    Require-ExactConditions -Model $syncModels[0] -Expected @() -Context '分类镜像同步'
    Require-ExactActions -Model $syncModels[0] -Expected @(
        'PROC_COS_ConfigSeedCategories();',
        'PROC_COS_ConfigAddEnabledCategoryMirrors(_Character);',
        'PROC_COS_ConfigRemoveDisabledCategoryMirrors(_Character);'
    ) -Context '分类镜像同步'
}

function Assert-CategoryEventContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $enableModels = @(
        Get-ProcedureModels -Content $Content -Name 'PROC_COS_ConfigEnableEvents' |
            Where-Object { $_.Conditions -ccontains 'DB_COS_ConfigCategoryEvent(_Event, _Key)' }
    )
    Require ($enableModels.Count -eq 1) '分类 TutorialEvent 启用规则必须唯一'
    Require-ExactConditions -Model $enableModels[0] -Expected @(
        'DB_COS_ConfigCategoryEvent(_Event, _Key)'
    ) -Context '分类 TutorialEvent 启用'
    Require-ExactActions -Model $enableModels[0] -Expected @(
        'EnableTutorialEvent(_Character, _Event);'
    ) -Context '分类 TutorialEvent 启用'

    $eventModels = @(
        Get-OsirisRuleModels -Content $Content |
            Where-Object { $_.Kind -ceq 'IF' -and $_.Conditions -ccontains 'DB_COS_ConfigCategoryEvent(_Event, _Key)' }
    )
    Require ($eventModels.Count -eq 1) '分类修改事件处理规则必须唯一'
    Require-ExactConditions -Model $eventModels[0] -Expected @(
        'TutorialEvent(_Character, _Event)',
        'DB_COS_ConfigCategoryEvent(_Event, _Key)',
        'HasPassive(_Character, "COS_ChaosOriginMarker", 1)',
        'IsControlled(_Character, 1)',
        'IsInCombat(_Character, 0)',
        'DB_COS_ConfigCategorySchema(_Character, 1)'
    ) -Context '分类修改事件'
    Require-ExactActions -Model $eventModels[0] -Expected @(
        'PROC_COS_ConfigToggleCategory(_Character, _Key);'
    ) -Context '分类切换事件'
}

function Assert-PresetWorkflowContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $selectionModels = @(
        Get-OsirisRuleModels -Content $Content |
            Where-Object { $_.Kind -ceq 'IF' -and $_.Conditions -ccontains 'DB_COS_PresetSelectEvent(_Event, _Preset)' }
    )
    Require ($selectionModels.Count -eq 1) '预设选择事件规则必须唯一'
    Require-ExactActions -Model $selectionModels[0] -Expected @(
        'PROC_COS_PresetSelect(_Character, _Preset);'
    ) -Context '预设选择事件'

    $selectModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_PresetSelect')
    Require ($selectModels.Count -eq 1) '预设选择过程必须唯一'
    Require-ExactConditions -Model $selectModels[0] -Expected @(
        'DB_COS_PresetPendingStatus(_Preset, _Status)'
    ) -Context '预设选择过程'
    Require ($selectModels[0].Actions.Count -eq 4) '预设选择动作数量不精确'
    Require ($selectModels[0].Actions[0] -ceq 'PROC_COS_PresetClearPreview(_Character);') '预设选择必须先清理旧预览'
    Require ($selectModels[0].Actions[1] -ceq 'DB_COS_PresetPending(_Character, _Preset);') '预设选择必须写入唯一 pending'
    Require ([regex]::IsMatch($selectModels[0].Actions[2], '^ApplyStatus\(_Character, (?:_Status|"COS_PRESET_PENDING_[A-Z_]+"), [^,]+, [^)]+\);$')) '预设选择必须应用映射出的 pending 状态'
    Require ($selectModels[0].Actions[3] -ceq 'PROC_COS_PresetBuildPreview(_Character, _Preset);') '预设选择必须最后构建预览'

    $previewModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_PresetBuildPreview')
    Require ($previewModels.Count -gt 0) '预设构建预览过程集合缺失'
    foreach ($model in @($selectModels) + @($previewModels)) {
        foreach ($action in $model.Actions) {
            Require (-not [regex]::IsMatch($action, '^(?:NOT\s+)?DB_COS_Config(?:Category|LifeSkill)\(')) '预设预览不得写正式配置'
            Require (-not [regex]::IsMatch($action, '^PROC_COS_Config(?:SetLifeSkill|SyncCharacter)\(')) '预设预览不得调用正式配置写入或同步'
            Require (-not $action.StartsWith('PROC_COS_PresetApply(', [System.StringComparison]::Ordinal)) '预设预览不得绕过应用入口'
        }
    }

    $applyModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_PresetApply')
    Require ($applyModels.Count -eq 2) '预设应用必须恰好包含主规则与成功规则'
    $mainApplyModels = @($applyModels | Where-Object { $_.Conditions -ccontains 'DB_COS_PresetValidated(_Character, _Preset, 0)' })
    Require ($mainApplyModels.Count -eq 1) '预设应用主规则缺失或重复'
    Require-ExactConditions -Model $mainApplyModels[0] -Expected @(
        'DB_COS_PresetPending(_Character, _Preset)',
        'DB_COS_PresetValidated(_Character, _Preset, 0)',
        'DB_COS_PresetLife(_Preset, _Life)'
    ) -Context '预设应用主规则'
    Require-ExactActions -Model $mainApplyModels[0] -Expected @(
        'PROC_COS_PresetSetCategory(_Character, _Preset);',
        'PROC_COS_ConfigSetLifeSkill(_Character, _Life);',
        'PROC_COS_ConfigSyncCharacter(_Character);',
        'PROC_COS_PresetDetect(_Character);',
        'PROC_COS_ConfigSyncCategoryActual(_Character);',
        'PROC_COS_PresetValidate(_Character, _Preset, 1);'
    ) -Context '预设应用主规则'

    $successApplyModels = @($applyModels | Where-Object { $_.Conditions -ccontains 'DB_COS_PresetValidated(_Character, _Preset, 1)' })
    Require ($successApplyModels.Count -eq 1) '预设应用成功规则缺失或重复'
    Require-ExactConditions -Model $successApplyModels[0] -Expected @(
        'DB_COS_PresetValidated(_Character, _Preset, 1)',
        'NOT DB_COS_PresetMismatch(_Character, _Preset, _, 1)'
    ) -Context '预设应用成功规则'
    Require-ExactActions -Model $successApplyModels[0] -Expected @(
        'PROC_COS_PresetClearPreview(_Character);',
        'PROC_COS_RuntimeDiagnosticUpdate(_Character);'
    ) -Context '预设应用成功规则'

    $setCategoryModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_PresetSetCategory')
    Require ($setCategoryModels.Count -eq 1) '预设分类写入规则必须唯一'
    Require-ExactConditions -Model $setCategoryModels[0] -Expected @(
        'DB_COS_PresetCategory(_Preset, _Category, _Target)',
        '_Target != -1',
        'DB_COS_ConfigCategory(_Character, _Category, _OldValue)',
        '_OldValue != _Target'
    ) -Context '预设分类写入'
    Require-ExactActions -Model $setCategoryModels[0] -Expected @(
        'NOT DB_COS_ConfigCategory(_Character, _Category, _OldValue);',
        'DB_COS_ConfigCategory(_Character, _Category, _Target);'
    ) -Context '预设分类写入'
    foreach ($action in $setCategoryModels[0].Actions) {
        Require (-not $action.Contains('"Origin"', [System.StringComparison]::Ordinal)) 'PureChaos Origin 通配被直接写入'
    }
}

function Assert-PresetWriteContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string[]]$ExpectedProcedureNames,

        [Parameter(Mandatory)]
        [string[]]$ApprovedStatusIds,

        [Parameter(Mandatory)]
        [string[]]$ExpectedDetectionOrder
    )

    $forbiddenTables = @(
        'DB_COS_ConfigMechanic',
        'DB_COS_ConfigRacial',
        'DB_COS_GrantSetting',
        'DB_COS_TagSpellsSetting',
        'DB_COS_VoloEyeSetting',
        'DB_COS_CarryEnabled',
        'DB_COS_ConfigCost'
    )
    $staticTables = @(
        'DB_COS_PresetCategory',
        'DB_COS_PresetLife',
        'DB_COS_PresetDetectionOrder',
        'DB_COS_PresetSelectEvent',
        'DB_COS_PresetApplyEvent',
        'DB_COS_PresetCancelEvent',
        'DB_COS_PresetPendingStatus',
        'DB_COS_PresetPreviewCategoryStatus',
        'DB_COS_PresetPreviewLifeStatus',
        'DB_COS_PresetCurrentStatus',
        'DB_COS_PresetErrorStatus'
    )
    $dynamicTables = @(
        'DB_COS_PresetPending',
        'DB_COS_PresetPreviewCategory',
        'DB_COS_PresetPreviewLife',
        'DB_COS_PresetValidated',
        'DB_COS_PresetMismatch'
    )
    $allowedTables = @('DB_COS_ConfigCategory') + $staticTables + $dynamicTables
    $allowedProcedureCalls = @(
        'PROC_COS_ConfigSetLifeSkill',
        'PROC_COS_ConfigSyncCharacter',
        'PROC_COS_ConfigSyncCategoryActual',
        'PROC_COS_RuntimeDiagnosticUpdate'
    ) + $ExpectedProcedureNames
    $presetModels = @(
        Get-OsirisRuleModels -Content $Content |
            Where-Object { $_.Kind -ceq 'PROC' -and $_.Head.StartsWith('PROC_COS_Preset', [System.StringComparison]::Ordinal) }
    )
    Require ($presetModels.Count -gt 0) '预设过程集合缺失'
    $declaredProcedureNames = @(
        foreach ($model in $presetModels) {
            $match = [regex]::Match($model.Head, '^(PROC_COS_Preset[A-Za-z0-9_]*)\(')
            Require $match.Success "预设过程声明无法解析: $($model.Head)"
            $match.Groups[1].Value
        }
    )
    Require (Test-ExactOrdinalSet -Actual @($declaredProcedureNames | Sort-Object -Unique) -Expected $ExpectedProcedureNames) '预设过程声明批准集合不精确'

    $lifeSetterSites = [System.Collections.Generic.List[string]]::new()
    $syncSites = [System.Collections.Generic.List[string]]::new()
    $seedWrittenTables = [System.Collections.Generic.List[string]]::new()
    $pendingStatuses = @($ApprovedStatusIds | Where-Object { $_.StartsWith('COS_PRESET_PENDING_', [System.StringComparison]::Ordinal) })
    $previewStatuses = @($ApprovedStatusIds | Where-Object { $_.StartsWith('COS_PRESET_PREVIEW_', [System.StringComparison]::Ordinal) })
    $currentStatuses = @($ApprovedStatusIds | Where-Object { $_.StartsWith('COS_PRESET_CURRENT_', [System.StringComparison]::Ordinal) })
    $errorStatuses = @($ApprovedStatusIds | Where-Object { $_.StartsWith('COS_PRESET_ERROR_', [System.StringComparison]::Ordinal) })
    $statusMapContracts = [ordered]@{
        DB_COS_PresetPendingStatus = $pendingStatuses
        DB_COS_PresetPreviewCategoryStatus = @($previewStatuses | Where-Object { -not $_.StartsWith('COS_PRESET_PREVIEW_LIFE_', [System.StringComparison]::Ordinal) })
        DB_COS_PresetPreviewLifeStatus = @($previewStatuses | Where-Object { $_.StartsWith('COS_PRESET_PREVIEW_LIFE_', [System.StringComparison]::Ordinal) })
        DB_COS_PresetCurrentStatus = $currentStatuses
        DB_COS_PresetErrorStatus = $errorStatuses
    }

    foreach ($model in $presetModels) {
        $procedureName = [regex]::Match($model.Head, '^(PROC_COS_Preset[A-Za-z0-9_]*)\(').Groups[1].Value
        foreach ($action in $model.Actions) {
            $writeMatch = [regex]::Match($action, '^(?:NOT\s+)?(DB_[A-Za-z0-9_]+)\s*\(')
            if ($writeMatch.Success) {
                $table = $writeMatch.Groups[1].Value
                Require ($allowedTables -ccontains $table) "预设过程写入未批准表: $table"
                switch ($procedureName) {
                    PROC_COS_PresetSeed {
                        Require ($staticTables -ccontains $table) "PresetSeed 写入非静态表: $table"
                        Require (-not $action.StartsWith('NOT ', [System.StringComparison]::Ordinal)) "PresetSeed 不得删除静态表: $table"
                        $seedWrittenTables.Add($table)
                    }
                    PROC_COS_PresetClearPreview {
                        Require ($dynamicTables -ccontains $table) "ClearPreview 写入未批准 scratch: $table"
                        Require ($action.StartsWith('NOT ', [System.StringComparison]::Ordinal)) "ClearPreview 只能删除 scratch: $table"
                        if ($table -ceq 'DB_COS_PresetValidated' -or $table -ceq 'DB_COS_PresetMismatch') {
                            Require (-not [regex]::IsMatch($action, ',\s*2\);$')) "ClearPreview 不得清除 phase2: $table"
                            Require ([regex]::IsMatch($action, ',\s*[01]\);$')) "ClearPreview 只能清除 phase0/1: $table"
                        }
                    }
                    PROC_COS_PresetSelect {
                        Require ($table -ceq 'DB_COS_PresetPending' -and -not $action.StartsWith('NOT ', [System.StringComparison]::Ordinal)) "PresetSelect 只能写 pending: $table"
                    }
                    PROC_COS_PresetBuildPreview {
                        Require ($table -ceq 'DB_COS_PresetPreviewCategory' -or $table -ceq 'DB_COS_PresetPreviewLife') "BuildPreview 写入未批准 scratch: $table"
                        Require (-not $action.StartsWith('NOT ', [System.StringComparison]::Ordinal)) "BuildPreview 不得删除 preview scratch: $table"
                    }
                    PROC_COS_PresetApply {
                        Require $false "PresetApply 不得直接写 DB: $table"
                    }
                    PROC_COS_PresetSetCategory {
                        Require ($table -ceq 'DB_COS_ConfigCategory') "SetCategory 写入非分类配置: $table"
                    }
                    PROC_COS_PresetDetect {
                        Require ($table -ceq 'DB_COS_PresetMismatch' -and $action.StartsWith('NOT ', [System.StringComparison]::Ordinal) -and [regex]::IsMatch($action, ',\s*2\);$')) "PresetDetect 只能清 phase2 mismatch: $action"
                    }
                    PROC_COS_PresetSetCurrent {
                        Require ($table -ceq 'DB_COS_PresetMismatch' -and $action.StartsWith('NOT ', [System.StringComparison]::Ordinal) -and [regex]::IsMatch($action, ',\s*2\);$')) "SetCurrent 只能清 phase2 mismatch: $action"
                    }
                    PROC_COS_PresetValidate {
                        Require ($table -ceq 'DB_COS_PresetValidated' -or $table -ceq 'DB_COS_PresetMismatch') "PresetValidate 写入未批准 scratch: $table"
                        Require ([regex]::IsMatch($action, ',\s*(?:[012]|_Phase)\);$')) "PresetValidate phase 未批准: $action"
                        if ($action.EndsWith(', _Phase);', [System.StringComparison]::Ordinal)) {
                            Require ($model.Head.Contains('(INTEGER)_Phase', [System.StringComparison]::Ordinal)) 'PresetValidate 使用 _Phase 时签名必须声明整数 phase 参数'
                        }
                    }
                    default {
                        Require $false "预设过程写入未分配过程: $procedureName $table"
                    }
                }
                if ($table -ceq 'DB_COS_ConfigCategory') {
                    Require ($action -ceq 'NOT DB_COS_ConfigCategory(_Character, _Category, _OldValue);' -or $action -ceq 'DB_COS_ConfigCategory(_Character, _Category, _Target);') "预设分类写入位置或参数未批准: $action"
                }
                continue
            }

            $callMatch = [regex]::Match($action, '^(PROC_[A-Za-z0-9_]+)\s*\(')
            if ($callMatch.Success) {
                $procedure = $callMatch.Groups[1].Value
                Require ($allowedProcedureCalls -ccontains $procedure) "预设过程调用未批准过程: $procedure"
                $allowedForProcedure = switch ($procedureName) {
                    PROC_COS_PresetSeed { @() }
                    PROC_COS_PresetClearPreview { @() }
                    PROC_COS_PresetSelect { @('PROC_COS_PresetClearPreview', 'PROC_COS_PresetBuildPreview') }
                    PROC_COS_PresetBuildPreview { @() }
                    PROC_COS_PresetApply { @('PROC_COS_PresetSetCategory', 'PROC_COS_ConfigSetLifeSkill', 'PROC_COS_ConfigSyncCharacter', 'PROC_COS_PresetDetect', 'PROC_COS_ConfigSyncCategoryActual', 'PROC_COS_PresetValidate', 'PROC_COS_PresetClearPreview', 'PROC_COS_RuntimeDiagnosticUpdate') }
                    PROC_COS_PresetSetCategory { @() }
                    PROC_COS_PresetDetect { @('PROC_COS_PresetValidate', 'PROC_COS_PresetSetCurrent') }
                    PROC_COS_PresetSetCurrent { @() }
                    PROC_COS_PresetValidate { @() }
                }
                Require ($allowedForProcedure -ccontains $procedure) "$procedureName 调用未批准过程: $procedure"
                if ($procedure -ceq 'PROC_COS_ConfigSetLifeSkill') {
                    Require ($procedureName -ceq 'PROC_COS_PresetApply') '生活加值 setter 只能由 PROC_COS_PresetApply 调用'
                    Require ($action -ceq 'PROC_COS_ConfigSetLifeSkill(_Character, _Life);') "生活加值 setter 参数未批准: $action"
                    $lifeSetterSites.Add($model.Head)
                }
                if ($procedure -ceq 'PROC_COS_ConfigSyncCharacter') {
                    Require ($procedureName -ceq 'PROC_COS_PresetApply') '统一同步只能由 PROC_COS_PresetApply 调用'
                    Require ($action -ceq 'PROC_COS_ConfigSyncCharacter(_Character);') "统一同步参数未批准: $action"
                    $syncSites.Add($model.Head)
                }
                continue
            }

            $applyStatusMatch = [regex]::Match($action, '^ApplyStatus\(_Character, (?:(?:"([^"]+)")|(_Status)), [^,]+, [^)]+\);$')
            if ($applyStatusMatch.Success) {
                $allowedForProcedure = switch ($procedureName) {
                    PROC_COS_PresetSelect { $pendingStatuses }
                    PROC_COS_PresetBuildPreview { $previewStatuses }
                    PROC_COS_PresetSetCurrent { $currentStatuses }
                    PROC_COS_PresetValidate { $errorStatuses }
                    default { @() }
                }
                Require ($procedureName -cin @('PROC_COS_PresetSelect', 'PROC_COS_PresetBuildPreview', 'PROC_COS_PresetSetCurrent', 'PROC_COS_PresetValidate')) "$procedureName 不得调用 ApplyStatus"
                if ($applyStatusMatch.Groups[1].Success) {
                    Require ($allowedForProcedure -ccontains $applyStatusMatch.Groups[1].Value) "预设过程 ApplyStatus 使用未批准状态: $($applyStatusMatch.Groups[1].Value)"
                }
                else {
                    $allowedMapTables = switch ($procedureName) {
                        PROC_COS_PresetSelect { @('DB_COS_PresetPendingStatus') }
                        PROC_COS_PresetBuildPreview { @('DB_COS_PresetPreviewCategoryStatus', 'DB_COS_PresetPreviewLifeStatus') }
                        PROC_COS_PresetSetCurrent { @('DB_COS_PresetCurrentStatus') }
                        PROC_COS_PresetValidate { @('DB_COS_PresetErrorStatus') }
                    }
                    $statusMapConditions = @($model.Conditions | Where-Object {
                        $mapMatch = [regex]::Match($_, '^(DB_COS_Preset[A-Za-z0-9_]+Status)\(.*_Status\)$')
                        $mapMatch.Success -and $allowedMapTables -ccontains $mapMatch.Groups[1].Value
                    })
                    Require ($statusMapConditions.Count -eq 1) "$procedureName 的 _Status 未由唯一批准映射绑定"
                }
                continue
            }

            $removeStatusMatch = [regex]::Match($action, '^RemoveStatus\(_Character, (?:(?:"([^"]+)")|(_Status))\);$')
            if ($removeStatusMatch.Success) {
                $allowedForProcedure = switch ($procedureName) {
                    PROC_COS_PresetClearPreview { @($pendingStatuses + $previewStatuses + $errorStatuses) }
                    PROC_COS_PresetSetCurrent { $currentStatuses }
                    PROC_COS_PresetValidate { $errorStatuses }
                    default { @() }
                }
                Require ($procedureName -cin @('PROC_COS_PresetClearPreview', 'PROC_COS_PresetSetCurrent', 'PROC_COS_PresetValidate')) "$procedureName 不得调用 RemoveStatus"
                if ($removeStatusMatch.Groups[1].Success) {
                    Require ($allowedForProcedure -ccontains $removeStatusMatch.Groups[1].Value) "预设过程 RemoveStatus 使用未批准状态: $($removeStatusMatch.Groups[1].Value)"
                }
                else {
                    $allowedMapTables = switch ($procedureName) {
                        PROC_COS_PresetClearPreview { @('DB_COS_PresetPendingStatus', 'DB_COS_PresetPreviewCategoryStatus', 'DB_COS_PresetPreviewLifeStatus', 'DB_COS_PresetErrorStatus') }
                        PROC_COS_PresetSetCurrent { @('DB_COS_PresetCurrentStatus') }
                        PROC_COS_PresetValidate { @('DB_COS_PresetErrorStatus') }
                    }
                    $statusMapConditions = @($model.Conditions | Where-Object {
                        $mapMatch = [regex]::Match($_, '^(DB_COS_Preset[A-Za-z0-9_]+Status)\(.*_Status\)$')
                        $mapMatch.Success -and $allowedMapTables -ccontains $mapMatch.Groups[1].Value
                    })
                    Require ($statusMapConditions.Count -eq 1) "$procedureName 的 _Status 未由唯一批准映射绑定"
                }
                continue
            }

            Require $false "预设过程包含未批准 THEN 动作: $action"
        }

        foreach ($table in $forbiddenTables) {
            $forbiddenWrites = @($model.Actions | Where-Object {
                $_.StartsWith("$table(", [System.StringComparison]::Ordinal) -or
                $_.StartsWith("NOT $table(", [System.StringComparison]::Ordinal)
            })
            Require ($forbiddenWrites.Count -eq 0) "预设过程写入子配置/消耗表: $table"
        }
    }

    Require ($lifeSetterSites.Count -eq 1) "预设流程生活加值 setter 调用次数错误: 期望 1，实际 $($lifeSetterSites.Count)"
    Require ($syncSites.Count -eq 1) "预设流程统一同步调用次数错误: 期望 1，实际 $($syncSites.Count)"
    Require (Test-ExactOrdinalSet -Actual @($seedWrittenTables.ToArray() | Sort-Object -Unique) -Expected $staticTables) 'PresetSeed 静态表写入集合不精确'

    $clearModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_PresetClearPreview')
    $clearTables = @(
        $clearModels.Actions | ForEach-Object {
            $match = [regex]::Match($_, '^NOT\s+(DB_[A-Za-z0-9_]+)\(')
            if ($match.Success) { $match.Groups[1].Value }
        } | Sort-Object -Unique
    )
    Require (Test-ExactOrdinalSet -Actual $clearTables -Expected $dynamicTables) 'ClearPreview scratch 清理表集合不精确'
    foreach ($phaseTable in @('DB_COS_PresetValidated', 'DB_COS_PresetMismatch')) {
        $clearPhases = @(
            $clearModels.Actions | Where-Object { $_.StartsWith("NOT $phaseTable(", [System.StringComparison]::Ordinal) } | ForEach-Object {
                $match = [regex]::Match($_, ',\s*([01])\);$')
                if ($match.Success) { $match.Groups[1].Value }
            } | Sort-Object -Unique
        )
        Require (Test-ExactOrdinalSet -Actual $clearPhases -Expected @('0', '1')) "ClearPreview $phaseTable 必须精确清理 phase0/1"
    }

    $previewModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_PresetBuildPreview')
    $previewTables = @(
        $previewModels.Actions | ForEach-Object {
            $match = [regex]::Match($_, '^(DB_[A-Za-z0-9_]+)\(')
            if ($match.Success) { $match.Groups[1].Value }
        } | Sort-Object -Unique
    )
    Require (Test-ExactOrdinalSet -Actual $previewTables -Expected @('DB_COS_PresetPreviewCategory', 'DB_COS_PresetPreviewLife')) 'BuildPreview scratch 写入表集合不精确'

    $validateModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_PresetValidate')
    $validateTables = @(
        $validateModels.Actions | ForEach-Object {
            $match = [regex]::Match($_, '^(?:NOT\s+)?(DB_[A-Za-z0-9_]+)\(')
            if ($match.Success) { $match.Groups[1].Value }
        } | Sort-Object -Unique
    )
    Require (Test-ExactOrdinalSet -Actual $validateTables -Expected @('DB_COS_PresetValidated', 'DB_COS_PresetMismatch')) 'PresetValidate scratch 写入表集合不精确'

    $getStatusCoverage = {
        param(
            [psobject[]]$Models,
            [string]$Verb,
            [string[]]$AllowedMapTables,
            [System.Collections.IDictionary]$MapContracts
        )

        $covered = [System.Collections.Generic.List[string]]::new()
        foreach ($coverageModel in $Models) {
            foreach ($coverageAction in $coverageModel.Actions) {
                $match = [regex]::Match($coverageAction, '^' + [regex]::Escape($Verb) + '\(_Character, (?:(?:"([^"]+)")|(_Status))(?:, [^,]+, [^)]+)?\);$')
                if (-not $match.Success) { continue }
                if ($match.Groups[1].Success) {
                    $covered.Add($match.Groups[1].Value)
                    continue
                }
                $mapConditions = @($coverageModel.Conditions | ForEach-Object {
                    $mapMatch = [regex]::Match($_, '^(DB_COS_Preset[A-Za-z0-9_]+Status)\(.*_Status\)$')
                    if ($mapMatch.Success -and $AllowedMapTables -ccontains $mapMatch.Groups[1].Value) {
                        $mapMatch.Groups[1].Value
                    }
                })
                Require ($mapConditions.Count -eq 1) "$Verb _Status 覆盖无法绑定唯一批准映射"
                foreach ($status in $MapContracts[$mapConditions[0]]) { $covered.Add($status) }
            }
        }
        @($covered.ToArray() | Sort-Object -Unique)
    }

    $clearStatusCoverage = @(& $getStatusCoverage $clearModels 'RemoveStatus' @('DB_COS_PresetPendingStatus', 'DB_COS_PresetPreviewCategoryStatus', 'DB_COS_PresetPreviewLifeStatus', 'DB_COS_PresetErrorStatus') $statusMapContracts)
    Require (Test-ExactOrdinalSet -Actual $clearStatusCoverage -Expected @($pendingStatuses + $previewStatuses + $errorStatuses)) 'ClearPreview 移除状态覆盖集合不精确'
    $previewStatusCoverage = @(& $getStatusCoverage $previewModels 'ApplyStatus' @('DB_COS_PresetPreviewCategoryStatus', 'DB_COS_PresetPreviewLifeStatus') $statusMapContracts)
    Require (Test-ExactOrdinalSet -Actual $previewStatusCoverage -Expected $previewStatuses) 'BuildPreview 应用状态覆盖集合不精确'
    $setCurrentModels = @(Get-ProcedureModels -Content $Content -Name 'PROC_COS_PresetSetCurrent')
    $currentApplyCoverage = @(& $getStatusCoverage $setCurrentModels 'ApplyStatus' @('DB_COS_PresetCurrentStatus') $statusMapContracts)
    $currentRemoveCoverage = @(& $getStatusCoverage $setCurrentModels 'RemoveStatus' @('DB_COS_PresetCurrentStatus') $statusMapContracts)
    Require (Test-ExactOrdinalSet -Actual $currentApplyCoverage -Expected $currentStatuses) 'SetCurrent 应用 current 状态覆盖集合不精确'
    Require (Test-ExactOrdinalSet -Actual $currentRemoveCoverage -Expected $currentStatuses) 'SetCurrent 移除 current 状态覆盖集合不精确'
    $validateApplyCoverage = @(& $getStatusCoverage $validateModels 'ApplyStatus' @('DB_COS_PresetErrorStatus') $statusMapContracts)
    $validateRemoveCoverage = @(& $getStatusCoverage $validateModels 'RemoveStatus' @('DB_COS_PresetErrorStatus') $statusMapContracts)
    Require (Test-ExactOrdinalSet -Actual $validateApplyCoverage -Expected $errorStatuses) 'PresetValidate 应用 error 状态覆盖集合不精确'
    Require (Test-ExactOrdinalSet -Actual $validateRemoveCoverage -Expected $errorStatuses) 'PresetValidate 移除 error 状态覆盖集合不精确'

    $seedActions = @($presetModels | Where-Object { $_.Head.StartsWith('PROC_COS_PresetSeed(', [System.StringComparison]::Ordinal) } | ForEach-Object { $_.Actions })
    $detectionRows = @(
        $seedActions | Where-Object { $_.StartsWith('DB_COS_PresetDetectionOrder(', [System.StringComparison]::Ordinal) } | ForEach-Object {
            $presetMatches = @([regex]::Matches($_, '"([^"]+)"') | Where-Object { $ExpectedDetectionOrder -ccontains $_.Groups[1].Value })
            Require ($presetMatches.Count -eq 1) "PresetDetectionOrder 行无法解析: $_"
            $presetMatches[0].Groups[1].Value
        }
    )
    Require (Test-ExactOrdinalSequence -Actual $detectionRows -Expected $ExpectedDetectionOrder) 'PresetSeed detection order 行集合或顺序错误'

    foreach ($table in $statusMapContracts.Keys) {
        $mappedStatuses = @(
            $seedActions | Where-Object { $_.StartsWith("$table(", [System.StringComparison]::Ordinal) } | ForEach-Object {
                $statusMatches = @([regex]::Matches($_, '"(COS_(?:PRESET|CATEGORY_ACTUAL)_[A-Z0-9_]+)"'))
                Require ($statusMatches.Count -eq 1) "$table 行必须映射唯一批准状态: $_"
                $statusMatches[0].Groups[1].Value
            }
        )
        Require (Test-ExactOrdinalSet -Actual $mappedStatuses -Expected $statusMapContracts[$table]) "PresetSeed 状态映射集合错误: $table"
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

    $nonEmptyLines = @(
        $Entry.Body -split '\r?\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('//') }
    )
    Require ($nonEmptyLines.Count -eq 4) "分类镜像字段或声明数量错误: $($Entry.Name)"
    Require (@($nonEmptyLines | Where-Object { $_ -ceq 'type "PassiveData"' }).Count -eq 1) "分类镜像不是 PassiveData: $($Entry.Name)"
    Require (-not [regex]::IsMatch($Entry.Body, '(?i)Boosts|StatsFunctorContext|Spell|ActionResource|Interrupt')) "分类镜像包含玩法效果: $($Entry.Name)"
    Require (-not [regex]::IsMatch($Entry.Body, '(?m)^using ')) "分类镜像不得继承 using: $($Entry.Name)"
    $fields = Get-StatsDataFields -Entry $Entry
    Require (Test-ExactOrdinalSet -Actual @($fields.Keys) -Expected @('DisplayName', 'Description', 'Properties')) "分类镜像字段集合错误: $($Entry.Name)"
    Require ($fields.Properties -ceq 'Highlighted') "分类镜像 Properties 必须精确为 Highlighted: $($Entry.Name)"
}

function Assert-StatsContract {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content,

        [Parameter(Mandatory)]
        [string[]]$ExpectedMirrors,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$StatusGroups,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ExpectedMirrorHandles
    )

    $entries = @(Get-StatsEntries -Content $Content)
    $semanticByHandle = [ordered]@{}
    $addSemanticHandle = {
        param(
            [string]$Value,
            [string]$Descriptor,
            [string]$Context
        )

        $match = [regex]::Match($Value, '^(h[0-9a-z]+)(?:;1)?$')
        Require $match.Success "本地化 handle 格式错误: $Context"
        $handle = $match.Groups[1].Value
        if ($semanticByHandle.Contains($handle)) {
            Require ($semanticByHandle[$handle] -ceq $Descriptor) "本地化 handle 被复用于不同语义: $handle"
        }
        else {
            $semanticByHandle[$handle] = $Descriptor
        }
    }
    $mirrorEntries = @($entries | Where-Object { $_.Name.StartsWith('COS_CFG_CATEGORY_', [System.StringComparison]::Ordinal) })
    $mirrorNames = @($mirrorEntries | ForEach-Object { $_.Name })
    Require (Test-ExactOrdinalSet -Actual $mirrorNames -Expected $ExpectedMirrors) '分类 mirror Stats 集合不精确'
    foreach ($entry in $mirrorEntries) {
        Assert-MirrorPassiveContract -Entry $entry
        Require ($ExpectedMirrorHandles.Contains($entry.Name)) "分类镜像缺少固定 handle 合同: $($entry.Name)"
        $fields = Get-StatsDataFields -Entry $entry
        Require ($fields.DisplayName -ceq $ExpectedMirrorHandles[$entry.Name].DisplayName) "分类镜像 DisplayName handle 错误: $($entry.Name)"
        Require ($fields.Description -ceq $ExpectedMirrorHandles[$entry.Name].Description) "分类镜像 Description handle 错误: $($entry.Name)"
        & $addSemanticHandle $fields.DisplayName $entry.Name "$($entry.Name).DisplayName"
        & $addSemanticHandle $fields.Description $entry.Name "$($entry.Name).Description"
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
    $statusNames = @($statusEntries | ForEach-Object { $_.Name })
    Require (Test-ExactOrdinalSet -Actual $statusNames -Expected $expectedStatuses) '分类/预设状态批准集合不精确'

    foreach ($groupName in $StatusGroups.Keys) {
        foreach ($statusName in $StatusGroups[$groupName].Keys) {
            $matchingEntries = @($statusEntries | Where-Object { $_.Name -ceq $statusName })
            Require ($matchingEntries.Count -eq 1) "状态 entry 缺失或重复: $statusName"
            Assert-StatsStatusContract -Entry $matchingEntries[0] -ExpectedStackId $StatusGroups[$groupName][$statusName]
            $fields = Get-StatsDataFields -Entry $matchingEntries[0]
            & $addSemanticHandle $fields.DisplayName $statusName "$statusName.DisplayName"
            & $addSemanticHandle $fields.Description $statusName "$statusName.Description"
        }
    }

    Require (Test-ExactOrdinalSet -Actual @($ExpectedMirrorHandles.Keys) -Expected $ExpectedMirrors) '固定 mirror handle entry 集合不精确'
    $semanticByHandle
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

function Test-XamlDescendantOrSelf {
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlNode]$Node,

        [Parameter(Mandatory)]
        [System.Xml.XmlNode]$Scope
    )

    $cursor = $Node
    while ($null -ne $cursor) {
        if ([object]::ReferenceEquals($cursor, $Scope)) {
            return $true
        }
        $cursor = $cursor.ParentNode
    }
    return $false
}

function Get-XamlNearestAncestor {
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlNode]$Node,

        [Parameter(Mandatory)]
        [string]$LocalName
    )

    $cursor = $Node.ParentNode
    while ($null -ne $cursor) {
        if ($cursor.LocalName -ceq $LocalName) {
            return $cursor
        }
        $cursor = $cursor.ParentNode
    }
    return $null
}

function Assert-XamlStateNodeContract {
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]$Document,

        [Parameter(Mandatory)]
        [string]$NodeName,

        [Parameter(Mandatory)]
        [string[]]$ExpectedValues,

        [Parameter(Mandatory)]
        [string]$ExpectedBinding,

        [Parameter(Mandatory)]
        [string]$ExpectedItemsSource,

        [Parameter(Mandatory)]
        [string]$Context
    )

    $nodes = @(Get-XamlNamedNodes -Document $Document -Name $NodeName)
    Require ($nodes.Count -eq 1) "$Context 状态节点缺失或重复: $NodeName"
    $triggers = @($nodes[0].SelectNodes('.//*[local-name()="DataTrigger" and @Value]'))
    $actualValues = @($triggers | ForEach-Object { $_.GetAttribute('Value') })
    Require (Test-ExactOrdinalSequence -Actual $actualValues -Expected $ExpectedValues) "$Context 状态过滤集合或顺序错误: $NodeName"
    foreach ($trigger in $triggers) {
        Require ($trigger.GetAttribute('Binding') -ceq $ExpectedBinding) "$Context DataTrigger Binding 错误: $NodeName $($trigger.GetAttribute('Value'))"
        Require ($trigger.ParentNode.LocalName -ceq 'Style.Triggers' -or $trigger.ParentNode.LocalName -ceq 'DataTemplate.Triggers') "$Context DataTrigger 未位于模板或控件 Style: $NodeName"
        $templateOrStyle = $trigger.ParentNode.ParentNode
        Require ($templateOrStyle.LocalName -ceq 'Style' -or $templateOrStyle.LocalName -ceq 'DataTemplate') "$Context DataTrigger 作用域错误: $NodeName"
        $itemsControl = Get-XamlNearestAncestor -Node $trigger -LocalName 'ItemsControl'
        Require ($null -ne $itemsControl -and (Test-XamlDescendantOrSelf -Node $itemsControl -Scope $nodes[0])) "$Context DataTrigger 不在命名节点的 ItemsControl 作用域: $NodeName"
        Require ($itemsControl.GetAttribute('ItemsSource') -ceq $ExpectedItemsSource) "$Context ItemsSource 错误: $NodeName"
    }
    $actualValues
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
        [string[]]$ButtonOrder,

        [Parameter(Mandatory)]
        [string[]]$ExpectedNamedNodes,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$UiHandleDescriptors,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ControllerNavigation,

        [Parameter(Mandatory)]
        [string[]]$ExpectedMirrors,

        [Parameter(Mandatory)]
        [string[]]$ExpectedCategorySections,

        [Parameter(Mandatory)]
        [string[]]$ApprovedStatusIds
    )

    [xml]$document = $Content
    $allNames = @(Get-NamedNodeOrder -Document $document)
    Assert-OrderedSubset -Actual $allNames -Expected $PanelOrder -Context $PageName
    Assert-OrderedSubset -Actual $allNames -Expected $ButtonOrder -Context "$PageName 按钮"

    $featureNames = @(
        $allNames | Where-Object {
            $_.StartsWith('COSPreset', [System.StringComparison]::Ordinal) -or
            $_.StartsWith('COSCategory', [System.StringComparison]::Ordinal)
        }
    )
    Require (Test-ExactOrdinalSet -Actual $featureNames -Expected $ExpectedNamedNodes) "$PageName 分类/预设命名节点批准集合错误"

    $eventMap = [ordered]@{}
    foreach ($buttonName in $ButtonEvents.Keys) {
        $nodes = @(Get-XamlNamedNodes -Document $document -Name $buttonName)
        Require ($nodes.Count -eq 1) "$PageName 按钮命名节点缺失或重复: $buttonName"
        $event = Get-UiButtonEvent -Node $nodes[0] -Context "$PageName $buttonName"
        $clickTriggers = @($nodes[0].SelectNodes('.//*[local-name()="EventTrigger" and @EventName="Click"]'))
        Require ($clickTriggers.Count -eq 1) "$PageName 按钮必须具有唯一 pointer Click: $buttonName"
        $clickEvent = Get-UiButtonEvent -Node $clickTriggers[0] -Context "$PageName $buttonName pointer Click"
        Require ($event -ceq $ButtonEvents[$buttonName] -and $clickEvent -ceq $event) "$PageName 按钮 Click 事件错误: $buttonName"
        $eventMap[$buttonName] = $event

        if ($Controller -and $ControllerNavigation.Contains($buttonName)) {
            Require ($nodes[0].GetAttribute('BoundEvent') -ceq 'UIAccept') "$PageName 手柄按钮缺少 UIAccept: $buttonName"
            Require ($nodes[0].GetAttribute('MoveFocus.Focusable', 'clr-namespace:ls;assembly=Code') -ceq 'True') "$PageName 手柄按钮 MoveFocus.Focusable 必须为 True: $buttonName"
            foreach ($direction in @('Up', 'Down', 'Left', 'Right')) {
                $actualTarget = $nodes[0].GetAttribute("MoveFocus.$direction", 'clr-namespace:ls;assembly=Code')
                $expectedTarget = $ControllerNavigation[$buttonName][$direction]
                Require (-not [string]::IsNullOrWhiteSpace($actualTarget)) "$PageName 手柄焦点方向缺失: $buttonName $direction"
                Require ($actualTarget -ceq $expectedTarget) "$PageName 手柄焦点方向错误: $buttonName $direction"
                Require ($ControllerNavigation.Contains($actualTarget)) "$PageName 手柄焦点方向形成死路: $buttonName $direction"
            }
        }
        elseif (-not $Controller) {
            Require ([string]::IsNullOrWhiteSpace($nodes[0].GetAttribute('BoundEvent'))) "$PageName 键鼠按钮不得依赖手柄 BoundEvent: $buttonName"
        }
    }

    $statusMap = [ordered]@{}
    foreach ($nodeName in $StatusNodeSets.Keys) {
        $nodes = @(Get-XamlNamedNodes -Document $document -Name $nodeName)
        Require ($nodes.Count -eq 1) "$PageName 状态节点缺失或重复: $nodeName"
        Require ($nodes[0].GetAttribute('IsHitTestVisible') -ceq 'False') "$PageName 状态节点必须只读: $nodeName"
        Require ($nodes[0].GetAttribute('Focusable') -ceq 'False') "$PageName 状态节点必须不可聚焦: $nodeName"
        $actualValues = @(Assert-XamlStateNodeContract -Document $document -NodeName $nodeName -ExpectedValues $StatusNodeSets[$nodeName] -ExpectedBinding '{Binding StatusId}' -ExpectedItemsSource '{Binding CurrentPlayer.SelectedCharacter.StatusEffects}' -Context $PageName)
        $statusMap[$nodeName] = $actualValues
    }

    $panelNodes = @(Get-XamlNamedNodes -Document $document -Name 'COSPresetPanel')
    Require ($panelNodes.Count -eq 1) "$PageName 分类/预设面板缺失或重复"
    foreach ($featureName in $ExpectedNamedNodes) {
        $featureNodes = @(Get-XamlNamedNodes -Document $document -Name $featureName)
        Require ($featureNodes.Count -eq 1) "$PageName 新增命名节点缺失或重复: $featureName"
        if ($featureName -cne 'COSPresetPanel') {
            $insidePanel = $false
            $ancestor = $featureNodes[0].ParentNode
            while ($null -ne $ancestor) {
                if ([object]::ReferenceEquals($ancestor, $panelNodes[0])) {
                    $insidePanel = $true
                    break
                }
                $ancestor = $ancestor.ParentNode
            }
            Require $insidePanel "$PageName 新增命名节点不在 COSPresetPanel 内: $featureName"
        }
    }

    $stateScopes = [System.Collections.Generic.List[System.Xml.XmlElement]]::new()
    $stateScopes.Add($panelNodes[0])
    foreach ($sectionName in $ExpectedCategorySections) {
        $sectionNodes = @(Get-XamlNamedNodes -Document $document -Name $sectionName)
        Require ($sectionNodes.Count -eq 1) "$PageName 分类 section 缺失或重复: $sectionName"
        $stateScopes.Add($sectionNodes[0])
        $token = $sectionName.Substring('COSCategory'.Length, $sectionName.Length - 'COSCategory'.Length - 'Section'.Length)
        $expectedSectionNames = @(
            $sectionName,
            "COSCategory${token}MasterRow",
            "COSCategory${token}Toggle",
            "COSCategory${token}Mirror",
            "COSCategory${token}Actual",
            "COSCategory${token}Children",
            "COSCategory${token}PausedOverlay"
        )
        $actualSectionNames = @(
            Get-XamlName -Node $sectionNodes[0]
            $sectionNodes[0].SelectNodes('.//*') |
                ForEach-Object { Get-XamlName -Node $_ } |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_) -and
                    $_.StartsWith("COSCategory$token", [System.StringComparison]::Ordinal)
                }
        )
        Require (Test-ExactOrdinalSet -Actual $actualSectionNames -Expected $expectedSectionNames) "$PageName 分类 section 新增命名节点集合错误: $sectionName"
        $childrenNodes = @(Get-XamlNamedNodes -Document $document -Name "COSCategory${token}Children")
        $pausedNodes = @(Get-XamlNamedNodes -Document $document -Name "COSCategory${token}PausedOverlay")
        Require ($childrenNodes.Count -eq 1 -and $pausedNodes.Count -eq 1 -and [object]::ReferenceEquals($pausedNodes[0].ParentNode, $childrenNodes[0])) "$PageName paused overlay 必须只覆盖 child grid: $sectionName"
        Require ($pausedNodes[0].GetAttribute('IsHitTestVisible') -ceq 'True') "$PageName paused overlay 必须阻断 child grid: $sectionName"
        $expectedMirror = $ExpectedMirrors[[Array]::IndexOf($ExpectedCategorySections, $sectionName)]
        $statusToken = $expectedMirror.Substring('COS_CFG_CATEGORY_'.Length)
        [void](Assert-XamlStateNodeContract -Document $document -NodeName "COSCategory${token}PausedOverlay" -ExpectedValues @("COS_CATEGORY_ACTUAL_${statusToken}_PAUSED") -ExpectedBinding '{Binding StatusId}' -ExpectedItemsSource '{Binding CurrentPlayer.SelectedCharacter.StatusEffects}' -Context $PageName)
        [void](Assert-XamlStateNodeContract -Document $document -NodeName "COSCategory${token}Mirror" -ExpectedValues @($expectedMirror) -ExpectedBinding '{Binding Name.Str}' -ExpectedItemsSource '{Binding CurrentPlayer.SelectedCharacter.Stats.Passives}' -Context $PageName)
    }
    $stateReferences = [System.Collections.Generic.List[string]]::new()
    foreach ($scope in $stateScopes) {
        foreach ($trigger in @($scope.SelectNodes('.//*[local-name()="DataTrigger" and @Value]'))) {
            $value = $trigger.GetAttribute('Value')
            if ($value.StartsWith('COS_PRESET_', [System.StringComparison]::Ordinal) -or $value.StartsWith('COS_CATEGORY_ACTUAL_', [System.StringComparison]::Ordinal)) {
                Require ($ApprovedStatusIds -ccontains $value) "$PageName 包含未批准状态引用: $value"
                $stateReferences.Add($value)
            }
        }
        foreach ($node in @($scope) + @($scope.SelectNodes('.//*'))) {
            foreach ($attribute in @($node.Attributes)) {
                if ($attribute.LocalName -ceq 'StatusId' -or $attribute.LocalName -ceq 'Name.Str') {
                    $value = $attribute.Value
                    if ($value.StartsWith('COS_PRESET_', [System.StringComparison]::Ordinal) -or $value.StartsWith('COS_CATEGORY_ACTUAL_', [System.StringComparison]::Ordinal)) {
                        Require ($ApprovedStatusIds -ccontains $value) "$PageName 包含未批准状态属性引用: $value"
                        $stateReferences.Add($value)
                    }
                }
            }
        }
    }
    $allEventValues = @(
        $panelNodes[0].SelectNodes('.//*[local-name()="InvokeCommandAction" and @CommandParameter]') |
            ForEach-Object { $_.GetAttribute('CommandParameter') }
    )
    $expectedEventValues = @($ButtonOrder | ForEach-Object { $ButtonEvents[$_] })
    Require (Test-ExactOrdinalSequence -Actual $allEventValues -Expected $expectedEventValues) "$PageName 分类/预设事件批准集合或顺序错误"

    $uiHandles = [ordered]@{}
    foreach ($nodeName in $UiHandleDescriptors.Keys) {
        $nodes = @(Get-XamlNamedNodes -Document $document -Name $nodeName)
        Require ($nodes.Count -eq 1) "$PageName 本地化 handle 节点缺失或重复: $nodeName"
        $handleReferences = @(
            [regex]::Matches($nodes[0].OuterXml, '\bSource=[''"](h[^''"]+)[''"]') |
                ForEach-Object { $_.Groups[1].Value }
        )
        Require ($handleReferences.Count -eq 1 -and [regex]::IsMatch($handleReferences[0], '^h[0-9a-z]+$')) "$PageName 本地化 handle 缺失、重复或格式错误: $nodeName"
        $uiHandles[$nodeName] = $handleReferences[0]
    }

    $mirrorValues = @(
        $panelNodes[0].SelectNodes('.//*[local-name()="DataTrigger" and @Binding="{Binding Name.Str}" and @Value]') |
            ForEach-Object { $_.GetAttribute('Value') } |
            Where-Object { $_.StartsWith('COS_CFG_CATEGORY_', [System.StringComparison]::Ordinal) }
    )
    Require (Test-ExactOrdinalSequence -Actual $mirrorValues -Expected $ExpectedMirrors) "$PageName 分类 mirror 过滤集合或顺序错误"

    $combatTriggers = @(
        $panelNodes[0].SelectNodes('.//*[local-name()="DataTrigger"]') |
            Where-Object { [regex]::IsMatch($_.GetAttribute('Binding'), '(?:^|[^A-Za-z0-9_])IsInCombat(?:[^A-Za-z0-9_]|$)') }
    )
    Require ($combatTriggers.Count -eq 1) "$PageName 战斗只读条件数量不精确"
    Require ($combatTriggers[0].GetAttribute('Binding') -ceq '{Binding CurrentPlayer.SelectedCharacter.IsInCombat}') "$PageName 战斗只读 Binding 错误"
    Require ($combatTriggers[0].GetAttribute('Value') -ceq 'True') "$PageName 战斗只读条件值必须为 True"
    Require ($combatTriggers[0].ParentNode.LocalName -ceq 'Style.Triggers' -and $combatTriggers[0].ParentNode.ParentNode.LocalName -ceq 'Style') "$PageName 战斗只读条件必须位于 COSPresetPanel Style"
    $styleProperty = $combatTriggers[0].ParentNode.ParentNode.ParentNode
    Require ($styleProperty.LocalName -ceq "$($panelNodes[0].LocalName).Style" -and [object]::ReferenceEquals($styleProperty.ParentNode, $panelNodes[0])) "$PageName 战斗只读条件未覆盖 COSPresetPanel"
    $readonlySetters = @($combatTriggers[0].SelectNodes('./*[local-name()="Setter" and @Property="IsHitTestVisible" and @Value="False"]'))
    Require ($readonlySetters.Count -eq 1) "$PageName 战斗时必须禁用面板交互"

    [pscustomobject]@{
        Document = $document
        Events = $eventMap
        Statuses = $statusMap
        Handles = $uiHandles
        Mirrors = $mirrorValues
        Navigation = $ControllerNavigation
        StateReferences = @($stateReferences.ToArray())
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
        Require (Test-ExactOrdinalSequence -Actual $Keyboard.Statuses[$name] -Expected $Controller.Statuses[$name]) "键鼠/手柄状态集合或顺序不对称: $name"
    }
    Require (Test-ExactOrdinalSequence -Actual @($Keyboard.Handles.Keys) -Expected @($Controller.Handles.Keys)) '键鼠/手柄本地化节点语义不对称'
    foreach ($name in $Keyboard.Handles.Keys) {
        Require ($Keyboard.Handles[$name] -ceq $Controller.Handles[$name]) "键鼠/手柄本地化 handle 语义不对称: $name"
    }
    Require (Test-ExactOrdinalSequence -Actual $Keyboard.Mirrors -Expected $Controller.Mirrors) '键鼠/手柄分类 mirror 语义不对称'
    Require (Test-ExactOrdinalSequence -Actual $Keyboard.StateReferences -Expected $Controller.StateReferences) '键鼠/手柄状态引用语义不对称'
}

function Get-SemanticTokens {
    param(
        [Parameter(Mandatory)]
        [string]$Descriptor
    )

    $concepts = [ordered]@{
        NEAR_VANILLA = @('原版', 'vanilla', 'バニラ', '바닐라')
        PURE_CHAOS = @('混沌', 'chaos', 'カオス', '카오스')
        ALL_CONVENIENCE = @('全部', 'all', 'すべて', '모두')
        BALANCED = @('平衡', 'balanced', 'バランス', '균형')
        CUSTOM = @('自定义', 'custom', 'カスタム', '사용자')
        WEAPON = @('武器', 'weapon', '武器', '무기')
        ARMOR = @('护甲', 'armor', '防具', '방어구')
        RACETAGS = @('种族标签', 'race tag', '種族タグ', '종족 태그')
        RACIAL = @('种族能力', 'racial', '種族能力', '종족 능력')
        CONVENIENCE = @('便利', 'convenience', '便利', '편의')
        ORIGIN = @('起源', 'origin', 'オリジン', '기원')
        CORE = @('核心', 'core', 'コア', '핵심')
        WAITING_CONDITION = @('等待', 'waiting', '待機', '대기')
        MISSING_CONFIG = @('缺失', 'missing', '不足', '누락')
        SYNC_FAILED = @('同步', 'sync', '同期', '동기화')
        CONFIG_INCOMPLETE = @('不完整', 'incomplete', '不完全', '불완전')
        COMBAT_READONLY = @('战斗', 'combat', '戦闘', '전투')
        NO_SELECTION = @('选择', 'selection', '選択', '선택')
        CURRENT = @('当前', 'current', '現在', '현재')
        PENDING = @('待应用', 'pending', '保留', '대기')
        PREVIEW = @('预览', 'preview', 'プレビュー', '미리보기')
        ACTIVE = @('启用', 'active', '有効', '활성')
        PAUSED = @('暂停', 'paused', '一時停止', '일시 중지')
        ERROR = @('错误', 'error', 'エラー', '오류')
        APPLY = @('应用', 'apply', '適用', '적용')
        CANCEL = @('取消', 'cancel', 'キャンセル', '취소')
        LIFE = @('生活', 'life', '生活', '생활')
        CATEGORY = @('分类', 'category', 'カテゴリー', '분류')
        PRESET = @('预设', 'preset', 'プリセット', '프리셋')
        ACTUAL = @('实际', 'actual', '実際', '실제')
        ON = @('开启', 'on', 'オン', '켜짐')
        OFF = @('关闭', 'off', 'オフ', '꺼짐')
        TITLE = @('设置', 'settings', '設定', '설정')
        SELECT = @('选择', 'select', '選択', '선택')
        REFRESH = @('刷新', 'refresh', '更新', '새로고침')
    }

    $tokens = [ordered]@{
        Chinese = [System.Collections.Generic.List[string]]::new()
        English = [System.Collections.Generic.List[string]]::new()
        Japanese = [System.Collections.Generic.List[string]]::new()
        Korean = [System.Collections.Generic.List[string]]::new()
    }
    foreach ($concept in $concepts.Keys) {
        $conceptPattern = '(?:^|_)' + [regex]::Escape($concept) + '(?:_|$)'
        if ([regex]::IsMatch($Descriptor, $conceptPattern)) {
            $values = $concepts[$concept]
            $tokens.Chinese.Add($values[0])
            $tokens.English.Add($values[1])
            $tokens.Japanese.Add($values[2])
            $tokens.Korean.Add($values[3])
        }
    }
    foreach ($number in @('0', '5', '20')) {
        if ($Descriptor.EndsWith("_$number", [System.StringComparison]::Ordinal)) {
            foreach ($language in $tokens.Keys) { $tokens[$language].Add($number) }
        }
    }
    Require ($tokens.English.Count -gt 0) "验证器内部错误: 缺少语义 token 定义 $Descriptor"
    $tokens
}

function Assert-LocalizationContract {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$ContentByLanguage,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$SemanticByHandle
    )

    $nodesByLanguage = [ordered]@{}
    $handlesByLanguage = [ordered]@{}
    foreach ($language in $ContentByLanguage.Keys) {
        [xml]$document = $ContentByLanguage[$language]
        $nodes = @($document.SelectNodes('/contentList/content'))
        $nodesByLanguage[$language] = $nodes
        $handlesByLanguage[$language] = @($nodes | ForEach-Object { $_.GetAttribute('contentuid') })
        Require (Test-ExactOrdinalSet -Actual $handlesByLanguage[$language] -Expected $handlesByLanguage[$language]) "本地化 handle 重复: $language"
        foreach ($handle in $SemanticByHandle.Keys) {
            Require (@($handlesByLanguage[$language] | Where-Object { $_ -ceq $handle }).Count -eq 1) "分类/预设批准 handle 缺失或重复: $language $handle"
        }
    }

    $referenceHandles = $handlesByLanguage.Chinese
    foreach ($language in $ContentByLanguage.Keys) {
        Require (Test-ExactOrdinalSet -Actual $handlesByLanguage[$language] -Expected $referenceHandles) "四语 handle 集合不一致: $language"
    }

    foreach ($handle in $SemanticByHandle.Keys) {
        $texts = [ordered]@{}
        foreach ($language in $ContentByLanguage.Keys) {
            $nodes = @($nodesByLanguage[$language] | Where-Object { $_.GetAttribute('contentuid') -ceq $handle })
            Require ($nodes.Count -eq 1) "本地化 handle 未唯一覆盖: $language $handle"
            $text = $nodes[0].InnerText
            Require (-not [string]::IsNullOrWhiteSpace($text)) "本地化文本为空: $language $handle"
            Require (-not [regex]::IsMatch($text, '(?i)\bNot Found\b')) "本地化包含 Not Found: $language $handle"
            Require ($text.Trim() -cne 'A') "本地化文本不得使用占位符 A: $language $handle"
            $texts[$language] = $text
        }

        Require ([regex]::IsMatch($texts.Chinese, '\p{IsCJKUnifiedIdeographs}')) "中文语义不完整: $handle"
        Require ([regex]::IsMatch($texts.English, '[A-Za-z]')) "英文语义不完整: $handle"
        Require ([regex]::IsMatch($texts.Japanese, '[\p{IsHiragana}\p{IsKatakana}]')) "日文必须包含日文假名: $handle"
        Require ([regex]::IsMatch($texts.Korean, '\p{IsHangulSyllables}')) "韩文必须包含韩文字符: $handle"
        $semanticTokens = Get-SemanticTokens -Descriptor $SemanticByHandle[$handle]
        foreach ($language in $ContentByLanguage.Keys) {
            foreach ($token in $semanticTokens[$language]) {
                Require ($texts[$language].IndexOf($token, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) "$language 缺少语义 token '$token': $handle"
            }
        }
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
    GlobalBenefits = Join-Path $Root 'Mods\ChaosOriginsStory\Story\RawFiles\Goals\COS_GlobalPlayerBenefits.txt'
    Mastery = Join-Path $Root 'Mods\ChaosOriginsStory\Story\RawFiles\Goals\COS_ChaosMastery.txt'
    Stats = Join-Path $Root 'Public\ChaosOriginsStory\Stats\Generated\Data\ChaosConfig.txt'
    Keyboard = Join-Path $Root 'Mods\ChaosOriginsStory\GUI\Pages\COS_ConfigMenu.xaml'
    Controller = Join-Path $Root 'Mods\ChaosOriginsStory\GUI\Pages\COS_ConfigMenu_c.xaml'
    Package = Join-Path $Root 'package-files.json'
}

$config = Read-Required $paths.Config
$mechanics = Read-Required $paths.Mechanics
$globalBenefits = Read-Required $paths.GlobalBenefits
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

$task3LegacyProbes = [ordered]@{
    DB_COS_ConfigMechanic = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyMechanic'; Arity = 3 }
    DB_COS_ConfigLifeSkill = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyLifeSkill'; Arity = 2 }
    DB_COS_ConfigCost = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyCost'; Arity = 3 }
    DB_COS_ConfigRacial = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyRacial'; Arity = 3 }
    DB_COS_GrantSetting = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyGrant'; Arity = 3 }
    DB_COS_TagSpellsSetting = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyTagSpells'; Arity = 2 }
    DB_COS_VoloEyeSetting = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyVoloEye'; Arity = 2 }
    DB_COS_CarryEnabled = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyCarry'; Arity = 2 }
}
$task3CategoryEvents = [ordered]@{
    Core = '7e990000-0000-4000-8000-000000000001'
    Origin = '7e990000-0000-4000-8000-000000000002'
    RaceTags = '7e990000-0000-4000-8000-000000000003'
    WeaponProficiencies = '7e990000-0000-4000-8000-000000000004'
    ArmorProficiencies = '7e990000-0000-4000-8000-000000000005'
    RacialAbilities = '7e990000-0000-4000-8000-000000000006'
    Convenience = '7e990000-0000-4000-8000-000000000007'
}
$task3NewCategories = [ordered]@{
    Core = 0
    Origin = 1
    RaceTags = 0
    WeaponProficiencies = 0
    ArmorProficiencies = 0
    RacialAbilities = 0
    Convenience = 0
}
$task3LegacyCategories = [ordered]@{
    Core = 1
    Origin = 1
    RaceTags = 1
    WeaponProficiencies = 1
    ArmorProficiencies = 1
    RacialAbilities = 1
    Convenience = 1
}
$legacyWriterEntrypoints = [ordered]@{
    ConfigSyncCharacter = [pscustomobject]@{
        Content = $config
        Procedure = 'PROC_COS_ConfigSyncCharacter'
        SelectorAction = ''
    }
    MechanicsSync = [pscustomobject]@{
        Content = $mechanics
        Procedure = 'PROC_COS_Sync'
        SelectorAction = 'PROC_COS_ConfigEnsureCosts(_Character);'
    }
    GlobalPlayerBenefitsSync = [pscustomobject]@{
        Content = $globalBenefits
        Procedure = 'PROC_COS_SyncGlobalPlayerBenefits'
        SelectorAction = ''
    }
    GrantSync = [pscustomobject]@{
        Content = $config
        Procedure = 'PROC_COS_ConfigSyncGrants'
        SelectorAction = ''
    }
    VoloEyeSync = [pscustomobject]@{
        Content = $config
        Procedure = 'PROC_COS_SyncVoloEye'
        SelectorAction = ''
    }
}

Assert-OsirisParserContract
Assert-MutationHarnessContract

if ($Focus -ceq 'Task3') {
    Assert-CategoryMappingContract -Content $config -ExpectedCategories $categories
    Assert-LegacyDetectionContract -Content $config -ExpectedProbes $task3LegacyProbes
    Assert-CategorySeedContract -Content $config -ExpectedCategories $categories -ExpectedEvents $task3CategoryEvents -ExpectedLegacyTables @($task3LegacyProbes.Keys)
    Assert-CategoryInitializationContract -Content $config -NewCategories $task3NewCategories -LegacyCategories $task3LegacyCategories -NewLife 0
    Assert-LegacyWriterInitializationContract -Entrypoints $legacyWriterEntrypoints
    Assert-CategoryMirrorContract -Content $config
    Assert-CategoryEventContract -Content $config
    Assert-CategoryToggleContract -Content $config -Task3Stage

    $newInitModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_ConfigInitializeNew')[0]
    $newLifeMutationBlock = Replace-FirstLiteral -Content $newInitModel.Block -OldValue 'DB_COS_ConfigLifeSkill(_Character, 0);' -NewValue 'DB_COS_ConfigLifeSkill(_Character, 5);' -ProbeName 'task3-new-life-not-zero'
    $newLifeMutation = Replace-RuleBlock -Content $config -OldBlock $newInitModel.Block -NewBlock $newLifeMutationBlock -ProbeName 'task3-new-life-not-zero'
    Assert-MutationRejected -Name 'task3-new-life-not-zero' -ExpectedMessagePattern '^新角色分类初始化 THEN 动作序列不精确$' -Probe {
        Assert-CategoryInitializationContract -Content $newLifeMutation -NewCategories $task3NewCategories -LegacyCategories $task3LegacyCategories -NewLife 0
    }

    $legacyInitModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_ConfigInitializeLegacy')[0]
    $legacyLifeMutationBlock = Replace-FirstLiteral -Content $legacyInitModel.Block -OldValue 'THEN' -NewValue "THEN`nDB_COS_ConfigLifeSkill(_Character, 0);" -ProbeName 'task3-legacy-life-write'
    $legacyLifeMutation = Replace-RuleBlock -Content $config -OldBlock $legacyInitModel.Block -NewBlock $legacyLifeMutationBlock -ProbeName 'task3-legacy-life-write'
    Assert-MutationRejected -Name 'task3-legacy-life-write' -ExpectedMessagePattern '^旧角色分类初始化 THEN 动作序列不精确$' -Probe {
        Assert-CategoryInitializationContract -Content $legacyLifeMutation -NewCategories $task3NewCategories -LegacyCategories $task3LegacyCategories -NewLife 0
    }

    $commitModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_ConfigCommitCategorySchema')[0]
    $sixRowCondition = @($commitModel.Conditions | Where-Object { $_ -match '^DB_COS_ConfigCategory\(_Character, "Convenience", ' })[0]
    $sixRowBlock = Replace-FirstLiteral -Content $commitModel.Block -OldValue $sixRowCondition -NewValue "// mutation: removed seventh category row" -ProbeName 'task3-schema-six-rows'
    $sixRowMutation = Replace-RuleBlock -Content $config -OldBlock $commitModel.Block -NewBlock $sixRowBlock -ProbeName 'task3-schema-six-rows'
    Assert-MutationRejected -Name 'task3-schema-six-rows' -ExpectedMessagePattern '^分类 schema 提交条件行数错误: 期望 8，实际 7$' -Probe {
        Assert-CategoryInitializationContract -Content $sixRowMutation -NewCategories $task3NewCategories -LegacyCategories $task3LegacyCategories -NewLife 0
    }

    $rowModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_ConfigInitCategory')[0]
    $rewriteBlock = Replace-FirstLiteral -Content $rowModel.Block -OldValue 'NOT DB_COS_ConfigCategory(_Character, _Category, _)' -NewValue 'DB_COS_ConfigCategory(_Character, _Category, _)' -ProbeName 'task3-second-init-rewrite'
    $rewriteMutation = Replace-RuleBlock -Content $config -OldBlock $rowModel.Block -NewBlock $rewriteBlock -ProbeName 'task3-second-init-rewrite'
    Assert-MutationRejected -Name 'task3-second-init-rewrite' -ExpectedMessagePattern '^分类单行初始化 条件集合不精确$' -Probe {
        Assert-CategoryInitializationContract -Content $rewriteMutation -NewCategories $task3NewCategories -LegacyCategories $task3LegacyCategories -NewLife 0
    }

    $partialProbeName = $task3LegacyProbes.DB_COS_ConfigMechanic.Procedure
    $partialProbeModel = @(Get-ProcedureModels -Content $config -Name $partialProbeName)[0]
    $partialProbeBlock = Replace-FirstLiteral -Content $partialProbeModel.Block -OldValue 'THEN' -NewValue "AND`nDB_COS_ConfigLifeSkill(_Character, _)`nTHEN" -ProbeName 'task3-partial-legacy-requires-two-tables'
    $partialProbeMutation = Replace-RuleBlock -Content $config -OldBlock $partialProbeModel.Block -NewBlock $partialProbeBlock -ProbeName 'task3-partial-legacy-requires-two-tables'
    Assert-MutationRejected -Name 'task3-partial-legacy-requires-two-tables' -ExpectedMessagePattern '^旧档 probe 条件集合不精确: DB_COS_ConfigMechanic$' -Probe {
        Assert-LegacyDetectionContract -Content $partialProbeMutation -ExpectedProbes $task3LegacyProbes
    }

    $disabledMirrorModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_ConfigRemoveDisabledCategoryMirrors')[0]
    $missingAsDisabledBlock = Replace-FirstLiteral -Content $disabledMirrorModel.Block -OldValue 'DB_COS_ConfigCategory(_Character, _Category, 0)' -NewValue 'NOT DB_COS_ConfigCategory(_Character, _Category, 1)' -ProbeName 'task3-missing-category-defaults-off'
    $missingAsDisabledMutation = Replace-RuleBlock -Content $config -OldBlock $disabledMirrorModel.Block -NewBlock $missingAsDisabledBlock -ProbeName 'task3-missing-category-defaults-off'
    Assert-MutationRejected -Name 'task3-missing-category-defaults-off' -ExpectedMessagePattern '^关闭分类镜像 条件集合不精确$' -Probe {
        Assert-CategoryMirrorContract -Content $missingAsDisabledMutation
    }

    $toggleModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_ConfigToggleCategory')[0]
    $toggleWriteBlock = Replace-FirstLiteral -Content $toggleModel.Block -OldValue 'THEN' -NewValue "THEN`nDB_COS_ConfigCost(_Character, `"Fate`", 999);" -ProbeName 'task3-category-toggle-child-write'
    $toggleWriteMutation = Replace-RuleBlock -Content $config -OldBlock $toggleModel.Block -NewBlock $toggleWriteBlock -ProbeName 'task3-category-toggle-child-write'
    Assert-MutationRejected -Name 'task3-category-toggle-child-write' -ExpectedMessagePattern '^分类切换过程 THEN 动作序列不精确$' -Probe {
        Assert-CategoryToggleContract -Content $toggleWriteMutation -Task3Stage
    }

    $mechanicsSyncModel = @(Get-ProcedureModels -Content $mechanics -Name 'PROC_COS_Sync' | Where-Object { $_.Actions -ccontains 'PROC_COS_ConfigEnsureCosts(_Character);' })[0]
    $mechanicsInitMutationBlock = Replace-FirstLiteral -Content $mechanicsSyncModel.Block -OldValue 'PROC_COS_ConfigInitializeCategories(_Character);' -NewValue '// mutation: category initialization removed' -ProbeName 'task3-mechanics-sync-init-removed'
    $mechanicsInitMutation = Replace-RuleBlock -Content $mechanics -OldBlock $mechanicsSyncModel.Block -NewBlock $mechanicsInitMutationBlock -ProbeName 'task3-mechanics-sync-init-removed'
    $mechanicsMutationEntrypoints = [ordered]@{} + $legacyWriterEntrypoints
    $mechanicsMutationEntrypoints.MechanicsSync = [pscustomobject]@{
        Content = $mechanicsInitMutation
        Procedure = 'PROC_COS_Sync'
        SelectorAction = 'PROC_COS_ConfigEnsureCosts(_Character);'
    }
    Assert-MutationRejected -Name 'task3-mechanics-sync-init-removed' -ExpectedMessagePattern '^生命周期 legacy-writer 入口未先初始化分类: MechanicsSync$' -Probe {
        Assert-LegacyWriterInitializationContract -Entrypoints $mechanicsMutationEntrypoints
    }

    $globalSyncModel = @(Get-ProcedureModels -Content $globalBenefits -Name 'PROC_COS_SyncGlobalPlayerBenefits')[0]
    $globalInitMutationBlock = Replace-FirstLiteral -Content $globalSyncModel.Block -OldValue "PROC_COS_ConfigInitializeCategories(_Character);`nPROC_COS_EnsureCarrySetting(_Character);" -NewValue "PROC_COS_EnsureCarrySetting(_Character);`nPROC_COS_ConfigInitializeCategories(_Character);" -ProbeName 'task3-global-sync-init-downshifted'
    $globalInitMutation = Replace-RuleBlock -Content $globalBenefits -OldBlock $globalSyncModel.Block -NewBlock $globalInitMutationBlock -ProbeName 'task3-global-sync-init-downshifted'
    $globalMutationEntrypoints = [ordered]@{} + $legacyWriterEntrypoints
    $globalMutationEntrypoints.GlobalPlayerBenefitsSync = [pscustomobject]@{
        Content = $globalInitMutation
        Procedure = 'PROC_COS_SyncGlobalPlayerBenefits'
        SelectorAction = ''
    }
    Assert-MutationRejected -Name 'task3-global-sync-init-downshifted' -ExpectedMessagePattern '^生命周期 legacy-writer 入口未先初始化分类: GlobalPlayerBenefitsSync$' -Probe {
        Assert-LegacyWriterInitializationContract -Entrypoints $globalMutationEntrypoints
    }

    $grantSyncModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_ConfigSyncGrants')[0]
    $grantInitMutationBlock = Replace-FirstLiteral -Content $grantSyncModel.Block -OldValue 'PROC_COS_ConfigInitializeCategories(_Character);' -NewValue '// mutation: category initialization removed' -ProbeName 'task3-grant-sync-init-removed'
    $grantInitMutation = Replace-RuleBlock -Content $config -OldBlock $grantSyncModel.Block -NewBlock $grantInitMutationBlock -ProbeName 'task3-grant-sync-init-removed'
    $grantMutationEntrypoints = [ordered]@{} + $legacyWriterEntrypoints
    $grantMutationEntrypoints.GrantSync = [pscustomobject]@{
        Content = $grantInitMutation
        Procedure = 'PROC_COS_ConfigSyncGrants'
        SelectorAction = ''
    }
    Assert-MutationRejected -Name 'task3-grant-sync-init-removed' -ExpectedMessagePattern '^生命周期 legacy-writer 入口未先初始化分类: GrantSync$' -Probe {
        Assert-LegacyWriterInitializationContract -Entrypoints $grantMutationEntrypoints
    }

    $voloSyncModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_SyncVoloEye')[0]
    $voloInitMutationBlock = Replace-FirstLiteral -Content $voloSyncModel.Block -OldValue "PROC_COS_ConfigInitializeCategories(_Character);`nEnableTutorialEvent(_Character, (TUTORIALEVENT)COS_CFG_VOLO_EYE_77000000-0000-4000-8000-000000000001);" -NewValue "EnableTutorialEvent(_Character, (TUTORIALEVENT)COS_CFG_VOLO_EYE_77000000-0000-4000-8000-000000000001);`nPROC_COS_ConfigInitializeCategories(_Character);" -ProbeName 'task3-volo-sync-init-downshifted'
    $voloInitMutation = Replace-RuleBlock -Content $config -OldBlock $voloSyncModel.Block -NewBlock $voloInitMutationBlock -ProbeName 'task3-volo-sync-init-downshifted'
    $voloMutationEntrypoints = [ordered]@{} + $legacyWriterEntrypoints
    $voloMutationEntrypoints.VoloEyeSync = [pscustomobject]@{
        Content = $voloInitMutation
        Procedure = 'PROC_COS_SyncVoloEye'
        SelectorAction = ''
    }
    Assert-MutationRejected -Name 'task3-volo-sync-init-downshifted' -ExpectedMessagePattern '^生命周期 legacy-writer 入口未先初始化分类: VoloEyeSync$' -Probe {
        Assert-LegacyWriterInitializationContract -Entrypoints $voloMutationEntrypoints
    }

    Write-Output 'Task 3 category persistence contract: PASS'
    Write-Output 'Task 3 mutation probes: new=PASS; legacy=PASS; partial=PASS; schema=PASS; idempotence=PASS; missing-row=PASS; toggle=PASS; lifecycle-init=PASS'
    exit 0
}

# Fail first here on the .98 baseline. Later contracts must not mask a missing category implementation.
Assert-CategoryMappingContract -Content $config -ExpectedCategories $categories

$legacyProbes = [ordered]@{
    DB_COS_ConfigMechanic = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyMechanic'; Arity = 3 }
    DB_COS_ConfigLifeSkill = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyLifeSkill'; Arity = 2 }
    DB_COS_ConfigCost = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyCost'; Arity = 3 }
    DB_COS_ConfigRacial = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyRacial'; Arity = 3 }
    DB_COS_GrantSetting = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyGrant'; Arity = 3 }
    DB_COS_TagSpellsSetting = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyTagSpells'; Arity = 2 }
    DB_COS_VoloEyeSetting = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyVoloEye'; Arity = 2 }
    DB_COS_CarryEnabled = [pscustomobject]@{ Procedure = 'PROC_COS_ConfigProbeLegacyCarry'; Arity = 2 }
}
Assert-LegacyDetectionContract -Content $config -ExpectedProbes $legacyProbes
Assert-CategorySeedContract -Content $config -ExpectedCategories $categories -ExpectedEvents $task3CategoryEvents -ExpectedLegacyTables @($legacyProbes.Keys)
Assert-LegacyWriterInitializationContract -Entrypoints $legacyWriterEntrypoints

$coreCategorySeedGuard = 'NOT DB_COS_ConfigCategoryMap("Core", "COS_CFG_CATEGORY_CORE")'
$coreCategorySeedMutation = Replace-FirstLiteral -Content $config -OldValue $coreCategorySeedGuard -NewValue 'DB_COS_ConfigCategoryMap("Core", "COS_CFG_CATEGORY_CORE")' -ProbeName 'default-all-category-seed-missing-not-guard'
Assert-MutationRejected -Name 'default-all-category-seed-missing-not-guard' -ExpectedMessagePattern '^分类 seed 幂等条件与数据动作不匹配: DB_COS_ConfigCategoryMap\("Core", "COS_CFG_CATEGORY_CORE"\)$' -Probe {
    Assert-CategorySeedContract -Content $coreCategorySeedMutation -ExpectedCategories $categories -ExpectedEvents $task3CategoryEvents -ExpectedLegacyTables @($legacyProbes.Keys)
}
Write-Output 'Default All category seed contract and missing-NOT mutation: PASS'

$presetOrder = @('AllConvenience', 'Balanced', 'NearVanilla', 'PureChaos', 'Custom')
Assert-PresetDetectionOrderContract -Content $config -ExpectedOrder $presetOrder
$expectedPresetProcedures = @(
    'PROC_COS_PresetSeed',
    'PROC_COS_PresetClearPreview',
    'PROC_COS_PresetSelect',
    'PROC_COS_PresetBuildPreview',
    'PROC_COS_PresetApply',
    'PROC_COS_PresetSetCategory',
    'PROC_COS_PresetDetect',
    'PROC_COS_PresetSetCurrent',
    'PROC_COS_PresetValidate'
)

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

$newCategoryInitialization = [ordered]@{
    Core = 0
    Origin = 1
    RaceTags = 0
    WeaponProficiencies = 0
    ArmorProficiencies = 0
    RacialAbilities = 0
    Convenience = 0
}
$legacyCategoryInitialization = [ordered]@{
    Core = 1
    Origin = 1
    RaceTags = 1
    WeaponProficiencies = 1
    ArmorProficiencies = 1
    RacialAbilities = 1
    Convenience = 1
}
Assert-CategoryInitializationContract -Content $config -NewCategories $newCategoryInitialization -LegacyCategories $legacyCategoryInitialization -NewLife 0
Assert-EventGuardContract -Content $config
Assert-CategoryToggleContract -Content $config
Assert-PresetWorkflowContract -Content $config

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

$expectedMirrorHandles = [ordered]@{
    COS_CFG_CATEGORY_CORE = [pscustomobject]@{ DisplayName = 'h7e990000g0000g4000g8000g000000000101'; Description = 'h7e990000g0000g4000g8000g000000000102' }
    COS_CFG_CATEGORY_ORIGIN = [pscustomobject]@{ DisplayName = 'h7e990000g0000g4000g8000g000000000103'; Description = 'h7e990000g0000g4000g8000g000000000104' }
    COS_CFG_CATEGORY_RACETAGS = [pscustomobject]@{ DisplayName = 'h7e990000g0000g4000g8000g000000000105'; Description = 'h7e990000g0000g4000g8000g000000000106' }
    COS_CFG_CATEGORY_WEAPON = [pscustomobject]@{ DisplayName = 'h7e990000g0000g4000g8000g000000000107'; Description = 'h7e990000g0000g4000g8000g000000000108' }
    COS_CFG_CATEGORY_ARMOR = [pscustomobject]@{ DisplayName = 'h7e990000g0000g4000g8000g000000000109'; Description = 'h7e990000g0000g4000g8000g000000000110' }
    COS_CFG_CATEGORY_RACIAL = [pscustomobject]@{ DisplayName = 'h7e990000g0000g4000g8000g000000000111'; Description = 'h7e990000g0000g4000g8000g000000000112' }
    COS_CFG_CATEGORY_CONVENIENCE = [pscustomobject]@{ DisplayName = 'h7e990000g0000g4000g8000g000000000113'; Description = 'h7e990000g0000g4000g8000g000000000114' }
}

$semanticByHandle = Assert-StatsContract -Content $stats -ExpectedMirrors @($categories.Values) -StatusGroups $statusGroups -ExpectedMirrorHandles $expectedMirrorHandles
$configCode = (Get-OsirisCodeLines -Content $config) -join "`n"
foreach ($status in @($statusGroups.Values | ForEach-Object { $_.Keys })) {
    $statusPattern = '(?:^|[^A-Za-z0-9_])' + [regex]::Escape($status) + '(?:[^A-Za-z0-9_]|$)'
    Require ([regex]::IsMatch($configCode, $statusPattern)) "Story 未使用分类/预设状态: $status"
}
$approvedStatusIds = @($statusGroups.Values | ForEach-Object { $_.Keys })
Assert-PresetWriteContract -Content $config -ExpectedProcedureNames $expectedPresetProcedures -ApprovedStatusIds $approvedStatusIds -ExpectedDetectionOrder $presetOrder

$buttonEvents = [ordered]@{
    COSCategoryCoreToggle = $categoryEvents.Core
    COSCategoryOriginToggle = $categoryEvents.Origin
    COSCategoryRaceTagsToggle = $categoryEvents.RaceTags
    COSCategoryWeaponToggle = $categoryEvents.WeaponProficiencies
    COSCategoryArmorToggle = $categoryEvents.ArmorProficiencies
    COSCategoryRacialToggle = $categoryEvents.RacialAbilities
    COSCategoryConvenienceToggle = $categoryEvents.Convenience
    COSPresetNearVanillaButton = $presetEvents.NearVanilla
    COSPresetPureChaosButton = $presetEvents.PureChaos
    COSPresetBalancedButton = $presetEvents.Balanced
    COSPresetAllConvenienceButton = $presetEvents.AllConvenience
    COSPresetApplyButton = $presetEvents.Apply
    COSPresetCancelButton = $presetEvents.Cancel
}
$statusNodeSets = [ordered]@{
    COSPresetCurrent = $currentStatuses
    COSPresetPreview = $previewStatuses
    COSPresetPreviewNotice = @($pendingStatuses + $errorStatuses)
}
$categoryUiTokens = [ordered]@{
    Core = 'CORE'
    Origin = 'ORIGIN'
    RaceTags = 'RACETAGS'
    Weapon = 'WEAPON'
    Armor = 'ARMOR'
    Racial = 'RACIAL'
    Convenience = 'CONVENIENCE'
}
foreach ($token in $categoryUiTokens.Keys) {
    $statusNodeSets["COSCategory${token}Actual"] = @($actualStatuses | Where-Object { $_.StartsWith("COS_CATEGORY_ACTUAL_$($categoryUiTokens[$token])_", [System.StringComparison]::Ordinal) })
}
$uiHandleDescriptors = [ordered]@{
    COSPresetNearVanillaButton = 'PRESET_NEAR_VANILLA'
    COSPresetPureChaosButton = 'PRESET_PURE_CHAOS'
    COSPresetBalancedButton = 'PRESET_BALANCED'
    COSPresetAllConvenienceButton = 'PRESET_ALL_CONVENIENCE'
    COSPresetPreviewNotice = 'PRESET_PREVIEW'
    COSCategoryCoreToggle = 'COS_CFG_CATEGORY_CORE'
    COSCategoryOriginToggle = 'COS_CFG_CATEGORY_ORIGIN'
    COSCategoryRaceTagsToggle = 'COS_CFG_CATEGORY_RACETAGS'
    COSCategoryWeaponToggle = 'COS_CFG_CATEGORY_WEAPON'
    COSCategoryArmorToggle = 'COS_CFG_CATEGORY_ARMOR'
    COSCategoryRacialToggle = 'COS_CFG_CATEGORY_RACIAL'
    COSCategoryConvenienceToggle = 'COS_CFG_CATEGORY_CONVENIENCE'
    COSPresetApplyButton = 'PRESET_APPLY'
    COSPresetCancelButton = 'PRESET_CANCEL'
}

$expectedFeatureNamedNodes = @(
    'COSPresetPanel',
    'COSPresetCurrent',
    'COSPresetButtons',
    'COSPresetNearVanillaButton',
    'COSPresetPureChaosButton',
    'COSPresetBalancedButton',
    'COSPresetAllConvenienceButton',
    'COSPresetPreview',
    'COSPresetPreviewEntry',
    'COSPresetPreviewNotice',
    'COSPresetActions',
    'COSPresetApplyButton',
    'COSPresetCancelButton'
    foreach ($token in $categoryUiTokens.Keys) {
        "COSCategory${token}Section"
        "COSCategory${token}MasterRow"
        "COSCategory${token}Toggle"
        "COSCategory${token}Mirror"
        "COSCategory${token}Actual"
        "COSCategory${token}Children"
        "COSCategory${token}PausedOverlay"
    }
)
$expectedCategorySections = @($categoryUiTokens.Keys | ForEach-Object { "COSCategory${_}Section" })
$panelOrder = @(
    'COSRuntimeDiagnosticPanel',
    'COSPresetPanel',
    'COSPresetCurrent',
    'COSPresetButtons',
    'COSPresetPreview',
    'COSPresetPreviewNotice'
    foreach ($sectionName in $expectedCategorySections) { $sectionName }
    'COSPresetActions',
    'COSConfigOverview'
)
$buttonOrder = @(
    'COSPresetNearVanillaButton',
    'COSPresetPureChaosButton',
    'COSPresetBalancedButton',
    'COSPresetAllConvenienceButton',
    'COSCategoryCoreToggle',
    'COSCategoryOriginToggle',
    'COSCategoryRaceTagsToggle',
    'COSCategoryWeaponToggle',
    'COSCategoryArmorToggle',
    'COSCategoryRacialToggle',
    'COSCategoryConvenienceToggle',
    'COSPresetApplyButton',
    'COSPresetCancelButton'
)

$controllerNavigation = [ordered]@{
    COSPresetNearVanillaButton = [ordered]@{ Up = 'COSPresetApplyButton'; Down = 'COSPresetBalancedButton'; Left = 'COSPresetPureChaosButton'; Right = 'COSPresetPureChaosButton' }
    COSPresetPureChaosButton = [ordered]@{ Up = 'COSPresetCancelButton'; Down = 'COSPresetAllConvenienceButton'; Left = 'COSPresetNearVanillaButton'; Right = 'COSPresetNearVanillaButton' }
    COSPresetBalancedButton = [ordered]@{ Up = 'COSPresetNearVanillaButton'; Down = 'COSPresetApplyButton'; Left = 'COSPresetAllConvenienceButton'; Right = 'COSPresetAllConvenienceButton' }
    COSPresetAllConvenienceButton = [ordered]@{ Up = 'COSPresetPureChaosButton'; Down = 'COSPresetCancelButton'; Left = 'COSPresetBalancedButton'; Right = 'COSPresetBalancedButton' }
    COSPresetApplyButton = [ordered]@{ Up = 'COSPresetBalancedButton'; Down = 'COSPresetNearVanillaButton'; Left = 'COSPresetCancelButton'; Right = 'COSPresetCancelButton' }
    COSPresetCancelButton = [ordered]@{ Up = 'COSPresetAllConvenienceButton'; Down = 'COSPresetPureChaosButton'; Left = 'COSPresetApplyButton'; Right = 'COSPresetApplyButton' }
}

$keyboardContract = Assert-UiPageContract -Content $keyboardXaml -PageName 'COS_ConfigMenu.xaml' -Controller $false -ButtonEvents $buttonEvents -StatusNodeSets $statusNodeSets -PanelOrder $panelOrder -ButtonOrder $buttonOrder -ExpectedNamedNodes $expectedFeatureNamedNodes -UiHandleDescriptors $uiHandleDescriptors -ControllerNavigation $controllerNavigation -ExpectedMirrors @($categories.Values) -ExpectedCategorySections $expectedCategorySections -ApprovedStatusIds $approvedStatusIds
$controllerContract = Assert-UiPageContract -Content $controllerXaml -PageName 'COS_ConfigMenu_c.xaml' -Controller $true -ButtonEvents $buttonEvents -StatusNodeSets $statusNodeSets -PanelOrder $panelOrder -ButtonOrder $buttonOrder -ExpectedNamedNodes $expectedFeatureNamedNodes -UiHandleDescriptors $uiHandleDescriptors -ControllerNavigation $controllerNavigation -ExpectedMirrors @($categories.Values) -ExpectedCategorySections $expectedCategorySections -ApprovedStatusIds $approvedStatusIds
Assert-UiParityContract -Keyboard $keyboardContract -Controller $controllerContract

foreach ($nodeName in $keyboardContract.Handles.Keys) {
    $handle = $keyboardContract.Handles[$nodeName]
    $descriptor = $uiHandleDescriptors[$nodeName]
    if ($semanticByHandle.Contains($handle)) {
        Require ($semanticByHandle[$handle] -ceq $descriptor) "UI handle 被复用于不同语义: $nodeName $handle"
    }
    else {
        $semanticByHandle[$handle] = $descriptor
    }
}

Assert-LocalizationContract -ContentByLanguage $localization -SemanticByHandle $semanticByHandle

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
$coreMapLine = 'DB_COS_ConfigCategoryMap("Core", "COS_CFG_CATEGORY_CORE");'
$missingCategoryMutation = Replace-FirstLiteral -Content $config -OldValue $coreMapLine -NewValue '// mutation: removed Core category' -ProbeName 'missing-category'
Assert-MutationRejected -Name 'missing-category' -ExpectedMessagePattern '^缺少分类映射: Core$' -Probe {
    Assert-CategoryMappingContract -Content $missingCategoryMutation -ExpectedCategories $categories
}

$coreMirrorEntry = @(Get-StatsEntries -Content $stats | Where-Object { $_.Name -ceq 'COS_CFG_CATEGORY_CORE' })[0]
$coreMirrorIconSource = Replace-FirstLiteral -Content $coreMirrorEntry.Source -OldValue 'data "Properties" "Highlighted"' -NewValue "data `"Properties`" `"Highlighted`"`ndata `"Icon`" `"Mutation_Icon`"" -ProbeName 'mirror-illegal-icon'
$mirrorIconMutation = Replace-FirstLiteral -Content $stats -OldValue $coreMirrorEntry.Source -NewValue $coreMirrorIconSource -ProbeName 'mirror-illegal-icon'
Assert-MutationRejected -Name 'mirror-illegal-icon' -ExpectedMessagePattern '^分类镜像字段或声明数量错误: COS_CFG_CATEGORY_CORE$' -Probe {
    [void](Assert-StatsContract -Content $mirrorIconMutation -ExpectedMirrors @($categories.Values) -StatusGroups $statusGroups -ExpectedMirrorHandles $expectedMirrorHandles)
}

$mirrorHandleMutation = Replace-FirstLiteral -Content $stats -OldValue $expectedMirrorHandles.COS_CFG_CATEGORY_CORE.DisplayName -NewValue 'h7e990000g0000g4000g8000g000000009999' -ProbeName 'mirror-handle-drift'
Assert-MutationRejected -Name 'mirror-handle-drift' -ExpectedMessagePattern '^分类镜像 DisplayName handle 错误: COS_CFG_CATEGORY_CORE$' -Probe {
    [void](Assert-StatsContract -Content $mirrorHandleMutation -ExpectedMirrors @($categories.Values) -StatusGroups $statusGroups -ExpectedMirrorHandles $expectedMirrorHandles)
}

$balancedCoreLine = 'DB_COS_PresetCategory("Balanced", "Core", 1);'
$wrongPresetMutation = Replace-FirstLiteral -Content $config -OldValue $balancedCoreLine -NewValue 'DB_COS_PresetCategory("Balanced", "Core", 0);' -ProbeName 'wrong-preset-value'
Assert-MutationRejected -Name 'wrong-preset-value' -ExpectedMessagePattern '^预设分类矩阵不精确$' -Probe {
    Assert-PresetMatrixContract -Content $wrongPresetMutation -ExpectedMatrix $presetMatrix -ExpectedLife $presetLife
}

$newInitModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_ConfigInitializeNew')[0]
$newInitMutationBlock = Replace-FirstLiteral -Content $newInitModel.Block -OldValue 'THEN' -NewValue "THEN`nPROC_COS_ConfigInitCategory(_Character, `"Extra`", 0);" -ProbeName 'new-init-nine-actions'
$newInitMutation = Replace-RuleBlock -Content $config -OldBlock $newInitModel.Block -NewBlock $newInitMutationBlock -ProbeName 'new-init-nine-actions'
Assert-MutationRejected -Name 'new-init-nine-actions' -ExpectedMessagePattern '^新角色分类初始化 THEN 动作序列不精确$' -Probe {
    Assert-CategoryInitializationContract -Content $newInitMutation -NewCategories $newCategoryInitialization -LegacyCategories $legacyCategoryInitialization -NewLife 0
}

$legacyInitModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_ConfigInitializeLegacy')[0]
$legacyInitMutationBlock = Replace-FirstLiteral -Content $legacyInitModel.Block -OldValue 'THEN' -NewValue "THEN`nDB_COS_ConfigCost(_Character, `"Fate`", 99);" -ProbeName 'legacy-init-child-write'
$legacyInitMutation = Replace-RuleBlock -Content $config -OldBlock $legacyInitModel.Block -NewBlock $legacyInitMutationBlock -ProbeName 'legacy-init-child-write'
Assert-MutationRejected -Name 'legacy-init-child-write' -ExpectedMessagePattern '^旧角色分类初始化 THEN 动作序列不精确$' -Probe {
    Assert-CategoryInitializationContract -Content $legacyInitMutation -NewCategories $newCategoryInitialization -LegacyCategories $legacyCategoryInitialization -NewLife 0
}

$initializeModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_ConfigInitializeCategories')[0]
$initializeNeverTrueBlock = Replace-FirstLiteral -Content $initializeModel.Block -OldValue 'THEN' -NewValue "AND`nDB_COS_NeverTrue(_Character)`nTHEN" -ProbeName 'initialize-never-true'
$initializeNeverTrueMutation = Replace-RuleBlock -Content $config -OldBlock $initializeModel.Block -NewBlock $initializeNeverTrueBlock -ProbeName 'initialize-never-true'
Assert-MutationRejected -Name 'initialize-never-true' -ExpectedMessagePattern '^分类统一初始化入口 条件集合不精确$' -Probe {
    Assert-CategoryInitializationContract -Content $initializeNeverTrueMutation -NewCategories $newCategoryInitialization -LegacyCategories $legacyCategoryInitialization -NewLife 0
}

$commitModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_ConfigCommitCategorySchema')[0]
$extraSchemaConditionBlock = Replace-FirstLiteral -Content $commitModel.Block -OldValue 'THEN' -NewValue "AND`nDB_COS_ConfigCategory(_Character, `"Extra`", _Extra)`nTHEN" -ProbeName 'schema-extra-condition'
$extraSchemaConditionMutation = Replace-RuleBlock -Content $config -OldBlock $commitModel.Block -NewBlock $extraSchemaConditionBlock -ProbeName 'schema-extra-condition'
Assert-MutationRejected -Name 'schema-extra-condition' -ExpectedMessagePattern '^分类 schema 提交条件行数错误: 期望 8，实际 9$' -Probe {
    Assert-CategoryInitializationContract -Content $extraSchemaConditionMutation -NewCategories $newCategoryInitialization -LegacyCategories $legacyCategoryInitialization -NewLife 0
}

$presetApplyModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_PresetApply' | Where-Object { $_.Conditions -ccontains 'DB_COS_PresetValidated(_Character, _Preset, 0)' })[0]
$presetApplyBlock = $presetApplyModel.Block
$injectedApplyBlock = Replace-FirstLiteral -Content $presetApplyBlock -OldValue 'THEN' -NewValue "THEN`nDB_COS_ConfigCost(_Character, `"Fate`", 999);" -ProbeName 'preset-subconfig-write'
$presetWriteMutation = Replace-RuleBlock -Content $config -OldBlock $presetApplyBlock -NewBlock $injectedApplyBlock -ProbeName 'preset-subconfig-write'
Assert-MutationRejected -Name 'preset-subconfig-write' -ExpectedMessagePattern '^预设过程写入未批准表: DB_COS_ConfigCost$' -Probe {
    Assert-PresetWriteContract -Content $presetWriteMutation -ExpectedProcedureNames $expectedPresetProcedures -ApprovedStatusIds $approvedStatusIds -ExpectedDetectionOrder $presetOrder
}

$unapprovedApplyBlock = Replace-FirstLiteral -Content $presetApplyBlock -OldValue 'THEN' -NewValue "THEN`nDB_COS_PresetUnapproved(_Character);" -ProbeName 'preset-unapproved-db'
$unapprovedApplyMutation = Replace-RuleBlock -Content $config -OldBlock $presetApplyBlock -NewBlock $unapprovedApplyBlock -ProbeName 'preset-unapproved-db'
Assert-MutationRejected -Name 'preset-unapproved-db' -ExpectedMessagePattern '^预设过程写入未批准表: DB_COS_PresetUnapproved$' -Probe {
    Assert-PresetWriteContract -Content $unapprovedApplyMutation -ExpectedProcedureNames $expectedPresetProcedures -ApprovedStatusIds $approvedStatusIds -ExpectedDetectionOrder $presetOrder
}

$previewModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_PresetBuildPreview')[0]
$previewCostBlock = Replace-FirstLiteral -Content $previewModel.Block -OldValue 'THEN' -NewValue "THEN`nDB_COS_ConfigCost(_Character, `"Fate`", 999);" -ProbeName 'preview-subconfig-write'
$previewCostMutation = Replace-RuleBlock -Content $config -OldBlock $previewModel.Block -NewBlock $previewCostBlock -ProbeName 'preview-subconfig-write'
Assert-MutationRejected -Name 'preview-subconfig-write' -ExpectedMessagePattern '^预设过程写入未批准表: DB_COS_ConfigCost$' -Probe {
    Assert-PresetWriteContract -Content $previewCostMutation -ExpectedProcedureNames $expectedPresetProcedures -ApprovedStatusIds $approvedStatusIds -ExpectedDetectionOrder $presetOrder
}

$newPresetProcedureMutation = $config + @'

PROC   // hidden tenth procedure
PROC_COS_PresetUnapproved((CHARACTERGUID)_Character)
AND
DB_COS_PresetPending(_Character, _Preset)
THEN // hidden action section
PROC_COS_PresetDetect(_Character);
'@
Assert-MutationRejected -Name 'preset-new-procedure' -ExpectedMessagePattern '^预设过程声明批准集合不精确$' -Probe {
    Assert-PresetWriteContract -Content $newPresetProcedureMutation -ExpectedProcedureNames $expectedPresetProcedures -ApprovedStatusIds $approvedStatusIds -ExpectedDetectionOrder $presetOrder
}

$commentedHeaderIllegalActionMutation = $config + @'

PROC // duplicate approved procedure with illegal action
PROC_COS_PresetBuildPreview((CHARACTERGUID)_Character, (STRING)_Preset)
THEN // hidden illegal action section
DB_COS_ConfigCost(_Character, "Fate", 999);
'@
Assert-MutationRejected -Name 'preset-comment-header-illegal-action' -ExpectedMessagePattern '^预设过程写入未批准表: DB_COS_ConfigCost$' -Probe {
    Assert-PresetWriteContract -Content $commentedHeaderIllegalActionMutation -ExpectedProcedureNames $expectedPresetProcedures -ApprovedStatusIds $approvedStatusIds -ExpectedDetectionOrder $presetOrder
}

$unapprovedStatusBlock = Replace-FirstLiteral -Content $previewModel.Block -OldValue 'THEN' -NewValue "THEN`nApplyStatus(_Character, `"COS_PRESET_UNAPPROVED`", -1, 1);" -ProbeName 'preset-unapproved-apply-status'
$unapprovedStatusMutation = Replace-RuleBlock -Content $config -OldBlock $previewModel.Block -NewBlock $unapprovedStatusBlock -ProbeName 'preset-unapproved-apply-status'
Assert-MutationRejected -Name 'preset-unapproved-apply-status' -ExpectedMessagePattern '^预设过程 ApplyStatus 使用未批准状态: COS_PRESET_UNAPPROVED$' -Probe {
    Assert-PresetWriteContract -Content $unapprovedStatusMutation -ExpectedProcedureNames $expectedPresetProcedures -ApprovedStatusIds $approvedStatusIds -ExpectedDetectionOrder $presetOrder
}

$directLifeBlock = Replace-FirstLiteral -Content $previewModel.Block -OldValue 'THEN' -NewValue "THEN`nDB_COS_ConfigLifeSkill(_Character, 99);" -ProbeName 'preset-direct-life-write'
$directLifeMutation = Replace-RuleBlock -Content $config -OldBlock $previewModel.Block -NewBlock $directLifeBlock -ProbeName 'preset-direct-life-write'
Assert-MutationRejected -Name 'preset-direct-life-write' -ExpectedMessagePattern '^预设过程写入未批准表: DB_COS_ConfigLifeSkill$' -Probe {
    Assert-PresetWriteContract -Content $directLifeMutation -ExpectedProcedureNames $expectedPresetProcedures -ApprovedStatusIds $approvedStatusIds -ExpectedDetectionOrder $presetOrder
}

$previewFormalBlock = Replace-FirstLiteral -Content $previewModel.Block -OldValue 'THEN' -NewValue "THEN`nDB_COS_ConfigCategory(_Character, `"Core`", 1);" -ProbeName 'preview-formal-config-write'
$previewFormalMutation = Replace-RuleBlock -Content $config -OldBlock $previewModel.Block -NewBlock $previewFormalBlock -ProbeName 'preview-formal-config-write'
Assert-MutationRejected -Name 'preview-formal-config-write' -ExpectedMessagePattern '^预设预览不得写正式配置$' -Probe {
    Assert-PresetWorkflowContract -Content $previewFormalMutation
}

$previewSyncBlock = Replace-FirstLiteral -Content $previewModel.Block -OldValue 'THEN' -NewValue "THEN`nPROC_COS_ConfigSyncCharacter(_Character);" -ProbeName 'preview-extra-sync'
$previewSyncMutation = Replace-RuleBlock -Content $config -OldBlock $previewModel.Block -NewBlock $previewSyncBlock -ProbeName 'preview-extra-sync'
Assert-MutationRejected -Name 'preview-extra-sync' -ExpectedMessagePattern '^预设预览不得调用正式配置写入或同步$' -Probe {
    Assert-PresetWorkflowContract -Content $previewSyncMutation
}

$legacyLine = 'DB_COS_ConfigLegacyTable("DB_COS_ConfigMechanic");'
$legacyMutation = Replace-FirstLiteral -Content $config -OldValue $legacyLine -NewValue '// mutation: removed legacy mechanic check' -ProbeName 'missing-legacy-table'
Assert-MutationRejected -Name 'missing-legacy-table' -ExpectedMessagePattern '^旧档识别表集合不精确$' -Probe {
    Assert-LegacyDetectionContract -Content $legacyMutation -ExpectedProbes $legacyProbes
}

$legacyMechanicModel = @(Get-ProcedureModels -Content $config -Name $legacyProbes.DB_COS_ConfigMechanic.Procedure)[0]
$legacyMechanicCondition = @($legacyMechanicModel.Conditions | Where-Object { $_ -match '^DB_COS_ConfigMechanic\(_Character' })[0]
$legacyCommentOnlyBlock = Replace-FirstLiteral -Content $legacyMechanicModel.Block -OldValue $legacyMechanicCondition -NewValue "// $legacyMechanicCondition" -ProbeName 'legacy-comment-only'
$legacyCommentOnlyMutation = Replace-RuleBlock -Content $config -OldBlock $legacyMechanicModel.Block -NewBlock $legacyCommentOnlyBlock -ProbeName 'legacy-comment-only'
Assert-MutationRejected -Name 'legacy-comment-only' -ExpectedMessagePattern '^旧档 probe 条件签名或 arity 错误: DB_COS_ConfigMechanic$' -Probe {
    Assert-LegacyDetectionContract -Content $legacyCommentOnlyMutation -ExpectedProbes $legacyProbes
}

$legacyDetectModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_ConfigDetectPreexisting')[0]
$firstLegacyTable = @($legacyProbes.Keys)[0]
$firstLegacyProbeCall = "$($legacyProbes[$firstLegacyTable].Procedure)(_Character);"
$legacyDeadBlock = Replace-FirstLiteral -Content $legacyDetectModel.Block -OldValue $firstLegacyProbeCall -NewValue "// mutation: removed dispatcher call $firstLegacyProbeCall" -ProbeName 'legacy-dead-probe'
$legacyDeadMutation = Replace-RuleBlock -Content $config -OldBlock $legacyDetectModel.Block -NewBlock $legacyDeadBlock -ProbeName 'legacy-dead-probe'
Assert-MutationRejected -Name 'legacy-dead-probe' -ExpectedMessagePattern '^旧档检测调度 THEN 动作序列不精确$' -Probe {
    Assert-LegacyDetectionContract -Content $legacyDeadMutation -ExpectedProbes $legacyProbes
}

$legacyNeverTrueBlock = Replace-FirstLiteral -Content $legacyMechanicModel.Block -OldValue 'THEN' -NewValue "AND`nDB_COS_NeverTrue(_Character)`nTHEN" -ProbeName 'legacy-never-true'
$legacyNeverTrueMutation = Replace-RuleBlock -Content $config -OldBlock $legacyMechanicModel.Block -NewBlock $legacyNeverTrueBlock -ProbeName 'legacy-never-true'
Assert-MutationRejected -Name 'legacy-never-true' -ExpectedMessagePattern '^旧档 probe 条件集合不精确: DB_COS_ConfigMechanic$' -Probe {
    Assert-LegacyDetectionContract -Content $legacyNeverTrueMutation -ExpectedProbes $legacyProbes
}

$legacyFixedCondition = [regex]::Replace($legacyMechanicCondition, '\(_Character.*\)$', '(_Character, "Power", 1)')
Require ($legacyFixedCondition -cne $legacyMechanicCondition) 'legacy-fixed-value 探针未改变条件'
$legacyFixedBlock = Replace-FirstLiteral -Content $legacyMechanicModel.Block -OldValue $legacyMechanicCondition -NewValue $legacyFixedCondition -ProbeName 'legacy-fixed-value'
$legacyFixedMutation = Replace-RuleBlock -Content $config -OldBlock $legacyMechanicModel.Block -NewBlock $legacyFixedBlock -ProbeName 'legacy-fixed-value'
Assert-MutationRejected -Name 'legacy-fixed-value' -ExpectedMessagePattern '^旧档 probe 条件签名或 arity 错误: DB_COS_ConfigMechanic$' -Probe {
    Assert-LegacyDetectionContract -Content $legacyFixedMutation -ExpectedProbes $legacyProbes
}

$categoryEventModel = @(
    Get-OsirisRuleModels -Content $config |
        Where-Object { $_.Kind -ceq 'IF' -and $_.Conditions -ccontains 'DB_COS_ConfigCategoryEvent(_Event, _Key)' }
)[0]
$categoryEventBlock = $categoryEventModel.Block
$unguardedCategoryBlock = Replace-FirstLiteral -Content $categoryEventBlock -OldValue 'IsInCombat(_Character, 0)' -NewValue 'IsInCombat(_Character, 1)' -ProbeName 'missing-combat-guard'
$combatMutation = Replace-RuleBlock -Content $config -OldBlock $categoryEventBlock -NewBlock $unguardedCategoryBlock -ProbeName 'missing-combat-guard'
Assert-MutationRejected -Name 'missing-combat-guard' -ExpectedMessagePattern '^修改事件 Category 条件集合不精确$' -Probe {
    Assert-EventGuardContract -Content $combatMutation
}

$schemaCommentBlock = Replace-FirstLiteral -Content $categoryEventBlock -OldValue 'DB_COS_ConfigCategorySchema(_Character, 1)' -NewValue '// DB_COS_ConfigCategorySchema(_Character, 1)' -ProbeName 'event-schema-comment-only'
$schemaCommentMutation = Replace-RuleBlock -Content $config -OldBlock $categoryEventBlock -NewBlock $schemaCommentBlock -ProbeName 'event-schema-comment-only'
Assert-MutationRejected -Name 'event-schema-comment-only' -ExpectedMessagePattern '^修改事件 Category 条件集合不精确$' -Probe {
    Assert-EventGuardContract -Content $schemaCommentMutation
}

$categoryEventCostBlock = Replace-FirstLiteral -Content $categoryEventBlock -OldValue 'THEN' -NewValue "THEN`nDB_COS_ConfigCost(_Character, `"Fate`", 999);" -ProbeName 'category-event-cost-write'
$categoryEventCostMutation = Replace-RuleBlock -Content $config -OldBlock $categoryEventBlock -NewBlock $categoryEventCostBlock -ProbeName 'category-event-cost-write'
Assert-MutationRejected -Name 'category-event-cost-write' -ExpectedMessagePattern '^分类切换事件 THEN 动作序列不精确$' -Probe {
    Assert-EventGuardContract -Content $categoryEventCostMutation
}

$categoryToggleModel = @(Get-ProcedureModels -Content $config -Name 'PROC_COS_ConfigToggleCategory')[0]
$categoryToggleCostBlock = Replace-FirstLiteral -Content $categoryToggleModel.Block -OldValue 'THEN' -NewValue "THEN`nDB_COS_ConfigCost(_Character, `"Fate`", 999);" -ProbeName 'category-toggle-cost-write'
$categoryToggleCostMutation = Replace-RuleBlock -Content $config -OldBlock $categoryToggleModel.Block -NewBlock $categoryToggleCostBlock -ProbeName 'category-toggle-cost-write'
Assert-MutationRejected -Name 'category-toggle-cost-write' -ExpectedMessagePattern '^分类切换过程 THEN 动作序列不精确$' -Probe {
    Assert-CategoryToggleContract -Content $categoryToggleCostMutation
}

$previewBypassBlock = Replace-FirstLiteral -Content $presetApplyBlock -OldValue 'DB_COS_PresetValidated(_Character, _Preset, 0)' -NewValue 'DB_COS_PresetMutationBypass(_Character, _Preset)' -ProbeName 'preview-bypass'
$previewBypassMutation = Replace-RuleBlock -Content $config -OldBlock $presetApplyBlock -NewBlock $previewBypassBlock -ProbeName 'preview-bypass'
Assert-MutationRejected -Name 'preview-bypass' -ExpectedMessagePattern '^预设应用主规则缺失或重复$' -Probe {
    Assert-PresetWorkflowContract -Content $previewBypassMutation
}

$applyOrderBlock = Replace-FirstLiteral -Content $presetApplyBlock -OldValue 'PROC_COS_PresetSetCategory(_Character, _Preset);' -NewValue 'PROC_COS_PresetMutationOrderPlaceholder(_Character, _Preset);' -ProbeName 'apply-order'
$applyOrderBlock = Replace-FirstLiteral -Content $applyOrderBlock -OldValue 'PROC_COS_ConfigSetLifeSkill(_Character, _Life);' -NewValue 'PROC_COS_PresetSetCategory(_Character, _Preset);' -ProbeName 'apply-order'
$applyOrderBlock = Replace-FirstLiteral -Content $applyOrderBlock -OldValue 'PROC_COS_PresetMutationOrderPlaceholder(_Character, _Preset);' -NewValue 'PROC_COS_ConfigSetLifeSkill(_Character, _Life);' -ProbeName 'apply-order'
$applyOrderMutation = Replace-RuleBlock -Content $config -OldBlock $presetApplyBlock -NewBlock $applyOrderBlock -ProbeName 'apply-order'
Assert-MutationRejected -Name 'apply-order' -ExpectedMessagePattern '^预设应用主规则 THEN 动作序列不精确$' -Probe {
    Assert-PresetWorkflowContract -Content $applyOrderMutation
}

$duplicateCommitBlock = Replace-FirstLiteral -Content $commitModel.Block -OldValue 'DB_COS_ConfigCategorySchema(_Character, 1);' -NewValue "DB_COS_ConfigCategorySchema(_Character, 1);`nDB_COS_ConfigCategorySchema(_Character, 1);" -ProbeName 'duplicate-schema-commit'
$duplicateCommitMutation = Replace-RuleBlock -Content $config -OldBlock $commitModel.Block -NewBlock $duplicateCommitBlock -ProbeName 'duplicate-schema-commit'
Assert-MutationRejected -Name 'duplicate-schema-commit' -ExpectedMessagePattern '^分类 schema 提交 THEN 动作序列不精确$' -Probe {
    Assert-CategoryInitializationContract -Content $duplicateCommitMutation -NewCategories $newCategoryInitialization -LegacyCategories $legacyCategoryInitialization -NewLife 0
}

$schemaVersionBlock = Replace-FirstLiteral -Content $initializeModel.Block -OldValue 'NOT DB_COS_ConfigCategorySchema(_Character, _)' -NewValue 'NOT DB_COS_ConfigCategorySchema(_Character, 2)' -ProbeName 'schema-non-one-version'
$schemaVersionMutation = Replace-RuleBlock -Content $config -OldBlock $initializeModel.Block -NewBlock $schemaVersionBlock -ProbeName 'schema-non-one-version'
Assert-MutationRejected -Name 'schema-non-one-version' -ExpectedMessagePattern '^分类统一初始化入口 条件集合不精确$' -Probe {
    Assert-CategoryInitializationContract -Content $schemaVersionMutation -NewCategories $newCategoryInitialization -LegacyCategories $legacyCategoryInitialization -NewLife 0
}

$controllerProbeArguments = [ordered]@{
    PageName = 'controller-probe'
    Controller = $true
    ButtonEvents = $buttonEvents
    StatusNodeSets = $statusNodeSets
    PanelOrder = $panelOrder
    ButtonOrder = $buttonOrder
    ExpectedNamedNodes = $expectedFeatureNamedNodes
    UiHandleDescriptors = $uiHandleDescriptors
    ControllerNavigation = $controllerNavigation
    ExpectedMirrors = @($categories.Values)
    ExpectedCategorySections = $expectedCategorySections
    ApprovedStatusIds = $approvedStatusIds
}

[xml]$controllerEventMutationDocument = $controllerXaml
$controllerPresetButton = @(Get-XamlNamedNodes -Document $controllerEventMutationDocument -Name 'COSPresetNearVanillaButton')[0]
$controllerPresetAction = @($controllerPresetButton.SelectNodes('.//*[local-name()="InvokeCommandAction" and @CommandParameter]'))[0]
$controllerPresetAction.SetAttribute('CommandParameter', $presetEvents.PureChaos)
$controllerEventMutation = $controllerEventMutationDocument.OuterXml
Assert-MutationRejected -Name 'controller-event-drift' -ExpectedMessagePattern '^controller-probe 按钮 Click 事件错误: COSPresetNearVanillaButton$' -Probe {
    [void](Assert-UiPageContract -Content $controllerEventMutation @controllerProbeArguments)
}

[xml]$extraEventDocument = $controllerXaml
$extraEventPanel = @(Get-XamlNamedNodes -Document $extraEventDocument -Name 'COSPresetPanel')[0]
$extraEventAction = $extraEventDocument.CreateElement('b', 'InvokeCommandAction', 'http://schemas.microsoft.com/xaml/behaviors')
$extraEventAction.SetAttribute('CommandParameter', '7e990000-0000-4000-8000-000000000099')
[void]$extraEventPanel.AppendChild($extraEventAction)
Assert-MutationRejected -Name 'xaml-extra-event' -ExpectedMessagePattern '^controller-probe 分类/预设事件批准集合或顺序错误$' -Probe {
    [void](Assert-UiPageContract -Content $extraEventDocument.OuterXml @controllerProbeArguments)
}

[xml]$extraStatusDocument = $controllerXaml
$previewNode = @(Get-XamlNamedNodes -Document $extraStatusDocument -Name 'COSPresetPreview')[0]
$firstPreviewTrigger = @($previewNode.SelectNodes('.//*[local-name()="DataTrigger" and @Value]'))[0]
$extraPreviewTrigger = $firstPreviewTrigger.CloneNode($true)
$extraPreviewTrigger.SetAttribute('Value', 'COS_PRESET_PREVIEW_UNAPPROVED')
[void]$firstPreviewTrigger.ParentNode.AppendChild($extraPreviewTrigger)
Assert-MutationRejected -Name 'xaml-extra-preview-status' -ExpectedMessagePattern '^controller-probe 状态过滤集合或顺序错误: COSPresetPreview$' -Probe {
    [void](Assert-UiPageContract -Content $extraStatusDocument.OuterXml @controllerProbeArguments)
}

[xml]$hiddenStatusDocument = $controllerXaml
$hiddenStatusPanel = @(Get-XamlNamedNodes -Document $hiddenStatusDocument -Name 'COSPresetPanel')[0]
$hiddenTrigger = $hiddenStatusDocument.CreateElement('DataTrigger', $hiddenStatusPanel.NamespaceURI)
$hiddenTrigger.SetAttribute('Value', 'COS_CATEGORY_ACTUAL_UNKNOWN_ACTIVE')
[void]$hiddenStatusPanel.AppendChild($hiddenTrigger)
Assert-MutationRejected -Name 'xaml-hidden-unknown-state' -ExpectedMessagePattern '^controller-probe 包含未批准状态引用: COS_CATEGORY_ACTUAL_UNKNOWN_ACTIVE$' -Probe {
    [void](Assert-UiPageContract -Content $hiddenStatusDocument.OuterXml @controllerProbeArguments)
}

[xml]$wrongDirectionDocument = $controllerXaml
$wrongDirectionButton = @(Get-XamlNamedNodes -Document $wrongDirectionDocument -Name 'COSPresetNearVanillaButton')[0]
$wrongDirectionButton.SetAttribute('MoveFocus.Up', 'clr-namespace:ls;assembly=Code', 'COSPresetCancelButton')
Assert-MutationRejected -Name 'controller-wrong-direction' -ExpectedMessagePattern '^controller-probe 手柄焦点方向错误: COSPresetNearVanillaButton Up$' -Probe {
    [void](Assert-UiPageContract -Content $wrongDirectionDocument.OuterXml @controllerProbeArguments)
}

[xml]$missingDirectionDocument = $controllerXaml
$missingDirectionButton = @(Get-XamlNamedNodes -Document $missingDirectionDocument -Name 'COSPresetNearVanillaButton')[0]
$missingDirectionButton.RemoveAttribute('MoveFocus.Up', 'clr-namespace:ls;assembly=Code')
Assert-MutationRejected -Name 'controller-missing-direction' -ExpectedMessagePattern '^controller-probe 手柄焦点方向缺失: COSPresetNearVanillaButton Up$' -Probe {
    [void](Assert-UiPageContract -Content $missingDirectionDocument.OuterXml @controllerProbeArguments)
}

[xml]$buttonOrderDocument = $controllerXaml
$nearButton = @(Get-XamlNamedNodes -Document $buttonOrderDocument -Name 'COSPresetNearVanillaButton')[0]
$pureButton = @(Get-XamlNamedNodes -Document $buttonOrderDocument -Name 'COSPresetPureChaosButton')[0]
Require ([object]::ReferenceEquals($nearButton.ParentNode, $pureButton.ParentNode)) '按钮顺序探针要求两个预设按钮同属一个容器'
[void]$nearButton.ParentNode.RemoveChild($pureButton)
[void]$nearButton.ParentNode.InsertBefore($pureButton, $nearButton)
Assert-MutationRejected -Name 'controller-button-order' -ExpectedMessagePattern '^controller-probe 按钮 节点顺序错误: COSPresetPureChaosButton$' -Probe {
    [void](Assert-UiPageContract -Content $buttonOrderDocument.OuterXml @controllerProbeArguments)
}

[xml]$wrongBindingDocument = $controllerXaml
$currentNode = @(Get-XamlNamedNodes -Document $wrongBindingDocument -Name 'COSPresetCurrent')[0]
$currentTrigger = @($currentNode.SelectNodes('.//*[local-name()="DataTrigger" and @Value]'))[0]
$currentTrigger.SetAttribute('Binding', '{Binding Name.Str}')
Assert-MutationRejected -Name 'xaml-wrong-status-binding' -ExpectedMessagePattern '^controller-probe DataTrigger Binding 错误: COSPresetCurrent COS_PRESET_CURRENT_NEAR_VANILLA$' -Probe {
    [void](Assert-UiPageContract -Content $wrongBindingDocument.OuterXml @controllerProbeArguments)
}

[xml]$crossPausedDocument = $controllerXaml
$corePausedNode = @(Get-XamlNamedNodes -Document $crossPausedDocument -Name 'COSCategoryCorePausedOverlay')[0]
$corePausedTrigger = @($corePausedNode.SelectNodes('.//*[local-name()="DataTrigger" and @Value]'))[0]
$corePausedTrigger.SetAttribute('Value', 'COS_CATEGORY_ACTUAL_ARMOR_PAUSED')
Assert-MutationRejected -Name 'xaml-cross-category-paused' -ExpectedMessagePattern '^controller-probe 状态过滤集合或顺序错误: COSCategoryCorePausedOverlay$' -Probe {
    [void](Assert-UiPageContract -Content $crossPausedDocument.OuterXml @controllerProbeArguments)
}

[xml]$movedCombatDocument = $controllerXaml
$movedCombatPanel = @(Get-XamlNamedNodes -Document $movedCombatDocument -Name 'COSPresetPanel')[0]
$movedCombatTrigger = @(
    $movedCombatPanel.SelectNodes('.//*[local-name()="DataTrigger"]') |
        Where-Object { [regex]::IsMatch($_.GetAttribute('Binding'), '(?:^|[^A-Za-z0-9_])IsInCombat(?:[^A-Za-z0-9_]|$)') }
)[0]
[void]$movedCombatTrigger.ParentNode.RemoveChild($movedCombatTrigger)
$textBlock = $movedCombatDocument.CreateElement('TextBlock', $movedCombatPanel.NamespaceURI)
$textBlockStyleProperty = $movedCombatDocument.CreateElement('TextBlock.Style', $movedCombatPanel.NamespaceURI)
$textBlockStyle = $movedCombatDocument.CreateElement('Style', $movedCombatPanel.NamespaceURI)
$textBlockTriggers = $movedCombatDocument.CreateElement('Style.Triggers', $movedCombatPanel.NamespaceURI)
[void]$textBlockTriggers.AppendChild($movedCombatTrigger)
[void]$textBlockStyle.AppendChild($textBlockTriggers)
[void]$textBlockStyleProperty.AppendChild($textBlockStyle)
[void]$textBlock.AppendChild($textBlockStyleProperty)
[void]$movedCombatPanel.AppendChild($textBlock)
Assert-MutationRejected -Name 'xaml-combat-trigger-wrong-scope' -ExpectedMessagePattern '^controller-probe 战斗只读条件未覆盖 COSPresetPanel$' -Probe {
    [void](Assert-UiPageContract -Content $movedCombatDocument.OuterXml @controllerProbeArguments)
}

$featureHandles = @($semanticByHandle.Keys)
$mutationHandle = $featureHandles[0]
[xml]$chineseDocument = $localization.Chinese
$chineseNode = @($chineseDocument.SelectNodes('/contentList/content') | Where-Object { $_.GetAttribute('contentuid') -ceq $mutationHandle })[0]
Require ($null -ne $chineseNode) '本地化变异探针缺少中文真实节点'

foreach ($language in @('English', 'Japanese', 'Korean')) {
    $copyMutation = [ordered]@{}
    foreach ($sourceLanguage in $localization.Keys) { $copyMutation[$sourceLanguage] = $localization[$sourceLanguage] }
    [xml]$targetDocument = $localization[$language]
    $targetNode = @($targetDocument.SelectNodes('/contentList/content') | Where-Object { $_.GetAttribute('contentuid') -ceq $mutationHandle })[0]
    Require ($null -ne $targetNode) "本地化复制中文探针缺少真实节点: $language"
    $targetNode.InnerText = $chineseNode.InnerText
    $copyMutation[$language] = $targetDocument.OuterXml
    $copyExpectedPattern = switch ($language) {
        English { '^(?:英文语义不完整|English 缺少语义 token ''[^'']+''|English 直接复制中文): {0}$' -f [regex]::Escape($mutationHandle) }
        Japanese { '^(?:日文必须包含日文假名|Japanese 缺少语义 token ''[^'']+''|Japanese 直接复制中文): {0}$' -f [regex]::Escape($mutationHandle) }
        Korean { '^(?:韩文必须包含韩文字符|Korean 缺少语义 token ''[^'']+''|Korean 直接复制中文): {0}$' -f [regex]::Escape($mutationHandle) }
    }
    Assert-MutationRejected -Name "$($language.ToLowerInvariant())-copies-chinese" -ExpectedMessagePattern $copyExpectedPattern -Probe {
        Assert-LocalizationContract -ContentByLanguage $copyMutation -SemanticByHandle $semanticByHandle
    }
}

$placeholderMutation = [ordered]@{}
foreach ($language in $localization.Keys) { $placeholderMutation[$language] = $localization[$language] }
[xml]$placeholderDocument = $localization.English
$placeholderNode = @($placeholderDocument.SelectNodes('/contentList/content') | Where-Object { $_.GetAttribute('contentuid') -ceq $mutationHandle })[0]
$placeholderNode.InnerText = 'A'
$placeholderMutation.English = $placeholderDocument.OuterXml
Assert-MutationRejected -Name 'localization-placeholder-a' -ExpectedMessagePattern ('^本地化文本不得使用占位符 A: English {0}$' -f [regex]::Escape($mutationHandle)) -Probe {
    Assert-LocalizationContract -ContentByLanguage $placeholderMutation -SemanticByHandle $semanticByHandle
}

Write-Output 'Category/preset contract counts: categories=7; preset-category-rows=28; preset-life-rows=4; events=13'
Write-Output 'Category/preset mutation probes: initialization=PASS; legacy-dispatch=PASS; procedure-set=PASS; write-allowlist=PASS; workflow=PASS; schema=PASS; xaml=PASS; localization=PASS'
Write-Output 'ChaosOriginsStory category/preset verification: ok'
