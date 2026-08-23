# Story 源码区

此目录包含原生 Story 源码。`1.0.1.25` 的起源/守护者、基础能力、种族身份和七起源身份开关已通过实机验收；`1.0.1.28` 在该基线上接入身份即时能力、剧情奖励与混沌核心机制。Story 版不依赖 Script Extender、MCM 或 NMCM，也不授予额外技能熟练、专精、种族主动能力或 20 个种族被动。

当前可打包结构：

```text
story-src/
├─ Mods/<Story模块名>/
│  ├─ meta.lsx
│  └─ Story/
├─ Public/<Story模块名>/
│  ├─ Origins/
│  └─ Stats/Generated/Data/Passive.txt
├─ resource-src/Public/<Story模块名>/Tags/
└─ Localization/
   ├─ Chinese/
   ├─ English/
   ├─ Japanese/
   └─ Korean/
```

`package-files.json` 锁定 23 个正式文件。`verify.ps1` 核对装备熟练、七个基础法术、32 个种族身份标签、七个起源身份开关及即时能力、11 个官方剧情 Flag、混沌核心 Stats/Story，并禁止技能熟练、专精、种族主动能力、旧菜单和 SE/MCM 依赖混入。运行 `build.ps1` 会编译 Story、标签与四语本地化、生成 PAK，并反向解包逐文件比较 SHA-256。

`version.json` 保存当前成功构建版本。每次完整构建与反向校验全部成功后，最后一段版本号才会 `+1`，并同步写入源 `meta.lsx`、PAK 内 `meta.lsx` 和 `dist/build-manifest.json`。

`1.0.1.25` 已通过用户实机验收：七个起源身份开关直接写入 Origin 的 `Passives`，使用原生 `ToggledDefaultOn` 在创建阶段默认开启；装备熟练与七个基础法术仍延迟授予，创建流程与游戏运行正常。`1.0.1.28` 已通过 StoryCompiler、23/23 文件反向解包和安装 SHA-256 校验，等待游戏内验收。
回退前完整实现保存在 Git 提交 `19c5d89`。
