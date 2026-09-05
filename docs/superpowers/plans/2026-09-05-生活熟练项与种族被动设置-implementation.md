# 生活熟练项与种族被动设置实施计划

> 设计依据：`docs/superpowers/specs/2026-09-05-生活熟练项与种族被动设置-design.md`

## 交付目标

在当前 `ChaosOriginsStory` 纯 Story 版本上增加可保存的 `0..20` 生活熟练项固定加值，以及 20 个去重官方种族被动的独立开关、全选和全取消。不得引入 SE/MCM/NMCM 依赖，不得破坏角色原生种族被动。

## 任务 1：先建立会失败的设置契约检查

修改：

- `story-src/verify.ps1`

检查内容：

1. 生活熟练项默认值必须是 5，范围必须是 0..20，只有固定增减事件。
2. `COS_BaseProficiencies` 不再包含 `RollBonus(SkillCheck,5)`。
3. 1..20 的技能检定加值映射完整、唯一，每项只含对应 `RollBonus(SkillCheck,N)`。
4. 20 个种族被动清单必须去重且默认关闭。
5. 每个被动都有唯一固定事件和 UI 镜像。
6. 开启/关闭必须经过模组授予账本；关闭不得无条件 `RemovePassive`。
7. 全选/全取消必须复用逐项应用过程。
8. 键鼠 XAML、手柄 XAML、本地化、TutorialEvents 和 ActionResource 定义完整一致。

先运行 `story-src/verify.ps1 -SkipStoryCompile`，确认新增断言在旧实现上失败，并记录失败点。

## 任务 2：建立 Stats 与 UI 数值通道

修改：

- `story-src/Public/ChaosOriginsStory/Stats/Generated/Data/Passive.txt`
- `story-src/Public/ChaosOriginsStory/Stats/Generated/Data/ChaosConfig.txt`
- `story-src/Public/ChaosOriginsStory/ActionResourceDefinitions/ActionResourceDefinitions.lsx`
- `story-src/Public/ChaosOriginsStory/Tutorials/TutorialEvents.lsx`

实现：

1. 从 `COS_BaseProficiencies` 移除固定技能检定 +5，保留装备等原有熟练。
2. 定义 `COS_CFG_LIFE_SKILL_BONUS_01..20` 隐藏被动，每项严格对应一个 `RollBonus(SkillCheck,N)`。
3. 定义用于设置页显示的隐藏 Action Resource，最大值 20、永不自动恢复、不显示在玩法资源栏。
4. 定义数值增加、数值减少、数值恢复默认的固定 TutorialEvent。
5. 为 20 个种族被动定义 20 个独立切换事件及两个批量事件。
6. 定义只用于 UI 勾选显示的隐藏镜像被动；镜像不得包含任何玩法 Boost。

运行快速验证，目标是 Stats、资源和事件检查通过，Story/UI 检查仍明确失败。

## 任务 3：实现 Story 存档、夹取与归属保护

修改：

- `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt`
- 必要时更新 `story-src/Mods/ChaosOriginsStory/Story/RawFiles/story_header.div`

实现：

1. 增加每角色生活熟练项设置数据库，缺失时写入 5。
2. 增加 `+1/-1` 过程，并在 Story 中夹取到 0..20。
3. 每次修改时移除旧数值被动并只添加一个新数值被动；0 不添加玩法被动。
4. 打开 UI 时，将当前角色数值同步到 UI Action Resource。
5. 增加 20 项种族被动默认、角色设置、固定事件、镜像和模组授予账本。
6. 开启时仅在角色当前没有该被动时添加并记账；已有被动不记账。
7. 关闭时只有账本存在才移除并清账；无账本时保留原生被动。
8. 全选/全取消逐项调用相同的设置应用过程。
9. 在载入、获得控制、升级、洗点与 UI 打开时对账。
10. 所有可写事件保持现有门禁：混沌起源、当前受控、非战斗。

运行 Story 编译与快速验证，目标是所有 Story 契约通过。

## 任务 4：重构原生设置页与本地化

修改：

- `story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu.xaml`
- `story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu_c.xaml`
- `story-src/Localization/Chinese/ChaosOriginsStory.xml`
- `story-src/Localization/English/ChaosOriginsStory.xml`
- `story-src/Localization/Japanese/ChaosOriginsStory.xml`
- `story-src/Localization/Korean/ChaosOriginsStory.xml`

实现：

1. 用可滚动容器替换九行固定 `Viewbox`。
2. 保留九个核心机制开关。
3. 增加生活熟练项进度条、当前值、减号/加号及恢复 +5。
4. 增加种族被动分区、全选/全取消及 20 个开关。
5. 每项使用本地化名称和简明说明。
6. 键鼠与手柄页面的事件、顺序、焦点和滚动能力一致。
7. 批量恢复按钮分区明确，不把核心、熟练项和种族被动混在一个模糊操作中。

运行 XML/XAML 解析检查和完整快速验证。

## 任务 5：完整回归、构建与发布候选

修改：

- `story-src/package-files.json`（仅当新增正式打包文件时）
- `story-src/README.md`
- `README.md`
- `story-src/version.json`

步骤：

1. 更新说明，写明纯 Story、默认 +5、0..20、种族被动默认关闭和原生归属保护。
2. 运行完整 `verify.ps1`，不得跳过 Story 编译。
3. 运行完整构建并反向解包逐文件哈希比较。
4. 只有全部检查通过后运行正式构建；构建脚本从 `lastBuild=63` 成功增加一次到 64，生成 `1.0.1.64`。不得在构建前手工预增，避免生成 65。
5. 检查游戏未运行；若运行则按用户既有授权关闭游戏后安装。
6. 只替换命名为 `ChaosOriginsStory*.pak` 的目标包，保留所有其他 MOD。
7. 验证安装包、仓库产物和桌面 `ChaosOriginsStory-1.0.1.64.pak` 哈希一致。
8. 提交并推送当前分支与 GitHub 主分支，保留可回滚点。

## 实机验收清单

自动检查通过不等于实机验收。发布候选需要用户确认：

- 新建混沌起源进入游戏后默认技能检定 +5。
- 威吓、求生、洞察的实际掷骰结算包含设置值。
- 设置页显示 5，减到 0 和加到 20 均正确且不会越界。
- 重开游戏后仍载入上次设置值。
- 20 个种族被动默认都关闭。
- 单项开启、关闭、全选和全取消可用。
- 角色原生拥有的同名种族被动不会被关闭操作删除。
- 种族主动能力和种族法术不会被额外发送。
- 键鼠与手柄均可滚动和修改。
