# Chaos Origins Story Lite

这是“混沌起源 Story Lite”独立工程。当前已回退到只用于验证角色创建的最小起源阶段：

- `reference-se/`：Chaos Origins Remastered SE 版 `1.0.25` 的只读源码快照；
- `story-src/`：最小原生起源源码与构建验证工具；
- `docs/项目构造与迁移说明.md`：当前 SE 架构、迁移边界、目标结构和阶段验收；
- `docs/功能迁移矩阵.md`：逐项说明保留、删除或重新设计的功能；
- `docs/新任务启动说明.md`：可直接复制到新 Codex 任务的启动提示词。

## 隔离规则

1. 不在 `reference-se/` 内继续开发；它只用于核对旧版行为、资源 ID、文本和算法。
2. Story 版源码只写入 `story-src/`，构建产物只写入忽略目录。
3. 本仓库不关联 SE 版 GitHub 远程仓库。
4. 在决定 Story 版是否与 SE 版共存之前，不复用 SE 模组 UUID。
5. 不把 Lua 能力伪装成已经完成的 Story 功能；无法由原生 Story 等价实现的部分必须明确降级或重新设计。

## 当前最小测试包

正式 PAK 只包含 8 个文件：四语本地化、模块元数据、起源定义、一个无效果的隐藏起源标记，以及一个由 LSX 编译的起源标签。

- 不包含 Story Goals 或 `story.div.osi`；
- 不包含种族身份、起源身份、技能、剧情奖励或混沌机制；
- 不包含设置菜单、配置手册、图标、动作资源或测试命令；
- 起源标签严格使用 `Code`、`Dialog`、`DialogHidden`，不再错误注册为 `Race` 或 `PlayerRace`；
- 本阶段只验收默认男性半精灵、骗子背景、自由种族/职业/体型、守护者，以及 1–12 级官方升级。

回退前的完整 Story 工作保存在 Git 提交 `19c5d89`，需要时可恢复。

## 当前基线

- SE 参考版本：`1.0.25`
- SE 参考提交：`3a9834f4d078fab3488846b80579a6e6776d641c`
- 快照来源：`C:\Users\ankerlcg\Desktop\chaos-BG3-mod\ChaosOriginsRemastered`
- 快照范围：该提交中 54 个受 Git 管理的文件
- 未复制内容：原仓库 `.git`、`.worktrees`、`backups`、`dist`、`work` 及其他未跟踪生成物

开始测试前先阅读[最小起源回退说明](docs/最小起源回退说明.md)。后续开发仍以[项目构造与迁移说明](docs/项目构造与迁移说明.md)和[功能迁移矩阵](docs/功能迁移矩阵.md)为准。
