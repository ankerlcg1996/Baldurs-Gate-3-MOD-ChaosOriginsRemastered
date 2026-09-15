# ChaosOriginsStory 1.0.1.101 发布记录

## 修复范围

`1.0.1.100` 首次打开设置页面时，新增的分类、预设和分类实际状态映射由运行时 `PROC` 写入，但同一轮同步随即尝试读取这些映射并启用对应 `TutorialEvent`。新映射尚未进入下一轮 Story 求值，因此分类与预设按钮有点击反馈却不产生事件，分类实际状态为空，依赖该状态惰性加载的细分设置也全部隐藏。

本版在运行时映射写入后启动一次 100 毫秒对象计时器，并在下一轮重新启用菜单事件、检测当前预设、投影分类实际状态及刷新诊断。这样旧存档第一次打开菜单即可完成新增设置的升级，不必先保存并重新加载一次。

## 候选版本

- 显示版本：`1.0.1.101`
- Version64：`36028799166447717`
- 模块 UUID：`a5062238-0d2b-46d1-a093-cb02775b9f57`
- 修复提交：`5c4a37e`
- 游戏内验收：待用户测试按钮、预设及细分设置。

## 构建与验证证明

- 新回归检查先在旧实现上失败，再在修复后输出 `CATEGORY_RUNTIME_BOOTSTRAP=PASS`。
- 正式清单：38 个文件。
- 原生 Story：6 个 Goal，2744 个节点，1556 个有效常量。
- 游戏合并编译类型回归：`GAME_MERGE_OSIRIS_TYPES=PASS`。
- 完整 `verify.ps1`：PASS。
- Story IR SHA-256：`97b765d90fd9f0f27f8f32577ba7269415b4c356527af641f9ab9c38a423571a`
- Story debug info SHA-256：`f6f61b43852cdc82e65cc8ae51738dfc2f2fe3e15089928f104b5abb29829ecf`
- PAK SHA-256：`2af12d8392111bf70e7433363d7a8caaebf611cafa747356294c4fbf8c36f765`
- PAK 已完成反向解包、38 文件清单核对和逐文件 SHA-256 核对。

## 安装目标

- 导出：`C:\Users\ankerlcg\Desktop\博德之门3mod\ChaosOriginsStory-1.0.1.101.pak`
- 游戏目录：`%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods\ChaosOriginsStory.pak`
- `modsettings.lsx` 只更新本模块 Version64，保留其他模块和加载顺序。
