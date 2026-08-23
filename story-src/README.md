# Story 源码区

- `Mods/ChaosOriginsStory/`：模块元数据、Story Header 与 Goal；
- `Public/ChaosOriginsStory/`：起源、Stats、图标和动作资源；
- `resource-src/`：需要编译为 LSF 的标签与 TextureBank；
- `Localization/`：四语 XML 源；
- `compile-story.ps1`、`compile-resources.ps1`、`build.ps1`：编译、打包与反向校验；
- `package-files.json`：正式 PAK 的唯一文件清单。

`work/` 与仓库根目录 `dist/` 是生成物，不受 Git 管理。正式包禁止出现 `ScriptExtender`、`MCM_blueprint.json` 或 `BG3MCM`。

## 原生设置

设置系统由原生 Story 数据库与一本角色专属设置手册组成，不依赖 NMCM、MCM 或 Script Extender。仅主机当前控制的混沌角色可在非战斗状态修改自己的设置；战斗中手册操作只读。

- 八项玩法机制、七项起源身份和十五项受击负面结果默认开启；
- 二十项去重后的官方可选种族被动逐项独立，默认全部关闭；
- 种族被动与起源身份均提供一键全选/取消，另有恢复全部默认值；
- 关闭种族被动时只移除本模组实际授予并记账的同 ID 被动，不移除角色原本拥有的同名被动。

暂停菜单 XAML 扩展在实际客户端 `Load` 阶段导致崩溃，已从正式包移除；设置入口统一为角色背包内的“混沌起源设置手册”。运行 `verify.ps1`、`compile-story.ps1`、`compile-resources.ps1` 后再执行 `build.ps1`。当前精确清单为 20 个 PAK 文件；静态检查、安装哈希一致和游戏内验收是三个不同结论。
