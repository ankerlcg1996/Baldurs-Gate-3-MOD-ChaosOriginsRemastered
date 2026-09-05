# 1.0.1.66：逐项技能加值

用户确认设置页和种族被动生效，但技能面板没有显示设置的统一加值。
原实现为 RollBonus(SkillCheck,N)，只声明通用检定加值。
本体 Shared.pak 的 Armor.txt 使用 Skill(Stealth,1)、Skill(Athletics,1)、Skill(Acrobatics,1)；Status_BOOST.txt 使用 Skill(Stealth,10)。

将 COS_CFG_LIFE_SKILL_BONUS_01 至 20 替换为全部 18 项 Skill(技能,N)，保留现有设置账本、0关闭、移除旧档再应用当前档的流程。
不同时保留 RollBonus(SkillCheck,N)，避免检定双重加值；不授予熟练或专精。
验证覆盖每档的完整18项列表以及无通用+5叠加；旧实现已被新断言拒绝。

验收：存档加载后打开设置，将数值改成0再改成5，关闭设置并重新打开技能面板。各项应比0档增加5，20档增加20；恢复0应移除本设置加值。原有属性、熟练、专精和种族加值依然保留。
