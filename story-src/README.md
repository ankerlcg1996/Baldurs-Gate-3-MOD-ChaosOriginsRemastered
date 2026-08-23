# Story 源码区

此目录当前只包含原生 Story Lite 的最小起源测试包，不应直接复制 `reference-se/source/Mods/.../ScriptExtender`。

当前可打包结构：

```text
story-src/
├─ Mods/<Story模块名>/
│  └─ meta.lsx
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

`package-files.json` 锁定 8 个正式文件。`verify.ps1` 会拒绝 Story Goals、机制 Stats、错误的 `Race`/`PlayerRace` 标签分类以及额外资源。运行 `build.ps1` 会编译标签与四语本地化、生成 PAK，并反向解包逐文件比较 SHA-256。

当前阶段只验证最小起源、守护者和 1–12 级升级流程；这些项目通过前不得恢复身份、奖励、配置或随机机制。
回退前完整实现保存在 Git 提交 `19c5d89`。
