# Story 源码区

此目录预留给原生 Story Lite 版，不应直接复制 `reference-se/source/Mods/.../ScriptExtender`。

建议在完成官方数据和 Story 编译链验证后建立以下结构：

```text
story-src/
├─ Mods/<Story模块名>/
│  ├─ meta.lsx
│  └─ Story/
│     └─ RawFiles/
│        ├─ story_header.div
│        └─ Goals/
├─ Public/<Story模块名>/
│  ├─ Origins/
│  ├─ Tags/
│  ├─ Stats/Generated/Data/
│  ├─ ActionResourceDefinitions/
│  └─ GUI/                 # 仅在确实需要自定义图标时创建
└─ Localization/
   ├─ Chinese/
   ├─ English/
   ├─ Japanese/
   └─ Korean/
```

这只是目标布局，不代表 Story 编译链已经建立。第一个实现提交必须先验证最小起源、守护者和 1–12 级升级流程，再逐层迁移机制。

