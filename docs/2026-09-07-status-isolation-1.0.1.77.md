# .77 状态监听隔离测试

用户实测 .76 可进入，但熟练项无法勾选；后者符合 .76 无菜单事件、无授予入口的测试范围，并非新的功能回归证据。

## 当前假设与单一差异

恢复 .72 的完整 BaseAfterCreation 和 Config，仅移除 Config 最后的两条新规则：
`StatusApplied/StatusRemoved -> DB_COS_GrantOrigin(_, _, _Status, _) -> PROC_COS_SyncOriginGrantMirrors`。
原有 BaseAfterCreation 中的起源身份状态处理不变。

这与 .72 的差异只剩两个监听规则（及版本），不像前几版断开整个功能。自动入口、Seed、标签保护、默认开启、镜像同步过程、两个 TutorialEvent 菜单处理均恢复。
仍不能宣称这两个监听就是最终根因，需用户测试。

## 检查和安装

- 隔离校验对 .72 先失败，.77 通过。279 rules、6 goals、1253 nodes、567 valid constants。
- 常规源码功能检查通过，不使用未读表忽略名单。
- 38 文件逐项检查：除 Config 源码、Story 二进制、meta 版本外，其他文件与 .72 字节相同。
- 构建：`pwsh -NoProfile -File story-src/build.ps1 -GrantStatusIsolation`。
- 版本 1.0.1.77 / `36028799166447693`。
- SHA256 `05C670E8F7DA9636C0AEE3B9F06207EF83836D3CD57913DA5564C5561166F033`。
- 已安装游戏 `Mods/ChaosOriginsStory.pak`，加载条目版本已核对。
- 已交付桌面 `博德之门3mod/ChaosOriginsStory-1.0.1.77-status-isolation.pak`。
- 其他加载配置归一化哈希前后 `B1974A8B7794211944770EFBBA02FDA5016CC2475EB5F04BF0B53502C7011082`。
- 安装时游戏关闭；未修改存档、其他模组或 GitHub。

## 验收与限制

1. 先测试角色创建及读档能否进入。
2. 若正常，非战斗时主控混沌角色，测试分项熟练项默认勾选、取消、重新勾选；选择角色自身职业不提供的熟练项检查实际变化。
3. 不要覆盖原测试存档，尚未完成正式验收。

因为移除了两个实时监听，通过旧快捷栏切换起源身份后，新增菜单镜像可能要等重新打开设置/同步才刷新；通过新增菜单点击则仍调用同步。未增加其他补偿处理，以保持此次对照干净。

若 .77 失败，重点拆分 .76 尚未含有的镜像同步、切换与 TutorialEvent 规则或自动同步组合；若通过，再处理原监听的根因与快捷栏刷新方式。
当前源码已恢复自动入口，仅这两个监听被移除；下一版本为 .78。
