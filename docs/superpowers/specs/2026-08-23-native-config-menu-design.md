# 混沌起源原生设置菜单设计

## 目标

为 `ChaosOriginsStory` 增加完全独立的原生设置系统。玩家可从暂停菜单或角色专属的“混沌设置手册”修改配置。系统只使用 BG3 原生 XAML、Stats、RootTemplate 与 Story，不依赖 NMCM、MCM、ImprovedUI 或 Script Extender。

设置按混沌角色分别保存。只有主机可以修改其当前控制的混沌角色；战斗中只允许查看。新角色、旧存档首次迁移和“恢复默认”均启用原有正式玩法设置；新增的“全部种族被动”开关始终默认关闭。

## 非目标

- 不复制或内嵌 NMCM。
- 不保留 SE 调试日志或“12级测试经验”选项。
- 不提供跨存档的全局配置。
- 不通过静态编译结果宣称游戏内 UI 已通过。
- 本设计不扩大 Story 伤害接口的能力；两仪的致死伤害、临时生命和复合伤害限制仍然存在。

## 用户界面

### 暂停菜单入口

`Keyboard.xaml` 和 `Controller.xaml` 使用 `ModType="Extend"` 向原生暂停状态添加“混沌起源设置”按钮。按钮打开独立的 `COS_ConfigMenu` 模态状态，不替换原生暂停菜单。

设置页包含三个标签：

1. 常规机制
2. 七起源身份
3. 受击轮盘结果

页面底部提供“恢复默认”和“返回”。鼠标、键盘和手柄均可完成打开、切换、修改和关闭操作。ESC 或手柄 B 键关闭当前页面。

页面以主机当前控制的角色为设置对象。主机要修改另一名角色，必须先取得该角色的控制权。非主机、非混沌角色和战斗中的角色看到只读页面及明确原因。

### 设置手册入口

每个混沌角色获得一本“混沌设置手册”。发放过程先检查模板是否已经存在于角色物品栏，避免重复生成。

使用手册后，玩家通过原生法术容器依次进入“常规机制”“起源身份”或“受击结果”。每个设置提供开启和关闭操作；与当前状态冲突的操作不可用。手册还提供“全部身份开启”“全部身份关闭”和“恢复默认”。

手册修改使用者自身。Story 对手册请求执行与 XAML 请求相同的权限、战斗状态和角色身份校验。

## 配置范围

### 常规机制

系统保存八项原有机制设置，并在同一页提供一项独立的种族被动总开关：

| 键 | 设置 | 控制范围 |
| --- | --- | --- |
| `Skills` | 技能专精 | 全技能熟练与专精 |
| `Power` | 混沌之力 | 迷失积累、转化和开天辟地 |
| `Wound` | 混沌受创 | 每回合首次受击轮盘 |
| `KillPower` | 击杀之力 | 击杀计数及混沌之力奖励 |
| `Duality` | 混沌两仪 | 攻击伤害轮盘 |
| `AllIn` | 混沌孤注 | 孤注技能、次数和倍率 |
| `Echo` | 混沌回响 | 攻击后的额外伤害或治疗 |
| `Strike` | 混沌强袭 | 12级强袭能力 |
| `AllRacialPassives` | 全部种族被动 | 审核白名单中的二十项官方种族被动；默认关闭 |

关闭机制时保留混沌之力、迷失层数和击杀计数。重新开启后继续使用原值。关闭孤注或强袭时立即清理等待结算的相关状态。关闭两仪时取消尚未结算的延迟轮盘伤害。

“全部种族被动”开启时，系统向该混沌角色补充以下二十项被动：

| 被动 Stats ID | 被动 Stats ID |
| --- | --- |
| `DeepGnome_StoneCamouflage` | `Drow_DrowWeaponTraining` |
| `Duergar_DuergarResilience` | `Dwarf_DwarvenCombatTraining` |
| `Dwarf_DwarvenResilience` | `Elf_WeaponTraining` |
| `FeyAncestry` | `Gith_MartialProdigy` |
| `Gnome_Cunning` | `Halfling_Brave` |
| `Halfling_LightfootStealth` | `Halfling_Lucky` |
| `Halfling_StoutResilience` | `HumanMilitia` |
| `MountainDwarf_DwarvenArmorTraining` | `RelentlessEndurance` |
| `RockGnome_ArtificersLore` | `SavageAttacks` |
| `SuperiorDarkvision` | `Tiefling_HellishResistance` |

系统使用 `DB_COS_RacialPassiveGranted(Character, Passive)` 记录本开关实际补发的被动。开启时，角色已经拥有的同名被动不写入授予账本；关闭时只移除账本内的被动。因此，角色由原生种族、其他能力或其他 MOD 获得的同名被动不受影响。该开关不授予种族标签、种族主动技能或种族法术。

### 起源身份

系统分别保存阿斯代伦、盖尔、莱埃泽尔、影心、威尔、卡菈克和邪念七项身份设置，并提供全部开启或全部关闭操作。

关闭身份会移除该身份授予的官方标签和即时能力。系统保留已经通过剧情永久认领的奖励，也保留一次性奖励的消耗记录。再次开启身份时，系统根据当前剧情 Flag 补发尚未认领且符合条件的奖励。

七起源身份开关不控制32种族身份标签、29项种族主动技能或种族法术。这些种族功能继续保持启用，避免关闭起源身份时误删种族能力。二十项官方种族被动仅由独立的“全部种族被动”开关控制。

### 受击负面结果

系统分别保存十五项负面结果：疯狂、恐慌、眩晕、沉默、倒伏、目盲、减速、中毒、流血、燃烧、近战劣势、远程劣势、法术劣势、随机易伤和额外随机伤害。

关闭的结果从抽取池中移除。Story 根据当前启用结果重建每个角色的抽取池，并让剩余负面结果与固定保留的正面结果等概率出现。系统不使用“抽中后无效果”或递归重投。

## 状态与持久化

Story 数据库是设置的唯一真实来源。每个角色分别保存三组数据：

- `DB_COS_ConfigMechanic(Character, Key, Enabled)`
- `DB_COS_ConfigOrigin(Character, Key, Enabled)`
- `DB_COS_ConfigWound(Character, Key, Enabled)`

注册混沌角色时，初始化过程只补充缺失的键。现有值不会被覆盖。八项原有机制、七项身份和十五项负面结果的默认值为 `1`；`AllRacialPassives` 的默认值为 `0`。旧存档首次载入时也使用同一套默认值。

“恢复默认”把八项原有机制、七项身份和十五项负面结果改为 `1`，把 `AllRacialPassives` 改为 `0`。重置时只撤销授予账本内的种族被动，不修改角色原本拥有的同名被动，也不修改混沌之力、迷失、击杀计数、永久剧情奖励或一次性奖励的消耗记录。

XAML 无法直接读取 Story 数据库。每项设置因此对应一个 `COS_CFG_*` 隐藏被动。数据库保存真实值，隐藏被动只向 UI 回显。菜单打开、读档、切换控制角色和设置变化时触发同步；系统不逐帧轮询。

## 请求与权限

XAML 为每个固定操作发送独立的 `TutorialEvent`。手册为每个固定操作使用独立技能。系统不接受任意字符串键。

Story 按以下顺序处理请求：

1. 确认目标是混沌角色。
2. 读取主机角色和目标角色的 `GetReservedUserID`，确认目标当前归主机控制。
3. 确认目标不在战斗中。
4. 获取按角色设置的忙碌锁。
5. 更新配置数据库。
6. 应用或移除实际标签、被动、技能和运行状态。
7. 同步隐藏回显被动。
8. 释放忙碌锁。

界面禁用只改善交互体验，Story 校验负责安全。快速双击、迟到事件或伪造事件不能绕过权限与战斗锁。

拒绝请求时，系统显示本地化提示：

- 仅主机可以修改设置。
- 战斗中无法修改设置。
- 当前角色不是混沌起源角色。
- 设置正在同步。

实际能力同步失败时，系统不得把回显标记改成成功状态。失败必须保持可见，不得用默认值掩盖。

## 组件与文件边界

### Story

新增 `Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt`，负责配置初始化、权限校验、写入、重置、抽取池重建和 UI 镜像。现有战斗 Goal 只读取配置结果或调用明确的配置查询过程。

### GUI

新增以下独立资源：

- `Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigEscButton.xaml`
- `Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigEscButton_c.xaml`
- `Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu.xaml`
- `Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu_c.xaml`
- `Mods/ChaosOriginsStory/GUI/StateMachines/Keyboard.xaml`
- `Mods/ChaosOriginsStory/GUI/StateMachines/Controller.xaml`
- `Mods/ChaosOriginsStory/GUI/metadata.lsf`

所有页面、状态、事件和资源使用 `COS_CFG_*` 命名及新 UUID。GUI 不复用 NMCM 的模块名、栏位、资源路径或标识符。

### 数据资源

新增或扩展以下资源：

- `Public/ChaosOriginsStory/Tutorials/TutorialEvents.lsx`
- `Public/ChaosOriginsStory/Stats/Generated/Data/ChaosConfig.txt`
- 设置手册的 RootTemplate LSF
- 四语设置文本与错误提示

`ChaosConfig.txt` 保存隐藏回显被动、手册容器和固定操作技能。RootTemplate 定义每个角色持有的设置手册。

### 构建

资源编译脚本改为编译清单列出的全部 `.lsf.lsx`，不再断言输入必须恰好为两个文件。打包清单加入 GUI、TutorialEvents、RootTemplate、Stats 和本地化产物。

`meta.lsx` 的依赖列表保持为空。构建检查拒绝 `ScriptExtender`、`MCM_blueprint`、`BG3MCM` 和 `NMCM` 文件或路径。

## 兼容性边界

暂停菜单使用状态机扩展，避免覆盖原生状态。完全替换暂停状态的其他 UI MOD 仍可能遮蔽按钮。设置手册不依赖暂停状态，因此仍可操作同一套配置。

BG3 更新可能改变原生 XAML 绑定、资源名称或焦点行为。静态编译无法排除此风险。每次适配游戏版本后必须重新测试鼠标键盘和手柄。

本功能不改变 Story 的伤害观察时点。两仪继续在 `AttackedBy` 后处理汇总伤害，无法精确改写致死伤害、临时生命和复合伤害包。

## 验证方案

### 静态检查

- 八项原有机制、一项种族被动总开关、七项身份和十五项负面结果在数据库、XAML、手册与本地化中一一对应。
- 每个 XAML 事件和手册技能只有一个 Story 处理器。
- 所有 UUID、状态机名称和资源路径唯一。
- PAK 不包含 SE、MCM 或 NMCM 文件。
- 配置初始化只补缺失键；`AllRacialPassives` 在新角色、旧存档首次迁移和恢复默认时均为 `0`。
- 关闭或重置种族被动开关只移除 `DB_COS_RacialPassiveGranted` 记录的被动。
- 恢复默认不修改运行计数和奖励账本。

### 编译与打包

- StoryCompiler 成功生成 `story.div.osi`。
- 所有 LSX 转 LSF、XML 转 LOCA 操作成功。
- 打包文件与精确清单一致。
- 反向解包后的文件列表和 SHA-256 与 staging 完全一致。

### 游戏内设置验收

- 鼠标键盘和手柄均可打开、操作和关闭设置页。
- 每本手册只修改使用者。
- 切换控制角色后显示该角色自己的配置。
- 战斗中锁定控件；非主机只能查看。
- 保存、读档和换地图后配置保持不变。
- 恢复默认不清空力量、迷失、击杀和剧情奖励。
- 新角色和旧存档首次迁移后，“全部种族被动”均显示为关闭。
- 开启种族被动开关后获得白名单中原本缺失的被动；关闭后只撤销本开关授予的被动。
- 角色原本拥有的白名单同名被动在开关关闭和恢复默认后仍然保留。

### 玩法回归

- 逐项关闭八项原有机制，确认相应功能停止且无残留状态。
- 关闭任意受击结果后，抽取池没有空结果且剩余结果等概率。
- 关闭身份后移除标签和即时能力，但保留永久剧情奖励。
- 两仪、受击额外伤害和回响不递归触发。
- 首次受击锁、两仪倍率、孤注与强袭组合重新实测。

Story 编译、PAK 安装和游戏内通过是三个独立结论。只有完成游戏内设置验收与玩法回归后，才能声明原生设置菜单完成。
