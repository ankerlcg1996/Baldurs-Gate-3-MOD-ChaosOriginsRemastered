# Story 源码区

此目录包含原生 Story 源码。当前版本以 `version.json` 为唯一准绳；已验收的最小起源基线之上接入了身份即时能力、剧情奖励、混沌核心机制与一级掌控混沌。Story 版不依赖 Script Extender、MCM 或 NMCM，也不授予额外技能熟练、专精、种族主动能力或 20 个种族被动。

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

`package-files.json` 锁定 26 个正式文件和四个 Goal。`verify.ps1` 核对装备熟练、七个基础法术、32 个种族身份标签、七个起源身份开关及即时能力、11 个官方剧情 Flag、一级掌控混沌、混沌核心 Stats/Story 和图标 atlas，并禁止技能熟练、专精、种族主动能力、旧菜单和 SE/MCM 依赖混入。运行 `build.ps1` 会在无配置的独立 PowerShell 7 子进程中完成 Story 编译及 IR 校验，随后在未被 StoryCompiler 程序集污染的构建进程中加载并核对显式选择的 LSLib，编译标签与四语本地化、生成 PAK，并反向解包逐文件比较 SHA-256。

`version.json` 保存当前成功构建版本。每次完整构建与反向校验全部成功后，最后一段版本号才会 `+1`，并同步写入源 `meta.lsx`、PAK 内 `meta.lsx` 和 `dist/build-manifest.json`。

`1.0.1.25` 已通过用户实机验收：七个起源身份开关直接写入 Origin 的 `Passives`，使用原生 `ToggledDefaultOn` 在创建阶段默认开启；装备熟练与七个基础法术仍延迟授予，创建流程与游戏运行正常。当前候选只以 `version.json` 标识版本；新增机制通过本地验证与 StoryCompiler 后，仍等待游戏内验收。
回退前完整实现保存在 Git 提交 `19c5d89`。
