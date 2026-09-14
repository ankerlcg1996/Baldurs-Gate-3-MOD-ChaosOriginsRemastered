# ChaosOriginsStory 1.0.1.100 发布记录

## 修复范围

`1.0.1.99` 在游戏加载存档时由主游戏 Story 合并编译器拒绝。`Temp\Story\Log.txt` 记录了 12 个错误：状态事件提供的对象类型为 `GUIDSTRING`，相关规则却将其直接传给首参数为 `CHARACTER` 的数据库；运行诊断预设失败数据库的第二参数也缺少可推断的 `STRING` 类型。

本版只为这些数据库参数增加明确的 `CHARACTER`/`STRING` 类型，并加入 `verify-game-merge-types.ps1` 回归检查。未改变预设矩阵、默认配置或玩法数值。

## 候选版本

- 显示版本：`1.0.1.100`
- Version64：`36028799166447716`
- 模块 UUID：`a5062238-0d2b-46d1-a093-cb02775b9f57`
- 修复提交：`3ed731f`
- 回滚基线：`1.0.1.98`
- 游戏内验收：待用户重新加载存档确认。

## 构建与验证证明

- 正式清单：38 个文件。
- 原生 Story：6 个 Goal，2742 个节点，1553 个有效常量。
- 游戏合并编译类型回归：`GAME_MERGE_OSIRIS_TYPES=PASS`。
- 完整 `verify.ps1`：PASS。
- Story IR SHA-256：`05a6e86257dab1d56ee765adcc3cff19f2d4c5398e346c9302c57af24a2b8e6f`
- Story debug info SHA-256：`b9f769366d6f72c5f0ec7510262f52d807cc7525704c728a06a97d62d90717c5`
- PAK SHA-256：`b1601bb446ec132b7ecd34a527dd4ffaa30e918326fa08fe06ed4f80c383b1cd`
- PAK 已完成反向解包、38 文件清单核对和逐文件 SHA-256 核对。

## 安装目标

- 导出：`C:\Users\ankerlcg\Desktop\博德之门3mod\ChaosOriginsStory-1.0.1.100.pak`
- 游戏目录：`%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods\ChaosOriginsStory.pak`
- `modsettings.lsx` 只更新本模块 Version64，保留其他模块和加载顺序。
