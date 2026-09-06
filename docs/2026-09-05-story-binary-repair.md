# Story 二进制修复：1.0.1.71

## 原因与回归

已安装的 1.0.1.70 通过旧构建中的 IR 检查，但 LSLib StoryReader 反读实际 story.div.osi 时失败：
`An item with the same key has already been added. Key: 0`。
同机隐身术 1.0.0.3 也复现相同错误。

原编译器输出 1.15 格式，却没有为适配器常量设置 IsValid 和 Index。
1.15 格式直接从 Value 写索引，导致常量无效、多常量索引重复为 0。
本次仅切换到复制术已隔离修复的编译器，不改游戏机制。

工具目录：`C:/Users/ankerlcg/Documents/ChatGPT/博德之门3Mod/.tools/lslib-duplication-fix`。
重建方法：复制原工具的 LSLib、StoryCompiler 与 LICENSE；
在 LSLib/LS/Story/Compiler/StoryEmitter.cs 的 EmitValue(IRConstant) 初始化器设置 IsValid=true，
在 EmitJoinAdapter 调用 EmitValue 后设置 osiConst.Index=checked((sbyte)i)。
执行 `dotnet build StoryCompiler/StoryCompiler.csproj -c Release --no-restore`。

compile-story.ps1 保留原有 IR 验证，并新增 verify-story-binary.ps1：
完整反读、非空 Story、常量有效性、类型、逻辑索引匹配均须通过，否则禁止打包。

## 本次验证

- 修复前两个已安装包均复现重复索引错误。
- 混沌新包：6 goals、1163 nodes、540 valid constants。
- 隐身术新包：1 goal、28 nodes、18 valid constants。
- 混沌构建的原有测试、IR 验证、38 个打包条目反向校验通过。
- 与旧包比较：原始脚本、Stats、本地化等完全相同；四份重新生成的 LSF 解码后内容完全相同。
- 仅版本和编译 Story 内容发生实质变化。
- 安装包与构建包 SHA256 一致；旧包和加载顺序在桌面 Story修复备份-20260905。

这不是游戏内验收：仍需启动游戏，测试新建角色或读取存档，并验证两个隐身开关及混沌功能。
