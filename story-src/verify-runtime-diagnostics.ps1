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

function Get-RequiredText {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Require (Test-Path -LiteralPath $Path -PathType Leaf) "缺少文件: $Path"
    Get-Content -Raw -LiteralPath $Path
}

function Test-ExactOrdinalSet {
    param(
        [Parameter(Mandatory)]
        [string[]]$Actual,

        [Parameter(Mandatory)]
        [string[]]$Expected
    )

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

    return $actualSet.SetEquals($expectedSet)
}

function Test-ExactOrdinalSequence {
    param(
        [Parameter(Mandatory)]
        [string[]]$Actual,

        [Parameter(Mandatory)]
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

function Get-StatsEntryBlocks {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $entries = [System.Collections.Generic.List[object]]::new()
    $currentName = $null
    $currentLines = [System.Collections.Generic.List[string]]::new()

    foreach ($line in @($Content -split '\r?\n')) {
        $entryMatch = [regex]::Match($line, '^\s*new entry "([^"]+)"\s*$')
        if ($entryMatch.Success) {
            if ($null -ne $currentName) {
                $entries.Add([pscustomobject]@{
                    Name = $currentName
                    Lines = @($currentLines.ToArray())
                })
            }
            $currentName = $entryMatch.Groups[1].Value
            $currentLines = [System.Collections.Generic.List[string]]::new()
            continue
        }

        if ($null -ne $currentName) {
            $currentLines.Add($line)
        }
    }

    if ($null -ne $currentName) {
        $entries.Add([pscustomobject]@{
            Name = $currentName
            Lines = @($currentLines.ToArray())
        })
    }

    @($entries.ToArray())
}

function Get-StatsEntryDataFields {
    param(
        [Parameter(Mandatory)]
        [psobject]$Entry
    )

    $fields = [ordered]@{}
    foreach ($line in $Entry.Lines) {
        $dataMatch = [regex]::Match($line, '^\s*data "([^"]+)" "([^"]*)"\s*$')
        if (-not $dataMatch.Success) {
            continue
        }

        $fieldName = $dataMatch.Groups[1].Value
        Require (-not $fields.Contains($fieldName)) "Stats entry 包含重复 data 字段: $($Entry.Name).$fieldName"
        $fields[$fieldName] = $dataMatch.Groups[2].Value
    }

    $fields
}

function Test-DiagnosticStatusEntryContract {
    param(
        [Parameter(Mandatory)]
        [psobject]$Entry,

        [Parameter(Mandatory)]
        [string]$ExpectedStackId
    )

    $allowedDataFields = @('StatusType', 'DisplayName', 'Description', 'Icon', 'StackId', 'StackType', 'StatusPropertyFlags')
    $typeCount = 0
    $dataFields = [ordered]@{}

    foreach ($line in $Entry.Lines) {
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith('//', [System.StringComparison]::Ordinal)) {
            continue
        }

        if ($trimmedLine -ceq 'type "StatusData"') {
            $typeCount++
            continue
        }

        $dataMatch = [regex]::Match($trimmedLine, '^data "([^"]+)" "([^"]*)"$')
        if (-not $dataMatch.Success) {
            return $false
        }

        $fieldName = $dataMatch.Groups[1].Value
        if ($allowedDataFields -cnotcontains $fieldName -or $dataFields.Contains($fieldName)) {
            return $false
        }
        $dataFields[$fieldName] = $dataMatch.Groups[2].Value
    }

    if ($typeCount -ne 1 -or $dataFields.Count -ne 7) {
        return $false
    }

    foreach ($requiredField in $allowedDataFields) {
        if (-not $dataFields.Contains($requiredField) -or [string]::IsNullOrWhiteSpace($dataFields[$requiredField])) {
            return $false
        }
    }

    foreach ($handleField in @('DisplayName', 'Description')) {
        if (-not [regex]::IsMatch($dataFields[$handleField], '^[^;\s]+;1$')) {
            return $false
        }
    }

    if (
        $dataFields.StatusType -cne 'BOOST' -or
        $dataFields.Icon -cne 'PassiveFeature_Generic_Threat' -or
        $dataFields.StackId -cne $ExpectedStackId -or
        $dataFields.StackType -cne 'Overwrite'
    ) {
        return $false
    }

    $actualFlags = @($dataFields.StatusPropertyFlags -split ';')
    $expectedFlags = @('DisableOverhead', 'DisableCombatlog', 'DisablePortraitIndicator', 'IgnoreResting')
    if ($actualFlags.Count -ne 4 -or -not (Test-ExactOrdinalSet -Actual $actualFlags -Expected $expectedFlags)) {
        return $false
    }

    return $true
}

function Get-DiagnosticStatusEntries {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    @(
        Get-StatsEntryBlocks $Content |
            Where-Object { $_.Name.StartsWith('COS_DIAG_', [System.StringComparison]::OrdinalIgnoreCase) }
    )
}

function Assert-DiagnosticStatusSourceContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string[]]$ExpectedStateStatuses,

        [Parameter(Mandatory)]
        [string[]]$ExpectedLastStatuses
    )

    $expectedStatuses = @($ExpectedStateStatuses) + @($ExpectedLastStatuses)
    $entries = @(Get-DiagnosticStatusEntries $Content)

    foreach ($status in $expectedStatuses) {
        $matchingEntries = @($entries | Where-Object { $_.Name -ceq $status })
        Require ($matchingEntries.Count -ge 1) "缺少运行诊断状态: $status"
        Require ($matchingEntries.Count -eq 1) "运行诊断状态不是唯一 entry: $status"
    }

    Require ($entries.Count -eq 32) "运行诊断状态数量错误: 期望 32，实际 $($entries.Count)"
    Require (Test-ExactOrdinalSet -Actual @($entries.Name) -Expected $expectedStatuses) '运行诊断状态集合不精确、包含重复项或大小写错误'

    foreach ($status in $expectedStatuses) {
        $entry = @($entries | Where-Object { $_.Name -ceq $status })[0]
        $expectedStackId = if ($ExpectedStateStatuses -ccontains $status) { 'COS_RUNTIME_DIAGNOSTIC_STATE' } else { 'COS_RUNTIME_DIAGNOSTIC_LAST' }
        Require (Test-DiagnosticStatusEntryContract -Entry $entry -ExpectedStackId $expectedStackId) "运行诊断状态定义错误: $status"
    }

    @($entries)
}

function Test-DiagnosticStatusSourceContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string[]]$ExpectedStateStatuses,

        [Parameter(Mandatory)]
        [string[]]$ExpectedLastStatuses
    )

    try {
        [void]@(Assert-DiagnosticStatusSourceContract -Content $Content -ExpectedStateStatuses $ExpectedStateStatuses -ExpectedLastStatuses $ExpectedLastStatuses)
        return $true
    }
    catch {
        return $false
    }
}

function Add-StatsEntryLineForProbe {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$EntryName,

        [Parameter(Mandatory)]
        [string]$Line
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($sourceLine in @($Content -split '\r?\n')) {
        $lines.Add($sourceLine)
    }

    $entryIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -ceq "new entry `"$EntryName`"") {
            $entryIndex = $index
            break
        }
    }
    Require ($entryIndex -ge 0) "变异探针缺少真实 entry: $EntryName"

    $lines.Insert($entryIndex + 1, $Line)
    $lines -join "`n"
}

function Get-StatsEntrySourceBlock {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$EntryName
    )

    $lines = @($Content -split '\r?\n')
    $entryIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -ceq "new entry `"$EntryName`"") {
            $entryIndex = $index
            break
        }
    }
    Require ($entryIndex -ge 0) "变异探针缺少真实 entry: $EntryName"

    $endIndex = $lines.Count
    for ($index = $entryIndex + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^new entry ') {
            $endIndex = $index
            break
        }
    }

    @($lines[$entryIndex..($endIndex - 1)]) -join "`n"
}

function Get-UnversionedStatsHandle {
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$Context
    )

    $match = [regex]::Match($Value, '^([^;\s]+);1$')
    Require ($match.Success) "Stats 本地化 handle 必须恰好以 ;1 结尾: $Context"
    $match.Groups[1].Value
}

function Test-LocalizationHandleCoverage {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$HandlesByLanguage,

        [Parameter(Mandatory)]
        [string[]]$RequiredHandles
    )

    foreach ($language in $HandlesByLanguage.Keys) {
        $languageHandles = @($HandlesByLanguage[$language])
        foreach ($handle in $RequiredHandles) {
            if (@($languageHandles | Where-Object { $_ -ceq $handle }).Count -ne 1) {
                return $false
            }
        }
    }

    return $true
}

function Test-LocalizationHandleSetsEqual {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$HandlesByLanguage
    )

    $languages = @($HandlesByLanguage.Keys)
    if ($languages.Count -eq 0) {
        return $false
    }

    $referenceHandles = @($HandlesByLanguage[$languages[0]])
    foreach ($language in $languages) {
        $languageHandles = @($HandlesByLanguage[$language])
        if ($languageHandles.Count -ne $referenceHandles.Count -or -not (Test-ExactOrdinalSet -Actual $languageHandles -Expected $referenceHandles)) {
            return $false
        }
    }

    return $true
}

function Get-XamlNamedNodes {
    param(
        [Parameter(Mandatory)]
        [xml]$Document,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $xamlNamespace = 'http://schemas.microsoft.com/winfx/2006/xaml'
    @(
        $Document.SelectNodes('//*') |
            Where-Object { $_.GetAttribute('Name', $xamlNamespace) -ceq $Name }
    )
}

function Get-NextElementSibling {
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlNode]$Node
    )

    $candidate = $Node.NextSibling
    while ($null -ne $candidate -and $candidate.NodeType -ne [System.Xml.XmlNodeType]::Element) {
        $candidate = $candidate.NextSibling
    }
    $candidate
}

function Get-RuntimeDiagnosticUiHandleBindings {
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlElement]$Panel
    )

    $handles = [System.Collections.Generic.List[string]]::new()
    foreach ($node in @($Panel) + @($Panel.SelectNodes('.//*'))) {
        foreach ($attribute in @($node.Attributes)) {
            $match = [regex]::Match(
                $attribute.Value,
                "^\{Binding Source='([^']+)', Converter=\{StaticResource TranslatedStringConverter\}\}$"
            )
            if ($match.Success) {
                $handles.Add($match.Groups[1].Value)
            }
        }
    }
    @($handles.ToArray())
}

function Assert-RuntimeDiagnosticUiPageContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$PageName,

        [Parameter(Mandatory)]
        [string[]]$ExpectedStateStatuses,

        [Parameter(Mandatory)]
        [string[]]$ExpectedLastStatuses,

        [Parameter(Mandatory)]
        [string[]]$ExpectedUiHandles
    )

    [xml]$document = $Content
    $xamlNamespace = 'http://schemas.microsoft.com/winfx/2006/xaml'
    $expectedNames = @(
        'COSRuntimeDiagnosticPanel'
        'COSRuntimeDiagnosticVersion'
        'COSRuntimeDiagnosticState'
        'COSRuntimeDiagnosticLast'
        'COSRuntimeDiagnosticPower'
        'COSRuntimeDiagnosticMasteryRemaining'
    )

    $diagnosticNamedNodes = @(
        $document.SelectNodes('//*') |
            Where-Object {
                $_.GetAttribute('Name', $xamlNamespace).StartsWith(
                    'COSRuntimeDiagnostic',
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            }
    )
    Require ($diagnosticNamedNodes.Count -eq 6) "运行诊断 UI 命名节点数量错误: $PageName"
    Require (Test-ExactOrdinalSet -Actual @($diagnosticNamedNodes | ForEach-Object { $_.GetAttribute('Name', $xamlNamespace) }) -Expected $expectedNames) "运行诊断 UI 命名节点集合错误、重复或大小写不符: $PageName"

    $nodesByName = [ordered]@{}
    foreach ($name in $expectedNames) {
        $matches = @(Get-XamlNamedNodes -Document $document -Name $name)
        Require ($matches.Count -eq 1) "运行诊断 UI 节点必须唯一: $PageName/$name"
        $nodesByName[$name] = $matches[0]
    }

    $panel = [System.Xml.XmlElement]$nodesByName.COSRuntimeDiagnosticPanel
    Require ($panel.LocalName -ceq 'Border' -and $panel.GetAttribute('IsHitTestVisible') -ceq 'False') "运行诊断面板必须是不可命中的只读 Border: $PageName"
    foreach ($childName in $expectedNames | Select-Object -Skip 1) {
        $child = [System.Xml.XmlElement]$nodesByName[$childName]
        Require ($child.SelectSingleNode('ancestor::*[@*[local-name()="Name" and .="COSRuntimeDiagnosticPanel"]]') -ne $null) "运行诊断节点必须位于只读面板内: $PageName/$childName"
    }

    $rowsNodes = @(Get-XamlNamedNodes -Document $document -Name 'COSConfigRows')
    $overviewNodes = @(Get-XamlNamedNodes -Document $document -Name 'COSConfigOverview')
    Require ($rowsNodes.Count -eq 1 -and $overviewNodes.Count -eq 1) "设置页缺少 COSConfigRows 或 COSConfigOverview: $PageName"
    Require ([object]::ReferenceEquals($panel.ParentNode, $rowsNodes[0]) -and [object]::ReferenceEquals((Get-NextElementSibling -Node $panel), $overviewNodes[0])) "运行诊断面板必须紧邻并位于 COSConfigOverview 之前: $PageName"

    $interactiveNodes = @(
        $panel.SelectNodes('.//*') |
            Where-Object {
                $_.LocalName -in @(
                    'Button', 'LSButton', 'LSToggleButton', 'LSInputBinding',
                    'EventTrigger', 'InvokeCommandAction', 'ChangePropertyAction'
                )
            }
    )
    Require ($interactiveNodes.Count -eq 0) "运行诊断面板不得包含按钮、输入绑定或事件动作: $PageName"
    $interactiveAttributes = @(
        $panel.SelectNodes('.//*') |
            ForEach-Object { @($_.Attributes) } |
            Where-Object { $_.LocalName -in @('Command', 'CommandParameter', 'BoundEvent', 'Click') }
    )
    Require ($interactiveAttributes.Count -eq 0) "运行诊断面板不得包含命令或交互属性: $PageName"
    $focusConsumers = @(
        @($panel) + @($panel.SelectNodes('.//*')) |
            Where-Object {
                $_.GetAttribute('Focusable') -ceq 'True' -or
                $_.GetAttribute('ls:MoveFocus.Focusable') -ceq 'True'
            }
    )
    Require ($focusConsumers.Count -eq 0) "运行诊断面板不得消费键鼠或手柄焦点: $PageName"

    $actualUiHandles = @(Get-RuntimeDiagnosticUiHandleBindings -Panel $panel)
    Require ($actualUiHandles.Count -eq 7 -and (Test-ExactOrdinalSet -Actual $actualUiHandles -Expected $ExpectedUiHandles)) "运行诊断面板必须各使用一次 7 个批准的 UI handle: $PageName"

    $version = [System.Xml.XmlElement]$nodesByName.COSRuntimeDiagnosticVersion
    Require ($version.LocalName -ceq 'TextBlock') "静态版本节点必须是 TextBlock: $PageName"
    $versionHandles = @(Get-RuntimeDiagnosticUiHandleBindings -Panel $version)
    Require ($versionHandles.Count -eq 1 -and $versionHandles[0] -ceq 'h8f100002g0000g4000g8000g000000000002') "静态版本节点必须绑定批准的版本 handle: $PageName"

    foreach ($statusControlSpec in @(
        [pscustomobject]@{ Name = 'COSRuntimeDiagnosticState'; Expected = $ExpectedStateStatuses },
        [pscustomobject]@{ Name = 'COSRuntimeDiagnosticLast'; Expected = $ExpectedLastStatuses }
    )) {
        $control = [System.Xml.XmlElement]$nodesByName[$statusControlSpec.Name]
        Require ($control.LocalName -ceq 'ItemsControl' -and $control.GetAttribute('ItemsSource') -ceq '{Binding CurrentPlayer.SelectedCharacter.StatusEffects}') "诊断状态控件必须只读绑定当前角色 StatusEffects: $PageName/$($statusControlSpec.Name)"
        $triggers = @($control.SelectNodes('.//*[local-name()="DataTrigger"]'))
        $values = @($triggers | ForEach-Object { $_.GetAttribute('Value') })
        Require ($triggers.Count -eq $statusControlSpec.Expected.Count -and (Test-ExactOrdinalSet -Actual $values -Expected $statusControlSpec.Expected)) "诊断状态过滤集合错误、重复或大小写不符: $PageName/$($statusControlSpec.Name)"
        Require (@($triggers | Where-Object { $_.GetAttribute('Binding') -cne '{Binding StatusId}' }).Count -eq 0) "诊断状态过滤必须精确绑定 StatusId: $PageName/$($statusControlSpec.Name)"
    }

    foreach ($resourceControlSpec in @(
        [pscustomobject]@{ Name = 'COSRuntimeDiagnosticPower'; Resource = 'COS_ChaosPowerPoint' },
        [pscustomobject]@{ Name = 'COSRuntimeDiagnosticMasteryRemaining'; Resource = 'COS_ChaosMasteryPoint' }
    )) {
        $control = [System.Xml.XmlElement]$nodesByName[$resourceControlSpec.Name]
        Require ($control.LocalName -ceq 'ItemsControl' -and $control.GetAttribute('ItemsSource') -ceq '{Binding CurrentPlayer.SelectedCharacter.Stats.ActionResources}') "诊断资源控件必须只读绑定当前角色 ActionResources: $PageName/$($resourceControlSpec.Name)"
        $triggers = @($control.SelectNodes('.//*[local-name()="DataTrigger"]'))
        Require ($triggers.Count -eq 1 -and $triggers[0].GetAttribute('Binding') -ceq '{Binding TypeId}' -and $triggers[0].GetAttribute('Value') -ceq $resourceControlSpec.Resource) "诊断资源过滤必须精确匹配批准资源: $PageName/$($resourceControlSpec.Name)"
        $valueBindings = @($control.SelectNodes('.//*[local-name()="TextBlock"]') | Where-Object { $_.GetAttribute('Text') -ceq '{Binding Value, StringFormat={}{0:0}}' })
        Require ($valueBindings.Count -eq 1) "诊断资源控件必须显示唯一的当前整数值: $PageName/$($resourceControlSpec.Name)"
    }

    $loadedTriggers = @(
        $document.SelectNodes('//*[local-name()="EventTrigger"]') |
            Where-Object { $_.GetAttribute('EventName') -ceq 'Loaded' }
    )
    Require ($loadedTriggers.Count -eq 1) "设置页必须保留唯一 Loaded 事件: $PageName"
    $loadedActions = @($loadedTriggers[0].SelectNodes('.//*[local-name()="InvokeCommandAction"]'))
    Require ($loadedActions.Count -eq 1) "设置页 Loaded 必须只包含一个 InvokeCommandAction: $PageName"
    $loadedAction = $loadedActions[0]
    Require (
        $loadedAction.GetAttribute('Name', $xamlNamespace) -ceq 'COSConfigOpenOnLoaded' -and
        $loadedAction.GetAttribute('Command') -ceq '{Binding DataContext.TutorialEvent, RelativeSource={RelativeSource AncestorType={x:Type ls:UIWidget}}}' -and
        $loadedAction.GetAttribute('CommandParameter') -ceq '65247962-a3b0-417d-9044-85e4aad38079'
    ) "设置页 Loaded 必须仍只发送固定 UI_OPENED TutorialEvent: $PageName"

    [pscustomobject]@{
        PageName = $PageName
        PanelOuterXml = $panel.OuterXml
    }
}

function Test-RuntimeDiagnosticUiPageContract {
    param(
        [Parameter(Mandatory)] [string]$Content,
        [Parameter(Mandatory)] [string]$PageName,
        [Parameter(Mandatory)] [string[]]$ExpectedStateStatuses,
        [Parameter(Mandatory)] [string[]]$ExpectedLastStatuses,
        [Parameter(Mandatory)] [string[]]$ExpectedUiHandles
    )

    try {
        [void](Assert-RuntimeDiagnosticUiPageContract -Content $Content -PageName $PageName -ExpectedStateStatuses $ExpectedStateStatuses -ExpectedLastStatuses $ExpectedLastStatuses -ExpectedUiHandles $ExpectedUiHandles)
        return $true
    }
    catch {
        return $false
    }
}

function Test-RuntimeDiagnosticUiParity {
    param(
        [Parameter(Mandatory)] [string]$KeyboardContent,
        [Parameter(Mandatory)] [string]$ControllerContent,
        [Parameter(Mandatory)] [string[]]$ExpectedStateStatuses,
        [Parameter(Mandatory)] [string[]]$ExpectedLastStatuses,
        [Parameter(Mandatory)] [string[]]$ExpectedUiHandles
    )

    try {
        $keyboardResult = Assert-RuntimeDiagnosticUiPageContract -Content $KeyboardContent -PageName 'keyboard-probe' -ExpectedStateStatuses $ExpectedStateStatuses -ExpectedLastStatuses $ExpectedLastStatuses -ExpectedUiHandles $ExpectedUiHandles
        $controllerResult = Assert-RuntimeDiagnosticUiPageContract -Content $ControllerContent -PageName 'controller-probe' -ExpectedStateStatuses $ExpectedStateStatuses -ExpectedLastStatuses $ExpectedLastStatuses -ExpectedUiHandles $ExpectedUiHandles
        return $keyboardResult.PanelOuterXml -ceq $controllerResult.PanelOuterXml
    }
    catch {
        return $false
    }
}

function ConvertFrom-MarkdownTableLine {
    param(
        [Parameter(Mandatory)]
        [string]$Line
    )

    $trimmed = $Line.Trim()
    Require ($trimmed.StartsWith('|', [System.StringComparison]::Ordinal) -and $trimmed.EndsWith('|', [System.StringComparison]::Ordinal)) "Markdown 表格行格式错误: $Line"
    $body = $trimmed.Substring(1, $trimmed.Length - 2)
    @($body -split '\|' | ForEach-Object { $_.Trim().Replace('`', '') })
}

function Get-MarkdownTableRows {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$Heading
    )

    $lines = @($Content -split '\r?\n')
    $headingIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -ceq $Heading) {
            $headingIndex = $index
            break
        }
    }
    Require ($headingIndex -ge 0) "运行合同缺少表格章节: $Heading"

    $tableStart = -1
    for ($index = $headingIndex + 1; $index -lt $lines.Count; $index++) {
        $candidate = $lines[$index].Trim()
        if ($candidate.StartsWith('## ', [System.StringComparison]::Ordinal)) {
            break
        }
        if ($candidate.StartsWith('|', [System.StringComparison]::Ordinal)) {
            $tableStart = $index
            break
        }
    }
    Require ($tableStart -ge 0) "运行合同章节缺少 Markdown 表格: $Heading"

    $tableLines = [System.Collections.Generic.List[string]]::new()
    for ($index = $tableStart; $index -lt $lines.Count; $index++) {
        $candidate = $lines[$index].Trim()
        if (-not $candidate.StartsWith('|', [System.StringComparison]::Ordinal)) {
            break
        }
        $tableLines.Add($candidate)
    }
    Require ($tableLines.Count -ge 3) "运行合同 Markdown 表格没有数据行: $Heading"

    $headers = @(ConvertFrom-MarkdownTableLine $tableLines[0])
    $separator = @(ConvertFrom-MarkdownTableLine $tableLines[1])
    Require ($separator.Count -eq $headers.Count) "运行合同 Markdown 表格分隔列数错误: $Heading"
    foreach ($separatorCell in $separator) {
        Require ([regex]::IsMatch($separatorCell, '^:?-{3,}:?$')) "运行合同 Markdown 表格分隔符错误: $Heading"
    }

    for ($rowIndex = 2; $rowIndex -lt $tableLines.Count; $rowIndex++) {
        $cells = @(ConvertFrom-MarkdownTableLine $tableLines[$rowIndex])
        Require ($cells.Count -eq $headers.Count) "运行合同 Markdown 表格列数错误: $Heading 第 $rowIndex 行"
        $row = [ordered]@{}
        for ($columnIndex = 0; $columnIndex -lt $headers.Count; $columnIndex++) {
            $row[$headers[$columnIndex]] = $cells[$columnIndex]
        }
        [pscustomobject]$row
    }
}

function Test-ExactLifecycleContractRow {
    param(
        [Parameter(Mandatory)]
        [psobject]$Actual,

        [Parameter(Mandatory)]
        [psobject]$Expected
    )

    return (
        $Actual.Entry -ceq $Expected.Entry -and
        $Actual.Status -ceq $Expected.Status -and
        $Actual.Handlers -ceq $Expected.Handlers -and
        $Actual.'Frozen Behavior' -ceq $Expected.'Frozen Behavior'
    )
}

function Get-StoryRuleBlocks {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $lines = @($Content -split '\r?\n')
    $blocks = [System.Collections.Generic.List[object]]::new()
    $blockStart = -1

    for ($index = 0; $index -le $lines.Count; $index++) {
        $isBoundary = $index -eq $lines.Count -or $lines[$index] -ceq 'PROC' -or $lines[$index] -ceq 'IF' -or $lines[$index] -ceq 'EXITSECTION'
        if (-not $isBoundary) {
            continue
        }

        if ($blockStart -ge 0) {
            $blockLines = @($lines[$blockStart..($index - 1)])
            $header = if ($blockLines.Count -ge 2) { $blockLines[1].Trim() } else { '' }
            $nameMatch = [regex]::Match($header, '^([A-Za-z0-9_]+)\(')
            $blocks.Add([pscustomobject]@{
                Kind = $blockLines[0].Trim()
                Name = if ($nameMatch.Success) { $nameMatch.Groups[1].Value } else { '' }
                Text = $blockLines -join "`n"
                Lines = $blockLines
            })
        }

        if ($index -lt $lines.Count -and ($lines[$index] -ceq 'PROC' -or $lines[$index] -ceq 'IF')) {
            $blockStart = $index
        }
        else {
            $blockStart = -1
        }
    }

    @($blocks.ToArray())
}

function Get-StoryThenLines {
    param(
        [Parameter(Mandatory)]
        [psobject]$Block
    )

    $thenIndex = [Array]::IndexOf([string[]]$Block.Lines, 'THEN')
    if ($thenIndex -lt 0 -or $thenIndex -eq $Block.Lines.Count - 1) {
        return @()
    }

    @($Block.Lines[($thenIndex + 1)..($Block.Lines.Count - 1)])
}

function Get-StoryThenActions {
    param(
        [Parameter(Mandatory)]
        [psobject]$Block
    )

    @(
        Get-StoryThenLines -Block $Block |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('//', [System.StringComparison]::Ordinal) }
    )
}

function Get-StoryConditionLines {
    param(
        [Parameter(Mandatory)]
        [psobject]$Block
    )

    $thenIndex = [Array]::IndexOf([string[]]$Block.Lines, 'THEN')
    if ($thenIndex -le 2) {
        return @()
    }

    @(
        $Block.Lines[2..($thenIndex - 1)] |
            ForEach-Object { $_.Trim() } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                $_ -cne 'AND' -and
                $_ -cne 'OR' -and
                -not $_.StartsWith('//', [System.StringComparison]::Ordinal)
            }
    )
}

function Assert-RuntimeDiagnosticStoryContract {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [psobject[]]$CoreMechanics,

        [Parameter(Mandatory)]
        [string[]]$RacialKeys,

        [Parameter(Mandatory)]
        [string[]]$KnownDiagnosticStatuses
    )

    $allBlocks = @(Get-StoryRuleBlocks -Content $Content)
    $diagnosticBlocks = @($allBlocks | Where-Object { $_.Name.StartsWith('PROC_COS_RuntimeDiagnostic', [System.StringComparison]::Ordinal) })
    $expectedRuleCounts = [ordered]@{
        PROC_COS_RuntimeDiagnosticSeed = 15
        PROC_COS_RuntimeDiagnosticBegin = 1
        PROC_COS_RuntimeDiagnosticSelectFirst = 1
        PROC_COS_RuntimeDiagnosticCheckConfig = 1
        PROC_COS_RuntimeDiagnosticCheckCoreMissing = 1
        PROC_COS_RuntimeDiagnosticCheckLifeMissing = 1
        PROC_COS_RuntimeDiagnosticCheckCostMissing = 1
        PROC_COS_RuntimeDiagnosticCheckRacialMissing = 1
        PROC_COS_RuntimeDiagnosticCheckGrantMissing = 1
        PROC_COS_RuntimeDiagnosticCheckTagSpellsMissing = 1
        PROC_COS_RuntimeDiagnosticCheckVoloMissing = 1
        PROC_COS_RuntimeDiagnosticCheckCarryMissing = 1
        PROC_COS_RuntimeDiagnosticCheckMirrors = 1
        PROC_COS_RuntimeDiagnosticCheckCoreMismatch = 2
        PROC_COS_RuntimeDiagnosticCheckCarryMismatch = 2
        PROC_COS_RuntimeDiagnosticSetCurrent = 1
        PROC_COS_RuntimeDiagnosticSetLast = 1
        PROC_COS_RuntimeDiagnosticApply = 2
        PROC_COS_RuntimeDiagnosticEnsureLast = 1
        PROC_COS_RuntimeDiagnosticResolve = 3
        PROC_COS_RuntimeDiagnosticUpdate = 2
    }
    $expectedRuleCount = ($expectedRuleCounts.Values | Measure-Object -Sum).Sum
    Require ($diagnosticBlocks.Count -eq $expectedRuleCount) "运行诊断规则总数错误: 期望 $expectedRuleCount，实际 $($diagnosticBlocks.Count)"
    foreach ($block in $diagnosticBlocks) {
        Require (@($expectedRuleCounts.Keys | Where-Object { $_ -ceq $block.Name }).Count -eq 1) "出现未授权的运行诊断过程: $($block.Name)"
    }
    foreach ($processName in $expectedRuleCounts.Keys) {
        $actualCount = @($diagnosticBlocks | Where-Object { $_.Name -ceq $processName }).Count
        Require ($actualCount -eq $expectedRuleCounts[$processName]) "运行诊断过程规则数量错误: $processName 期望 $($expectedRuleCounts[$processName])，实际 $actualCount"
    }

    foreach ($block in $diagnosticBlocks) {
        Require (-not [regex]::IsMatch($block.Text, '(?i)\b(?:Random|GetRandom|RollRandom|Randomize)\w*\s*\(')) "运行诊断包含随机调用: $($block.Name)"
        Require (-not $block.Text.Contains('DB_COS_ConfigMechanicDefault(', [System.StringComparison]::Ordinal)) "运行诊断不得枚举 ConfigMechanicDefault: $($block.Name)"
        Require (-not $block.Text.Contains('DB_COS_ConfigRacialDefault(', [System.StringComparison]::Ordinal)) "运行诊断不得枚举 ConfigRacialDefault: $($block.Name)"

        foreach ($action in @(Get-StoryThenActions -Block $block)) {
            $isDiagnosticDbWrite = [regex]::IsMatch($action, '^(?:NOT\s+)?DB_COS_RuntimeDiagnostic[A-Za-z0-9_]*\([^\r\n]*\);$')
            $isDiagnosticProcCall = [regex]::IsMatch($action, '^PROC_COS_RuntimeDiagnostic[A-Za-z0-9_]*\([^\r\n]*\);$')
            $isLiteralDiagnosticApply = [regex]::IsMatch($action, '^ApplyStatus\(_Character, "COS_DIAG_[A-Z0-9_]+", -1\.0, 1, _Character\);$')
            $isLiteralDiagnosticRemove = [regex]::IsMatch($action, '^RemoveStatus\(_Character, "COS_DIAG_[A-Z0-9_]+", _Character\);$')
            $isGuardedDynamicApply = $block.Name -ceq 'PROC_COS_RuntimeDiagnosticApply' -and $action -ceq 'ApplyStatus(_Character, _Status, -1.0, 1, _Character);' -and $block.Text.Contains('DB_COS_RuntimeDiagnosticApplied(', [System.StringComparison]::Ordinal)
            $isGuardedDynamicRemove = $block.Name -ceq 'PROC_COS_RuntimeDiagnosticApply' -and $action -ceq 'RemoveStatus(_Character, _OldStatus, _Character);' -and $block.Text.Contains('DB_COS_RuntimeDiagnosticApplied(', [System.StringComparison]::Ordinal)
            Require ($isDiagnosticDbWrite -or $isDiagnosticProcCall -or $isLiteralDiagnosticApply -or $isLiteralDiagnosticRemove -or $isGuardedDynamicApply -or $isGuardedDynamicRemove) "运行诊断 THEN 动作不在只读白名单: $($block.Name) -> $action"
        }
    }

    $seedText = (@($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticSeed' }).Text) -join "`n"
    $expectedSeedRows = [System.Collections.Generic.List[string]]::new()
    foreach ($mechanic in $CoreMechanics) {
        $missingStatus = "COS_DIAG_LAST_MISSING_$($mechanic.Key.ToUpperInvariant())"
        if ($mechanic.Key -ceq 'KillPower') { $missingStatus = 'COS_DIAG_LAST_MISSING_KILLPOWER' }
        if ($mechanic.Key -ceq 'AllIn') { $missingStatus = 'COS_DIAG_LAST_MISSING_ALLIN' }
        $mismatchStatus = $missingStatus.Replace('MISSING_', 'MISMATCH_')
        $mapLine = "DB_COS_RuntimeDiagnosticCore(`"$($mechanic.Key)`", `"$($mechanic.Mirror)`", `"$missingStatus`", `"$mismatchStatus`");"
        $expectedSeedRows.Add($mapLine)
        Require ($seedText.Contains("NOT $($mapLine.TrimEnd(';'))", [System.StringComparison]::Ordinal)) "运行诊断 seed 缺少核心映射存在性门控: $($mechanic.Key)"
        Require ($seedText.Contains($mapLine, [System.StringComparison]::Ordinal)) "运行诊断 seed 缺少核心映射: $($mechanic.Key)"
    }
    foreach ($costSeed in @(
        'DB_COS_RuntimeDiagnosticCost("Fate", "COS_DIAG_LAST_MISSING_FATE_COST");'
        'DB_COS_RuntimeDiagnosticCost("Genesis", "COS_DIAG_LAST_MISSING_GENESIS_COST");'
    )) {
        $expectedSeedRows.Add($costSeed)
        Require ($seedText.Contains("NOT $($costSeed.TrimEnd(';'))", [System.StringComparison]::Ordinal)) "运行诊断 seed 缺少消耗映射存在性门控: $costSeed"
        Require ($seedText.Contains($costSeed, [System.StringComparison]::Ordinal)) "运行诊断 seed 缺少消耗映射: $costSeed"
    }
    foreach ($stateSeed in @(
        'DB_COS_RuntimeDiagnosticState("NotOrigin", "COS_DIAG_STATE_NOT_ORIGIN");'
        'DB_COS_RuntimeDiagnosticState("ConfigIncomplete", "COS_DIAG_STATE_CONFIG_INCOMPLETE");'
        'DB_COS_RuntimeDiagnosticState("CoreMismatch", "COS_DIAG_STATE_CORE_MISMATCH");'
        'DB_COS_RuntimeDiagnosticState("Ready", "COS_DIAG_STATE_READY");'
    )) {
        $expectedSeedRows.Add($stateSeed)
        Require ($seedText.Contains("NOT $($stateSeed.TrimEnd(';'))", [System.StringComparison]::Ordinal)) "运行诊断 seed 缺少当前状态映射存在性门控: $stateSeed"
        Require ($seedText.Contains($stateSeed, [System.StringComparison]::Ordinal)) "运行诊断 seed 缺少当前状态映射: $stateSeed"
    }
    $actualSeedRows = @(
        [regex]::Matches($seedText, '(?m)^DB_COS_RuntimeDiagnostic(?:Core|Cost|State)\([^\r\n]+\);\s*$') |
            ForEach-Object { $_.Value.Trim() }
    )
    Require ($actualSeedRows.Count -eq 15) "运行诊断 seed 映射数量错误: 期望 15，实际 $($actualSeedRows.Count)"
    Require (Test-ExactOrdinalSet -Actual $actualSeedRows -Expected @($expectedSeedRows.ToArray())) '运行诊断 seed 映射集合不精确、重复或包含额外项'
    foreach ($seedBlock in @($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticSeed' })) {
        $seedActions = @(Get-StoryThenActions -Block $seedBlock)
        Require ($seedActions.Count -eq 1 -and @($expectedSeedRows | Where-Object { $_ -ceq $seedActions[0] }).Count -eq 1) '每条 Seed 规则必须只写入一条精确映射'
        Require ($seedBlock.Text.Contains("NOT $($seedActions[0].TrimEnd(';'))", [System.StringComparison]::Ordinal)) "Seed 规则缺少对应的 NOT 存在性门控: $($seedActions[0])"
    }

    $beginBlocks = @($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticBegin' })
    Require ($beginBlocks[0].Text.Contains('DB_COS_RuntimeDiagnosticSelected(_Character, _Kind, _IssueStatus)', [System.StringComparison]::Ordinal)) 'Begin 缺少本轮 Selected 清理条件'
    Require (Test-ExactOrdinalSequence -Actual @(Get-StoryThenActions -Block $beginBlocks[0]) -Expected @('NOT DB_COS_RuntimeDiagnosticSelected(_Character, _Kind, _IssueStatus);')) 'Begin 只能清理本轮 Selected'
    $selectFirstBlocks = @($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticSelectFirst' })
    Require ($selectFirstBlocks.Count -eq 1) "SelectFirst 过程数量错误: 期望 1，实际 $($selectFirstBlocks.Count)"
    Require ($selectFirstBlocks[0].Text.Contains('NOT DB_COS_RuntimeDiagnosticSelected(_Character, _, _)', [System.StringComparison]::Ordinal)) 'SelectFirst 缺少只取第一项门控'
    Require ([regex]::Matches($selectFirstBlocks[0].Text, '(?m)^DB_COS_RuntimeDiagnosticSelected\(_Character, _Kind, _IssueStatus\);\s*$').Count -eq 1) 'SelectFirst 没有恰好写入一条 Selected'
    Require (Test-ExactOrdinalSequence -Actual @(Get-StoryThenActions -Block $selectFirstBlocks[0]) -Expected @('DB_COS_RuntimeDiagnosticSelected(_Character, _Kind, _IssueStatus);')) 'SelectFirst 只能写入一条 Selected'

    $checkConfigBlocks = @($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticCheckConfig' })
    Require ($checkConfigBlocks.Count -eq 1) "CheckConfig 过程数量错误: 期望 1，实际 $($checkConfigBlocks.Count)"
    $checkConfigText = $checkConfigBlocks[0].Text
    $missingCalls = [System.Collections.Generic.List[string]]::new()
    foreach ($mechanic in $CoreMechanics) {
        $suffix = $mechanic.Key.ToUpperInvariant()
        $missingCalls.Add("PROC_COS_RuntimeDiagnosticCheckCoreMissing(_Character, `"$($mechanic.Key)`", `"COS_DIAG_LAST_MISSING_$suffix`");")
    }
    $missingCalls.Add('PROC_COS_RuntimeDiagnosticCheckLifeMissing(_Character);')
    $missingCalls.Add('PROC_COS_RuntimeDiagnosticCheckCostMissing(_Character, "Fate", "COS_DIAG_LAST_MISSING_FATE_COST");')
    $missingCalls.Add('PROC_COS_RuntimeDiagnosticCheckCostMissing(_Character, "Genesis", "COS_DIAG_LAST_MISSING_GENESIS_COST");')
    foreach ($racialKey in $RacialKeys) {
        $missingCalls.Add("PROC_COS_RuntimeDiagnosticCheckRacialMissing(_Character, `"$racialKey`");")
    }
    $missingCalls.Add('PROC_COS_RuntimeDiagnosticCheckGrantMissing(_Character);')
    $missingCalls.Add('PROC_COS_RuntimeDiagnosticCheckTagSpellsMissing(_Character);')
    $missingCalls.Add('PROC_COS_RuntimeDiagnosticCheckVoloMissing(_Character);')
    $missingCalls.Add('PROC_COS_RuntimeDiagnosticCheckCarryMissing(_Character);')
    $lastPosition = -1
    foreach ($call in $missingCalls) {
        $position = $checkConfigText.IndexOf($call, [System.StringComparison]::Ordinal)
        Require ($position -gt $lastPosition) "运行诊断缺失检查顺序错误或缺少显式调用: $call"
        $lastPosition = $position
    }
    Require (Test-ExactOrdinalSequence -Actual @(Get-StoryThenActions -Block $checkConfigBlocks[0]) -Expected @($missingCalls.ToArray())) 'CheckConfig 必须只按固定顺序调用精确的缺失检查'

    $coreMissingText = (@($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticCheckCoreMissing' }).Text) -join "`n"
    Require ($coreMissingText.Contains('DB_COS_RuntimeDiagnosticCore(_Key, _, _IssueStatus, _)', [System.StringComparison]::Ordinal)) '核心缺失检查没有绑定已播种的精确诊断映射'
    Require ($coreMissingText.Contains('NOT DB_COS_ConfigMechanic(_Character, _Key, _)', [System.StringComparison]::Ordinal)) '核心缺失检查没有检查角色配置行'
    Require (Test-ExactOrdinalSequence -Actual @(Get-StoryThenActions -Block @($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticCheckCoreMissing' })[0]) -Expected @('PROC_COS_RuntimeDiagnosticSelectFirst(_Character, "Missing", _IssueStatus);')) '核心缺失检查动作不精确'
    $lifeMissingText = (@($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticCheckLifeMissing' }).Text) -join "`n"
    Require ($lifeMissingText.Contains('NOT DB_COS_ConfigLifeSkill(_Character, _)', [System.StringComparison]::Ordinal)) '生活加值缺失检查不完整'
    $costMissingText = (@($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticCheckCostMissing' }).Text) -join "`n"
    Require ($costMissingText.Contains('DB_COS_RuntimeDiagnosticCost(_Key, _IssueStatus)', [System.StringComparison]::Ordinal) -and $costMissingText.Contains('NOT DB_COS_ConfigCost(_Character, _Key, _)', [System.StringComparison]::Ordinal)) 'Fate/Genesis 消耗缺失检查不完整'
    $racialMissingText = (@($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticCheckRacialMissing' }).Text) -join "`n"
    Require ($racialMissingText.Contains('NOT DB_COS_ConfigRacial(_Character, _Passive, _)', [System.StringComparison]::Ordinal) -and $racialMissingText.Contains('"COS_DIAG_LAST_MISSING_RACIAL"', [System.StringComparison]::Ordinal)) '20 项种族配置缺失检查不完整'
    $grantMissingText = (@($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticCheckGrantMissing' }).Text) -join "`n"
    Require ($grantMissingText.Contains('DB_COS_GrantOption(_Key, _Mirror)', [System.StringComparison]::Ordinal) -and $grantMissingText.Contains('NOT DB_COS_GrantSetting(_Character, _Key, _)', [System.StringComparison]::Ordinal)) 'Grant 缺失检查必须逐个 GrantOption 检查对应设置'
    Require (-not $grantMissingText.Contains('DB_COS_GrantInitialized(', [System.StringComparison]::Ordinal)) 'Grant 缺失检查不能只依赖 GrantInitialized'
    $tagSpellsMissingText = (@($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticCheckTagSpellsMissing' }).Text) -join "`n"
    Require ($tagSpellsMissingText.Contains('NOT DB_COS_TagSpellsSetting(_Character, _)', [System.StringComparison]::Ordinal)) 'TagSpells 缺失检查不完整'
    $voloMissingText = (@($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticCheckVoloMissing' }).Text) -join "`n"
    Require ($voloMissingText.Contains('NOT DB_COS_VoloEyeSetting(_Character, _)', [System.StringComparison]::Ordinal)) 'Volo 缺失检查不完整'
    $carryMissingText = (@($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticCheckCarryMissing' }).Text) -join "`n"
    Require ($carryMissingText.Contains('NOT DB_COS_CarryEnabled(_Character, _)', [System.StringComparison]::Ordinal)) 'Carry 缺失检查不完整'
    $expectedSingleMissingActions = [ordered]@{
        PROC_COS_RuntimeDiagnosticCheckLifeMissing = 'PROC_COS_RuntimeDiagnosticSelectFirst(_Character, "Missing", "COS_DIAG_LAST_MISSING_LIFE");'
        PROC_COS_RuntimeDiagnosticCheckCostMissing = 'PROC_COS_RuntimeDiagnosticSelectFirst(_Character, "Missing", _IssueStatus);'
        PROC_COS_RuntimeDiagnosticCheckRacialMissing = 'PROC_COS_RuntimeDiagnosticSelectFirst(_Character, "Missing", "COS_DIAG_LAST_MISSING_RACIAL");'
        PROC_COS_RuntimeDiagnosticCheckGrantMissing = 'PROC_COS_RuntimeDiagnosticSelectFirst(_Character, "Missing", "COS_DIAG_LAST_MISSING_GRANT");'
        PROC_COS_RuntimeDiagnosticCheckTagSpellsMissing = 'PROC_COS_RuntimeDiagnosticSelectFirst(_Character, "Missing", "COS_DIAG_LAST_MISSING_TAG_SPELLS");'
        PROC_COS_RuntimeDiagnosticCheckVoloMissing = 'PROC_COS_RuntimeDiagnosticSelectFirst(_Character, "Missing", "COS_DIAG_LAST_MISSING_VOLO");'
        PROC_COS_RuntimeDiagnosticCheckCarryMissing = 'PROC_COS_RuntimeDiagnosticSelectFirst(_Character, "Missing", "COS_DIAG_LAST_MISSING_CARRY");'
    }
    foreach ($processName in $expectedSingleMissingActions.Keys) {
        $processBlock = @($diagnosticBlocks | Where-Object { $_.Name -ceq $processName })[0]
        Require (Test-ExactOrdinalSequence -Actual @(Get-StoryThenActions -Block $processBlock) -Expected @($expectedSingleMissingActions[$processName])) "缺失检查动作不精确: $processName"
    }

    $checkMirrorBlocks = @($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticCheckMirrors' })
    Require ($checkMirrorBlocks.Count -eq 1) "CheckMirrors 过程数量错误: 期望 1，实际 $($checkMirrorBlocks.Count)"
    $checkMirrorText = $checkMirrorBlocks[0].Text
    $lastPosition = -1
    foreach ($mechanic in $CoreMechanics) {
        $suffix = $mechanic.Key.ToUpperInvariant()
        $call = "PROC_COS_RuntimeDiagnosticCheckCoreMismatch(_Character, `"$($mechanic.Key)`", `"$($mechanic.Mirror)`", `"COS_DIAG_LAST_MISMATCH_$suffix`");"
        $position = $checkMirrorText.IndexOf($call, [System.StringComparison]::Ordinal)
        Require ($position -gt $lastPosition) "运行诊断镜像检查顺序错误或缺少显式调用: $($mechanic.Key)"
        $lastPosition = $position
    }
    $carryMismatchCall = 'PROC_COS_RuntimeDiagnosticCheckCarryMismatch(_Character);'
    $carryMismatchPosition = $checkMirrorText.IndexOf($carryMismatchCall, [System.StringComparison]::Ordinal)
    Require ($carryMismatchPosition -gt $lastPosition) '运行诊断缺少末尾 Carry 双向镜像检查'
    $expectedMirrorCalls = @(
        foreach ($mechanic in $CoreMechanics) {
            $suffix = $mechanic.Key.ToUpperInvariant()
            "PROC_COS_RuntimeDiagnosticCheckCoreMismatch(_Character, `"$($mechanic.Key)`", `"$($mechanic.Mirror)`", `"COS_DIAG_LAST_MISMATCH_$suffix`");"
        }
        $carryMismatchCall
    )
    Require (Test-ExactOrdinalSequence -Actual @(Get-StoryThenActions -Block $checkMirrorBlocks[0]) -Expected $expectedMirrorCalls) 'CheckMirrors 必须只按固定顺序调用九项核心与 Carry 检查'

    $coreMismatchBlocks = @($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticCheckCoreMismatch' })
    $enabledCoreMismatch = @($coreMismatchBlocks | Where-Object { $_.Text.Contains('DB_COS_ConfigMechanic(_Character, _Key, 1)', [System.StringComparison]::Ordinal) -and $_.Text.Contains('HasPassive(_Character, _Mirror, 0)', [System.StringComparison]::Ordinal) })
    $disabledCoreMismatch = @($coreMismatchBlocks | Where-Object { $_.Text.Contains('DB_COS_ConfigMechanic(_Character, _Key, 0)', [System.StringComparison]::Ordinal) -and $_.Text.Contains('HasPassive(_Character, _Mirror, 1)', [System.StringComparison]::Ordinal) })
    Require ($enabledCoreMismatch.Count -eq 1 -and $disabledCoreMismatch.Count -eq 1) '核心镜像检查规则没有严格分成两个相反方向'
    foreach ($coreMismatchBlock in $coreMismatchBlocks) {
        Require (Test-ExactOrdinalSequence -Actual @(Get-StoryThenActions -Block $coreMismatchBlock) -Expected @('PROC_COS_RuntimeDiagnosticSelectFirst(_Character, "Mismatch", _IssueStatus);')) '核心镜像检查只能选择对应不一致项'
    }
    $coreMismatchText = ($coreMismatchBlocks.Text) -join "`n"
    Require ($coreMismatchText.Contains('DB_COS_ConfigMechanic(_Character, _Key, 1)', [System.StringComparison]::Ordinal) -and $coreMismatchText.Contains('HasPassive(_Character, _Mirror, 0)', [System.StringComparison]::Ordinal)) '核心镜像检查缺少 setting=1 / passive=0 方向'
    Require ($coreMismatchText.Contains('DB_COS_ConfigMechanic(_Character, _Key, 0)', [System.StringComparison]::Ordinal) -and $coreMismatchText.Contains('HasPassive(_Character, _Mirror, 1)', [System.StringComparison]::Ordinal)) '核心镜像检查缺少 setting=0 / passive=1 方向'
    $carryMismatchBlocks = @($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticCheckCarryMismatch' })
    $enabledCarryMismatch = @($carryMismatchBlocks | Where-Object { $_.Text.Contains('DB_COS_CarryEnabled(_Character, 1)', [System.StringComparison]::Ordinal) -and $_.Text.Contains('HasPassive(_Character, "COS_CFG_CARRY", 0)', [System.StringComparison]::Ordinal) })
    $disabledCarryMismatch = @($carryMismatchBlocks | Where-Object { $_.Text.Contains('DB_COS_CarryEnabled(_Character, 0)', [System.StringComparison]::Ordinal) -and $_.Text.Contains('HasPassive(_Character, "COS_CFG_CARRY", 1)', [System.StringComparison]::Ordinal) })
    Require ($enabledCarryMismatch.Count -eq 1 -and $disabledCarryMismatch.Count -eq 1) 'Carry 镜像检查规则没有严格分成两个相反方向'
    foreach ($carryMismatchBlock in $carryMismatchBlocks) {
        Require (Test-ExactOrdinalSequence -Actual @(Get-StoryThenActions -Block $carryMismatchBlock) -Expected @('PROC_COS_RuntimeDiagnosticSelectFirst(_Character, "Mismatch", "COS_DIAG_LAST_MISMATCH_CARRY");')) 'Carry 镜像检查只能选择 Carry 不一致项'
    }
    $carryMismatchText = ($carryMismatchBlocks.Text) -join "`n"
    Require ($carryMismatchText.Contains('DB_COS_CarryEnabled(_Character, 1)', [System.StringComparison]::Ordinal) -and $carryMismatchText.Contains('HasPassive(_Character, "COS_CFG_CARRY", 0)', [System.StringComparison]::Ordinal)) 'Carry 镜像检查缺少 enabled=1 / passive=0 方向'
    Require ($carryMismatchText.Contains('DB_COS_CarryEnabled(_Character, 0)', [System.StringComparison]::Ordinal) -and $carryMismatchText.Contains('HasPassive(_Character, "COS_CFG_CARRY", 1)', [System.StringComparison]::Ordinal)) 'Carry 镜像检查缺少 enabled=0 / passive=1 方向'

    $applyBlocks = @($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticApply' })
    Require ($applyBlocks.Count -eq 2) "Apply 过程数量错误: 期望 2，实际 $($applyBlocks.Count)"
    foreach ($applyBlock in $applyBlocks) {
        Require ($applyBlock.Text.Contains('NOT DB_COS_RuntimeDiagnosticApplied(_Character, _Channel, _Status)', [System.StringComparison]::Ordinal)) 'Apply 分支缺少同状态不刷新门控'
    }
    $replaceAppliedBlock = @($applyBlocks | Where-Object { $_.Text.Contains('DB_COS_RuntimeDiagnosticApplied(_Character, _Channel, _OldStatus)', [System.StringComparison]::Ordinal) })
    $firstAppliedBlock = @($applyBlocks | Where-Object { $_.Text.Contains('NOT DB_COS_RuntimeDiagnosticApplied(_Character, _Channel, _)', [System.StringComparison]::Ordinal) })
    Require ($replaceAppliedBlock.Count -eq 1 -and $firstAppliedBlock.Count -eq 1) 'Apply 规则没有严格分成替换旧状态和首次应用'
    $expectedReplaceAppliedActions = @(
        'RemoveStatus(_Character, _OldStatus, _Character);'
        'NOT DB_COS_RuntimeDiagnosticApplied(_Character, _Channel, _OldStatus);'
        'DB_COS_RuntimeDiagnosticApplied(_Character, _Channel, _Status);'
        'ApplyStatus(_Character, _Status, -1.0, 1, _Character);'
    )
    $actualReplaceAppliedActions = @(Get-StoryThenActions -Block $replaceAppliedBlock[0])
    Require ($actualReplaceAppliedActions.Count -eq $expectedReplaceAppliedActions.Count) '替换诊断状态的 Apply 动作数量错误'
    for ($index = 0; $index -lt $expectedReplaceAppliedActions.Count; $index++) {
        Require ($actualReplaceAppliedActions[$index] -ceq $expectedReplaceAppliedActions[$index]) "替换诊断状态的 Apply 动作顺序错误: 索引 $index"
    }
    $expectedFirstAppliedActions = @(
        'DB_COS_RuntimeDiagnosticApplied(_Character, _Channel, _Status);'
        'ApplyStatus(_Character, _Status, -1.0, 1, _Character);'
    )
    $actualFirstAppliedActions = @(Get-StoryThenActions -Block $firstAppliedBlock[0])
    Require ($actualFirstAppliedActions.Count -eq $expectedFirstAppliedActions.Count) '首次诊断状态的 Apply 动作数量错误'
    for ($index = 0; $index -lt $expectedFirstAppliedActions.Count; $index++) {
        Require ($actualFirstAppliedActions[$index] -ceq $expectedFirstAppliedActions[$index]) "首次诊断状态的 Apply 动作顺序错误: 索引 $index"
    }
    $applyText = ($applyBlocks.Text) -join "`n"
    Require ($applyText.Contains('NOT DB_COS_RuntimeDiagnosticApplied(_Character, _Channel, _Status)', [System.StringComparison]::Ordinal)) 'Apply 缺少同状态不刷新门控'
    Require ($applyText.Contains('DB_COS_RuntimeDiagnosticApplied(_Character, _Channel, _OldStatus)', [System.StringComparison]::Ordinal)) 'Apply 缺少旧状态缓存读取'
    Require ($applyText.Contains('RemoveStatus(_Character, _OldStatus, _Character);', [System.StringComparison]::Ordinal)) 'Apply 缺少旧诊断状态移除'
    Require ($applyText.Contains('ApplyStatus(_Character, _Status, -1.0, 1, _Character);', [System.StringComparison]::Ordinal)) 'Apply 缺少新诊断状态应用'

    $setCurrentBlock = @($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticSetCurrent' })[0]
    Require ($setCurrentBlock.Text.Contains('DB_COS_RuntimeDiagnosticState(_, _Status)', [System.StringComparison]::Ordinal)) 'SetCurrent 必须由精确播种的 State 状态约束'
    Require (Test-ExactOrdinalSequence -Actual @(Get-StoryThenActions -Block $setCurrentBlock) -Expected @('PROC_COS_RuntimeDiagnosticApply(_Character, "State", _Status);')) 'SetCurrent 只能写入 State 诊断通道'
    $setLastBlock = @($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticSetLast' })[0]
    Require (Test-ExactOrdinalSequence -Actual @(Get-StoryThenActions -Block $setLastBlock) -Expected @('PROC_COS_RuntimeDiagnosticApply(_Character, "Last", _Status);')) 'SetLast 只能写入 Last 诊断通道'
    $ensureLastBlock = @($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticEnsureLast' })[0]
    Require ($ensureLastBlock.Text.Contains('NOT DB_COS_RuntimeDiagnosticApplied(_Character, "Last", _)', [System.StringComparison]::Ordinal)) 'EnsureLast 缺少 Last 不存在条件'
    Require (Test-ExactOrdinalSequence -Actual @(Get-StoryThenActions -Block $ensureLastBlock) -Expected @('PROC_COS_RuntimeDiagnosticSetLast(_Character, "COS_DIAG_LAST_NONE");')) 'EnsureLast 只能初始化 LAST_NONE'

    $updateBlocks = @($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticUpdate' })
    Require ($updateBlocks.Count -eq 2) "Update 过程数量错误: 期望 2，实际 $($updateBlocks.Count)"
    $nonOriginUpdate = @($updateBlocks | Where-Object { $_.Text.Contains('HasPassive(_Character, "COS_ChaosOriginMarker", 0)', [System.StringComparison]::Ordinal) })
    $originUpdate = @($updateBlocks | Where-Object { $_.Text.Contains('HasPassive(_Character, "COS_ChaosOriginMarker", 1)', [System.StringComparison]::Ordinal) })
    Require ($nonOriginUpdate.Count -eq 1 -and $originUpdate.Count -eq 1) 'Update 没有严格分成起源与非起源两条规则'
    $expectedNonOriginUpdateThen = @(
        'PROC_COS_RuntimeDiagnosticSeed();'
        'PROC_COS_RuntimeDiagnosticBegin(_Character);'
        'PROC_COS_RuntimeDiagnosticSetCurrent(_Character, "COS_DIAG_STATE_NOT_ORIGIN");'
        'PROC_COS_RuntimeDiagnosticSetLast(_Character, "COS_DIAG_LAST_NONE");'
    )
    $actualNonOriginUpdateThen = @((Get-StoryThenLines -Block $nonOriginUpdate[0]) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    Require ($actualNonOriginUpdateThen.Count -eq $expectedNonOriginUpdateThen.Count) '非起源 Update 不得运行配置诊断或其他逻辑'
    for ($index = 0; $index -lt $expectedNonOriginUpdateThen.Count; $index++) {
        Require ($actualNonOriginUpdateThen[$index] -ceq $expectedNonOriginUpdateThen[$index]) "非起源 Update 调用顺序错误: 索引 $index"
    }
    $expectedOriginUpdateThen = @(
        'PROC_COS_RuntimeDiagnosticSeed();'
        'PROC_COS_RuntimeDiagnosticBegin(_Character);'
        'PROC_COS_RuntimeDiagnosticCheckConfig(_Character);'
        'PROC_COS_RuntimeDiagnosticCheckMirrors(_Character);'
        'PROC_COS_RuntimeDiagnosticResolve(_Character);'
    )
    $actualOriginUpdateThen = @((Get-StoryThenLines -Block $originUpdate[0]) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    Require ($actualOriginUpdateThen.Count -eq $expectedOriginUpdateThen.Count) '起源 Update 调用数量错误'
    for ($index = 0; $index -lt $expectedOriginUpdateThen.Count; $index++) {
        Require ($actualOriginUpdateThen[$index] -ceq $expectedOriginUpdateThen[$index]) "起源 Update 调用顺序错误: 索引 $index"
    }
    $updateText = ($updateBlocks.Text) -join "`n"
    foreach ($requiredUpdateFragment in @(
        'PROC_COS_RuntimeDiagnosticSeed();'
        'PROC_COS_RuntimeDiagnosticBegin(_Character);'
        'HasPassive(_Character, "COS_ChaosOriginMarker", 0)'
        'PROC_COS_RuntimeDiagnosticSetCurrent(_Character, "COS_DIAG_STATE_NOT_ORIGIN");'
        'PROC_COS_RuntimeDiagnosticSetLast(_Character, "COS_DIAG_LAST_NONE");'
        'HasPassive(_Character, "COS_ChaosOriginMarker", 1)'
        'PROC_COS_RuntimeDiagnosticCheckConfig(_Character);'
        'PROC_COS_RuntimeDiagnosticCheckMirrors(_Character);'
        'PROC_COS_RuntimeDiagnosticResolve(_Character);'
    )) {
        Require ($updateText.Contains($requiredUpdateFragment, [System.StringComparison]::Ordinal)) "Update 缺少状态分类或调用: $requiredUpdateFragment"
    }

    $resolveBlocks = @($diagnosticBlocks | Where-Object { $_.Name -ceq 'PROC_COS_RuntimeDiagnosticResolve' })
    $missingResolve = @($resolveBlocks | Where-Object { $_.Text.Contains('DB_COS_RuntimeDiagnosticSelected(_Character, "Missing", _IssueStatus)', [System.StringComparison]::Ordinal) })
    $mismatchResolve = @($resolveBlocks | Where-Object { $_.Text.Contains('DB_COS_RuntimeDiagnosticSelected(_Character, "Mismatch", _IssueStatus)', [System.StringComparison]::Ordinal) })
    $readyResolve = @($resolveBlocks | Where-Object { $_.Text.Contains('NOT DB_COS_RuntimeDiagnosticSelected(_Character, _, _)', [System.StringComparison]::Ordinal) })
    Require ($missingResolve.Count -eq 1 -and $mismatchResolve.Count -eq 1 -and $readyResolve.Count -eq 1) 'Resolve 规则没有严格分成 Missing、Mismatch、Ready 三类'
    Require (Test-ExactOrdinalSequence -Actual @(Get-StoryConditionLines -Block $missingResolve[0]) -Expected @('DB_COS_RuntimeDiagnosticSelected(_Character, "Missing", _IssueStatus)')) 'Missing Resolve 条件必须精确且不得包含额外阻断条件'
    Require (Test-ExactOrdinalSequence -Actual @(Get-StoryConditionLines -Block $mismatchResolve[0]) -Expected @('DB_COS_RuntimeDiagnosticSelected(_Character, "Mismatch", _IssueStatus)')) 'Mismatch Resolve 条件必须精确且不得包含额外阻断条件'
    Require (Test-ExactOrdinalSequence -Actual @(Get-StoryConditionLines -Block $readyResolve[0]) -Expected @('NOT DB_COS_RuntimeDiagnosticSelected(_Character, _, _)')) 'Ready Resolve 条件必须精确且不得包含额外阻断条件'
    $expectedMissingResolveActions = @(
        'PROC_COS_RuntimeDiagnosticSetLast(_Character, _IssueStatus);'
        'PROC_COS_RuntimeDiagnosticSetCurrent(_Character, "COS_DIAG_STATE_CONFIG_INCOMPLETE");'
    )
    $actualMissingResolveActions = @(Get-StoryThenActions -Block $missingResolve[0])
    Require ($actualMissingResolveActions.Count -eq $expectedMissingResolveActions.Count) 'Missing Resolve 动作数量错误或包含矛盾状态'
    for ($index = 0; $index -lt $expectedMissingResolveActions.Count; $index++) {
        Require ($actualMissingResolveActions[$index] -ceq $expectedMissingResolveActions[$index]) "Missing Resolve 动作顺序错误: 索引 $index"
    }
    $expectedMismatchResolveActions = @(
        'PROC_COS_RuntimeDiagnosticSetLast(_Character, _IssueStatus);'
        'PROC_COS_RuntimeDiagnosticSetCurrent(_Character, "COS_DIAG_STATE_CORE_MISMATCH");'
    )
    $actualMismatchResolveActions = @(Get-StoryThenActions -Block $mismatchResolve[0])
    Require ($actualMismatchResolveActions.Count -eq $expectedMismatchResolveActions.Count) 'Mismatch Resolve 动作数量错误或包含矛盾状态'
    for ($index = 0; $index -lt $expectedMismatchResolveActions.Count; $index++) {
        Require ($actualMismatchResolveActions[$index] -ceq $expectedMismatchResolveActions[$index]) "Mismatch Resolve 动作顺序错误: 索引 $index"
    }
    $expectedReadyResolveActions = @(
        'PROC_COS_RuntimeDiagnosticEnsureLast(_Character);'
        'PROC_COS_RuntimeDiagnosticSetCurrent(_Character, "COS_DIAG_STATE_READY");'
    )
    $actualReadyResolveActions = @(Get-StoryThenActions -Block $readyResolve[0])
    Require ($actualReadyResolveActions.Count -eq $expectedReadyResolveActions.Count) 'Ready Resolve 动作数量错误或包含矛盾状态'
    for ($index = 0; $index -lt $expectedReadyResolveActions.Count; $index++) {
        Require ($actualReadyResolveActions[$index] -ceq $expectedReadyResolveActions[$index]) "Ready Resolve 动作顺序错误: 索引 $index"
    }
    $resolveText = ($resolveBlocks.Text) -join "`n"
    foreach ($requiredResolveFragment in @(
        'DB_COS_RuntimeDiagnosticSelected(_Character, "Missing", _IssueStatus)'
        'PROC_COS_RuntimeDiagnosticSetCurrent(_Character, "COS_DIAG_STATE_CONFIG_INCOMPLETE");'
        'DB_COS_RuntimeDiagnosticSelected(_Character, "Mismatch", _IssueStatus)'
        'PROC_COS_RuntimeDiagnosticSetCurrent(_Character, "COS_DIAG_STATE_CORE_MISMATCH");'
        'NOT DB_COS_RuntimeDiagnosticSelected(_Character, _, _)'
        'PROC_COS_RuntimeDiagnosticSetCurrent(_Character, "COS_DIAG_STATE_READY");'
        'PROC_COS_RuntimeDiagnosticEnsureLast(_Character);'
    )) {
        Require ($resolveText.Contains($requiredResolveFragment, [System.StringComparison]::Ordinal)) "Resolve 缺少当前/最近状态规则: $requiredResolveFragment"
    }

    $uiOpenedBlocks = @($allBlocks | Where-Object { $_.Kind -ceq 'IF' -and $_.Text.Contains('DB_COS_ConfigUiOpenedEvent(_Event)', [System.StringComparison]::Ordinal) })
    Require ($uiOpenedBlocks.Count -eq 2) "UI_OPENED 逻辑数量错误: 期望 2，实际 $($uiOpenedBlocks.Count)"
    $nonOriginUi = @($uiOpenedBlocks | Where-Object { $_.Text.Contains('HasPassive(_Character, "COS_ChaosOriginMarker", 0)', [System.StringComparison]::Ordinal) })
    $originUi = @($uiOpenedBlocks | Where-Object { $_.Text.Contains('HasPassive(_Character, "COS_ChaosOriginMarker", 1)', [System.StringComparison]::Ordinal) })
    Require ($nonOriginUi.Count -eq 1 -and $originUi.Count -eq 1) 'UI_OPENED 没有严格分成起源与非起源两条互斥规则'
    $nonOriginThen = @((Get-StoryThenLines -Block $nonOriginUi[0]) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Require ($nonOriginThen.Count -eq 1 -and $nonOriginThen[0].Trim() -ceq 'PROC_COS_RuntimeDiagnosticUpdate(_Character);') '非起源 UI_OPENED 规则必须只更新诊断'
    $originThen = @((Get-StoryThenLines -Block $originUi[0]) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    $expectedOriginThen = @(
        'PROC_COS_RuntimeDiagnosticUpdate(_Character);'
        'PROC_COS_ConfigSyncCharacter(_Character);'
        'PROC_COS_RuntimeDiagnosticUpdate(_Character);'
        'PROC_COS_ShowLastFate(_Character);'
    )
    Require ($originThen.Count -eq $expectedOriginThen.Count) '起源 UI_OPENED 调用数量错误'
    for ($index = 0; $index -lt $expectedOriginThen.Count; $index++) {
        Require ($originThen[$index] -ceq $expectedOriginThen[$index]) "起源 UI_OPENED 调用顺序错误: 索引 $index"
    }

    $knownStatusSet = [System.Collections.Generic.HashSet[string]]::new($KnownDiagnosticStatuses, [System.StringComparer]::Ordinal)
    foreach ($literalStatus in [regex]::Matches(($diagnosticBlocks.Text -join "`n"), '"(COS_DIAG_[A-Z0-9_]+)"')) {
        Require ($knownStatusSet.Contains($literalStatus.Groups[1].Value)) "Story 使用未定义诊断状态: $($literalStatus.Groups[1].Value)"
    }

    @($diagnosticBlocks)
}

function Test-RuntimeDiagnosticStoryContract {
    param(
        [Parameter(Mandatory)] [string]$Content,
        [Parameter(Mandatory)] [psobject[]]$CoreMechanics,
        [Parameter(Mandatory)] [string[]]$RacialKeys,
        [Parameter(Mandatory)] [string[]]$KnownDiagnosticStatuses
    )

    try {
        [void]@(Assert-RuntimeDiagnosticStoryContract -Content $Content -CoreMechanics $CoreMechanics -RacialKeys $RacialKeys -KnownDiagnosticStatuses $KnownDiagnosticStatuses)
        return $true
    }
    catch {
        return $false
    }
}

Require (-not (Test-ExactOrdinalSet -Actual @('cos_ChaosStrike') -Expected @('COS_ChaosStrike'))) '大小写敏感探针失败: ActionResource name'
Require (-not (Test-ExactOrdinalSet -Actual @('origin') -Expected @('Origin'))) '大小写敏感探针失败: grant group'
Require (-not (Test-ExactOrdinalSet -Actual @('mods/ChaosOriginsStory/meta.lsx') -Expected @('Mods/ChaosOriginsStory/meta.lsx'))) '大小写敏感探针失败: manifest path'
$levelGameplayExpectedProbe = [pscustomobject]@{ Entry = 'LevelGameplayStarted'; Status = 'handled'; Handlers = 'all-six-goals'; 'Frozen Behavior' = 'resync-runtime-and-clean-orphan-duality' }
$levelGameplayMutatedProbe = [pscustomobject]@{ Entry = 'LevelGameplayStarted'; Status = 'handled'; Handlers = 'all-six-goals'; 'Frozen Behavior' = 'wrong-behavior' }
Require (-not (Test-ExactLifecycleContractRow -Actual $levelGameplayMutatedProbe -Expected $levelGameplayExpectedProbe)) '生命周期行为变异探针失败: LevelGameplayStarted'

Require (Test-Path -LiteralPath $Root -PathType Container) "缺少根目录: $Root"

$goalRoot = Join-Path $Root 'Mods\ChaosOriginsStory\Story\RawFiles\Goals'
$actionResourcePath = Join-Path $Root 'Public\ChaosOriginsStory\ActionResourceDefinitions\ActionResourceDefinitions.lsx'
$chaosConfigPath = Join-Path $Root 'Public\ChaosOriginsStory\Stats\Generated\Data\ChaosConfig.txt'
$grantMenuPath = Join-Path $Root 'grant-menu.json'
$packageFilesPath = Join-Path $Root 'package-files.json'
$versionPath = Join-Path $Root 'version.json'
$contractPath = Join-Path $Root '..\docs\runtime-contract-1.0.1.97.md'

Require (Test-Path -LiteralPath $goalRoot -PathType Container) "缺少 Goal 目录: $goalRoot"

$expectedGoalNames = @(
    'COS_BaseAfterCreation.txt'
    'COS_ChaosMastery.txt'
    'COS_ChaosMechanics.txt'
    'COS_Config.txt'
    'COS_GlobalPlayerBenefits.txt'
    'COS_OriginStoryRewards.txt'
)

$actualGoalNames = @(Get-ChildItem -LiteralPath $goalRoot -File -Filter '*.txt' | Select-Object -ExpandProperty Name | Sort-Object)
Require ($actualGoalNames.Count -eq 6) "Goal 数量错误: 期望 6，实际 $($actualGoalNames.Count)"
Require (Test-ExactOrdinalSet -Actual $actualGoalNames -Expected $expectedGoalNames) 'Goal name 集合不精确或大小写错误'

$goalTexts = @{}
foreach ($goalName in $expectedGoalNames) {
    Require ($actualGoalNames -ccontains $goalName) "缺少 Goal: $goalName"
    $goalTexts[$goalName] = Get-RequiredText (Join-Path $goalRoot $goalName)
}

$characterLeftPartyCount = 0
foreach ($goalText in $goalTexts.Values) {
    $characterLeftPartyCount += [regex]::Matches($goalText, 'CharacterLeftParty\(').Count
}
Require ($characterLeftPartyCount -eq 0) "生产 Goal 包含 CharacterLeftParty 处理: 实际 $characterLeftPartyCount 处"

$version = Get-RequiredText $versionPath | ConvertFrom-Json
Require ($version.major -eq 1 -and $version.minor -eq 0 -and $version.revision -eq 1) '版本号不是 1.0.1'
Require ($version.lastBuild -eq 97) "version lastBuild 错误: 期望 97，实际 $($version.lastBuild)"

$packageFiles = Get-RequiredText $packageFilesPath | ConvertFrom-Json
$packagedPaths = @($packageFiles.files)
Require ($packagedPaths.Count -eq 38) "package-files 文件数错误: 期望 38，实际 $($packagedPaths.Count)"
Require (Test-ExactOrdinalSet -Actual $packagedPaths -Expected $packagedPaths) 'package-files 包含大小写精确的重复路径'
foreach ($goalName in $expectedGoalNames) {
    $packagedGoal = "Mods/ChaosOriginsStory/Story/RawFiles/Goals/$goalName"
    Require ($packagedPaths -ccontains $packagedGoal) "package-files 缺少 Goal 或路径大小写错误: $packagedGoal"
}

$configGoal = $goalTexts['COS_Config.txt']
$coreMechanics = @(
    [pscustomobject]@{ Key = 'Power';     Mirror = 'COS_CFG_MECH_POWER';     Event = '7f818c10-3f23-49f8-838a-d161c57bb35d' }
    [pscustomobject]@{ Key = 'Wound';     Mirror = 'COS_CFG_MECH_WOUND';     Event = '0574b4b8-549a-4b39-b810-6890c68642b1' }
    [pscustomobject]@{ Key = 'KillPower'; Mirror = 'COS_CFG_MECH_KILLPOWER'; Event = '71abdeef-69d2-4385-8885-4f9ebbd829ca' }
    [pscustomobject]@{ Key = 'Duality';   Mirror = 'COS_CFG_MECH_DUALITY';   Event = 'aa88abcb-5f2e-452c-bdce-3ca6176db1e0' }
    [pscustomobject]@{ Key = 'AllIn';     Mirror = 'COS_CFG_MECH_ALLIN';     Event = '2dd4ef80-1686-4989-8773-3cf6f12b9a36' }
    [pscustomobject]@{ Key = 'Fate';      Mirror = 'COS_CFG_MECH_FATE';      Event = 'aff82c28-d71a-4dad-837d-d41d8519051a' }
    [pscustomobject]@{ Key = 'Genesis';   Mirror = 'COS_CFG_MECH_GENESIS';   Event = '063cc1a5-fe65-43e5-8531-d6974a7b1dce' }
    [pscustomobject]@{ Key = 'Strike';    Mirror = 'COS_CFG_MECH_STRIKE';    Event = '78baf203-f60c-4dac-99ea-a7f5d1339d71' }
    [pscustomobject]@{ Key = 'Mastery';   Mirror = 'COS_CFG_MECH_MASTERY';   Event = '146d28dc-aa94-40e8-9bad-91b069055526' }
)

$expectedCoreKeys = @($coreMechanics.Key)
$mechanicDefaultMatches = [regex]::Matches($configGoal, '(?m)^DB_COS_ConfigMechanicDefault\("([^"]+)",\s*[^)]+\);\r?$')
$mechanicMirrorMatches = [regex]::Matches($configGoal, '(?m)^DB_COS_ConfigMechanicMirror\("([^"]+)",\s*"[^"]+"\);\r?$')
$mechanicEventMatches = [regex]::Matches($configGoal, '(?m)^DB_COS_ConfigMechanicEvent\(\(TUTORIALEVENT\)[^,]+,\s*"([^"]+)"\);\r?$')

Require ($mechanicDefaultMatches.Count -eq 9) "核心机制默认映射数量错误: 期望 9，实际 $($mechanicDefaultMatches.Count)"
Require ($mechanicMirrorMatches.Count -eq 9) "核心机制镜像映射数量错误: 期望 9，实际 $($mechanicMirrorMatches.Count)"
Require ($mechanicEventMatches.Count -eq 9) "核心机制 TutorialEvent 映射数量错误: 期望 9，实际 $($mechanicEventMatches.Count)"

$actualDefaultKeys = @($mechanicDefaultMatches | ForEach-Object { $_.Groups[1].Value })
$actualMirrorKeys = @($mechanicMirrorMatches | ForEach-Object { $_.Groups[1].Value })
$actualEventKeys = @($mechanicEventMatches | ForEach-Object { $_.Groups[1].Value })
Require (Test-ExactOrdinalSet -Actual $actualDefaultKeys -Expected $expectedCoreKeys) '核心机制默认映射 key 集合不精确或大小写错误'
Require (Test-ExactOrdinalSet -Actual $actualMirrorKeys -Expected $expectedCoreKeys) '核心机制镜像映射 key 集合不精确或大小写错误'
Require (Test-ExactOrdinalSet -Actual $actualEventKeys -Expected $expectedCoreKeys) '核心机制 TutorialEvent 映射 key 集合不精确或大小写错误'

foreach ($mechanic in $coreMechanics) {
    $defaultLine = "DB_COS_ConfigMechanicDefault(`"$($mechanic.Key)`", 1);"
    $mirrorLine = "DB_COS_ConfigMechanicMirror(`"$($mechanic.Key)`", `"$($mechanic.Mirror)`");"
    $eventIdentifier = "$($mechanic.Mirror)_$($mechanic.Event)"
    $eventLine = "DB_COS_ConfigMechanicEvent((TUTORIALEVENT)$eventIdentifier, `"$($mechanic.Key)`");"
    Require ($configGoal.Contains($defaultLine)) "核心机制默认值错误或缺失: $($mechanic.Key)"
    Require ($configGoal.Contains($mirrorLine)) "核心机制镜像错误或缺失: $($mechanic.Key)"
    Require ($configGoal.Contains($eventLine)) "核心机制 TutorialEvent 错误或缺失: $($mechanic.Key)"
}

Require ($configGoal.Contains('DB_COS_ConfigLifeDefault(5);')) '生活加值默认值不是 5'
Require ($configGoal.Contains('IntegerMax(_RawValue, 0, _FloorValue)')) '生活加值缺少下限 0'
Require ($configGoal.Contains('IntegerMin(_FloorValue, 20, _Value)')) '生活加值缺少上限 20'

$expectedRacialDefaults = @(
    'DeepGnome_StoneCamouflage'
    'Drow_DrowWeaponTraining'
    'Duergar_DuergarResilience'
    'Dwarf_DwarvenCombatTraining'
    'Dwarf_DwarvenResilience'
    'Elf_WeaponTraining'
    'FeyAncestry'
    'Gith_MartialProdigy'
    'Gnome_Cunning'
    'Halfling_Brave'
    'Halfling_LightfootStealth'
    'Halfling_Lucky'
    'Halfling_StoutResilience'
    'HumanMilitia'
    'MountainDwarf_DwarvenArmorTraining'
    'RelentlessEndurance'
    'RockGnome_ArtificersLore'
    'SavageAttacks'
    'SuperiorDarkvision'
    'Tiefling_HellishResistance'
)

$racialDefaultMatches = [regex]::Matches($configGoal, '(?m)^DB_COS_ConfigRacialDefault\("([^"]+)",\s*(-?\d+)\);\r?$')
Require ($racialDefaultMatches.Count -eq 20) "官方种族被动默认项数量错误: 期望 20，实际 $($racialDefaultMatches.Count)"
$actualRacialNames = @($racialDefaultMatches | ForEach-Object { $_.Groups[1].Value })
$actualRacialPairs = @($racialDefaultMatches | ForEach-Object { "$($_.Groups[1].Value)`t$($_.Groups[2].Value)" })
$expectedRacialPairs = @($expectedRacialDefaults | ForEach-Object { "$_`t0" })
Require (Test-ExactOrdinalSet -Actual $actualRacialNames -Expected $expectedRacialDefaults) '官方种族被动 name 集合不精确、包含重复项或大小写错误'
Require (Test-ExactOrdinalSet -Actual $actualRacialPairs -Expected $expectedRacialPairs) '官方种族被动 (Name,0) 集合不精确'

$grantMenu = @(Get-RequiredText $grantMenuPath | ConvertFrom-Json)
Require ($grantMenu.Count -eq 74) "grant-menu 项目数错误: 期望 74，实际 $($grantMenu.Count)"
Require (Test-ExactOrdinalSet -Actual @($grantMenu.key) -Expected @($grantMenu.key)) 'grant-menu 包含大小写精确的重复 key'
$expectedGrantGroups = [ordered]@{
    Origin = 7
    Tag = 31
    Weapon = 31
    Armor = 4
    Instrument = 1
}
$actualGrantGroups = @($grantMenu | Group-Object group -CaseSensitive)
Require ($actualGrantGroups.Count -eq 5) "grant-menu 分组数错误: 期望 5，实际 $($actualGrantGroups.Count)"
Require (Test-ExactOrdinalSet -Actual @($actualGrantGroups.Name) -Expected @($expectedGrantGroups.Keys)) 'grant-menu group 集合不精确或大小写错误'
foreach ($groupName in $expectedGrantGroups.Keys) {
    $actualGroup = $actualGrantGroups | Where-Object Name -ceq $groupName
    Require ($null -ne $actualGroup) "grant-menu 缺少分组: $groupName"
    Require ($actualGroup.Count -eq $expectedGrantGroups[$groupName]) "grant-menu 分组数量错误: $groupName 期望 $($expectedGrantGroups[$groupName])，实际 $($actualGroup.Count)"
}

[xml]$actionResourceXml = Get-RequiredText $actionResourcePath
$actionResourceNodes = @($actionResourceXml.SelectNodes('//node[@id="ActionResourceDefinition"]'))
$actionResourceNames = @(
    $actionResourceNodes | ForEach-Object {
        $nameNode = $_.SelectSingleNode('./attribute[@id="Name"]')
        Require ($null -ne $nameNode) 'ActionResourceDefinition 缺少 Name 属性'
        $nameNode.GetAttribute('value')
    }
)
$expectedActionResources = @(
    'COS_ChaosStrike'
    'COS_ChaosAllInUse'
    'COS_ChaosPowerPoint'
    'COS_ChaosMasteryPoint'
    'COS_ConfigLifeSkill'
    'COS_ConfigFateCost'
    'COS_ConfigGenesisCost'
)
Require ($actionResourceNames.Count -eq 7) "ActionResource 数量错误: 期望 7，实际 $($actionResourceNames.Count)"
Require (Test-ExactOrdinalSet -Actual $actionResourceNames -Expected $expectedActionResources) 'ActionResource Name 集合不精确、包含重复项或大小写错误'

$contract = Get-RequiredText $contractPath
Require ($contract.Contains('ChaosOriginsStory 1.0.1.97')) '运行合同缺少版本 1.0.1.97'
Require ($contract.Contains('lastBuild = 97')) '运行合同缺少 lastBuild = 97'
Require ($contract.Contains('38 个唯一文件')) '运行合同缺少 package-files 38 个唯一文件'
foreach ($goalName in $expectedGoalNames) {
    Require ($contract.Contains($goalName)) "运行合同缺少 Goal: $goalName"
}

$coreContractRows = @(Get-MarkdownTableRows -Content $contract -Heading '## 九个核心配置键')
Require ($coreContractRows.Count -eq 9) "运行合同核心配置表行数错误: 期望 9，实际 $($coreContractRows.Count)"
Require (Test-ExactOrdinalSet -Actual @($coreContractRows[0].PSObject.Properties.Name) -Expected @('Key', 'Default', 'Mirror', 'Event')) '运行合同核心配置表列不精确或大小写错误'
Require (Test-ExactOrdinalSet -Actual @($coreContractRows.Key) -Expected $expectedCoreKeys) '运行合同核心配置 Key 集合不精确、包含重复项或大小写错误'
foreach ($mechanic in $coreMechanics) {
    $eventIdentifier = "$($mechanic.Mirror)_$($mechanic.Event)"
    $matchingRows = @($coreContractRows | Where-Object { $_.Key -ceq $mechanic.Key })
    Require ($matchingRows.Count -eq 1) "运行合同核心配置表缺少唯一行: $($mechanic.Key)"
    Require ($matchingRows[0].Default -ceq '1') "运行合同核心默认值错误: $($mechanic.Key)"
    Require ($matchingRows[0].Mirror -ceq $mechanic.Mirror) "运行合同核心镜像错误: $($mechanic.Key)"
    Require ($matchingRows[0].Event -ceq $eventIdentifier) "运行合同核心 TutorialEvent 错误: $($mechanic.Key)"
}

$expectedLifeSkills = @(
    'AnimalHandling'
    'Arcana'
    'Deception'
    'History'
    'Insight'
    'Intimidation'
    'Investigation'
    'Medicine'
    'Nature'
    'Perception'
    'Performance'
    'Persuasion'
    'Religion'
    'SleightOfHand'
    'Stealth'
    'Survival'
)
Require ($contract.Contains('生活加值默认 5，范围 0..20，仅作用于 16 个生活技能')) '运行合同缺少生活加值默认值、范围或技能数量'
foreach ($lifeSkill in $expectedLifeSkills) {
    Require ($contract.Contains("``$lifeSkill``")) "运行合同缺少生活技能: $lifeSkill"
}
Require ($contract.Contains('明确排除 `Athletics` 与 `Acrobatics`')) '运行合同没有明确排除 Athletics 与 Acrobatics'

foreach ($racialPassive in $expectedRacialDefaults) {
    Require ($contract.Contains("``$racialPassive``")) "运行合同缺少官方种族被动: $racialPassive"
}
Require ($contract.Contains('20 个官方种族被动默认均为 0')) '运行合同缺少 20 个官方种族被动的默认值'

$grantContractRows = @(Get-MarkdownTableRows -Content $contract -Heading '## grant 菜单合同')
Require ($grantContractRows.Count -eq 5) "运行合同 grant group 表行数错误: 期望 5，实际 $($grantContractRows.Count)"
Require (Test-ExactOrdinalSet -Actual @($grantContractRows[0].PSObject.Properties.Name) -Expected @('Group', 'Count')) '运行合同 grant group 表列不精确或大小写错误'
Require (Test-ExactOrdinalSet -Actual @($grantContractRows.Group) -Expected @($expectedGrantGroups.Keys)) '运行合同 grant group 集合不精确、包含重复项或大小写错误'
foreach ($groupName in $expectedGrantGroups.Keys) {
    $matchingRows = @($grantContractRows | Where-Object { $_.Group -ceq $groupName })
    Require ($matchingRows.Count -eq 1) "运行合同缺少唯一 grant group 行: $groupName"
    Require ($matchingRows[0].Count -ceq "$($expectedGrantGroups[$groupName])") "运行合同 grant group 数量错误: $groupName"
}
Require ($contract.Contains('grant-menu.json` 共 74 项')) '运行合同缺少 grant-menu 总数 74'

$actionResourceContractRows = @(Get-MarkdownTableRows -Content $contract -Heading '## ActionResource 合同')
Require ($actionResourceContractRows.Count -eq 7) "运行合同 ActionResource 表行数错误: 期望 7，实际 $($actionResourceContractRows.Count)"
Require (Test-ExactOrdinalSet -Actual @($actionResourceContractRows[0].PSObject.Properties.Name) -Expected @('Name')) '运行合同 ActionResource 表列不精确或大小写错误'
Require (Test-ExactOrdinalSet -Actual @($actionResourceContractRows.Name) -Expected $expectedActionResources) '运行合同 ActionResource Name 集合不精确、包含重复项或大小写错误'

foreach ($marker in @('DB_COS_MasterySchema46To47', 'COS_CHAOS_FATE_PENDING', 'PROC_COS_SeedGrantMap')) {
    Require ($contract.Contains($marker)) "运行合同缺少旧档或运行时 seed 标识: $marker"
}

$expectedLifecycleRows = @(
    [pscustomobject]@{ Entry = 'CharacterCreationFinished'; Status = 'handled';     Handlers = 'COS_BaseAfterCreation.txt';                                                                                                                                                'Frozen Behavior' = 'seed-new-character-starting-bag-eligibility' }
    [pscustomobject]@{ Entry = 'LevelGameplayStarted';       Status = 'handled';     Handlers = 'COS_BaseAfterCreation.txt, COS_ChaosMastery.txt, COS_ChaosMechanics.txt, COS_Config.txt, COS_GlobalPlayerBenefits.txt, COS_OriginStoryRewards.txt'; 'Frozen Behavior' = 'resync-runtime-and-clean-orphan-duality' }
    [pscustomobject]@{ Entry = 'GainedControl';               Status = 'handled';     Handlers = 'COS_BaseAfterCreation.txt, COS_ChaosMastery.txt, COS_ChaosMechanics.txt, COS_Config.txt, COS_GlobalPlayerBenefits.txt, COS_OriginStoryRewards.txt'; 'Frozen Behavior' = 'resync-on-control-change' }
    [pscustomobject]@{ Entry = 'CharacterJoinedParty';        Status = 'handled';     Handlers = 'COS_ChaosMechanics.txt, COS_GlobalPlayerBenefits.txt';                                                                                                           'Frozen Behavior' = 'resync-mechanics-and-carry' }
    [pscustomobject]@{ Entry = 'LeveledUp';                   Status = 'handled';     Handlers = 'COS_BaseAfterCreation.txt, COS_ChaosMastery.txt, COS_ChaosMechanics.txt, COS_Config.txt';                                                                         'Frozen Behavior' = 'resync-base-mastery-mechanics-config' }
    [pscustomobject]@{ Entry = 'RespecCompleted';             Status = 'handled';     Handlers = 'COS_BaseAfterCreation.txt, COS_ChaosMastery.txt, COS_Config.txt, COS_GlobalPlayerBenefits.txt';                                                                  'Frozen Behavior' = 'resync-base-config-carry-reset-mastery' }
    [pscustomobject]@{ Entry = 'Resurrected';                 Status = 'handled';     Handlers = 'COS_Config.txt';                                                                                                                                                            'Frozen Behavior' = 'sync-volo-eye' }
    [pscustomobject]@{ Entry = 'PROC_LongRest';               Status = 'handled';     Handlers = 'COS_Config.txt';                                                                                                                                                            'Frozen Behavior' = 'sync-volo-eye-for-avatars' }
    [pscustomobject]@{ Entry = 'CharacterLeftParty';          Status = 'not-handled'; Handlers = 'none';                                                                                                                                                                      'Frozen Behavior' = 'no-handler' }
)
$lifecycleContractRows = @(Get-MarkdownTableRows -Content $contract -Heading '## 生命周期矩阵')
Require ($lifecycleContractRows.Count -eq 9) "运行合同生命周期表行数错误: 期望 9，实际 $($lifecycleContractRows.Count)"
Require (Test-ExactOrdinalSet -Actual @($lifecycleContractRows[0].PSObject.Properties.Name) -Expected @('Entry', 'Status', 'Handlers', 'Frozen Behavior')) '运行合同生命周期表列不精确或大小写错误'
Require (Test-ExactOrdinalSet -Actual @($lifecycleContractRows.Entry) -Expected @($expectedLifecycleRows.Entry)) '运行合同生命周期 Entry 集合不精确、包含重复项或大小写错误'
foreach ($expectedLifecycleRow in $expectedLifecycleRows) {
    $matchingRows = @($lifecycleContractRows | Where-Object { $_.Entry -ceq $expectedLifecycleRow.Entry })
    Require ($matchingRows.Count -eq 1) "运行合同生命周期表缺少唯一行: $($expectedLifecycleRow.Entry)"
    Require (Test-ExactLifecycleContractRow -Actual $matchingRows[0] -Expected $expectedLifecycleRow) "运行合同生命周期逐字段错误: $($expectedLifecycleRow.Entry)"
}
Require ($contract.Contains('当前没有 `CharacterLeftParty` 处理')) '运行合同缺少 CharacterLeftParty 的证据边界'

foreach ($unacceptedScenario in @('旧档升级', '离队重入', '多人主控切换', '手柄页', '重复打开菜单性能')) {
    Require ($contract.Contains($unacceptedScenario)) "运行合同缺少未经实机验收项: $unacceptedScenario"
}

$validDiagnosticProbe = [pscustomobject]@{
    Name = 'COS_DIAG_STATE_PROBE'
    Lines = @(
        'type "StatusData"'
        'data "StatusType" "BOOST"'
        'data "DisplayName" "hprobe-name;1"'
        'data "Description" "hprobe-description;1"'
        'data "Icon" "PassiveFeature_Generic_Threat"'
        'data "StackId" "COS_RUNTIME_DIAGNOSTIC_STATE"'
        'data "StackType" "Overwrite"'
        'data "StatusPropertyFlags" "DisableOverhead;DisableCombatlog;DisablePortraitIndicator;IgnoreResting"'
    )
}
Require (Test-DiagnosticStatusEntryContract -Entry $validDiagnosticProbe -ExpectedStackId 'COS_RUNTIME_DIAGNOSTIC_STATE') '运行诊断状态有效样本探针失败'
$boostsMutationProbe = [pscustomobject]@{
    Name = $validDiagnosticProbe.Name
    Lines = @($validDiagnosticProbe.Lines) + 'data "Boosts" "Ability(Strength,1)"'
}
Require (-not (Test-DiagnosticStatusEntryContract -Entry $boostsMutationProbe -ExpectedStackId 'COS_RUNTIME_DIAGNOSTIC_STATE')) '运行诊断状态 Boosts 变异探针失败'
$missingPortraitFlagMutationProbe = [pscustomobject]@{
    Name = $validDiagnosticProbe.Name
    Lines = @($validDiagnosticProbe.Lines | ForEach-Object { $_.Replace('DisablePortraitIndicator;', '') })
}
Require (-not (Test-DiagnosticStatusEntryContract -Entry $missingPortraitFlagMutationProbe -ExpectedStackId 'COS_RUNTIME_DIAGNOSTIC_STATE')) '运行诊断状态缺少 DisablePortraitIndicator 变异探针失败'

$localizationCoverageProbe = [ordered]@{
    Chinese = @('hprobe-a', 'hprobe-b')
    English = @('hprobe-a', 'hprobe-b')
    Japanese = @('hprobe-a', 'hprobe-b')
    Korean = @('hprobe-a', 'hprobe-b')
}
Require (Test-LocalizationHandleCoverage -HandlesByLanguage $localizationCoverageProbe -RequiredHandles @('hprobe-a', 'hprobe-b')) '本地化 handle 有效样本探针失败'
$deletedLocalizationHandleMutationProbe = [ordered]@{
    Chinese = @('hprobe-a')
    English = @('hprobe-a', 'hprobe-b')
    Japanese = @('hprobe-a', 'hprobe-b')
    Korean = @('hprobe-a', 'hprobe-b')
}
Require (-not (Test-LocalizationHandleCoverage -HandlesByLanguage $deletedLocalizationHandleMutationProbe -RequiredHandles @('hprobe-a', 'hprobe-b'))) '单语言删除 handle 变异探针失败'
$unequalLocalizationSetMutationProbe = [ordered]@{
    Chinese = @('hprobe-a', 'hprobe-b', 'hprobe-extra')
    English = @('hprobe-a', 'hprobe-b')
    Japanese = @('hprobe-a', 'hprobe-b')
    Korean = @('hprobe-a', 'hprobe-b')
}
Require (-not (Test-LocalizationHandleSetsEqual -HandlesByLanguage $unequalLocalizationSetMutationProbe)) '四语 handle 集合不一致变异探针失败'

$chaosConfig = Get-RequiredText $chaosConfigPath
$expectedStateStatuses = @(
    'COS_DIAG_STATE_NOT_ORIGIN'
    'COS_DIAG_STATE_CONFIG_INCOMPLETE'
    'COS_DIAG_STATE_CORE_MISMATCH'
    'COS_DIAG_STATE_READY'
)
$expectedLastStatuses = @(
    'COS_DIAG_LAST_NONE'
    'COS_DIAG_LAST_MISSING_POWER'
    'COS_DIAG_LAST_MISSING_WOUND'
    'COS_DIAG_LAST_MISSING_KILLPOWER'
    'COS_DIAG_LAST_MISSING_DUALITY'
    'COS_DIAG_LAST_MISSING_ALLIN'
    'COS_DIAG_LAST_MISSING_FATE'
    'COS_DIAG_LAST_MISSING_GENESIS'
    'COS_DIAG_LAST_MISSING_STRIKE'
    'COS_DIAG_LAST_MISSING_MASTERY'
    'COS_DIAG_LAST_MISSING_LIFE'
    'COS_DIAG_LAST_MISSING_FATE_COST'
    'COS_DIAG_LAST_MISSING_GENESIS_COST'
    'COS_DIAG_LAST_MISSING_RACIAL'
    'COS_DIAG_LAST_MISSING_GRANT'
    'COS_DIAG_LAST_MISSING_TAG_SPELLS'
    'COS_DIAG_LAST_MISSING_VOLO'
    'COS_DIAG_LAST_MISSING_CARRY'
    'COS_DIAG_LAST_MISMATCH_POWER'
    'COS_DIAG_LAST_MISMATCH_WOUND'
    'COS_DIAG_LAST_MISMATCH_KILLPOWER'
    'COS_DIAG_LAST_MISMATCH_DUALITY'
    'COS_DIAG_LAST_MISMATCH_ALLIN'
    'COS_DIAG_LAST_MISMATCH_FATE'
    'COS_DIAG_LAST_MISMATCH_GENESIS'
    'COS_DIAG_LAST_MISMATCH_STRIKE'
    'COS_DIAG_LAST_MISMATCH_MASTERY'
    'COS_DIAG_LAST_MISMATCH_CARRY'
)
$expectedDiagnosticStatuses = @($expectedStateStatuses) + @($expectedLastStatuses)

$diagnosticEntries = @(Assert-DiagnosticStatusSourceContract -Content $chaosConfig -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses)
$readySourceBlock = Get-StatsEntrySourceBlock -Content $chaosConfig -EntryName 'COS_DIAG_STATE_READY'
Require ($readySourceBlock.Contains('new entry "COS_DIAG_STATE_READY"')) '变异探针没有取得真实 READY block'

$usingMutationSource = Add-StatsEntryLineForProbe -Content $chaosConfig -EntryName 'COS_DIAG_STATE_READY' -Line 'using "SOME_STATUS"'
Require (-not (Test-DiagnosticStatusSourceContract -Content $usingMutationSource -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses)) '真实 READY block using 注入变异探针失败'

$extraFieldMutationSource = Add-StatsEntryLineForProbe -Content $chaosConfig -EntryName 'COS_DIAG_STATE_READY' -Line 'data "UnexpectedField" "unexpected"'
Require (-not (Test-DiagnosticStatusSourceContract -Content $extraFieldMutationSource -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses)) '真实 READY block 额外字段变异探针失败'

$caseVariantBlock = $readySourceBlock.Replace('new entry "COS_DIAG_STATE_READY"', 'new entry "cos_diag_state_ready"')
Require ($caseVariantBlock -cne $readySourceBlock) '小写诊断 entry 变异未生效'
$caseVariantMutationSource = $chaosConfig + "`n" + $caseVariantBlock
Require (-not (Test-DiagnosticStatusSourceContract -Content $caseVariantMutationSource -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses)) '小写 COS_DIAG_ entry 完整管线变异探针失败'

$readyEntry = @($diagnosticEntries | Where-Object { $_.Name -ceq 'COS_DIAG_STATE_READY' })[0]
$readyFields = Get-StatsEntryDataFields $readyEntry
$readyDisplayName = $readyFields.DisplayName
$readyDisplayNameWithoutVersion = Get-UnversionedStatsHandle -Value $readyDisplayName -Context 'COS_DIAG_STATE_READY.DisplayName'
$missingHandleVersionMutationSource = $chaosConfig.Replace(
    "data `"DisplayName`" `"$readyDisplayName`"",
    "data `"DisplayName`" `"$readyDisplayNameWithoutVersion`""
)
Require ($missingHandleVersionMutationSource -cne $chaosConfig) '漏 ;1 变异未生效'
Require (-not (Test-DiagnosticStatusSourceContract -Content $missingHandleVersionMutationSource -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses)) '真实 READY block 漏 ;1 变异探针失败'

$diagnosticHandles = [System.Collections.Generic.List[string]]::new()
foreach ($status in $expectedDiagnosticStatuses) {
    $entry = @($diagnosticEntries | Where-Object { $_.Name -ceq $status })[0]
    $expectedStackId = if ($expectedStateStatuses -ccontains $status) { 'COS_RUNTIME_DIAGNOSTIC_STATE' } else { 'COS_RUNTIME_DIAGNOSTIC_LAST' }
    Require (Test-DiagnosticStatusEntryContract -Entry $entry -ExpectedStackId $expectedStackId) "运行诊断状态定义错误: $status"

    $fields = Get-StatsEntryDataFields $entry
    foreach ($handleField in @('DisplayName', 'Description')) {
        $handle = Get-UnversionedStatsHandle -Value $fields[$handleField] -Context "$status.$handleField"
        $diagnosticHandles.Add($handle)
    }
}
Require ($diagnosticHandles.Count -eq 64) "运行诊断状态 handle 数量错误: 期望 64，实际 $($diagnosticHandles.Count)"
Require (Test-ExactOrdinalSet -Actual @($diagnosticHandles.ToArray()) -Expected @($diagnosticHandles.ToArray())) '运行诊断状态 DisplayName/Description handle 包含重复项'

$uiHandles = [ordered]@{
    RuntimeDiagnosticTitle = 'h8f100001g0000g4000g8000g000000000001'
    StaticVersion = 'h8f100002g0000g4000g8000g000000000002'
    CurrentStateTitle = 'h8f100003g0000g4000g8000g000000000003'
    LastSyncIssueTitle = 'h8f100004g0000g4000g8000g000000000004'
    ChaosPowerPoints = 'h8f100005g0000g4000g8000g000000000005'
    RemainingMasteryPoints = 'h8f100006g0000g4000g8000g000000000006'
    UsedMasteryExplanation = 'h8f100007g0000g4000g8000g000000000007'
}
$requiredLocalizationHandles = @($diagnosticHandles.ToArray()) + @($uiHandles.Values)
Require ($requiredLocalizationHandles.Count -eq 71) "运行诊断本地化 handle 数量错误: 期望 71，实际 $($requiredLocalizationHandles.Count)"
Require (Test-ExactOrdinalSet -Actual $requiredLocalizationHandles -Expected $requiredLocalizationHandles) '运行诊断本地化 handle 包含重复项'

$localizationPaths = [ordered]@{
    Chinese = Join-Path $Root 'Localization\Chinese\ChaosOriginsStory.xml'
    English = Join-Path $Root 'Localization\English\ChaosOriginsStory.xml'
    Japanese = Join-Path $Root 'Localization\Japanese\ChaosOriginsStory.xml'
    Korean = Join-Path $Root 'Localization\Korean\ChaosOriginsStory.xml'
}
$localizationHandlesByLanguage = [ordered]@{}
$localizationNodesByLanguage = [ordered]@{}
foreach ($language in $localizationPaths.Keys) {
    [xml]$localizationXml = Get-RequiredText $localizationPaths[$language]
    $contentNodes = @($localizationXml.SelectNodes('/contentList/content'))
    $localizationNodesByLanguage[$language] = $contentNodes
    $localizationHandlesByLanguage[$language] = @($contentNodes | ForEach-Object { $_.GetAttribute('contentuid') })
}

Require (Test-LocalizationHandleCoverage -HandlesByLanguage $localizationHandlesByLanguage -RequiredHandles $requiredLocalizationHandles) '四语未各自唯一覆盖全部运行诊断 handle'
Require (Test-LocalizationHandleSetsEqual -HandlesByLanguage $localizationHandlesByLanguage) '四语 handle 集合不一致'

foreach ($language in $localizationPaths.Keys) {
    $contentNodes = @($localizationNodesByLanguage[$language])
    foreach ($handle in $requiredLocalizationHandles) {
        $matchingNodes = @($contentNodes | Where-Object { $_.GetAttribute('contentuid') -ceq $handle })
        Require ($matchingNodes.Count -eq 1) "本地化 handle 未恰好出现一次: $language $handle"
        $localizedText = $matchingNodes[0].InnerText
        Require (-not [string]::IsNullOrWhiteSpace($localizedText)) "本地化文本为空: $language $handle"
        Require (-not [regex]::IsMatch($localizedText, '(?i)\bNot Found\b')) "本地化包含 Not Found: $language $handle"
    }

    $staticVersionNode = @($contentNodes | Where-Object { $_.GetAttribute('contentuid') -ceq $uiHandles.StaticVersion })[0]
    Require ($staticVersionNode.InnerText -ceq 'ChaosOriginsStory 1.0.1.98') "静态版本文本错误: $language"
}

Write-Output "Runtime diagnostic status count: $($diagnosticEntries.Count)"
Write-Output "Runtime diagnostic localization handle count: $($requiredLocalizationHandles.Count)"

$diagnosticStoryBlocks = @(Assert-RuntimeDiagnosticStoryContract -Content $configGoal -CoreMechanics $coreMechanics -RacialKeys $expectedRacialDefaults -KnownDiagnosticStatuses $expectedDiagnosticStatuses)

$diagnosticActionMutationAnchor = 'DB_COS_RuntimeDiagnosticCore("Power", "COS_CFG_MECH_POWER", "COS_DIAG_LAST_MISSING_POWER", "COS_DIAG_LAST_MISMATCH_POWER");'
$forbiddenDiagnosticActionProbes = [ordered]@{
    PartyIncreaseActionResourceValue = 'PartyIncreaseActionResourceValue(_Character, "COS_ChaosPowerPoint", 1.0);'
    ConfigApplyMechanic = 'PROC_COS_ConfigApplyMechanic(_Character, "Power", 1);'
    SyncGlobalPlayerBenefits = 'PROC_COS_SyncGlobalPlayerBenefits(_Character);'
    CharacterSetHitpoints = 'CharacterSetHitpoints(_Character, 1);'
    NonDiagnosticStatus = 'ApplyStatus(_Character, "BURNING", -1.0, 1, _Character);'
}
foreach ($probeName in $forbiddenDiagnosticActionProbes.Keys) {
    $probeAction = $forbiddenDiagnosticActionProbes[$probeName]
    $gameplayMutationSource = $configGoal.Replace($diagnosticActionMutationAnchor, "$diagnosticActionMutationAnchor`n$probeAction")
    Require ($gameplayMutationSource -cne $configGoal) "诊断 THEN 白名单变异未生效: $probeName"
    Require (-not (Test-RuntimeDiagnosticStoryContract -Content $gameplayMutationSource -CoreMechanics $coreMechanics -RacialKeys $expectedRacialDefaults -KnownDiagnosticStatuses $expectedDiagnosticStatuses)) "诊断 THEN 白名单变异探针失败: $probeName"
}

$selectionGuardMutationSource = $configGoal.Replace('NOT DB_COS_RuntimeDiagnosticSelected(_Character, _, _)', 'DB_COS_RuntimeDiagnosticMutationProbe(_Character)')
Require ($selectionGuardMutationSource -cne $configGoal) 'SelectFirst 门控删除变异未生效'
Require (-not (Test-RuntimeDiagnosticStoryContract -Content $selectionGuardMutationSource -CoreMechanics $coreMechanics -RacialKeys $expectedRacialDefaults -KnownDiagnosticStatuses $expectedDiagnosticStatuses)) 'SelectFirst 门控删除变异探针失败'

$powerMismatchCall = 'PROC_COS_RuntimeDiagnosticCheckCoreMismatch(_Character, "Power", "COS_CFG_MECH_POWER", "COS_DIAG_LAST_MISMATCH_POWER");'
$mismatchMutationSource = $configGoal.Replace($powerMismatchCall, '// removed by mutation probe')
Require ($mismatchMutationSource -cne $configGoal) '核心 mismatch 删除变异未生效'
Require (-not (Test-RuntimeDiagnosticStoryContract -Content $mismatchMutationSource -CoreMechanics $coreMechanics -RacialKeys $expectedRacialDefaults -KnownDiagnosticStatuses $expectedDiagnosticStatuses)) '核心 mismatch 删除变异探针失败'

$conflictingResolveRule = @'
PROC
PROC_COS_RuntimeDiagnosticResolve((CHARACTER)_Character)
AND
DB_COS_RuntimeDiagnosticSelected(_Character, "Missing", _IssueStatus)
THEN
PROC_COS_RuntimeDiagnosticSetCurrent(_Character, "COS_DIAG_STATE_READY");

'@
$resolveRuleMutationSource = [regex]::Replace(
    $configGoal,
    '(?m)^EXITSECTION\r?\nENDEXITSECTION\s*$',
    "$conflictingResolveRule`nEXITSECTION`nENDEXITSECTION",
    1
)
Require ($resolveRuleMutationSource -cne $configGoal) 'Missing 追加 READY Resolve 规则变异未生效'
Require (-not (Test-RuntimeDiagnosticStoryContract -Content $resolveRuleMutationSource -CoreMechanics $coreMechanics -RacialKeys $expectedRacialDefaults -KnownDiagnosticStatuses $expectedDiagnosticStatuses)) 'Missing 追加 READY Resolve 规则变异探针失败'

$missingResolveConditionAnchor = @'
DB_COS_RuntimeDiagnosticSelected(_Character, "Missing", _IssueStatus)
THEN
'@
$missingResolveBlockingCondition = @'
DB_COS_RuntimeDiagnosticSelected(_Character, "Missing", _IssueStatus)
AND
IsInCombat(_Character, 1)
THEN
'@
$resolveConditionMutationSource = $configGoal.Replace($missingResolveConditionAnchor, $missingResolveBlockingCondition)
Require ($resolveConditionMutationSource -cne $configGoal) 'Missing Resolve 追加 IsInCombat 条件变异未生效'
Require (-not (Test-RuntimeDiagnosticStoryContract -Content $resolveConditionMutationSource -CoreMechanics $coreMechanics -RacialKeys $expectedRacialDefaults -KnownDiagnosticStatuses $expectedDiagnosticStatuses)) 'Missing Resolve 追加 IsInCombat 条件变异探针失败'

Write-Output "Runtime diagnostic Story block count: $($diagnosticStoryBlocks.Count)"
Write-Output 'Runtime diagnostic Story mutations: then-allowlist=5/5 PASS; selection=PASS; mismatch=PASS; resolve-conflict=PASS; resolve-condition=PASS'

$keyboardPagePath = Join-Path $Root 'Mods\ChaosOriginsStory\GUI\Pages\COS_ConfigMenu.xaml'
$controllerPagePath = Join-Path $Root 'Mods\ChaosOriginsStory\GUI\Pages\COS_ConfigMenu_c.xaml'
$keyboardPageContent = Get-RequiredText $keyboardPagePath
$controllerPageContent = Get-RequiredText $controllerPagePath
$expectedUiHandleValues = @($uiHandles.Values)

$keyboardUiContract = Assert-RuntimeDiagnosticUiPageContract -Content $keyboardPageContent -PageName 'COS_ConfigMenu.xaml' -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses -ExpectedUiHandles $expectedUiHandleValues
$controllerUiContract = Assert-RuntimeDiagnosticUiPageContract -Content $controllerPageContent -PageName 'COS_ConfigMenu_c.xaml' -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses -ExpectedUiHandles $expectedUiHandleValues
Require ($keyboardUiContract.PanelOuterXml -ceq $controllerUiContract.PanelOuterXml) '键鼠与手柄运行诊断面板结构、ID、handle 或过滤集合发生漂移'

[xml]$missingPanelDocument = $keyboardPageContent
$missingPanel = @(Get-XamlNamedNodes -Document $missingPanelDocument -Name 'COSRuntimeDiagnosticPanel')[0]
[void]$missingPanel.ParentNode.RemoveChild($missingPanel)
Require (-not (Test-RuntimeDiagnosticUiPageContract -Content $missingPanelDocument.OuterXml -PageName 'missing-panel-probe' -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses -ExpectedUiHandles $expectedUiHandleValues)) '删除诊断面板变异探针失败'

[xml]$extraStateDocument = $keyboardPageContent
$stateControl = @(Get-XamlNamedNodes -Document $extraStateDocument -Name 'COSRuntimeDiagnosticState')[0]
$stateTrigger = @($stateControl.SelectNodes('.//*[local-name()="DataTrigger"]'))[0]
$extraStateTrigger = $stateTrigger.CloneNode($true)
$extraStateTrigger.SetAttribute('Value', 'COS_DIAG_STATE_UNAPPROVED')
[void]$stateTrigger.ParentNode.AppendChild($extraStateTrigger)
Require (-not (Test-RuntimeDiagnosticUiPageContract -Content $extraStateDocument.OuterXml -PageName 'extra-state-probe' -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses -ExpectedUiHandles $expectedUiHandleValues)) '混入第五个 current-state 变异探针失败'

[xml]$missingLastDocument = $keyboardPageContent
$lastControl = @(Get-XamlNamedNodes -Document $missingLastDocument -Name 'COSRuntimeDiagnosticLast')[0]
[void]$lastControl.ParentNode.RemoveChild($lastControl)
Require (-not (Test-RuntimeDiagnosticUiPageContract -Content $missingLastDocument.OuterXml -PageName 'missing-last-probe' -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses -ExpectedUiHandles $expectedUiHandleValues)) '删除 last-issue 控件变异探针失败'

[xml]$controllerMissingReadyDocument = $controllerPageContent
$controllerStateControl = @(Get-XamlNamedNodes -Document $controllerMissingReadyDocument -Name 'COSRuntimeDiagnosticState')[0]
$controllerReadyTrigger = @(
    $controllerStateControl.SelectNodes('.//*[local-name()="DataTrigger"]') |
        Where-Object { $_.GetAttribute('Value') -ceq 'COS_DIAG_STATE_READY' }
)[0]
[void]$controllerReadyTrigger.ParentNode.RemoveChild($controllerReadyTrigger)
Require (-not (Test-RuntimeDiagnosticUiPageContract -Content $controllerMissingReadyDocument.OuterXml -PageName 'controller-missing-ready-probe' -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses -ExpectedUiHandles $expectedUiHandleValues)) '手柄页删除 COS_DIAG_STATE_READY 变异探针失败'

[xml]$wrongResourceDocument = $keyboardPageContent
$powerControl = @(Get-XamlNamedNodes -Document $wrongResourceDocument -Name 'COSRuntimeDiagnosticPower')[0]
$powerTrigger = @($powerControl.SelectNodes('.//*[local-name()="DataTrigger"]'))[0]
$powerTrigger.SetAttribute('Value', 'COS_ChaosMasteryPoint')
Require (-not (Test-RuntimeDiagnosticUiPageContract -Content $wrongResourceDocument.OuterXml -PageName 'wrong-resource-probe' -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses -ExpectedUiHandles $expectedUiHandleValues)) '资源过滤串线变异探针失败'

[xml]$buttonDocument = $keyboardPageContent
$buttonPanel = @(Get-XamlNamedNodes -Document $buttonDocument -Name 'COSRuntimeDiagnosticPanel')[0]
$button = $buttonDocument.CreateElement('Button', $buttonDocument.DocumentElement.NamespaceURI)
[void]$buttonPanel.AppendChild($button)
Require (-not (Test-RuntimeDiagnosticUiPageContract -Content $buttonDocument.OuterXml -PageName 'button-probe' -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses -ExpectedUiHandles $expectedUiHandleValues)) '诊断面板按钮注入变异探针失败'

[xml]$eventDocument = $keyboardPageContent
$eventPanel = @(Get-XamlNamedNodes -Document $eventDocument -Name 'COSRuntimeDiagnosticPanel')[0]
$eventTrigger = $eventDocument.CreateElement('b', 'EventTrigger', 'http://schemas.microsoft.com/xaml/behaviors')
$eventTrigger.SetAttribute('EventName', 'Click')
[void]$eventPanel.AppendChild($eventTrigger)
Require (-not (Test-RuntimeDiagnosticUiPageContract -Content $eventDocument.OuterXml -PageName 'event-probe' -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses -ExpectedUiHandles $expectedUiHandleValues)) '诊断面板事件注入变异探针失败'

[xml]$controllerDriftDocument = $controllerPageContent
$controllerDriftPanel = @(Get-XamlNamedNodes -Document $controllerDriftDocument -Name 'COSRuntimeDiagnosticPanel')[0]
$controllerDriftPanel.SetAttribute('Margin', '1')
Require (-not (Test-RuntimeDiagnosticUiParity -KeyboardContent $keyboardPageContent -ControllerContent $controllerDriftDocument.OuterXml -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses -ExpectedUiHandles $expectedUiHandleValues)) '键鼠与手柄面板漂移变异探针失败'

[xml]$panelAfterOverviewDocument = $keyboardPageContent
$panelAfterOverview = @(Get-XamlNamedNodes -Document $panelAfterOverviewDocument -Name 'COSRuntimeDiagnosticPanel')[0]
$overviewBeforePanel = @(Get-XamlNamedNodes -Document $panelAfterOverviewDocument -Name 'COSConfigOverview')[0]
$rowsContainingPanel = $panelAfterOverview.ParentNode
[void]$rowsContainingPanel.RemoveChild($panelAfterOverview)
[void]$rowsContainingPanel.InsertAfter($panelAfterOverview, $overviewBeforePanel)
Require (-not (Test-RuntimeDiagnosticUiPageContract -Content $panelAfterOverviewDocument.OuterXml -PageName 'panel-after-overview-probe' -ExpectedStateStatuses $expectedStateStatuses -ExpectedLastStatuses $expectedLastStatuses -ExpectedUiHandles $expectedUiHandleValues)) '诊断面板移到 COSConfigOverview 之后变异探针失败'

Write-Output 'Runtime diagnostic UI pages: keyboard/controller read-only parity PASS'
Write-Output 'Runtime diagnostic UI mutations: missing-panel=PASS; extra-state=PASS; missing-last=PASS; controller-missing-ready=PASS; wrong-resource=PASS; button=PASS; event=PASS; parity-drift=PASS; panel-order=PASS'

Write-Output 'ChaosOriginsStory runtime diagnostics verification: ok'
