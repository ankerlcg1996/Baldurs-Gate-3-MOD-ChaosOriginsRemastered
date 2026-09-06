# .76 CaptureApply 隔离测试

## 已有结果

用户实测：.71 正常，.72 失败，.73 正常，.74 失败，.75 正常。
其中 .73 仅恢复 .71 Story；.74 保留 .72 全部规则但断开自动入口；.75 仅保留 Seed 映射定义。

## 本次唯一分组变化

从 .72 原始 PAK 的 `COS_Config.txt` 精确恢复 `PROC_COS_CaptureNativeGrantTags` 起、`PROC_COS_SyncOriginGrantMirrors` 前的十条规则：

- CaptureNative / CaptureExisting / CaptureLegacy / CaptureUnresolved：4 条。
- EnsureGrantOptions、EnableGrantEvents：2 条。
- ApplyGrantOptions：4 条（添加/删除镜像被动、添加/删除标签）。

仍无新菜单事件、状态事件、同步调用。没有自动授予入口。只测试规则加载，不作为功能修复版使用。
常规构建仍拦截断开的授予入口；编译器忽略名单仅在测试 staging 内包含 GrantOrigin/4、GrantInitialized/1、GrantUnresolved/2，符合此分组刻意缺失的读取/写入路径，不进入 PAK。

## 检查和安装

- 测试先对 .75 失败（缺少待恢复分组），对 .76 通过。
- 构建命令：`pwsh -NoProfile -File story-src/build.ps1 -GrantRuntimeIsolation -GrantSeedOnly -GrantPartition CaptureApply`。
- 271 rules、6 goals、1221 nodes、552 valid constants，38 个包条目。
- 非 Story 文件与 .72 字节一致；源码变动严格限定在隔离边界，meta 仅版本不同。
- 版本 1.0.1.76 / `36028799166447692`。
- SHA256 `284A4A7A9E07C225C1DC7723095A0A8E05FB76E594C2A9653C5F8D42FB8425D3`。
- 已安装为游戏 `Mods/ChaosOriginsStory.pak`，加载配置版本已核对。
- 桌面交付：`博德之门3mod/ChaosOriginsStory-1.0.1.76-capture-apply-isolation.pak`。
- 其他加载配置归一化哈希前后相同：`B1974A8B7794211944770EFBBA02FDA5016CC2475EB5F04BF0B53502C7011082`。
- 用户中途明确“已退出游戏”，工具也确认无游戏进程后才安装。未修改存档、其他模组、Git 远端。

若通过，重点测试未恢复的九条规则；若失败，继续拆分本次十条规则。不可从单次分组通过推断不存在组合问题。
请只测试能否进入角色创建，不保存、不操作新开关。当前源码保留该分组状态，下个版本 .77。
