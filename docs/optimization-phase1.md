# 优化第一批：实现与验收边界

基线 1.0.1.91，首批候选版本 1.0.1.92。本批保持纯 Story，不恢复命运改签。

## 本批实现

- 菜单复用现有混沌总览和最近受击结果状态的正文，显示剩余掌控点数、当前检定加值和已开启额外设置。
- 额外设置列表完整覆盖 74 个身份/标签/熟练项、20 个种族被动，以及标签法术、瓦罗、负重。列表明确表示配置开启，仍受等级与任务条件限制。
- 种族法术、瓦罗、检定加值、负重和礼包说明归入额外便利。开天辟地消耗留在核心开关后。
- 负重默认仍为全体玩家 50 倍；当前受控混沌角色可在非战斗时单独关闭，保存的关闭值不会被生命周期同步覆盖。
- 五类最强负面为攻击/护甲/豁免/检定 -3、移动 -9。最强项生效时，同族候选权重减半，重复抽中不施加、不刷新持续时间；保留抽中负面记录和失意计数。
- 新日志提示同类强负面已经存在；普通两仪与轮盘的数值机制不变。

## 仍未交付

完整的参数化数字结算日志和种族装备总开关不属于本批完成项。礼包只有既有一次性规则说明，未增加“已发放/未发放”状态镜像；额外设置列表不等于逐项能力已解锁清单。

当前 Story 头文件提供 ShowNotification、ResolveTranslatedString、ConcatenateInteger，但未核实参数化战斗日志接口。不能以通知 API 冒充可回看战斗日志，也不能把伤害计算值冒充实际扣血。

装备条件存在两个待验证点：伪装与模组标签重叠的资格保留，以及 BoostContext=OnCreate 的装备在切换后的刷新。没有引入猜测覆盖或清除角色身份标签。

## 已核实原版依据

本机原版目录 `C:/Users/ankerlcg/Documents/ChatGPT/博德之门3Mod/ChaosOrigins/work/official/Public`：

- GustavDev/Stats/Generated/Data/Passive.txt：MAG_Githborn_Circlet_Passive、CRE_MAG_Githborn_Amulet_Passive、MAG_Githborn_MagicEating_HalfPlate_Passive、MAG_Githborn_Mindcrusher_Greatsword_Passive、MAG_Githborn_PsionicMovement_Boots_Passive、MAG_Legendary_PsionicResistance_Passive、MAG_Drowelf_PoisonAgainstEnsnared_Passive、MAG_Nimblefinger_Passive。
- MAG_BG_BlightBringer_Passive 判定的是目标种族，不能误改为穿戴者资格。
- Shared/Stats/Generated/Data/Spell_Throw.txt：Throw_Throw、Throw_FrenziedThrow 的 DWARF 条件。

本机 UI 目录 `C:/Users/ankerlcg/Documents/ChatGPT/博德之门3Mod/.story-vfs/official-patch8-full`：

- Mods/MainUI/GUI/Override/Clairmont/Pages/CharacterSelect_Conditions_c.xaml：StatusEffects.SelectedItem 的 Description 使用 CtxTransStringRunGeneratorBehavior。
- Public/Game/GUI/Override/Clairmont/Library/Tooltips.xaml：VMStatus/ObjectStatusTemplate、PermanentStatusEffects 的 StatusId 及 Character.StatusEffects 模板链。过滤字段与运行时刷新仍需游戏验收。

## 游戏验收

1. 读旧档与新建角色，打开菜单；核对状态栏与菜单概率一致，分配点数后剩余点数同步。
2. 键鼠展开额外设置；手柄版直接显示列表并能正常滚动。切换角色后列表对应当前角色。
3. 关闭负重后切换控制并读档，确认保持关闭；原版/其他来源负重不移除。
4. 首次获得最强负面不显示保护误报；同族重复抽中显示保护且剩余时间不延长；状态消失后恢复基础权重。
5. 确认开天辟地仍按核心区成本扣费，普通两仪仍单次判定。

完整 verify.ps1、Story 编译（6 goals / 1478 nodes / 672 constants）、4 项资源编译和 38 文件 PAK 反向校验通过。静态回归和编译不能代替上述游戏验收。不自动安装本批候选包。
