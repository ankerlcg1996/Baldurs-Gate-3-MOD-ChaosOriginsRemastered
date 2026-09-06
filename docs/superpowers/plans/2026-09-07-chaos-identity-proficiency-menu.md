# 混沌逐项授予设置 Implementation Plan

> **For agentic workers:** 使用 executing-plans 在当前已选工作树内顺序实施，不启动代理，不切换分支。

**Goal:** 75 项默认开启的混沌额外授予设置，保留原生身份与其他来源熟练。

**Architecture:** 复用 COS_Config 的 TutorialEvent、持久 DB 和隐藏被动镜像。基础熟练拆为独立被动。身份快捷被动保持为唯一真值；种族标签以 REALLY 原生身份及授予账本保护。新增固定映射在每次同步时播种，兼容已存在的存档。

**Tech Stack:** 原生 Osiris Story、Stats、XAML、四语 loca、PowerShell、LSLib。

## 执行清单

- [x] 新增 `story-src/verify-grant-menu.ps1`，检查 75 行、事件映射、默认值、熟练总被动移除、原生标签保护和无遗漏本地化；在原始代码运行并记录失败。
- [x] 新增 `story-src/grant-menu.json` 作为事件、名称、类型与资源 ID 清单；从原版标签 LSF 与 Passive.txt 核对 32 标签及 31 武器类型，不引入猜测枚举。
- [x] 修改 `COS_BaseAfterCreation.txt` 的总熟练与无条件 SetTag 分支，改调 `PROC_COS_ConfigSyncGrants`；在 `COS_Config.txt` 扩展按角色 DB、运行时映射、事件处理和镜像同步。原生标签按官方 REALLY 标记保护，未知身份明确拒绝标签移除；旧存档无记录的标签仅在确认官方身份后迁移。
- [x] 修改 `Passive.txt` 与 `COS_ConfigMenu.xaml`、`COS_ConfigMenu_c.xaml`；每种熟练用 `Proficiency(官方类型)` 单独授予。菜单复用现有复选框行，分组两列；起源身份调用已有 `TogglePassive`，保留联动。
- [x] 更新四语 XML，逐条覆盖名称与说明；非中文语言使用英文完整说明，不产生 Not Found。
- [x] 更新既有 `verify.ps1` 中“总熟练常驻”旧断言，使其约束新的独立授予机制，保留其余回归检查。
- [x] 运行 `pwsh -NoProfile -File story-src/verify-grant-menu.ps1`、`story-src/verify.ps1`，修复真实失败；编译前检查所有新增 DB 参数类型与事件可重复触发。
- [x] 运行 `pwsh -NoProfile -File story-src/build.ps1`，成功时自动递增 1.0.1.72；反读包、核对哈希与版本，交付到桌面模组目录。无额外授权不关闭游戏或安装，不声称游戏验收。

游戏检查：读档、首次默认、单项关闭/重开、原生与非原生熟练对比、种族标签原生保护、保存重载、升级、两个菜单入口及起源快捷开关同步。

实施结果：已生成并交付 1.0.1.72，包哈希与构建清单一致。未安装，游戏验收待用户测试。源码与已有未提交修复保留在当前工作树，未自动提交或推送。
