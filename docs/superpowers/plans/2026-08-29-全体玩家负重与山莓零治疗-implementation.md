# 全体玩家负重与山莓零治疗 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在纯原生 Story 版中，让 `DB_Players` 内的所有玩家角色稳定获得 50 倍负重，并让无限使用的原版山莓通过 `RegainHitPoints(0)` 尝试进入治疗结算，发布为 `1.0.1.59`。

**Architecture:** 负重由一个无显示、无混沌起源前置的隐藏被动提供，独立 Story Goal 只在官方 `DB_Players` 范围内幂等补发；山莓继续覆盖唯一官方 RootTemplate，并由自定义 `FOOD` 子状态执行一次 0 点恢复 Functor。验证脚本锁死 Stats、Story、清单、说明和非神莓边界，构建脚本继续只接受精确文件集合。

**Tech Stack:** BG3 Stats (`PassiveData`/`StatusData`)、Osiris Story、PowerShell 7、Larian StoryCompiler、LSLib、Git/GitHub。

---

## 执行边界

- 工作目录：`C:\Users\ankerlcg\Desktop\chaos-BG3-mod-story\.worktrees\native-core-config`
- 当前分支：`codex/native-core-config`
- 基线版本：`1.0.1.58`
- 目标版本：`1.0.1.59`
- 设计规格：`docs/superpowers/specs/2026-08-29-全体玩家负重与山莓零治疗-design.md`
- 不修改 `FOOD_FRUIT_GOODBERRY`，不增加 Script Extender、MCM 或 NMCM 依赖。
- 不在本版静默回退到恢复 1 点；`RegainHitPoints(0)` 的实机表现必须由用户验收。
- `dist/` 产物和安装备份保持 Git 忽略；只提交源码、验证、说明和构建生成的版本元数据。

## Task 1: 以测试锁定全体玩家 50 倍负重和第六个 Goal

**Files:**

- Modify: `story-src/verify.ps1:63-75,286-333,539-573,872-896,2593-2603`
- Modify: `story-src/build.ps1:144-155`
- Modify: `story-src/package-files.json:13-21`
- Modify: `story-src/Public/ChaosOriginsStory/Stats/Generated/Data/Passive.txt:1-15`
- Create: `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_GlobalPlayerBenefits.txt`
- Modify: `README.md:21-28`
- Modify: `story-src/README.md:21-28`

- [ ] **Step 1: 记录干净基线并运行现有验证**

Run:

```powershell
git status --short --branch
pwsh -NoProfile -File .\story-src\verify.ps1
```

Expected: 分支只领先远端一个已提交的设计文档；验证结束显示 `ChaosOriginsStory final native Story source verification: ok`。

- [ ] **Step 2: 先把验证规则改成新契约**

在 `story-src/verify.ps1` 中完成以下精确变化：

1. 两份 README 的契约由 `36`/`五个 Goal` 改为 `37`/`六个 Goal`：

```powershell
Require ($readmeText.Contains('version.json') -and $readmeText.Contains('37') -and `
    $readmeText.Contains('六个 Goal')) "工程说明必须以version.json为准并记录37文件/6 Goals: $readmePath"
```

2. 在 `$expectedPackageFiles` 的 Goal 列表加入：

```powershell
'Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_GlobalPlayerBenefits.txt',
```

3. 将清单数量断言改为：

```powershell
Require ($manifest.Count -eq 38 -and @($manifest | Select-Object -Unique).Count -eq 38) `
    '原生 Story 打包清单必须恰好包含38个唯一文件'
```

4. 在 `$expectedPassiveEntries` 的三项基础被动后加入：

```powershell
'COS_GlobalCarryCapacity50x',
```

5. 将隐藏被动数量断言改为：

```powershell
Require ([regex]::Matches($passive, 'data "Properties" "IsHidden"').Count -eq 4) `
    '三项基础被动与全局负重被动必须全部隐藏'
```

6. 在 `Test-StatsField`/`Test-StatsUsing` 定义之后加入负重被动精确断言：

```powershell
$globalCarryPassiveBlock = Get-StatsEntryBlock $passive 'COS_GlobalCarryCapacity50x'
Require ((Test-StatsField $globalCarryPassiveBlock 'Properties' 'IsHidden') -and
    (Test-StatsField $globalCarryPassiveBlock 'Boosts' 'CarryCapacityMultiplier(50)')) `
    '全局负重被动必须隐藏并精确提供50倍负重'
Require ([regex]::Matches($globalCarryPassiveBlock, '(?m)^type "PassiveData"\r?$').Count -eq 1) `
    '全局负重被动必须唯一声明为 PassiveData'
```

7. 在 Goal 路径区增加：

```powershell
$globalBenefitsGoalPath = Join-Path $storyPath 'RawFiles\Goals\COS_GlobalPlayerBenefits.txt'
```

将 Goal 集合断言改为 6 个，并明确包含 `$globalBenefitsGoalPath`：

```powershell
$goals = @(Get-ChildItem -LiteralPath (Split-Path $goalPath -Parent) -File -Filter '*.txt')
Require ($goals.Count -eq 6 -and ($goals.FullName -contains $goalPath) -and `
    ($goals.FullName -contains $masteryGoalPath) -and ($goals.FullName -contains $rewardGoalPath) -and `
    ($goals.FullName -contains $mechanicsGoalPath) -and ($goals.FullName -contains $configGoalPath) -and `
    ($goals.FullName -contains $globalBenefitsGoalPath)) `
    '当前 Story 必须且只能包含基础同步、掌控混沌、混沌机制、核心设置、起源剧情奖励和全体玩家增益六个 Goal'
```

紧接着加入完整 Goal 契约：

```powershell
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
```

- [ ] **Step 3: 运行 RED 验证并确认失败原因正确**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify.ps1
```

Expected: 非零退出；首先在 README 新口径、38 文件清单、新被动或第六个 Goal 之一明确失败。不得出现语法解析错误或与本功能无关的失败。

- [ ] **Step 4: 添加隐藏负重被动**

在 `story-src/Public/ChaosOriginsStory/Stats/Generated/Data/Passive.txt` 的 `COS_BaseStarterSpells` 后加入完整定义：

```text
new entry "COS_GlobalCarryCapacity50x"
type "PassiveData"
data "Properties" "IsHidden"
data "Boosts" "CarryCapacityMultiplier(50)"
```

不要加入 DisplayName、图标、切换属性或混沌起源前置。

- [ ] **Step 5: 创建独立全体玩家同步 Goal**

创建 `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_GlobalPlayerBenefits.txt`，内容必须与 Step 2 的 `$expectedGlobalBenefitsGoal` 完全一致。

这保证：

- `INITSECTION` 的 NULL 删除只声明官方合并 Story 的 `DB_Players` 签名，不写入虚构玩家；
- `LevelGameplayStarted` 通过 `DB_Players` 遍历当前玩家角色；
- 其他三个事件只提供已绑定角色，统一过程再次用 `DB_Players` 限定作用域；
- `HasPassive(_Character, "COS_GlobalCarryCapacity50x", 0)` 后才 `AddPassive`，重复事件不会叠加；
- 普通 NPC、敌人和召唤物不会通过同步过程。

- [ ] **Step 6: 更新打包清单与构建脚本的精确集合**

在 `story-src/package-files.json` 的 Goal 区加入：

```json
"Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_GlobalPlayerBenefits.txt",
```

在 `story-src/build.ps1` 的 `$expectedStoryFiles` 加入同一路径，并把错误消息改为：

```powershell
'原生 Story 包装必须同时包含六个 Goal、当前原始头和编译 Story'
```

- [ ] **Step 7: 同步两份 README 的真实数量和功能说明**

在根 `README.md`：

- 将 `36 个正式文件` 改为 `37 个正式文件`；
- 将 `五个 Raw Goal` 改为 `六个 Raw Goal`；
- 将 Goal 条目改为：

```markdown
- 包含基础同步、一级掌控混沌、混沌核心机制、核心设置、起源剧情奖励和全体玩家增益六个 Goal；
- `DB_Players` 中的主角、已加入同伴和雇佣兵会幂等获得 50 倍负重，普通 NPC、敌人和召唤物不受影响；
```

在 `story-src/README.md`：

- 将 `36 个正式文件和五个 Goal` 改为 `37 个正式文件和六个 Goal`；
- 在 `verify.ps1` 的核对范围中加入“全体玩家 50 倍负重”；
- 保留“静态/编译/hash不等于实机验收”边界。

- [ ] **Step 8: 运行 GREEN 验证**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify.ps1
git diff --check
```

Expected: StoryCompiler 成功；最终显示 `ChaosOriginsStory final native Story source verification: ok`；`git diff --check` 无输出。

- [ ] **Step 9: 提交负重功能**

Run:

```powershell
git add README.md story-src/README.md story-src/verify.ps1 story-src/build.ps1 story-src/package-files.json story-src/Public/ChaosOriginsStory/Stats/Generated/Data/Passive.txt story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_GlobalPlayerBenefits.txt
git diff --cached --check
git commit -m "feat(carry-weight): multiply player capacity"
```

Expected: 提交成功；`story-src/version.json` 仍为 `1.0.1.58`，因为尚未执行发布构建。

## Task 2: 以测试锁定山莓 `RegainHitPoints(0)` 治疗结算试验

**Files:**

- Modify: `story-src/verify.ps1:4140-4164`
- Modify: `story-src/Public/ChaosOriginsStory/Stats/Generated/Data/Status_BOOST.txt:51-57`

- [ ] **Step 1: 将旧的“禁止治疗 Functor”断言改为精确的零治疗契约**

用下列断言替换当前 `OnApplyFunctors`/`RegainHitPoints` 禁止项：

```powershell
Require (Test-StatsField $raspberryStatusBlock 'OnApplyFunctors' 'RegainHitPoints(0)') `
    '山莓零治疗状态必须唯一执行 RegainHitPoints(0)'
Require (-not ($raspberryStatusBlock -match 'RegainHitPoints\((?!0\))')) `
    '山莓零治疗状态不得恢复非零生命值'
```

继续保留以下现有边界：

- RootTemplate `Consume=False`；
- `StatsId=COS_RASPBERRY_ZERO_HEAL`；
- 继承 `FOOD`，图标为 `Spell_Transmutation_Goodberry`，`StackId=FOOD`；
- 不包含 `FOOD_FRUIT_GOODBERRY` 覆盖。

- [ ] **Step 2: 运行 RED 验证并确认缺失 Functor**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify.ps1
```

Expected: 非零退出，明确报告“山莓零治疗状态必须唯一执行 RegainHitPoints(0)”。

- [ ] **Step 3: 给山莓状态加入唯一的零点恢复 Functor**

将 `COS_RASPBERRY_ZERO_HEAL` 完整定义改为：

```text
new entry "COS_RASPBERRY_ZERO_HEAL"
type "StatusData"
data "StatusType" "BOOST"
using "FOOD"
data "Icon" "Spell_Transmutation_Goodberry"
data "StackId" "FOOD"
data "OnApplyFunctors" "RegainHitPoints(0)"
```

不要同时增加 `RegainHitPoints(1)`，不要修改 RootTemplate 的 `Consume=False`，不要修改官方神莓状态。

- [ ] **Step 4: 运行 GREEN 验证并做定向搜索**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify.ps1
rg -n "COS_RASPBERRY_ZERO_HEAL|RegainHitPoints|FOOD_FRUIT_GOODBERRY|Consume" story-src/Public/ChaosOriginsStory/Stats/Generated/Data/Status_BOOST.txt story-src/resource-src/Public/ChaosOriginsStory/RootTemplates/COS_Raspberry.lsf.lsx
git diff --check
```

Expected:

- 完整验证通过；
- 自定义山莓状态只有 `RegainHitPoints(0)`；
- RootTemplate 仍为 `Consume=False`；
- 两个文件均未定义或改写 `FOOD_FRUIT_GOODBERRY`；
- `git diff --check` 无输出。

- [ ] **Step 5: 提交山莓修改**

Run:

```powershell
git add story-src/verify.ps1 story-src/Public/ChaosOriginsStory/Stats/Generated/Data/Status_BOOST.txt
git diff --cached --check
git commit -m "fix(raspberry): trigger zero-point healing"
```

Expected: 提交成功；版本仍为 `1.0.1.58`。

## Task 3: 复核、单次构建、安装并发布 `1.0.1.59`

**Files:**

- Verify: all tracked source files
- Generated/Modify: `story-src/version.json`
- Generated/Modify: `story-src/Mods/ChaosOriginsStory/meta.lsx`
- Generated/Ignored: `dist/ChaosOriginsStory.pak`
- Generated/Ignored: `dist/build-manifest.json`
- Backup/Ignored: `dist/installed-backups/ChaosOriginsStory-before-1.0.1.59-<timestamp>.pak`
- Install/External: `%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods\ChaosOriginsStory.pak`

- [ ] **Step 1: 做发布前规格覆盖与残留扫描**

Run:

```powershell
git status --short --branch
git log --oneline -4
rg -n "36 个正式文件|五个 Goal|五个 Raw Goal|RegainHitPoints\(1\)" README.md story-src -g "*.md" -g "*.txt" -g "*.ps1" -g "*.json"
rg -n "CarryCapacityMultiplier" story-src
git diff --check
pwsh -NoProfile -File .\story-src\verify.ps1
```

Expected:

- 只有计划文档尚未提交，或工作树完全干净；
- 第一条搜索无输出；第二条只显示 `CarryCapacityMultiplier(50)` 的实现与验证契约；
- 完整验证通过。

- [ ] **Step 2: 只执行一次正式构建**

Run:

```powershell
pwsh -NoProfile -File .\story-src\build.ps1 -LslibPath 'C:\Users\ankerlcg\Desktop\BG3ModManager_Latest\_Lib\LSLib.dll'
```

Expected:

- Story 编译、IR 证明、资源编译、Stats/本地化生成、38 文件打包和反向 SHA-256 比对全部通过；
- `story-src/version.json` 从 `lastBuild: 58` 变为 `lastBuild: 59`；
- `story-src/Mods/ChaosOriginsStory/meta.lsx` 两个 Version64 与 `1.0.1.59` 对齐；
- `dist/build-manifest.json` 声明 `1.0.1.59`；
- `dist/ChaosOriginsStory.pak` 存在。

构建失败时停止，不重跑构建，不手工递增版本；先定位真实失败原因。

- [ ] **Step 3: 验证构建后版本和产物**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify.ps1
Get-Content .\story-src\version.json -Raw
Get-Content .\dist\build-manifest.json -Raw
Get-FileHash -Algorithm SHA256 -LiteralPath .\dist\ChaosOriginsStory.pak
git diff --check
```

Expected: 源验证仍通过，两个清单均为 `1.0.1.59`，PAK SHA-256 可读且 `git diff --check` 无输出。

- [ ] **Step 4: 关闭 BG3、备份旧包并安装唯一目标 PAK**

Run:

```powershell
$gameProcesses = @(Get-Process -Name 'bg3','bg3_dx11' -ErrorAction SilentlyContinue)
if ($gameProcesses.Count -gt 0) {
    $gameProcesses | Stop-Process
    $gameProcesses | Wait-Process
}

$installedPak = Join-Path $env:LOCALAPPDATA "Larian Studios\Baldur's Gate 3\Mods\ChaosOriginsStory.pak"
$builtPak = Join-Path $PWD 'dist\ChaosOriginsStory.pak'
$backupDirectory = Join-Path $PWD 'dist\installed-backups'
New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
if (Test-Path -LiteralPath $installedPak -PathType Leaf) {
    $backupPak = Join-Path $backupDirectory ("ChaosOriginsStory-before-1.0.1.59-{0}.pak" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $installedPak -Destination $backupPak
}
Copy-Item -LiteralPath $builtPak -Destination $installedPak -Force

$builtHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $builtPak).Hash
$installedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installedPak).Hash
if ($builtHash -cne $installedHash) {
    throw "安装包哈希不一致: build=$builtHash installed=$installedHash"
}
"installed_sha256=$installedHash"
```

Expected: 只处理 `ChaosOriginsStory.pak`；如旧包存在则先产生带时间戳备份；构建包与安装包 SHA-256 完全一致。

- [ ] **Step 5: 提交发布元数据与本计划**

Run:

```powershell
git add story-src/version.json story-src/Mods/ChaosOriginsStory/meta.lsx docs/superpowers/plans/2026-08-29-全体玩家负重与山莓零治疗-implementation.md
git diff --cached --check
git commit -m "build(release): publish 1.0.1.59"
git status --short --branch
```

Expected: 发布提交成功；忽略的 `dist/` 不进入提交；工作树干净。

- [ ] **Step 6: 推送功能分支和 GitHub 主分支**

Run:

```powershell
git push github codex/native-core-config
git push github HEAD:main
git ls-remote github refs/heads/codex/native-core-config refs/heads/main
```

Expected: 两个远端引用都指向当前发布提交。若 `main` 不是可快进，停止并报告，不强推。

- [ ] **Step 7: 交付静态证据与实机验收清单**

最终报告必须包含：

- 发布提交 SHA；
- `1.0.1.59`；
- 构建 PAK 与安装 PAK 的相同 SHA-256；
- 远端功能分支与 `main` 的 SHA；
- 旧包备份绝对路径（若创建）；
- 明确说明静态验证、Story 编译、打包、哈希和安装均不能替代游戏内验收。

用户实机只需按以下顺序验收：

1. 主角、已加入同伴与雇佣兵的负重上限均为原来的 50 倍；
2. 普通 NPC 与召唤物无该增益；
3. 旧存档当前队伍、后来入队角色和洗点后角色均能获得或恢复增益；
4. 山莓使用动画/治疗表现触发，生命值不变，数量不减少；
5. 神莓术生成物仍按官方规则消耗并恢复生命。

若第 4 项仍无治疗表现，记录为 `RegainHitPoints(0)` 的运行时结论；下一版只把该 Functor 改为 `RegainHitPoints(1)`，不得在 `1.0.1.59` 内隐藏回退。
