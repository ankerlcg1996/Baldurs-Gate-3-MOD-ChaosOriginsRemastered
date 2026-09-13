# ChaosOriginsStory 1.0.1.97 运行合同

本文冻结纯 Story 版本 `1.0.1.97` 的静态运行合同，作为后续运行诊断状态的实现基线。它不是实机验收记录。

## 版本与打包边界

- `story-src/version.json`：`major.minor.revision = 1.0.1`，`lastBuild = 97`。
- `story-src/package-files.json`：`files` 包含 38 个唯一文件，其中明确列入下述六个 Story Goal。
- 本合同只描述 `ChaosOriginsStory` 的原生 Story/Osiris 路径，不引入 Script Extender 运行时。

## 六个 Goal 的职责与入口

| Goal | 冻结职责 | 生命周期入口与补充触发 |
| --- | --- | --- |
| `COS_BaseAfterCreation.txt` | `PROC_COS_SyncBaseAfterCreation` 同步基础被动、核心被动/法术、起源身份与 grant 镜像；`PROC_COS_TryStartingBag` 只为新建角色处理起始冒险者袋。 | `CharacterCreationFinished` 建立新角色袋资格；`LevelGameplayStarted`、`GainedControl`、`LeveledUp`、`RespecCompleted` 重同步。 |
| `COS_ChaosMastery.txt` | `PROC_COS_SyncMastery` 管理混沌精通可用点、路线计数、载体、状态、法术和总览，并负责 46 到 47 的旧档迁移。 | `LevelGameplayStarted`、`GainedControl`、`LeveledUp` 同步；`RespecCompleted` 执行 `PROC_COS_ResetMastery`。 |
| `COS_ChaosMechanics.txt` | `PROC_COS_Sync` 注册并同步 Power、Lost/Wound、KillPower、Duality、AllIn、Fate、Genesis、Strike、Mastery 关联的战斗运行态与生活加值状态。 | `LevelGameplayStarted`、`GainedControl`、`CharacterJoinedParty`、`LeveledUp` 重同步；另有战斗、施法、伤害、死亡、状态等机制事件。 |
| `COS_Config.txt` | `PROC_COS_ConfigSyncCharacter` 维护九个核心开关、生活加值、20 个种族被动、grant 菜单、标签法术、眼部奖励、Fate/Genesis 成本及其 TutorialEvent/镜像。 | `LevelGameplayStarted`、`GainedControl`、`LeveledUp`、`RespecCompleted` 同步；`Resurrected` 与 `PROC_LongRest` 专门同步 Volo eye。 |
| `COS_GlobalPlayerBenefits.txt` | `PROC_COS_SyncGlobalPlayerBenefits` 初始化、应用和镜像全局负重开关 `DB_COS_CarryEnabled` / `COS_GlobalCarryCapacity50x`。 | `LevelGameplayStarted`、`GainedControl`、`CharacterJoinedParty`、`RespecCompleted` 重同步。 |
| `COS_OriginStoryRewards.txt` | `PROC_COS_SyncOriginStoryRewards` 根据 `DB_COS_OriginStoryFlag` 与当前起源身份同步剧情奖励。阿斯代伦、盖尔、威尔只有正向授予路径；卡菈克会正向应用升级状态、二次升级时移除一次升级，并在移除其起源身份时移除两种升级状态；邪念的 Slayer 会在对应 flag 不成立或移除其起源身份时撤销，Power Word Kill 则只在实际使用后移除并记录消耗。`FlagCleared` 只触发同步，不代表所有奖励都有撤销分支。 | `LevelGameplayStarted`、`GainedControl` 同步；`StatusApplied`、`StatusRemoved`、`FlagSet`、`FlagCleared` 和特定 `UsingSpell` 维护源码中明确实现的奖励状态。 |

## 九个核心配置键

来源为 `COS_Config.txt` 的 `DB_COS_ConfigMechanicDefault`、`DB_COS_ConfigMechanicMirror` 与 `DB_COS_ConfigMechanicEvent`。九项默认值均为 `1`。

| Key | Default | Mirror | Event |
| --- | ---: | --- | --- |
| `Power` | 1 | `COS_CFG_MECH_POWER` | `COS_CFG_MECH_POWER_7f818c10-3f23-49f8-838a-d161c57bb35d` |
| `Wound` | 1 | `COS_CFG_MECH_WOUND` | `COS_CFG_MECH_WOUND_0574b4b8-549a-4b39-b810-6890c68642b1` |
| `KillPower` | 1 | `COS_CFG_MECH_KILLPOWER` | `COS_CFG_MECH_KILLPOWER_71abdeef-69d2-4385-8885-4f9ebbd829ca` |
| `Duality` | 1 | `COS_CFG_MECH_DUALITY` | `COS_CFG_MECH_DUALITY_aa88abcb-5f2e-452c-bdce-3ca6176db1e0` |
| `AllIn` | 1 | `COS_CFG_MECH_ALLIN` | `COS_CFG_MECH_ALLIN_2dd4ef80-1686-4989-8773-3cf6f12b9a36` |
| `Fate` | 1 | `COS_CFG_MECH_FATE` | `COS_CFG_MECH_FATE_aff82c28-d71a-4dad-837d-d41d8519051a` |
| `Genesis` | 1 | `COS_CFG_MECH_GENESIS` | `COS_CFG_MECH_GENESIS_063cc1a5-fe65-43e5-8531-d6974a7b1dce` |
| `Strike` | 1 | `COS_CFG_MECH_STRIKE` | `COS_CFG_MECH_STRIKE_78baf203-f60c-4dac-99ea-a7f5d1339d71` |
| `Mastery` | 1 | `COS_CFG_MECH_MASTERY` | `COS_CFG_MECH_MASTERY_146d28dc-aa94-40e8-9bad-91b069055526` |

## 生活加值

生活加值默认 5，范围 0..20，仅作用于 16 个生活技能。Story 侧由 `DB_COS_ConfigLifeDefault(5)` 建立默认值，`PROC_COS_ConfigStepLifeSkill` 通过 `IntegerMax(..., 0, ...)` 与 `IntegerMin(..., 20, ...)` 限制范围，`DB_COS_ConfigLifeBonusStatus` 将数值映射到 `COS_CFG_LIFE_SKILL_STATUS_01` 至 `COS_CFG_LIFE_SKILL_STATUS_20`。

冻结的 16 项为：`AnimalHandling`、`Arcana`、`Deception`、`History`、`Insight`、`Intimidation`、`Investigation`、`Medicine`、`Nature`、`Perception`、`Performance`、`Persuasion`、`Religion`、`SleightOfHand`、`Stealth`、`Survival`。明确排除 `Athletics` 与 `Acrobatics`。

## 官方种族被动默认值

`COS_Config.txt` 通过 `DB_COS_ConfigRacialDefault` 定义 20 个官方种族被动默认均为 0，并用相应的 `DB_COS_ConfigRacialMirror` 与 `DB_COS_ConfigRacialEvent` 提供配置镜像和 TutorialEvent。

这 20 项是：`DeepGnome_StoneCamouflage`、`Drow_DrowWeaponTraining`、`Duergar_DuergarResilience`、`Dwarf_DwarvenCombatTraining`、`Dwarf_DwarvenResilience`、`Elf_WeaponTraining`、`FeyAncestry`、`Gith_MartialProdigy`、`Gnome_Cunning`、`Halfling_Brave`、`Halfling_LightfootStealth`、`Halfling_Lucky`、`Halfling_StoutResilience`、`HumanMilitia`、`MountainDwarf_DwarvenArmorTraining`、`RelentlessEndurance`、`RockGnome_ArtificersLore`、`SavageAttacks`、`SuperiorDarkvision`、`Tiefling_HellishResistance`。

## grant 菜单合同

`story-src/grant-menu.json` 共 74 项，按 `group` 精确分为五组：

| Group | Count |
| --- | ---: |
| Origin | 7 |
| Tag | 31 |
| Weapon | 31 |
| Armor | 4 |
| Instrument | 1 |

`COS_Config.txt` 以 `PROC_COS_SeedGrantMap` 在运行时填充 `DB_COS_GrantEvent`、`DB_COS_GrantOrigin`、`DB_COS_GrantOption`、`DB_COS_GrantTag`、`DB_COS_GrantNativeMap`、批量分组和标签法术映射；JSON 中的 `key`、`event`、`mirror` 是这套 Story 映射的清单来源。

## ActionResource 合同

`story-src/Public/ChaosOriginsStory/ActionResourceDefinitions/ActionResourceDefinitions.lsx` 实际包含且只包含七个 `ActionResourceDefinition`：

| Name |
| --- |
| `COS_ChaosStrike` |
| `COS_ChaosAllInUse` |
| `COS_ChaosPowerPoint` |
| `COS_ChaosMasteryPoint` |
| `COS_ConfigLifeSkill` |
| `COS_ConfigFateCost` |
| `COS_ConfigGenesisCost` |

## 旧档标记与运行时 seed

- 精通迁移：`COS_ChaosMastery.txt` 用 `DB_COS_MasterySchema46To47` 区分迁移前后状态；`PROC_COS_MigrateMasterySchema46To47` 重置旧载体，再由 `PROC_COS_SyncMasteryAfterSchema47` 按当前等级补齐新结构。
- 命运改签 legacy 清理：`COS_ChaosMechanics.txt` 的 `PROC_COS_MigrateLegacyFatePending` 清除旧状态 `COS_CHAOS_FATE_PENDING`；仅当 Power 已启用且 `DB_COS_Power` 存在时返还 1 点，其他已定义分支只清除遗留状态。
- grant/runtime mapping seed：`COS_Config.txt` 明确把 grant configuration mappings 设计为升级存档的运行时 seed。`PROC_COS_ConfigSyncGrants` 每次先调用 `PROC_COS_SeedGrantMap`，再执行 native/existing/legacy/unresolved 捕获并写入 `DB_COS_GrantInitialized`。
- 成本 seed：`PROC_COS_ConfigSeedCosts` 在运行时建立 Fate 默认成本 1 与 Genesis 默认成本 10，使已有存档也能得到这两个控制项。

## 生命周期矩阵

`Frozen Behavior` 使用固定合同 token，并由专用验证器逐字段精确校验。

| Entry | Status | Handlers | Frozen Behavior |
| --- | --- | --- | --- |
| `CharacterCreationFinished` | handled | `COS_BaseAfterCreation.txt` | `seed-new-character-starting-bag-eligibility` |
| `LevelGameplayStarted` | handled | `COS_BaseAfterCreation.txt`, `COS_ChaosMastery.txt`, `COS_ChaosMechanics.txt`, `COS_Config.txt`, `COS_GlobalPlayerBenefits.txt`, `COS_OriginStoryRewards.txt` | `resync-runtime-and-clean-orphan-duality` |
| `GainedControl` | handled | `COS_BaseAfterCreation.txt`, `COS_ChaosMastery.txt`, `COS_ChaosMechanics.txt`, `COS_Config.txt`, `COS_GlobalPlayerBenefits.txt`, `COS_OriginStoryRewards.txt` | `resync-on-control-change` |
| `CharacterJoinedParty` | handled | `COS_ChaosMechanics.txt`, `COS_GlobalPlayerBenefits.txt` | `resync-mechanics-and-carry` |
| `LeveledUp` | handled | `COS_BaseAfterCreation.txt`, `COS_ChaosMastery.txt`, `COS_ChaosMechanics.txt`, `COS_Config.txt` | `resync-base-mastery-mechanics-config` |
| `RespecCompleted` | handled | `COS_BaseAfterCreation.txt`, `COS_ChaosMastery.txt`, `COS_Config.txt`, `COS_GlobalPlayerBenefits.txt` | `resync-base-config-carry-reset-mastery` |
| `Resurrected` | handled | `COS_Config.txt` | `sync-volo-eye` |
| `PROC_LongRest` | handled | `COS_Config.txt` | `sync-volo-eye-for-avatars` |
| `CharacterLeftParty` | not-handled | none | `no-handler` |

六个 Goal 的文本中当前没有 `CharacterLeftParty` 处理。因此，本文只记录离队入口缺口，不在本阶段增加清理规则，也不推断离队后数据库、被动或显示态一定会怎样变化。

## 实机验收边界

下列场景未经实机验收，静态文档、PowerShell 验证、Story 源码存在性、XML/JSON 解析和打包清单一致性均不能替代游戏内结论：

- 旧档升级；
- 离队重入；
- 多人主控切换；
- 手柄页；
- 重复打开菜单性能。
