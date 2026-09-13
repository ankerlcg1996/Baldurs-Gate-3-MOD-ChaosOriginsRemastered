# ChaosOrigins 1.0.1.98 运行审计与只读诊断实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Implementation also requires `superpowers:test-driven-development` for each code task and `superpowers:verification-before-completion` before release.

**Goal:** 以 `1.0.1.97` 为已发布基线，建立可复核的运行状态合同，并在原生设置菜单中加入不会改变玩法数据的运行诊断，为后续预设、迁移和玩法扩展提供稳定基线。

**Architecture:** 保持单一纯 Story PAK、六个 Goal 和 38 个正式文件。诊断逻辑放入现有 `COS_Config.txt`，诊断状态放入现有 `ChaosConfig.txt`，键鼠和手柄页面各增加相同的只读面板。菜单打开时先记录同步前异常，再执行已有角色同步，最后显示同步后的当前状态；诊断过程只允许维护 `DB_COS_RuntimeDiagnostic*` 和无 Boost 的诊断状态，不得写配置、发放能力、改变资源或触发战斗效果。

**Tech Stack:** BG3 原生 Osiris Story、BG3 Stats、LSX/XAML、四语 XML 本地化、PowerShell 7 验证脚本、StoryCompiler、LSLib、Git。

---

## 文件结构锁定

| 文件 | 本阶段唯一职责 |
|---|---|
| `docs/runtime-contract-1.0.1.97.md` | 冻结发布基线的设置、资源、镜像、迁移和生命周期事实 |
| `story-src/verify-runtime-diagnostics.ps1` | 独立验证审计、只读 Story、Stats、本地化和双输入页面合同，并执行变异探针 |
| `story-src/verify.ps1` | 调用专用诊断验证器，不复制其规则 |
| `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt` | 选择诊断结果、保存最近问题、响应既有 UI_OPENED 事件 |
| `story-src/Public/ChaosOriginsStory/Stats/Generated/Data/ChaosConfig.txt` | 定义无 Boost 的诊断状态；不增加新 Stats 文件 |
| `story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu.xaml` | 键鼠只读诊断显示 |
| `story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu_c.xaml` | 手柄只读诊断显示，状态集合与键鼠页相同 |
| 四个 `story-src/Localization/*/ChaosOriginsStory.xml` | 诊断标题、状态、资源和静态版本文本 |
| `docs/RELEASE-1.0.1.98.md` | 构建证据与尚待完成的游戏内验收矩阵 |

## 边界和验收口径

- 基线提交：`499890e` 的 `ChaosOriginsStory 1.0.1.97`；总设计提交：`3fcb6ab`。
- 本阶段只实现审计和诊断，不实现分类总开关、预设、统一迁移、种族装备资格、掌控重置或连续负面保护。
- 不创建新的 Story Goal 或新的 Stats 文件；`package-files.json` 仍为 38 个唯一文件。
- 不删除现有菜单打开时的 `PROC_COS_ConfigSyncCharacter`。诊断必须分别观察同步前和同步后，避免把被自动修复的缺口静默隐藏。
- “Story 已响应”只表示菜单 `Loaded` 的 TutorialEvent 已到达 Story；不把它描述成 PAK 哈希、全局加载顺序或游戏内完整验收。
- “配置完整”只表示本文列出的持久配置记录均存在；缺失数据不显示默认猜测值。
- “核心一致”表示九个 `DB_COS_ConfigMechanic` 值与九个 `COS_CFG_MECH_*` 镜像被动一致。核心机制本身仍以 DB 为行为真值，镜像被动只负责 UI 回显或已有 Stats 条件。
- 混沌之力和掌控混沌剩余点数从 `ActionResources` 只读显示；已用掌控点沿用 `COS_OVERVIEW_*` 中的调律、纠偏分配，不新增另一套计数。
- 自动验证通过只能证明源码、编译和包装合同；新档、旧档、切人、读档及菜单显示仍须游戏内测试。

## 固定诊断模型

当前状态只允许四种，全部共用 `StackId "COS_RUNTIME_DIAGNOSTIC_STATE"`：

1. `COS_DIAG_STATE_NOT_ORIGIN`
2. `COS_DIAG_STATE_CONFIG_INCOMPLETE`
3. `COS_DIAG_STATE_CORE_MISMATCH`
4. `COS_DIAG_STATE_READY`

最近一次明确问题共用 `StackId "COS_RUNTIME_DIAGNOSTIC_LAST"`。无历史问题时使用 `COS_DIAG_LAST_NONE`；发现问题时记录以下精确类别：

- 九个核心记录缺失：`COS_DIAG_LAST_MISSING_POWER`、`WOUND`、`KILLPOWER`、`DUALITY`、`ALLIN`、`FATE`、`GENESIS`、`STRIKE`、`MASTERY`。
- 其他配置缺失：`COS_DIAG_LAST_MISSING_LIFE`、`MISSING_FATE_COST`、`MISSING_GENESIS_COST`、`MISSING_RACIAL`、`MISSING_GRANT`、`MISSING_TAG_SPELLS`、`MISSING_VOLO`、`MISSING_CARRY`。
- 九个核心镜像不一致：`COS_DIAG_LAST_MISMATCH_POWER`、`WOUND`、`KILLPOWER`、`DUALITY`、`ALLIN`、`FATE`、`GENESIS`、`STRIKE`、`MASTERY`。
- 负重镜像不一致：`COS_DIAG_LAST_MISMATCH_CARRY`。

每次检查只记录一个问题，优先级固定为：起源识别 → 配置缺失 → 核心镜像 → 负重镜像 → 正常。多个配置缺口同时存在时，按上面的书写顺序选择第一个，不依赖数据库枚举顺序。

### Task 1：冻结 `1.0.1.97` 运行合同并建立失败检查

**Files:**

- Create: `docs/runtime-contract-1.0.1.97.md`
- Create: `story-src/verify-runtime-diagnostics.ps1`
- Read: `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/*.txt`
- Read: `story-src/Public/ChaosOriginsStory/ActionResourceDefinitions/ActionResourceDefinitions.lsx`
- Read: `story-src/grant-menu.json`
- Read: `story-src/package-files.json`

- [ ] **Step 1：写运行合同清单**

在 `docs/runtime-contract-1.0.1.97.md` 固定记录以下事实，并给出来源文件和标识符：

- 六个 Goal 的职责和生命周期入口。
- 九个核心键、默认值、TutorialEvent UUID、镜像被动。
- 生活加值默认 `5`，范围 `0..20`，排除 `Athletics` 与 `Acrobatics`。
- `grant-menu.json` 的 74 项：Origin 7、Tag 31、Weapon 31、Armor 4、Instrument 1。
- 20 个官方种族被动默认关闭。
- 六个 ActionResource：`COS_ChaosStrike`、`COS_ChaosAllInUse`、`COS_ChaosPowerPoint`、`COS_ChaosMasteryPoint`、`COS_ConfigLifeSkill`、`COS_ConfigFateCost`、`COS_ConfigGenesisCost`。注意实际为七个名称，合同必须按文件实数写成七个，验证器也必须断言七个，不能沿用文字误计。
- 现有旧档标记，包括 `DB_COS_MasterySchema46To47`、命运改签遗留清理和运行时 map seed。
- 生命周期矩阵：角色创建、`LevelGameplayStarted`、`GainedControl`、`CharacterJoinedParty`、`LeveledUp`、`RespecCompleted`、复活、长休；明确记录当前没有 `CharacterLeftParty` 处理，不在本阶段补写。
- 真实未验收项：旧档升级、离队后重入、多人主控切换、手柄页面、重复打开菜单的性能。

- [ ] **Step 2：先写会在旧版本失败的专用验证器**

`verify-runtime-diagnostics.ps1` 接受可选 `-Root`，默认 `$PSScriptRoot`，并实现独立 `Require`。先断言尚不存在的诊断合同：

```powershell
$expectedStateStatuses = @(
    'COS_DIAG_STATE_NOT_ORIGIN',
    'COS_DIAG_STATE_CONFIG_INCOMPLETE',
    'COS_DIAG_STATE_CORE_MISMATCH',
    'COS_DIAG_STATE_READY'
)

foreach ($status in $expectedStateStatuses) {
    Require ($chaosConfigStats.Contains("new entry `"$status`"")) `
        "缺少运行诊断状态: $status"
}
```

验证器还必须读取审计文档，断言九个核心键、20 个种族默认、74 个 grant 项、七个资源和六个 Goal 都在合同中出现，避免文档与代码脱节。

- [ ] **Step 3：运行红灯**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify-runtime-diagnostics.ps1
```

Expected: 非零退出，第一条明确失败为 `缺少运行诊断状态: COS_DIAG_STATE_NOT_ORIGIN`，而不是 XML、路径或 PowerShell 语法错误。

- [ ] **Step 4：保留审计与红灯检查**

不要单独推送不可构建的提交。保留工作区修改，等 Task 4 绿灯后与实现一起提交。

### Task 2：添加无 Boost 的诊断状态与四语文本

**Files:**

- Modify: `story-src/Public/ChaosOriginsStory/Stats/Generated/Data/ChaosConfig.txt`
- Modify: `story-src/Localization/Chinese/ChaosOriginsStory.xml`
- Modify: `story-src/Localization/English/ChaosOriginsStory.xml`
- Modify: `story-src/Localization/Japanese/ChaosOriginsStory.xml`
- Modify: `story-src/Localization/Korean/ChaosOriginsStory.xml`
- Test: `story-src/verify-runtime-diagnostics.ps1`

- [ ] **Step 1：扩展验证器的状态合同**

为上述 4 个当前状态和 28 个最近问题状态增加断言：

- 每个 entry 恰好出现一次。
- `StatusType` 为 `BOOST`。
- 当前状态分别使用同一个 State StackId；最近问题分别使用同一个 Last StackId。
- `StackType` 为 `Overwrite`。
- `StatusPropertyFlags` 同时包含 `DisableOverhead;DisableCombatlog;DisablePortraitIndicator;IgnoreResting`。
- 不得含 `Boosts`、`StatsFunctors`、`OnApplyFunctors`、`OnRemoveFunctors`、`RemoveEvents` 或 `TickFunctors`。
- 每个 DisplayName/Description handle 在四种语言中恰好一条，不得显示 `Not Found`。

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify-runtime-diagnostics.ps1
```

Expected: 非零退出，指出缺少状态属性或本地化 handle。

- [ ] **Step 2：在现有 `ChaosConfig.txt` 中定义状态**

使用统一图标 `PassiveFeature_Generic_Threat`。每个状态采用以下无效果模板：

```text
new entry "COS_DIAG_STATE_READY"
type "StatusData"
data "StatusType" "BOOST"
data "DisplayName" "<四语名称 handle>;1"
data "Description" "<四语说明 handle>;1"
data "Icon" "PassiveFeature_Generic_Threat"
data "StackId" "COS_RUNTIME_DIAGNOSTIC_STATE"
data "StackType" "Overwrite"
data "StatusPropertyFlags" "DisableOverhead;DisableCombatlog;DisablePortraitIndicator;IgnoreResting"
```

不得创建新 Stats 文件，避免把正式打包清单从 38 改为 39。

- [ ] **Step 3：补齐四语文本**

为诊断标题、静态版本 `ChaosOriginsStory 1.0.1.98`、资源标签、四个当前状态和 28 个最近问题状态分配唯一 handle。中文语义必须明确：

- READY：`Story 已收到菜单事件；当前角色已识别为混沌起源；配置记录完整；核心设置与镜像一致。`
- NOT_ORIGIN：`Story 已收到菜单事件；当前角色没有混沌起源标记，其他诊断不适用。`
- CONFIG_INCOMPLETE：`同步前或同步后发现明确配置缺口；查看“最近同步问题”。`
- CORE_MISMATCH：`设置记录与菜单镜像被动不一致；查看“最近同步问题”。`
- LAST_NONE：`本角色尚未记录到明确的配置缺失或镜像不一致。`

其他语言必须为对应语义，不得复制中文占位。

- [ ] **Step 4：运行局部检查**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify-runtime-diagnostics.ps1
```

Expected: 仍失败，但失败点前进到缺少 Story 过程或 UI 面板；Stats 与本地化检查通过。

### Task 3：实现确定性、只读的 Story 诊断

**Files:**

- Modify: `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt`
- Test: `story-src/verify-runtime-diagnostics.ps1`

- [ ] **Step 1：先写 Story 契约与变异检查**

验证器必须提取所有名称以 `PROC_COS_RuntimeDiagnostic` 开头的 PROC block，并检查：

- 存在 seed、begin、select-first、check-config、check-mirrors、set-current、set-last、apply 和 update 过程。
- 只允许写入 `DB_COS_RuntimeDiagnostic*`。
- 只允许对 `COS_DIAG_*` 调用 `ApplyStatus`/`RemoveStatus`。
- 禁止出现 `PartyIncreaseActionResourceValue`、`AddBoosts`、`RemoveBoosts`、`AddPassive`、`RemovePassive`、`TogglePassive`、`AddSpell`、`RemoveSpell`、`SetTag`、`ClearTag`、`ApplyDamage`、`PROC_COS_ConfigApply*`、随机数调用或任何 `DB_COS_Config*` 写操作。
- 使用固定顺序逐项检查，不允许依赖 `DB_COS_ConfigMechanicDefault` 或 `DB_COS_ConfigRacialDefault` 的枚举顺序选择“第一个”问题。
- 同一个检查周期只生成一条 `DB_COS_RuntimeDiagnosticSelected`。

增加三类内存变异探针并要求被拒绝：

1. 在诊断过程插入 `PartyIncreaseActionResourceValue`；
2. 删除 `NOT DB_COS_RuntimeDiagnosticSelected(_Character, _)`；
3. 删除任一核心镜像检查。

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify-runtime-diagnostics.ps1
```

Expected: 非零退出，指出缺少运行诊断 Story 合同。

- [ ] **Step 2：运行时 seed 固定映射**

在 `KBSECTION` 中增加 `PROC_COS_RuntimeDiagnosticSeed()`。每次调用使用 `NOT DB...` 后写入：

- 九个核心键 → 缺失状态 → 不一致状态 → 镜像被动。
- Fate/Genesis 两个消耗键。
- 四个当前状态类别。

不要只写在 `INITSECTION`；旧存档不会重新执行新增 INIT 数据。

- [ ] **Step 3：实现“只取第一个问题”**

检查周期先清理本轮临时 DB，然后按固定顺序显式调用检查过程。选择过程的核心门控为：

```text
PROC
PROC_COS_RuntimeDiagnosticSelectFirst((CHARACTER)_Character, (STRING)_Kind, (STRING)_IssueStatus)
AND
NOT DB_COS_RuntimeDiagnosticSelected(_Character, _, _)
THEN
DB_COS_RuntimeDiagnosticSelected(_Character, _Kind, _IssueStatus);
```

缺失检测必须覆盖：九个核心 DB 行、生活加值、Fate 消耗、Genesis 消耗、20 个种族配置是否至少缺一项、74 个 grant 设置是否至少缺一项、TagSpells、Volo、Carry。Grant 不能只看 `DB_COS_GrantInitialized`；还要检查每个 `DB_COS_GrantOption` 是否有对应 `DB_COS_GrantSetting`。

镜像检测必须覆盖九个核心键的两个方向：

- 设置为 1 且镜像被动不存在；
- 设置为 0 且镜像被动仍存在。

负重同时检查 `DB_COS_CarryEnabled` 与 `COS_CFG_CARRY` 的两个方向。

- [ ] **Step 4：维护当前状态和最近问题**

- 非混沌角色：当前状态为 `NOT_ORIGIN`，不执行混沌配置检查，最近问题默认 `NONE`。
- 混沌角色且有 Missing：当前状态为 `CONFIG_INCOMPLETE`，最近问题更新为选中的精确缺失状态。
- 混沌角色且有 Mismatch：当前状态为 `CORE_MISMATCH`，最近问题更新为选中的精确不一致状态。
- 混沌角色无问题：当前状态为 `READY`；不清除已有最近问题。若从未有问题，创建 `LAST_NONE`。

使用 `DB_COS_RuntimeDiagnosticApplied(_Character, _Channel, _Status)` 记录已应用的 State/Last 状态。仅当期望状态发生变化时移除旧的 `COS_DIAG_*` 并应用新的状态；重复打开菜单不得重复刷新同一状态。

- [ ] **Step 5：包围已有菜单同步，不改其职责**

把 UI_OPENED 入口调整为两条互斥规则：

```text
// 所有当前受控角色都能收到只读诊断。
IF
TutorialEvent(_Character, _Event)
AND
DB_COS_ConfigUiOpenedEvent(_Event)
AND
IsControlled(_Character, 1)
AND
HasPassive(_Character, "COS_ChaosOriginMarker", 0)
THEN
PROC_COS_RuntimeDiagnosticUpdate(_Character);

// 混沌起源先记录同步前缺口，再沿用旧同步，最后刷新当前诊断。
IF
TutorialEvent(_Character, _Event)
AND
DB_COS_ConfigUiOpenedEvent(_Event)
AND
IsControlled(_Character, 1)
AND
HasPassive(_Character, "COS_ChaosOriginMarker", 1)
THEN
PROC_COS_RuntimeDiagnosticUpdate(_Character);
PROC_COS_ConfigSyncCharacter(_Character);
PROC_COS_RuntimeDiagnosticUpdate(_Character);
PROC_COS_ShowLastFate(_Character);
```

不得新增第三条 UI_OPENED 游戏逻辑，也不得移除原有同步和最近命运显示。

- [ ] **Step 6：运行 Story 局部检查**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify-runtime-diagnostics.ps1
```

Expected: Story、Stats、本地化检查通过；只剩 UI 面板检查失败。

### Task 4：在键鼠与手柄菜单加入同构只读面板

**Files:**

- Modify: `story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu.xaml`
- Modify: `story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu_c.xaml`
- Test: `story-src/verify-runtime-diagnostics.ps1`

- [ ] **Step 1：先写 UI 结构检查**

两页都必须包含以下唯一命名节点：

- `COSRuntimeDiagnosticPanel`
- `COSRuntimeDiagnosticVersion`
- `COSRuntimeDiagnosticState`
- `COSRuntimeDiagnosticLast`
- `COSRuntimeDiagnosticPower`
- `COSRuntimeDiagnosticMasteryRemaining`

验证器解析 XAML，而不是只做字符串搜索，并检查：

- 面板在现有 `COSConfigOverview` 之前。
- 整个面板 `IsHitTestVisible="False"`，内部没有 Button、LSToggleButton、InvokeCommandAction 或 TutorialEvent。
- State ItemsControl 绑定 `CurrentPlayer.SelectedCharacter.StatusEffects`，只显示四个 State status。
- Last ItemsControl 同样绑定 StatusEffects，只显示 28 个 Last status。
- 两个资源 ItemsControl 绑定 `Stats.ActionResources`，分别筛选 `COS_ChaosPowerPoint` 和 `COS_ChaosMasteryPoint`。
- 键鼠和手柄页的诊断状态 ID、handle 与资源 TypeId 集合完全一致。
- 页面 Loaded 仍且只触发 UUID `65247962-a3b0-417d-9044-85e4aad38079`。

加入 UI 变异检查：删掉手柄页的 READY DataTrigger、把 Power TypeId 写成 Mastery、把面板放到 Overview 之后，三种变异都必须失败。

- [ ] **Step 2：添加面板**

在现有 ScrollViewer 的顶部加入诊断区，布局顺序固定：

1. 分区标题“运行诊断”；
2. 静态版本；
3. 当前状态；
4. 最近同步问题；
5. 混沌之力当前点数；
6. 掌控混沌剩余点数；
7. 现有 `COSConfigOverview`，其调律/纠偏即已用掌控点的构成。

状态说明继续用 `CtxTransStringRunGeneratorBehavior Source="{Binding Description}"`，资源数值继续用 `{Binding Value, StringFormat={}{0:0}}`。不要加入“未知”“0”或其他静默占位；绑定缺失时由 State 状态明确报告配置缺口。

- [ ] **Step 3：运行专用绿灯**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify-runtime-diagnostics.ps1
```

Expected:

```text
ChaosOriginsStory runtime diagnostics verification: ok
```

- [ ] **Step 4：接入总验证器**

在 `story-src/verify.ps1` 末尾、最终成功文本之前加入：

```powershell
& (Join-Path $PSScriptRoot 'verify-runtime-diagnostics.ps1')
```

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify.ps1
```

Expected: 退出码 0；现有 `verify-level5-multitarget.ps1`、`verify-life-skill-exclusions.ps1` 和新诊断验证器均通过。

- [ ] **Step 5：提交功能实现**

```powershell
git add docs/runtime-contract-1.0.1.97.md story-src/verify-runtime-diagnostics.ps1 story-src/verify.ps1 story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt story-src/Public/ChaosOriginsStory/Stats/Generated/Data/ChaosConfig.txt story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu.xaml story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu_c.xaml story-src/Localization/Chinese/ChaosOriginsStory.xml story-src/Localization/English/ChaosOriginsStory.xml story-src/Localization/Japanese/ChaosOriginsStory.xml story-src/Localization/Korean/ChaosOriginsStory.xml
git commit -m "feat(story): add read-only runtime diagnostics"
```

Expected: 提交成功；`git status --short` 为空。

### Task 5：全量验证、编译和 `1.0.1.98` 发布候选

**Files:**

- Modify by successful build: `story-src/version.json`
- Modify by successful build: `story-src/Mods/ChaosOriginsStory/meta.lsx`
- Modify by successful build: `dist/ChaosOriginsStory.pak`
- Modify by successful build: `dist/build-manifest.json`
- Create: `docs/RELEASE-1.0.1.98.md`

- [ ] **Step 1：确认构建前状态**

Run:

```powershell
git status --short
Get-Content .\story-src\version.json
pwsh -NoProfile -File .\story-src\verify.ps1
```

Expected: 工作区干净；`lastBuild` 为 97；总验证退出码 0。

- [ ] **Step 2：构建一次且只构建一次**

Run:

```powershell
pwsh -NoProfile -File .\story-src\build.ps1
```

Expected: 版本递增为 `1.0.1.98`，`Version64` 为 `36028799166447714`，Story 编译、资源编译、IR 证明、PAK 反向解包和逐文件哈希全部通过，正式文件仍为 38 个。

构建失败时不要再次无条件运行 `build.ps1`，先确认 `version.json` 是否仍为 97；只有定位并修复失败后才重跑，避免误增多个版本号。

- [ ] **Step 3：验证构建产物**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify.ps1
Get-Content .\dist\build-manifest.json
Get-FileHash -Algorithm SHA256 .\dist\ChaosOriginsStory.pak
```

Expected: `displayVersion` 为 `1.0.1.98`；manifest 记录 38 个文件；PAK SHA256 与 build manifest 完全一致。

- [ ] **Step 4：导出唯一桌面候选**

目标目录只保留命名明确的发布 PAK，不创建本地备份目录：

```powershell
$target = 'C:\Users\ankerlcg\Desktop\博德之门3mod\ChaosOriginsStory-1.0.1.98.pak'
Copy-Item -LiteralPath .\dist\ChaosOriginsStory.pak -Destination $target -Force
(Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
```

Expected: 桌面候选与 `dist/ChaosOriginsStory.pak` SHA256 相同。本计划不自动替换游戏 Mods 目录；安装必须作为明确的后续动作执行，并保留其他 MOD 与加载顺序。

- [ ] **Step 5：写发布记录**

`docs/RELEASE-1.0.1.98.md` 必须记录：

- commit、显示版本、Version64、PAK SHA256、38 文件清单结论；
- 专用验证、总验证、Story 编译、IR 和反向解包结论；
- 诊断只读边界；
- 尚未游戏内验证，不能写“实机通过”；
- 下一阶段在本版实机通过后才开始。

- [ ] **Step 6：提交并推送 GitHub**

```powershell
git add story-src/version.json story-src/Mods/ChaosOriginsStory/meta.lsx dist/ChaosOriginsStory.pak dist/build-manifest.json docs/RELEASE-1.0.1.98.md
git commit -m "release(story): publish runtime diagnostics v1.0.1.98"
git push github codex/native-core-config
git status --short --branch
git log -3 --oneline --decorate
```

Expected: 本地分支与 `github/codex/native-core-config` 同步；工作区干净。GitHub 是源码和发布包备份，桌面不生成额外备份副本。

### Task 6：游戏内验收清单

**Files:**

- Update after test: `docs/RELEASE-1.0.1.98.md`

安装必须先确认游戏已退出，再仅替换模块 UUID `a5062238-0d2b-46d1-a093-cb02775b9f57` 对应 PAK；安装前后规范化比较 `modsettings.lsx`，不得改变其他模块和顺序。

- [ ] **Step 1：验证新档**

1. 非混沌起源角色打开菜单：显示 NOT_ORIGIN；不出现能力、资源或配置变化。
2. 新建混沌起源：显示 `1.0.1.98`、READY、混沌之力、剩余掌控点和现有分配总览。
3. 连续打开/关闭菜单 20 次：没有重复状态、服务器忙提示或明显卡顿。

- [ ] **Step 2：验证旧档**

1. 载入 `1.0.1.97` 存档：能进入游戏和角色创建界面，不清空加载顺序。
2. 打开菜单后当前状态为 READY；如果同步前曾有缺口，最近问题必须保留具体类别，不能被同步后的 READY 清除。
3. 关闭一个核心机制后重开菜单：配置、勾选镜像和诊断一致；再开启亦然。
4. 修改 Fate/Genesis 消耗、生活加值和负重后读档：本版不改变其保存行为。

- [ ] **Step 3：验证生命周期**

1. 升级、洗点、主控切换、队友加入后分别打开菜单。
2. 离队再入队路径只记录观察结果；本阶段没有 `CharacterLeftParty` 修复，发现问题进入阶段三迁移设计，不在诊断层兜底。
3. 键鼠和手柄页面显示相同状态和数值，诊断区不可点击。

- [ ] **Step 4：记录验收结果**

- 新档与旧档均可进入；菜单无 `Not Found`。
- 诊断状态与实际角色类型、配置和镜像相符。
- 打开菜单不改变混沌点、掌控点、设置值、法术、被动数量或战斗状态；已有同步路径除外，其修复必须被“最近同步问题”记录。
- 日志无新增 Osiris 错误、Story 初始化错误或资源加载错误。

完成实机测试后，只更新发布记录中的实机矩阵并提交证据；若失败，保留 `1.0.1.97` 为最近已知可用基线，先修复本阶段，不开始阶段二。
