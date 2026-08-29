# Story 源码区

此目录包含原生 Story 源码。当前版本以 `version.json` 为唯一准绳；已验收的最小起源基线之上接入了身份即时能力、剧情奖励、混沌核心机制与 1 至 12 级掌控混沌。Story 版不依赖 Script Extender、MCM 或 NMCM，也不授予额外技能熟练、专精、种族主动能力或 20 个种族被动。

当前可打包结构：

```text
story-src/
├─ Mods/<Story模块名>/
│  ├─ meta.lsx
│  └─ Story/
├─ Public/<Story模块名>/
│  ├─ Origins/
│  ├─ Stats/Generated/Data/
│  │  ├─ ChaosConfig.txt
│  │  └─ Passive.txt
│  └─ Tutorials/TutorialEvents.lsx
├─ resource-src/Public/<Story模块名>/Tags/
└─ Localization/
   ├─ Chinese/
   ├─ English/
   ├─ Japanese/
   └─ Korean/
```

`package-files.json` 锁定 38 个正式文件和六个 Goal。`verify.ps1` 核对装备熟练、七个基础法术、全体玩家 50 倍负重、32 个种族身份标签、七个起源身份开关及即时能力、11 个官方剧情 Flag、1 至 12 级掌控混沌、混沌核心设置、混沌核心 Stats/Story、图标 atlas 和原生设置菜单，并禁止技能熟练、专精、种族主动能力、旧菜单和 SE/MCM 依赖混入。每角色 Story DB 随存档保存；旧存档只补缺失键不覆盖；XAML只发送固定 TutorialEvent不接受任意字符串键。静态/编译/hash不等于实机验收：菜单仍须在新游戏、旧存档、暂停与手柄操作中实测。`build-process.ps1` 使用 `ProcessStartInfo` 固定从当前 `$PSHOME` 启动真正的 `pwsh.exe -NoProfile -NonInteractive -File`，通过 `ArgumentList` 逐项传参，并发读取和透传 stdout/stderr，只按 `Process.ExitCode` 判定；运行测试覆盖 native-error 偏好 true/false、含空格/中文路径、重复调用、输出透传、非零退出码、`cmd.exe` 和 `if(false)` 变异，并确认调用者偏好未变。Story 编译的独立 IR root 验证只有全部通过后才生成绑定当前 `story.div.osi` 与 debug-info SHA-256/时间戳的新鲜证明；`verify.ps1` 和 `build.ps1` 都会实际编译并核对证明。随后构建进程才加载路径一致的指定 LSLib，编译标签与四语本地化、生成 PAK，并反向解包逐文件比较 SHA-256。

`version.json` 保存当前成功构建版本。每次完整构建与反向校验全部成功后，最后一段版本号才会 `+1`，并同步写入源 `meta.lsx`、PAK 内 `meta.lsx` 和 `dist/build-manifest.json`。

`1.0.1.25` 已通过用户实机验收：七个起源身份开关直接写入 Origin 的 `Passives`，使用原生 `ToggledDefaultOn` 在创建阶段默认开启；装备熟练与七个基础法术仍延迟授予，创建流程与游戏运行正常。当前候选只以 `version.json` 标识版本；新增机制通过本地验证与 StoryCompiler 后，仍等待游戏内验收。
回退前完整实现保存在 Git 提交 `19c5d89`。
