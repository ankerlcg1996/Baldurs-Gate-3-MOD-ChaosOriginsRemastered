# 1.0.1.65 设置显示修复

实机显示新增文本 Not Found，但 1.0.1.64 PAK 反解出的四语语言文件均有 718 条，XAML 引用存在。
游戏 Data/Localization 中另有四个同路径旧语言文件，各含 668 条，完全缺少新增 h740 条目。
Data/Public/ChaosOriginsStory 中还残留十个旧资源文件，包括 ActionResourceDefinitions 和 TutorialEvents。
这些散装文件覆盖 PAK，导致安装包与游戏实际加载内容不一致。

安装使用 story-src/install.ps1：先验证发布哈希，仅根据本模组打包清单定位散装覆盖文件，移动到桌面时间戳备份，再安装 PAK。
使用 -CheckOnly 可检查覆盖冲突；修复前确实检出 14 个覆盖文件。

混沌与 NMCM 的键鼠 ESC 按钮原先均以 Top/Center、1700 边距定位；混沌入口现移至右下角。
菜单参考 NMCM 的原版行背景、分区标题装饰与页脚空间；拓宽内容区，键鼠种族被动为两列，手柄保持纵向焦点顺序。
没有改变 Story 开关或技能数值。游戏内显示和操作仍需实机验收。
