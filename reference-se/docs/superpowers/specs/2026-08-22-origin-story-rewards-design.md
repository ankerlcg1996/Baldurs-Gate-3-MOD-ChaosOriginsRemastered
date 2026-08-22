# 起源剧情奖励同步设计

日期：2026-08-22

## 目标

把七个起源身份的能力成长从角色等级中完全移除，改为由官方剧情结果驱动。混沌起源角色既可以因自己经历相应起源剧情而获得奖励，也可以因队伍中的真实起源同伴完成相同剧情结果而获得奖励。旧存档中已经成立的剧情结果必须在重新开启对应身份时补发。

本次同时补齐盖尔的耐色瑞尔魔球自爆、幽影能力和完整成神形态，并把现有 100000 经验测试功能改为默认关闭的 MCM 选项。

## 已确认原则

- 七个起源身份默认全部开启。
- 身份基础能力在身份开启时存在，身份关闭时移除。
- 剧情成长能力不再依据角色等级发放。
- 官方剧情 Flag 是剧情结果的唯一事实来源，不根据对话决策者或角色等级猜测结果。
- 真实起源同伴完成剧情结果同样允许混沌角色认领奖励。
- 永久剧情奖励一旦被混沌角色认领，不因随后关闭身份而消失。
- 官方可撤销结果继续跟随官方 Flag；阶段升级按照官方顺序替换旧阶段。
- 不伪造起源角色 UUID，不 Hook 官方 UUID 查询，也不修改真实起源同伴的奖励过程。
- 不复制剧情奖励装备，只提取设计中明确列出的能力。
- 不主动增加容错或猜测性回退；资源、状态、调用或存档结构异常时明确失败。

## 模块边界

### `OriginFeatures.lua`

只管理身份开关、起源标签和基础能力。该模块不再保存任何等级阈值，也不处理剧情 Flag。

基础能力为：

- 阿斯代伦：`Target_VampireBite_Astarion`
- 威尔：`BladeOfFrontiers`
- 卡菈克：`ORI_Karlach_SweatImmune`、`ORI_Karlach_Rage_Flames`
- 盖尔、莱埃泽尔、影心、邪念：无额外基础战斗能力，仅保留各自身份标签

### `OriginStoryRewards.lua`

新增独立模块，以声明式规则表管理：

- 身份名称
- 官方剧情 Flag 及其作用域
- 奖励类型与资源名称
- 永久、可撤销、阶段替换或一次性消费语义
- 真实起源角色的固定 UUID（仅用于查询角色 Flag，不用于伪装混沌角色）

该模块公开统一同步入口，以及供服务器监听器调用的 `FlagSet`、`FlagCleared` 和 `CastedSpell` 处理函数。

### `BootstrapServer.lua`

继续作为唯一调度入口。角色载入、进入区域、MCM 修改、升级、洗点及相关 Flag 事件只负责安排同步，不在监听器内复制奖励规则。

Flag 变化后延迟一帧再同步，使官方 Story 有机会在同一处理链中完成校验、撤销或替换，避免认领短暂的中间状态。

## 存档结构与迁移

存档 Schema 从当前版本递增一版。每个混沌角色新增：

- `OriginStoryRewards.Claimed`：已经认领的永久奖励与一次性奖励键
- `OriginStoryRewards.Consumed`：已经使用的一次性奖励键
- `OriginStoryGranted.Passives`
- `OriginStoryGranted.Spells`
- `OriginStoryGranted.Statuses`

所有集合均使用明确的字符串到布尔值映射，并接受严格字段校验。

迁移时读取旧 `OriginGranted` 账本，只移除其中确认由旧版等级规则发放的被动和法术，再由新的基础身份规则与剧情规则重新计算。不得移除账本未认领的同名能力，避免破坏游戏本体、装备或其他 MOD 的来源。

永久剧情奖励的 Flag 在身份开启时成立即可首次写入 `Claimed`。写入后关闭身份不会删除该奖励。可撤销奖励不转为永久所有权；一次性奖励使用后写入 `Consumed`，身份关闭、重新开启、载入存档和洗点均不得刷新。

## 剧情奖励目录

### 阿斯代伦

官方结果：

- `ORI_Astarion_State_BecameVampireLord_c446ce94-efd8-45d5-b407-284177b6b57e`

永久奖励：

- `LOW_Astarion_VampireAscendant`
- `Shout_EPI_Astarion_TurnIntoBat`

官方蝙蝠能力原本在尾声阶段发放。本设计在飞升结果成立后直接作为飞升能力发给混沌角色，不额外等待尾声区域。

### 盖尔

#### 耐色瑞尔魔球自爆

官方结果：

- `ORI_Gale_Event_BombDisarmed_3d014e79-5595-9365-87bb-5cbb1f87fe5c`

永久奖励：

- `Target_END_Gale_ActivateNethereseOrb`

官方施法监听写死真实盖尔 UUID，因此混沌角色施放该法术时不得调用 `PROC_ORI_Gale_Explosion`。`OriginStoryRewards.lua` 单独监听混沌角色施法，在确认该角色已经认领自爆奖励后调用游戏结束界面。此能力不是普通范围伤害技能，施放结果固定为游戏结束。

#### 幽影法术位

官方结果：

- `ORI_Gale_State_AbsorbedTWNBossPower_7d08986a-5410-ccdf-fe70-aaec379a1962`

永久奖励：

- `ORI_Gale_ShadowSpellSlots`

该被动提供 1 点幽影法术位，资源上限为 3 点。

#### 幽影召唤

官方结果：

- `ORI_Gale_State_CraftedDarkLantern_3ddebb12-8c9f-47b4-8b6a-bb8eeac51a9b`

永久奖励：

- `Target_ORI_Gale_ShadowSummon`

游戏本体通过幽影提灯装备解锁该法术。本设计不复制提灯，仅在制作提灯结果成立后直接发放法术。

#### 完整成神形态

官方结果：

- `ORI_Gale_State_IsGod_ec94f9a4-b032-ce25-f4eb-ecf4ed37d65d`

永久奖励与状态：

- 普通角色应用 `EPI_GALEGOD`
- 具有 `FULL_CEREMORPH_3797bfc4-8004-4a19-9578-61ce0714cc0b` 标签时应用 `EPI_GALEGOD_MINDFLAYER`
- 设置不死
- 设置无敌
- 保持角色当前等级，不执行官方队友版神盖尔的 20 级调整

`EPI_GALEGOD` 系列状态负责神化外观、4 米范围内友方技能检定与裸属性检定 `+10`，并解锁：

- `Projectile_EPI_Disintegrate_GaleGod`
- `Target_EPI_PartyTime_GaleGod`
- `Target_EPI_Polymorph_GaleGod`

同步时根据混沌角色当前夺心魔标签确保只保留正确的神化状态变体。

### 威尔

#### 米佐拉审判奖励

角色 Flag：

- `CAMP_MizorasJudgement_Event_Reward_eb10f6f8-cf1a-a2b2-4421-63b0fbeb7a23`

永久奖励：

- `Shout_ORI_Wyll_FireShield_Warm`

不复制 `ORI_Wyll_Infernal_Robe`，也不继承长袍的护甲等级与火焰抗性。

#### 营救米佐拉奖励

角色 Flag：

- `COL_MizorasRescue_Event_Reward_0e2f2a09-604c-2b9d-b8c0-db2baa1e6ac8`

永久奖励：

- `Target_ORI_Wyll_SummonCambion`

不复制 `ORI_Wyll_Infernal_Rapier` 及其其他装备属性。

两项角色 Flag 均查询混沌角色和真实威尔 `c774d764-4a17-48dc-b470-32ace9ce447d`。任一对象具有 Flag 即视为队伍已经完成该结果。

### 卡菈克

第一次引擎升级 Flag：

- `GLO_ForgingOfTheHeart_State_KarlachUpgraded_a818e2f5-9e0c-4ab3-8c1e-00765d3b892f`

对应状态：

- `ORI_KARLACH_FIRSTUPGRADE`

第二次引擎升级 Flag：

- `GLO_ForgingOfTheHeart_State_KarlachSecondUpgrade_f6dc0de4-1089-43c0-b392-306a9a44387c`

对应状态：

- `ORI_KARLACH_SECONDUPGRADE`

第二次结果优先于第一次结果。第二次 Flag 成立时移除第一次状态并应用第二次状态。不得继续直接发放 `Karlach_Infernal_Fury`，因为它不是这两个剧情升级结果直接给予的能力。

### 邪念

#### 杀戮形态

官方结果：

- `ORI_DarkUrge_State_GivenSlayerForm_14aec5bc-1013-4845-96ca-20722c5219e3`

可撤销奖励：

- `Shout_DarkUrge_Slayer`

Flag 成立时存在，Flag 清除时移除。该规则不得转成永久 `Claimed` 所有权。

#### 一次性律令：死亡

官方结果：

- `ORI_DarkUrge_State_BhaalAccepted_904c45e0-bb06-40ed-b5d7-4f1c851b9d86`

一次性奖励：

- `Target_LOW_DarkUrge_PowerWordKill`

混沌角色首次满足结果并开启邪念身份时获得一次。混沌角色施放后立即移除该法术并写入 `Consumed`。该消费记录与真实邪念角色的一次性使用状态相互独立。

旧版等级规则中的 `UNI_DarkUrge_Stealth_Expertise_Passive` 和 `UNI_DarkUrge_Bleeding_Dagger_Passive` 不属于本设计的剧情奖励，迁移后不再发放。

### 莱埃泽尔与影心

本次仅保留身份标签。银剑、莎尔/塞伦涅武器等属于剧情装备，不转换为直接能力，也不新增未经验证的成长奖励。

## MCM 与 12 级测试经验

新增默认关闭的“12级测试经验”布尔选项，并对每个混沌角色独立保存。

- 从关闭切换为开启时，立即读取主控混沌角色总经验。
- 总经验低于 100000 时只补足差额。
- 总经验已经达到或超过 100000 时不做处理。
- 选项保持开启时，每次进入游戏会再次检查，但不得重复超过 100000。
- 关闭选项不扣除经验、不降级。
- 不调用直接升级接口，玩家仍在原生升级界面逐级确认成长。

MCM 继续禁止战斗中修改身份与机制。身份页帮助文字必须说明：开启身份会补发已经完成的剧情奖励；关闭身份不会收回已经认领的永久奖励；剧情奖励没有手动解锁开关。

## 同步与事件

以下事件安排角色同步：

- 会话载入和 `LevelGameplayStarted`
- 角色创建结束、成为玩家、加入队伍、区域可用状态变化
- 升级和洗点完成/取消
- MCM 身份或测试经验选项变化
- 本设计登记的 `FlagSet` 与 `FlagCleared`

`CastedSpell` 仅处理：

- 混沌角色施放耐色瑞尔魔球自爆后显示游戏结束
- 混沌角色施放一次性律令死亡后消费奖励

同步必须可重入保护且幂等。同一个事件被多次触发时不得重复认领、重复增加资源或重复消费。

## 验证要求

### 静态验证

- `OriginFeatures.lua` 中不再出现起源能力等级阈值。
- `OriginStoryRewards.lua` 的每个被动、法术和状态均通过 `Ext.Stats.Get` 验证。
- Flag UUID、真实威尔 UUID、完整夺心魔标签和能力名称与规则表固定值一致。
- 旧等级能力不得重新出现在基础能力表。
- MCM 协议、四种本地化和存档字段保持一致。

### 存档与逻辑验证

- Schema 迁移只清理旧 MOD 账本认领的能力。
- 新旧存档重复同步结果一致。
- 身份关闭后基础能力移除，永久剧情奖励保留。
- 关闭身份时发生的剧情结果，在重新开启后补发。
- 真实起源同伴完成剧情结果也能补发给混沌角色。
- 卡菈克第二升级替换第一升级。
- 杀戮形态随 Flag 清除而移除。
- 律令死亡使用后，载入、洗点和重新开启身份均不恢复。

### 游戏内验收

- 新角色创建、守护者创建和 1 至 12 级升级仍正常。
- 默认不再自动获得 100000 经验；MCM 开启后只补足差额。
- 阿斯代伦飞升能力、威尔两项奖励、卡菈克两阶段升级和邪念两项奖励按目录工作。
- 盖尔自爆导致游戏结束。
- 幽影法术位和幽影召唤分别由各自 Flag 触发。
- 普通与夺心魔成神形态均具有正确外观、三项法术、`+10` 光环、不死和无敌，且混沌角色等级不改变。
- 身份被动本身不产生明显的可见 BUFF 图标。

### 构建与安装

实现完成后运行静态验证、正式构建和反向解包文件/哈希校验。构建版本从当前已安装的 `1.0.20` 递增为下一小版本。仅在确认游戏已经关闭后安装 PAK，并分别报告构建成功、安装哈希和仍需游戏内验证的项目。
