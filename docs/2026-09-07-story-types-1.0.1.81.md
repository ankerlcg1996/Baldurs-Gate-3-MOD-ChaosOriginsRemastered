# 1.0.1.81：修复角色创建时 Story 编译失败

游戏 Temp/Story/Log.txt 明确报告 6 条错误，对应 3 个调用：
StatusApplied/StatusRemoved 提供 GUIDSTRING，但 PROC_COS_SyncOriginGrantMirrors
与 PROC_COS_SyncVoloEye 要求 CHARACTER。

修复仅为这三个调用添加显式 (CHARACTER) 转换。保留身份菜单、瓦罗救援到营地
后永久解锁、默认开启及后续手术/拒绝后的开关规则。

先增强 verify-grant-menu.ps1 与 verify-volo-eye.ps1，确认旧调用不通过，
再修改源代码。两项回归通过，完整构建生成 1.0.1.81。
外部编译器此前未拒绝隐式转换，因此构建通过不等于游戏原生编译通过。

Version64：36028799166447697。

PAK SHA256：A02D4442E77779504F5AEAA141AA65EF435EFCB5F7936DB898BB2C564ED7CA2E。

检测游戏退出后，替换 Mods/ChaosOriginsStory.pak，并导出到桌面博德之门3mod目录。
加载配置仅更新本模块 Version64，不修改其他模组与存档。

待游戏内验收：进入角色创建、进入存档，以及身份菜单和瓦罗开关行为。
