# 探索便利实施计划

目标：独立纯 Story MOD、逐角色持久开关、六类战斗外增益。

结构：src 中仅本模块元数据、一个 Story goal、一个 Stats 文件、中英本地化；build.ps1 使用已验证的本机编译器和 LSLib 生成独立包。现有混沌起源文件只读。

- [x] 测试先行：verify.ps1 验证资格、开关、战斗条件、独立状态、六类 Boost、事件和清理范围。首次运行因 Missing exploration Story implementation 失败，随后实现通过。
- [x] 实现 EBS_Exploration goal：初始化 DB_EBS_Enabled 缺失值为 1；原生被动状态投影；StatusApplied/Removed 接受玩家切换；参战、脱战、读档、入队、离队、复活、洗点同步。编译无错误。
- [x] 实现 EBS_Toggle、EBS_ENABLED、EBS_EXPLORING。增益采用原版 JumpMaxDistanceMultiplier(3)、IgnoreFallDamage()、Tag(PETPAL)、DarkvisionRangeMin(12)、Attribute(SlippingImmunity)、StatusImmunity(SG_DifficultTerrain)。本机结构定义 AttributeFlags 包含 SlippingImmunity。
- [x] 增加独立元数据和中英本地化。隐藏开关标记，显示一个汇总增益状态，不伪装原版效果来源。
- [x] 构建时检查退出码、二进制 Story 读取和节点、PAK 文件白名单及逐文件哈希；不打包头文件、工具包数据或 SE。
- [x] 源检查和变异检查、即时/排队回调规则模型均通过；独立审阅完成，未发现有充分证据的阻断缺陷。已导出桌面“博德之门3mod”并核对哈希。游戏测试尚未完成，不自动安装。死亡时隐藏标记与原生被动状态可能分离的条件风险详见 README。

检查命令：pwsh -NoProfile -File exploration-benefits/verify.ps1；pwsh -NoProfile -File exploration-benefits/build.ps1。

游戏测试：新旧档发放、单人开关、两个队员分离参战、关闭后脱战及重读档、死亡复活、长休、离队重入、原版同类状态保留、地表防滑与困难地形实测。
