# 混沌起源原生设置菜单实施计划

> 设计依据：`docs/superpowers/specs/2026-08-23-native-config-menu-design.md`

## 目标

在 `ChaosOriginsStory` 中实现完全独立的原生设置系统：暂停菜单 XAML 页面和角色专属设置手册共用同一套 Story 配置；不依赖 NMCM、MCM、ImprovedUI 或 Script Extender。设置按混沌角色保存、仅主机可改、战斗中只读。

正式配置包括八项玩法机制、二十项去重的官方种族被动、七项起源身份和十五项受击负面结果。原有玩法、身份和负面结果默认开启；二十项种族被动默认关闭，并支持逐项切换、一键全选和一键取消。

## 实现原则

- `DB_COS_Config*` 是唯一真实来源；XAML 隐藏被动和手册技能只负责显示与发出固定请求。
- 每个 XAML 操作使用固定 TutorialEvent UUID，每个手册操作使用固定 Spell Stats ID；不接收任意字符串键。
- 种族被动以官方 Stats ID 去重。`DB_COS_RacialPassiveGranted` 只记录本 MOD 实际添加的被动，关闭时不得删除角色原本已有项。
- 所有修改请求使用同一权限、战斗锁和角色忙碌锁。
- 参考 PAK 只用于核对原生资源结构。正式包不得包含其模块、UUID、SE、MCM 或 NMCM 文件。
- 静态验证、Story 编译、PAK 反向校验、安装哈希和游戏内验收分别报告。

## Task 1：建立可重复的静态验证基线

**文件：**

- 新增：`story-src/verify.ps1`
- 读取：`story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosOrigins.txt`
- 读取：`story-src/package-files.json`

**步骤：**

1. 编写失败即抛错的验证脚本，检查模块 UUID、`COS_` 命名、四语本地化 handle 集合、打包清单唯一性和依赖列表为空。
2. 扫描正式源目录和打包清单，拒绝 `ScriptExtender`、`MCM_blueprint`、`BG3MCM`、`NMCM_` 及参考模块 UUID。
3. 记录当前八项机制、七项身份、十五项负面结果和二十项种族被动 Stats ID 的精确清单；检查清单无重复。
4. 运行：

   ```powershell
   .\story-src\verify.ps1
   ```

   预期：输出 `ChaosOriginsStory source verification: ok`。
5. 仅提交验证脚本：`test: add Story source verification`。

## Task 2：扩展资源编译与打包清单

**文件：**

- 修改：`story-src/compile-resources.ps1`
- 修改：`story-src/build.ps1`
- 修改：`story-src/package-files.json`
- 修改：`story-src/verify.ps1`

**步骤：**

1. 删除“资源必须恰好为两个”的断言，改为递归编译清单中声明的全部 `*.lsf.lsx`。
2. 保留扩展名、源文件存在、目标文件生成和失败即抛错规则；不扫描并自动夹带未列入清单的文件。
3. 让清单可容纳 `Mods/ChaosOriginsStory/GUI/metadata.lsf`、RootTemplate LSF、现有 Tags 与 TextureBank LSF。
4. 保持 staging 精确文件集检查、反向解包和逐文件 SHA-256 比较。
5. 先运行 `verify.ps1`，再运行当前 `build.ps1`，确认扩展编译器未破坏现有 18 文件基线。
6. 提交：`build: support native config resources`。

## Task 3：建立配置目录、默认值和持久化

**文件：**

- 新增：`story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt`
- 修改：`story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosOrigins.txt`
- 修改：`story-src/verify.ps1`

**步骤：**

1. 在 `COS_Config.txt` 声明四组角色配置：

   - `DB_COS_ConfigMechanic(Character, Key, Enabled)`
   - `DB_COS_ConfigRacialPassive(Character, Passive, Enabled)`
   - `DB_COS_ConfigOrigin(Character, Key, Enabled)`
   - `DB_COS_ConfigWound(Character, Key, Enabled)`

2. 声明精确目录行：八项机制默认 `1`、七项身份默认 `1`、十五项负面结果默认 `1`、二十项种族被动默认 `0`。
3. 实现只补缺失键的幂等初始化；不得覆盖旧存档中已经存在的值。
4. 从现有 `PROC_COS_Register` 和 `PROC_COS_Sync` 调用配置初始化与同步。
5. 实现“恢复默认”：前三组恢复 `1`，二十项种族被动恢复 `0`；不修改力量、迷失、击杀和剧情奖励账本。
6. 为每个角色实现 `DB_COS_ConfigBusy(Character)`；请求完成或明确拒绝时必须释放。
7. 用 StoryCompiler 编译，预期生成 `story.div.osi`；连续编译两次确认幂等。
8. 提交：`feat: add per-character Story configuration`。

## Task 4：实现二十项独立种族被动与批量操作

**文件：**

- 修改：`story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt`
- 修改：`story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosOrigins.txt`
- 修改：`story-src/verify.ps1`

**步骤：**

1. 将以下二十个唯一 Stats ID 写入配置目录：

   `DeepGnome_StoneCamouflage`、`Drow_DrowWeaponTraining`、`Duergar_DuergarResilience`、`Dwarf_DwarvenCombatTraining`、`Dwarf_DwarvenResilience`、`Elf_WeaponTraining`、`FeyAncestry`、`Gith_MartialProdigy`、`Gnome_Cunning`、`Halfling_Brave`、`Halfling_LightfootStealth`、`Halfling_Lucky`、`Halfling_StoutResilience`、`HumanMilitia`、`MountainDwarf_DwarvenArmorTraining`、`RelentlessEndurance`、`RockGnome_ArtificersLore`、`SavageAttacks`、`SuperiorDarkvision`、`Tiefling_HellishResistance`。
2. 单项开启：仅当 `HasPassive` 为 `0` 时调用 `AddPassive`，成功后写入 `DB_COS_RacialPassiveGranted(Character, Passive)`；已经存在时只更新配置，不写授予账本。
3. 单项关闭：仅在授予账本存在时调用 `RemovePassive` 并清除对应账本行。
4. 一键全选和一键取消在同一角色忙碌锁内遍历精确二十项；禁止递归触发二十次界面同步。
5. 读档/换地图同步不得重复授予；角色原生同名被动在单项关闭、一键取消和恢复默认后必须保留。
6. 调整现有 `DB_COS_ForbiddenPassive` 同步顺序，确保它不会误删新开关允许授予的二十项，也不会把禁用清单悄悄纳入种族被动目录。
7. 静态验证清单计数、默认值、去重和账本删除条件；Story 编译通过。
8. 提交：`feat: add individual racial passive settings`。

## Task 5：让八项玩法机制读取配置

**文件：**

- 修改：`story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt`
- 修改：`story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosOrigins.txt`
- 修改：`story-src/verify.ps1`

**步骤：**

1. 将 `Skills`、`Power`、`Wound`、`KillPower`、`Duality`、`AllIn`、`Echo`、`Strike` 分别接到现有授予、事件和结算入口。
2. 关闭 `Skills` 时移除仅由本 MOD 授予的技能专精；重新开启时幂等补回。
3. 关闭 `Power`、`KillPower` 时停止新增与结算，但保留现有力量、迷失和击杀计数。
4. 关闭 `Wound`、`Duality`、`Echo` 时在相应 `AttackedBy` 分支前读取配置。
5. 关闭 `AllIn` 或 `Strike` 时清理等待状态；关闭 `Duality` 时清理尚未结算的轮盘标记。
6. 验证所有伤害分支仍保留 `_AttackOwner == _Attacker`、无来源追加伤害不递归和首次受击锁。
7. Story 编译并运行静态验证。
8. 提交：`feat: gate chaos mechanics by Story settings`。

## Task 6：实现七起源身份开关

**文件：**

- 修改：`story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt`
- 修改：`story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosOrigins.txt`
- 修改：`story-src/verify.ps1`

**步骤：**

1. 把阿斯代伦、盖尔、莱埃泽尔、影心、威尔、卡菈克和邪念的官方标签与即时能力拆到七个精确目录中。
2. 单项关闭只移除该身份标签与即时能力；不得移除 32 个种族身份标签、29 项种族主动技能/法术或已经认领的永久剧情奖励。
3. 单项开启重新同步标签与即时能力，并按当前官方 Flag 补发尚未认领的剧情奖励。
4. “全部身份开启/关闭”在同一角色锁内执行，并只做一次最终 UI 同步。
5. 对 11 个剧情 Flag 的永久、阶段、可撤销和一次性规则做静态回归。
6. Story 编译并运行验证。
7. 提交：`feat: add origin identity settings`。

## Task 7：实现十五项受击负面结果开关

**文件：**

- 修改：`story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt`
- 修改：`story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosOrigins.txt`
- 修改：`story-src/verify.ps1`

**步骤：**

1. 为疯狂、恐慌、眩晕、沉默、倒伏、目盲、减速、中毒、流血、燃烧、近战劣势、远程劣势、法术劣势、随机易伤和额外随机伤害建立独立键。
2. 用每角色启用池替代固定 `Random(26)` 索引；固定保留现有正面结果，关闭项不进入候选池。
3. 先计算候选数，再进行一次等概率抽取；禁止“抽到后无效果”和递归重投。
4. 所有负面项关闭时，正面结果仍能正常抽取，首次受击锁仍只消费一次。
5. 静态验证目录、候选构建和随机上界；Story 编译通过。
6. 提交：`feat: make wound outcomes configurable`。

## Task 8：生成隐藏回显被动与固定 TutorialEvents

**文件：**

- 新增：`story-src/Public/ChaosOriginsStory/Stats/Generated/Data/ChaosConfig.txt`
- 新增：`story-src/Public/ChaosOriginsStory/Tutorials/TutorialEvents.lsx`
- 修改：`story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt`
- 修改：`story-src/verify.ps1`

**步骤：**

1. 为 8 + 20 + 7 + 15 个设置各创建一个 `COS_CFG_*` 隐藏回显被动；被动不产生玩法 Boost。
2. 为每项开启和关闭操作创建独立 EventType `8` TutorialEvent UUID；另建恢复默认、种族全选/取消、身份全开/全关和菜单打开同步事件。
3. 菜单打开、读档、取得角色控制权和配置变化时，根据数据库增删回显被动；禁止逐帧轮询。
4. Story 为每个固定 UUID 提供唯一处理器。未知事件不进入通用字符串分发。
5. 验证 50 个设置、100 个单项事件、批量事件、回显被动和 Story 处理器一一对应且 UUID 唯一。
6. Story 编译和静态验证通过。
7. 提交：`feat: add native config event protocol`。

## Task 9：实现暂停菜单键鼠与手柄页面

**文件：**

- 新增：`story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigEscButton.xaml`
- 新增：`story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigEscButton_c.xaml`
- 新增：`story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu.xaml`
- 新增：`story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu_c.xaml`
- 新增：`story-src/Mods/ChaosOriginsStory/GUI/StateMachines/Keyboard.xaml`
- 新增：`story-src/Mods/ChaosOriginsStory/GUI/StateMachines/Controller.xaml`
- 新增：`story-src/resource-src/Mods/ChaosOriginsStory/GUI/metadata.lsf.lsx`
- 修改：`story-src/package-files.json`
- 修改：`story-src/verify.ps1`

**步骤：**

1. 以本地 NMCM 参考包的 `ModType="Extend"`、`CustomEvent` 和 `TutorialEvent` 绑定方式为结构参考，创建全新的 `COS_CFG_*` 状态、页面、资源名称和 UUID。
2. 页面提供四个标签：常规机制、种族被动、七起源身份、受击轮盘结果；二十项种族被动使用可滚动列表。
3. 每行显示本地化名称、当前状态和开启/关闭控件；状态绑定角色的 `COS_CFG_*` 回显被动。
4. 种族页提供一键全选/取消，身份页提供全部开启/关闭，页脚提供恢复默认和返回。
5. 非主机、非混沌角色和战斗中角色显示明确只读原因，并禁用修改控件。
6. 键鼠支持鼠标、键盘导航和 ESC；手柄支持方向导航、确认和 B 返回。不得只复制键鼠模板改名。
7. 编译 metadata LSF，更新精确打包清单，验证正式源中没有 `NMCM_` 名称或参考 UUID。
8. 构建 PAK 并反向检查 XAML、metadata 和 TutorialEvents 均存在。
9. 提交：`feat: add native pause config pages`。

## Task 10：实现角色专属原生设置手册

**文件：**

- 新增：`story-src/resource-src/Public/ChaosOriginsStory/RootTemplates/COS_ConfigBook.lsf.lsx`
- 修改：`story-src/Public/ChaosOriginsStory/Stats/Generated/Data/ChaosConfig.txt`
- 修改：`story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt`
- 修改：`story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_ChaosOrigins.txt`
- 修改：`story-src/package-files.json`
- 修改：`story-src/verify.ps1`

**步骤：**

1. 创建新的书本 RootTemplate UUID；只复用原生模板结构，不复用 AbsoluteWrath 模块身份、SE Lua 或资源 UUID。
2. 在 `ChaosConfig.txt` 创建四个顶层 SpellContainer、逐项开启/关闭操作技能和批量/恢复技能。
3. 操作技能不产生伤害、状态或资源消耗，只由 `UsingSpell` 触发同一套 Story 请求处理器。
4. 注册混沌角色时先用 `TemplateIsInInventory` 检查，再补发一本手册；死亡、换图、读档和重复同步不得复制物品。
5. 手册只修改使用者自身，并执行与 XAML 相同的主机、控制权、战斗和忙碌锁校验。
6. 更新 RootTemplate LSF 编译与打包清单；静态检查所有手册技能均有唯一 Story 处理器。
7. Story 编译、资源编译、完整构建和反向校验通过。
8. 提交：`feat: add character config handbook`。

## Task 11：补齐四语文本和项目文档

**文件：**

- 修改：`story-src/Localization/Chinese/ChaosOriginsStory.xml`
- 修改：`story-src/Localization/English/ChaosOriginsStory.xml`
- 修改：`story-src/Localization/Japanese/ChaosOriginsStory.xml`
- 修改：`story-src/Localization/Korean/ChaosOriginsStory.xml`
- 修改：`story-src/README.md`
- 修改：`docs/功能迁移矩阵.md`
- 修改：`docs/项目构造与迁移说明.md`
- 修改：`story-src/verify.ps1`

**步骤：**

1. 为页面、四个标签、50 个设置、批量操作、只读原因、设置手册和操作技能补齐四语文本。
2. 种族被动优先引用官方可用名称；无法直接引用时使用四语明确译名，不留下占位符。
3. 文档明确：二十项默认关闭；其他正式玩法默认开启；无 NMCM/MCM/SE 依赖。
4. 更新功能矩阵中的“额外 20 种族被动”行为和构建文件数，不把静态完成写成实机完成。
5. 验证四语 handle 集合完全一致，无 `TODO`、`TBD`、空文本或旧 MCM 描述。
6. 提交：`docs: document native Story settings`。

## Task 12：完整构建、安装与游戏内验收

**文件：**

- 生成：`dist/ChaosOriginsStory.pak`
- 读取：`story-src/package-files.json`
- 安装目标：`%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods\ChaosOriginsStory.pak`

**步骤：**

1. 连续运行两次：

   ```powershell
   .\story-src\verify.ps1
   .\story-src\compile-story.ps1
   .\story-src\compile-resources.ps1
   ```

   预期：两次均通过且没有生成物漂移。
2. 运行 `story-src/build.ps1`；确认 staging、PAK 反向文件表和逐文件 SHA-256 完全一致。
3. 反向扫描 PAK，确认无 `ScriptExtender`、MCM、NMCM、AbsoluteWrath 模块文件或非空依赖。
4. 安装前检查 `bg3` 和 `bg3_dx11` 进程。若游戏正在运行，停止安装并请用户关闭游戏。
5. 对现有安装包创建不覆盖旧备份的时间戳备份，再复制新 PAK；比较构建包与安装包 SHA-256。
6. 游戏内设置验收：

   - 键鼠与手柄分别打开、导航、修改和关闭暂停菜单。
   - 设置手册只修改使用者；每个角色只有一本。
   - 非主机和战斗中只读；换控制角色后显示各自状态。
   - 新角色、旧存档首次迁移、保存/读档和换地图的默认值与持久化正确。
   - 二十项种族被动逐项开关、同名去重、一键全选/取消及原生被动保留正确。
   - 八项机制、七身份、十五受击结果逐项关闭后行为正确。
   - 受击池无空结果并保持等概率；两仪、受击额外伤害和回响不递归。
   - 两仪致死伤害、临时生命、多段和复合伤害继续按 Story 已知边界单独记录。

7. 分开报告：静态验证、Story/资源编译、PAK 反向校验、安装哈希、游戏内验收。只有最后一项全部通过才能声明功能完成。

## 工作区与提交约束

- 当前工作树已有用户的未提交内容。每个提交只暂存本任务明确列出的文件，不触碰或清理其他修改。
- `story-src/work/plan-reference/` 是本地解包参考目录，受忽略规则约束，不得加入 Git 或 PAK。
- 禁止使用 `git reset --hard`、`git checkout --` 或批量删除来处理现有工作树。
- 任一真实编译、资源或运行错误必须直接暴露，不添加猜测性默认值来掩盖。
