# Chaos Origins Story

“混沌起源”原生 Story 版。源码位于 `story-src/`，不依赖 Script Extender、BG3 MCM 或 Lua；`reference-se/` 仅保留 SE `1.0.25` 的行为参考。

## 已实现

- 独立模块、起源与资源 UUID，可与 SE 版共存；
- 自由种族、职业、体型的混沌起源，默认男性半精灵与骗子背景；
- 全武器/护甲熟练、18 技能熟练与精通，无固定 `+5`；
- 32 个可选种族身份标签、29 项种族主动技能/法术，不授予额外 20 项种族被动；
- 七起源身份固定启用，剧情 Flag 驱动已定义的起源奖励；
- 混沌受创、迷失/混沌之力、开天辟地、混沌回响、孤注、强袭与 Story 版混沌两仪；
- 中、英、日、韩四语本地化；
- Story/LSF/LOCA 编译、精确清单打包和反向 SHA-256 校验。

## Story 伤害边界

原生 Story 只能在 `AttackedBy` 后读取汇总伤害，不能像 SE 的 `BeforeDealDamage` 一样改写伤害列表。两仪因此只对仍存活的目标回补一半伤害，再结算轮盘的另一半；致死伤害、临时生命与复合伤害包无法做到逐项等价。回响和倍率伤害使用无来源的追加伤害，避免递归触发自身。

## 构建

```powershell
& .\story-src\build.ps1
```

产物为 `dist/ChaosOriginsStory.pak`。构建依赖本机已有的 LSLib、Divine、StoryCompiler 与官方 Story VFS；缺失时会直接报错。

编译通过、PAK 安装成功和游戏内通过是三个独立验收结论。首次实机测试请重点检查角色创建/守护者、1–12 级升级、首次受创锁、两仪伤害、孤注/强袭组合倍率和剧情 Flag 奖励。
