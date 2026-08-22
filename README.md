# Chaos Origins Story Lite

这是“混沌起源 Story Lite”独立工程的起点。当前仓库没有实现 Story 版功能，只完成了以下交接准备：

- `reference-se/`：Chaos Origins Remastered SE 版 `1.0.25` 的只读源码快照；
- `story-src/`：后续原生 Story 实现区；
- `docs/项目构造与迁移说明.md`：当前 SE 架构、迁移边界、目标结构和阶段验收；
- `docs/功能迁移矩阵.md`：逐项说明保留、删除或重新设计的功能；
- `docs/新任务启动说明.md`：可直接复制到新 Codex 任务的启动提示词。

## 隔离规则

1. 不在 `reference-se/` 内继续开发；它只用于核对旧版行为、资源 ID、文本和算法。
2. Story 版源码只写入 `story-src/`，构建产物只写入忽略目录。
3. 本仓库不关联 SE 版 GitHub 远程仓库。
4. 在决定 Story 版是否与 SE 版共存之前，不复用 SE 模组 UUID。
5. 不把 Lua 能力伪装成已经完成的 Story 功能；无法由原生 Story 等价实现的部分必须明确降级或重新设计。

## 当前基线

- SE 参考版本：`1.0.25`
- SE 参考提交：`3a9834f4d078fab3488846b80579a6e6776d641c`
- 快照来源：`C:\Users\ankerlcg\Desktop\chaos-BG3-mod\ChaosOriginsRemastered`
- 快照范围：该提交中 54 个受 Git 管理的文件
- 未复制内容：原仓库 `.git`、`.worktrees`、`backups`、`dist`、`work` 及其他未跟踪生成物

开始开发前先阅读[项目构造与迁移说明](docs/项目构造与迁移说明.md)和[功能迁移矩阵](docs/功能迁移矩阵.md)。

