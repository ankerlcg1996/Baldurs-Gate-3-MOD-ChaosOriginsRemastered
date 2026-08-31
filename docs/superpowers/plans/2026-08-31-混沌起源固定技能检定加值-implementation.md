# 混沌起源固定技能检定加值 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让混沌起源的所有技能检定固定获得 `+5`，同时把现有等级成长限制为纯属性检定 `+1` 至 `+7`，并发布 `1.0.1.61`。

**Architecture:** 复用延迟授予的隐藏被动 `COS_BaseProficiencies`，在其唯一 `Boosts` 中加入 `RollBonus(SkillCheck,5)`；不新增被动、状态或 Story 入口。七档 `COS_CHAOS_LIFE_SKILL_BONUS_*` 保留现有等级同步与覆盖关系，但每档只提供 `RollBonus(RawAbility,N)`。`verify.ps1` 先锁定 Stats 与四语言精确契约，再修改生产数据使验证转绿。

**Tech Stack:** BG3 Stats、BG3 Localization XML、PowerShell、StoryCompiler、LSLib、Git。

---

### Task 1: 先锁定固定技能检定与非叠加契约

**Files:**
- Modify: `story-src/verify.ps1:625-628`
- Modify: `story-src/verify.ps1:811-821`
- Modify: `story-src/verify.ps1:1967-1977`
- Test: `story-src/verify.ps1`

- [ ] **Step 1: 为基础被动写入失败契约**

用以下代码替换当前基础熟练清单检查，同时保留技能熟练与专精禁令：

```powershell
$expectedBaseProficienciesBoosts = 'Proficiency(LightArmor);Proficiency(MediumArmor);Proficiency(HeavyArmor);Proficiency(Shields);Proficiency(SimpleWeapons);Proficiency(MartialWeapons);Proficiency(MusicalInstrument);RollBonus(SkillCheck,5)'
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
    '混沌起源基础熟练必须精确包含装备熟练和固定技能检定+5'
Require (-not ($passive -match 'ProficiencyBonus\(Skill,|ExpertiseBonus\(')) `
    'Story 版不得额外授予任何技能熟练或专精'
```

- [ ] **Step 2: 为七档纯属性成长写入失败契约**

把现有生活检定循环改为：

```powershell
Require ([regex]::Matches($allStats, 'RollBonus\(SkillCheck,5\)').Count -eq 1) `
    '完整 Stats 必须且只能由基础熟练被动提供一次固定技能检定+5'
Require (-not ($allStats -match 'ProficiencyBonus\(Skill|ExpertiseBonus\(')) `
    '完整 Stats 不得额外授予任何技能熟练或专精'
Require ([regex]::Matches($mechanicsGoal, 'DB_COS_LifeSkillLevel\(\d+, \d+, "COS_CHAOS_LIFE_SKILL_BONUS_\d"\);').Count -eq 7) `
    '生活检定成长必须严格包含 5 至 30 级的 7 个阶段'
foreach ($lifeSkillBonus in 1..7) {
    $lifeSkillEntry = "COS_CHAOS_LIFE_SKILL_BONUS_$lifeSkillBonus"
    $lifeSkillPattern = 'new entry "{0}"[\s\S]*?(?=\r?\nnew entry|\z)' -f [regex]::Escape($lifeSkillEntry)
    $lifeSkillBlock = [regex]::Match($allStats, $lifeSkillPattern).Value
    $lifeSkillBoosts = @([regex]::Matches($lifeSkillBlock, '(?m)^data "Boosts" "([^"]*)"\r?$'))
    Require ($lifeSkillBoosts.Count -eq 1 -and
        $lifeSkillBoosts[0].Groups[1].Value -ceq "RollBonus(RawAbility,$lifeSkillBonus)") `
        "生活检定成长必须只提供对应的纯属性检定档位: $lifeSkillEntry"
    Require (-not $lifeSkillBlock.Contains('RollBonus(SkillCheck,')) `
        "生活检定成长不得叠加固定技能检定+5: $lifeSkillEntry"
}
```

- [ ] **Step 3: 为四语言说明写入失败契约**

在本地化循环前增加：

```powershell
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
    Korean = '혼돈 기원은 모든 기술 판정에 고정 +5를 얻습니다. 이 레벨 성장 상태는 순수 능력 판정에 +{0}을 부여합니다. 숙련이나 전문화를 부여하지 않으며 공격, 내성, 주문 DC에는 영향을 주지 않습니다.'
}
```

在 `foreach ($language ...)` 中构建 `$contentsByHandle` 后增加：

```powershell
for ($lifeSkillBonus = 1; $lifeSkillBonus -le 7; $lifeSkillBonus++) {
    $handle = $lifeSkillDescriptionHandles[$lifeSkillBonus - 1]
    $expectedText = $lifeSkillDescriptionTemplates[$language] -f $lifeSkillBonus
    Require ($contentsByHandle.ContainsKey($handle) -and
        [string]$contentsByHandle[$handle].InnerText -ceq $expectedText) `
        "混沌阅历说明必须精确显示固定技能检定+5和当前纯属性档位: $language / $lifeSkillBonus"
}
```

- [ ] **Step 4: 运行完整验证并确认 RED**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify.ps1
```

Expected: 非零退出，首先报告 `混沌起源基础熟练必须精确包含装备熟练和固定技能检定+5`。失败来自生产 Stats 尚未加入 `RollBonus(SkillCheck,5)`，不是 PowerShell 语法错误。

### Task 2: 实施固定技能检定、纯属性成长和四语言说明

**Files:**
- Modify: `story-src/Public/ChaosOriginsStory/Stats/Generated/Data/Passive.txt:5-8`
- Modify: `story-src/Public/ChaosOriginsStory/Stats/Generated/Data/ChaosRuntime.txt:460-541`
- Modify: `story-src/Localization/Chinese/ChaosOriginsStory.xml:616-622`
- Modify: `story-src/Localization/English/ChaosOriginsStory.xml:616-622`
- Modify: `story-src/Localization/Japanese/ChaosOriginsStory.xml:616-622`
- Modify: `story-src/Localization/Korean/ChaosOriginsStory.xml:616-622`
- Test: `story-src/verify.ps1`

- [ ] **Step 1: 在现有延迟被动中加入唯一固定技能检定加值**

把 `COS_BaseProficiencies` 精确改为：

```text
new entry "COS_BaseProficiencies"
type "PassiveData"
data "Properties" "IsHidden"
data "Boosts" "Proficiency(LightArmor);Proficiency(MediumArmor);Proficiency(HeavyArmor);Proficiency(Shields);Proficiency(SimpleWeapons);Proficiency(MartialWeapons);Proficiency(MusicalInstrument);RollBonus(SkillCheck,5)"
```

不修改 `Origins.lsx`，也不把该被动移入角色创建阶段。

- [ ] **Step 2: 删除七档状态中的技能检定叠加**

在 `ChaosRuntime.txt` 中把七个 `Boosts` 精确改为：

```text
data "Boosts" "RollBonus(RawAbility,1)"
data "Boosts" "RollBonus(RawAbility,2)"
data "Boosts" "RollBonus(RawAbility,3)"
data "Boosts" "RollBonus(RawAbility,4)"
data "Boosts" "RollBonus(RawAbility,5)"
data "Boosts" "RollBonus(RawAbility,6)"
data "Boosts" "RollBonus(RawAbility,7)"
```

每行继续位于对应的 `COS_CHAOS_LIFE_SKILL_BONUS_1` 至 `_7` 条目中。不得修改 StackId、StackType、图标、持续属性或 Story 等级表。

- [ ] **Step 3: 更新中文与英文七档说明**

中文七个描述句柄改为：

```xml
<content contentuid="h71000002g0002g4002g8002g000000000002" version="1">混沌起源的所有技能检定固定+5；此等级成长状态使纯属性检定+1。不授予熟练或专精，不影响攻击、豁免与法术难度。</content>
<content contentuid="h71000003g0003g4003g8003g000000000003" version="1">混沌起源的所有技能检定固定+5；此等级成长状态使纯属性检定+2。不授予熟练或专精，不影响攻击、豁免与法术难度。</content>
<content contentuid="h71000004g0004g4004g8004g000000000004" version="1">混沌起源的所有技能检定固定+5；此等级成长状态使纯属性检定+3。不授予熟练或专精，不影响攻击、豁免与法术难度。</content>
<content contentuid="h71000005g0005g4005g8005g000000000005" version="1">混沌起源的所有技能检定固定+5；此等级成长状态使纯属性检定+4。不授予熟练或专精，不影响攻击、豁免与法术难度。</content>
<content contentuid="h71000006g0006g4006g8006g000000000006" version="1">混沌起源的所有技能检定固定+5；此等级成长状态使纯属性检定+5。不授予熟练或专精，不影响攻击、豁免与法术难度。</content>
<content contentuid="h71000007g0007g4007g8007g000000000007" version="1">混沌起源的所有技能检定固定+5；此等级成长状态使纯属性检定+6。不授予熟练或专精，不影响攻击、豁免与法术难度。</content>
<content contentuid="h71000008g0008g4008g8008g000000000008" version="1">混沌起源的所有技能检定固定+5；此等级成长状态使纯属性检定+7。不授予熟练或专精，不影响攻击、豁免与法术难度。</content>
```

英文七个描述句柄改为：

```xml
<content contentuid="h71000002g0002g4002g8002g000000000002" version="1">All Skill Checks for the Chaos Origin gain a fixed +5; this level-based status grants +1 to raw Ability Checks. It grants no proficiency or expertise and does not affect attacks, saves, or spell DC.</content>
<content contentuid="h71000003g0003g4003g8003g000000000003" version="1">All Skill Checks for the Chaos Origin gain a fixed +5; this level-based status grants +2 to raw Ability Checks. It grants no proficiency or expertise and does not affect attacks, saves, or spell DC.</content>
<content contentuid="h71000004g0004g4004g8004g000000000004" version="1">All Skill Checks for the Chaos Origin gain a fixed +5; this level-based status grants +3 to raw Ability Checks. It grants no proficiency or expertise and does not affect attacks, saves, or spell DC.</content>
<content contentuid="h71000005g0005g4005g8005g000000000005" version="1">All Skill Checks for the Chaos Origin gain a fixed +5; this level-based status grants +4 to raw Ability Checks. It grants no proficiency or expertise and does not affect attacks, saves, or spell DC.</content>
<content contentuid="h71000006g0006g4006g8006g000000000006" version="1">All Skill Checks for the Chaos Origin gain a fixed +5; this level-based status grants +5 to raw Ability Checks. It grants no proficiency or expertise and does not affect attacks, saves, or spell DC.</content>
<content contentuid="h71000007g0007g4007g8007g000000000007" version="1">All Skill Checks for the Chaos Origin gain a fixed +5; this level-based status grants +6 to raw Ability Checks. It grants no proficiency or expertise and does not affect attacks, saves, or spell DC.</content>
<content contentuid="h71000008g0008g4008g8008g000000000008" version="1">All Skill Checks for the Chaos Origin gain a fixed +5; this level-based status grants +7 to raw Ability Checks. It grants no proficiency or expertise and does not affect attacks, saves, or spell DC.</content>
```

- [ ] **Step 4: 更新日文与韩文七档说明**

日文七个描述句柄改为：

```xml
<content contentuid="h71000002g0002g4002g8002g000000000002" version="1">混沌の起源はすべての技能判定に固定+5を得る。このレベル成長状態は能力値判定に+1を与える。習熟や専門化は付与せず、攻撃、セーヴ、呪文DCには影響しない。</content>
<content contentuid="h71000003g0003g4003g8003g000000000003" version="1">混沌の起源はすべての技能判定に固定+5を得る。このレベル成長状態は能力値判定に+2を与える。習熟や専門化は付与せず、攻撃、セーヴ、呪文DCには影響しない。</content>
<content contentuid="h71000004g0004g4004g8004g000000000004" version="1">混沌の起源はすべての技能判定に固定+5を得る。このレベル成長状態は能力値判定に+3を与える。習熟や専門化は付与せず、攻撃、セーヴ、呪文DCには影響しない。</content>
<content contentuid="h71000005g0005g4005g8005g000000000005" version="1">混沌の起源はすべての技能判定に固定+5を得る。このレベル成長状態は能力値判定に+4を与える。習熟や専門化は付与せず、攻撃、セーヴ、呪文DCには影響しない。</content>
<content contentuid="h71000006g0006g4006g8006g000000000006" version="1">混沌の起源はすべての技能判定に固定+5を得る。このレベル成長状態は能力値判定に+5を与える。習熟や専門化は付与せず、攻撃、セーヴ、呪文DCには影響しない。</content>
<content contentuid="h71000007g0007g4007g8007g000000000007" version="1">混沌の起源はすべての技能判定に固定+5を得る。このレベル成長状態は能力値判定に+6を与える。習熟や専門化は付与せず、攻撃、セーヴ、呪文DCには影響しない。</content>
<content contentuid="h71000008g0008g4008g8008g000000000008" version="1">混沌の起源はすべての技能判定に固定+5を得る。このレベル成長状態は能力値判定に+7を与える。習熟や専門化は付与せず、攻撃、セーヴ、呪文DCには影響しない。</content>
```

韩文七个描述句柄改为：

```xml
<content contentuid="h71000002g0002g4002g8002g000000000002" version="1">혼돈 기원은 모든 기술 판정에 고정 +5를 얻습니다. 이 레벨 성장 상태는 순수 능력 판정에 +1을 부여합니다. 숙련이나 전문화를 부여하지 않으며 공격, 내성, 주문 DC에는 영향을 주지 않습니다.</content>
<content contentuid="h71000003g0003g4003g8003g000000000003" version="1">혼돈 기원은 모든 기술 판정에 고정 +5를 얻습니다. 이 레벨 성장 상태는 순수 능력 판정에 +2를 부여합니다. 숙련이나 전문화를 부여하지 않으며 공격, 내성, 주문 DC에는 영향을 주지 않습니다.</content>
<content contentuid="h71000004g0004g4004g8004g000000000004" version="1">혼돈 기원은 모든 기술 판정에 고정 +5를 얻습니다. 이 레벨 성장 상태는 순수 능력 판정에 +3을 부여합니다. 숙련이나 전문화를 부여하지 않으며 공격, 내성, 주문 DC에는 영향을 주지 않습니다.</content>
<content contentuid="h71000005g0005g4005g8005g000000000005" version="1">혼돈 기원은 모든 기술 판정에 고정 +5를 얻습니다. 이 레벨 성장 상태는 순수 능력 판정에 +4를 부여합니다. 숙련이나 전문화를 부여하지 않으며 공격, 내성, 주문 DC에는 영향을 주지 않습니다.</content>
<content contentuid="h71000006g0006g4006g8006g000000000006" version="1">혼돈 기원은 모든 기술 판정에 고정 +5를 얻습니다. 이 레벨 성장 상태는 순수 능력 판정에 +5를 부여합니다. 숙련이나 전문화를 부여하지 않으며 공격, 내성, 주문 DC에는 영향을 주지 않습니다.</content>
<content contentuid="h71000007g0007g4007g8007g000000000007" version="1">혼돈 기원은 모든 기술 판정에 고정 +5를 얻습니다. 이 레벨 성장 상태는 순수 능력 판정에 +6을 부여합니다. 숙련이나 전문화를 부여하지 않으며 공격, 내성, 주문 DC에는 영향을 주지 않습니다.</content>
<content contentuid="h71000008g0008g4008g8008g000000000008" version="1">혼돈 기원은 모든 기술 판정에 고정 +5를 얻습니다. 이 레벨 성장 상태는 순수 능력 판정에 +7을 부여합니다. 숙련이나 전문화를 부여하지 않으며 공격, 내성, 주문 DC에는 영향을 주지 않습니다.</content>
```

- [ ] **Step 5: 运行完整验证并确认 GREEN**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify.ps1
git diff --check
```

Expected: 验证输出 `ChaosOriginsStory final native Story source verification: ok`，两个命令均以 0 退出。

- [ ] **Step 6: 提交功能改动**

```powershell
git add -- story-src/verify.ps1 story-src/Public/ChaosOriginsStory/Stats/Generated/Data/Passive.txt story-src/Public/ChaosOriginsStory/Stats/Generated/Data/ChaosRuntime.txt story-src/Localization/Chinese/ChaosOriginsStory.xml story-src/Localization/English/ChaosOriginsStory.xml story-src/Localization/Japanese/ChaosOriginsStory.xml story-src/Localization/Korean/ChaosOriginsStory.xml
git commit -m "feat(skill-check): add fixed chaos bonus"
```

### Task 3: 构建、安装并发布 1.0.1.61

**Files:**
- Modify by build: `story-src/version.json`
- Modify by build: `story-src/Mods/ChaosOriginsStory/meta.lsx`
- Generate locally and keep ignored: `dist/build-manifest.json`
- Generate locally and keep ignored: `dist/ChaosOriginsStory.pak`
- Install: `C:/Users/ankerlcg/AppData/Local/Larian Studios/Baldur's Gate 3/Mods/ChaosOriginsStory.pak`

- [ ] **Step 1: 只运行一次正式构建**

```powershell
pwsh -NoProfile -File .\story-src\build.ps1 -LslibPath 'C:\Users\ankerlcg\Desktop\BG3ModManager_Latest\_Lib\LSLib.dll'
```

Expected: 以 0 退出；`lastBuild` 从 `60` 变为 `61`；输出报告 `1.0.1.61`、38 个文件和 PAK 反向校验完成。构建失败时停止，不重复运行，也不手工增加版本号。

- [ ] **Step 2: 关闭游戏并只安装目标 PAK**

执行以下 PowerShell 逻辑：

```powershell
$source = (Resolve-Path '.\dist\ChaosOriginsStory.pak').Path
$target = Join-Path $env:LOCALAPPDATA "Larian Studios\Baldur's Gate 3\Mods\ChaosOriginsStory.pak"
$games = @(Get-Process -Name 'bg3','bg3_dx11' -ErrorAction SilentlyContinue)
if ($games.Count -gt 0) {
    $gameIds = @($games.Id)
    $games | Stop-Process -Force
    foreach ($gameId in $gameIds) {
        Wait-Process -Id $gameId -Timeout 30 -ErrorAction SilentlyContinue
    }
    $remaining = @(Get-Process -Id $gameIds -ErrorAction SilentlyContinue)
    if ($remaining.Count -ne 0) { throw "游戏进程未完全退出: $($remaining.Id -join ',')" }
}
$backup = ''
if (Test-Path -LiteralPath $target -PathType Leaf) {
    $backupDir = Join-Path (Resolve-Path '.\dist').Path 'installed-backups'
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $backupDir "ChaosOriginsStory-before-1.0.1.61-$stamp.pak"
    Copy-Item -LiteralPath $target -Destination $backup
    if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -cne
        (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash) {
        throw '安装前 PAK 备份哈希不一致'
    }
}
Copy-Item -LiteralPath $source -Destination $target -Force
$sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$targetHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
if ($sourceHash -cne $targetHash) {
    throw "安装包哈希不一致: source=$sourceHash target=$targetHash"
}
```

若目标 PAK 在安装前不存在，明确记录“无旧安装包可备份”，然后创建唯一目标文件。不得读取后改写或删除其他 MOD。

- [ ] **Step 3: 提交发布元数据**

```powershell
git add -- story-src/version.json story-src/Mods/ChaosOriginsStory/meta.lsx
git commit -m "build(release): publish 1.0.1.61"
```

- [ ] **Step 4: 推送功能分支和 main**

```powershell
git push github codex/native-core-config
git push github HEAD:main
```

两个推送都必须是非强制推送。任一推送失败时停止并报告原始错误。

- [ ] **Step 5: 做发布后新鲜验证**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify.ps1
git diff --check
git status --short --branch
git ls-remote github refs/heads/main refs/heads/codex/native-core-config
```

Expected: 验证以 0 退出；工作树干净；两个远端引用均指向本地 `HEAD`；构建包、安装包和构建清单中的 SHA-256 相同。

游戏内仍需分别使用混沌起源和普通角色验收：混沌起源技能检定固定 `+5`，普通角色无该加值，等级成长只增加纯属性检定，攻击、豁免、法术命中和法术难度不受影响。
