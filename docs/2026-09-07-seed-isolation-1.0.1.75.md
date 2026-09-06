# .75 映射定义隔离测试

用户确认 .74 仍无法进入，说明断开两个自动授予调用不足以消除故障。不能据此认定所有事件路径都无关。

在 .74 基础上，仅删除 `COS_Config.txt` 中从 `PROC_COS_CaptureNativeGrantTags` 到 `EXITSECTION` 之前的新增规则，保留未调用的 `PROC_COS_SeedGrantMap` 及其原始映射动作。原有游戏规则不变，.72 非 Story 内容保持逐字节一致。

当前源码就是这个诊断分区；正式修复需要从已保留的 .72 PAK 恢复被隔离规则，不能直接当完整版发布。

构建命令：`pwsh -NoProfile -File story-src/build.ps1 -GrantRuntimeIsolation -GrantSeedOnly`。

编译器将“表只写不读”视为 E25。这个分区故意无读取规则，因此只在编译 staging 的 `Story/story_orphanqueries_ignore_local.txt` 列出六个准确签名：RaceIdentityTag、GrantEvent、GrantOrigin、GrantOption、GrantTag、GrantNativeMap。该名单不进入源码或 PAK 清单；正常编译不创建名单，不降低其他错误检查。

## 验证及安装

- 同一个隔离检查对 .74 先失败，对 .75 通过。
- 38 个包条目；261 rules、6 goals、1164 nodes、535 valid constants。
- Source/IR/PAK 检查确认移除范围准确，Seed 过程仍在但无人调用，其余文件与 .72 相同（meta 仅版本不同）。
- 版本 1.0.1.75 / `36028799166447691`。
- SHA256 `DA9E2CC61CE89D2D38CED74EE924F020704C3ADB659FB93FDC326708B29D7ACE`。
- 已安装游戏 `Mods/ChaosOriginsStory.pak`，启用条目版本核对一致。
- 已交付桌面 `博德之门3mod/ChaosOriginsStory-1.0.1.75-seed-isolation.pak`。
- 其他加载配置归一化哈希前后均为 `B1974A8B7794211944770EFBBA02FDA5016CC2475EB5F04BF0B53502C7011082`。
- 游戏在安装时已关闭；没有结束进程、修改存档或其他模组，没有创建桌面备份，没有提交/推送 GitHub。

请测试进入角色创建，不保存、不操作新增开关。新开关和分项熟练项功能仍未恢复。

- 若通过，继续拆分被移除的关系/事件规则；不能直接声称 Seed 在完整上下文必然安全。
- 若失败，重点检查保留的 Seed/映射，以及相对 .73 仍不同的 Story 部分（旧基础授予规则已撤回），不能未经对照就断言 Seed 单独有错。

目前游戏验收待反馈，下一版本为 .76。
