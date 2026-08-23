# ChaosOrigins icon set v2

12 枚图标是使用内置 imagegen 生成的原创技能符号。提示方向为：参考 BG3 本体的魔法技能图标视觉语言，但不复制现有符号；每枚只有一个居中大符号，高对比元素辉光，在 64px 下仍可辨认，无文字、无外框、transparent 背景。

图集行映射（保留旧图集中的 `COS_Identity` / `COS_Status` / `COS_Echo` 格）：

- row0: `COS_Identity`, `COS_Status`, `COS_Lost`, `COS_Power`
- row1: `COS_AllIn`, `COS_Echo`, `COS_Strike`, `COS_Genesis`
- row2: `COS_Finisher`, `COS_Wound`, `COS_Duality`, `COS_FateRevision`
- row3: `COS_Mastery`, `COS_MasteryTune`, `COS_MasteryCorrect`

`COS_Origin` 是有意指向 `COS_Identity` 同一坐标的唯一 UV alias，用于闭合 `ChaosRuntime` 的七处既有引用；除此之外 MapKey 唯一且不允许坐标重复。

`preview-64px.png` 在实际 `#808080` 灰底上按展示顺序排列：Power / Lost / Wound / Duality，AllIn / FateRevision / Genesis / Strike，Mastery / MasteryTune / MasteryCorrect / Finisher。

后处理由 `rebuild-atlas.ps1` 固定执行：对 12 枚 256×256 RGBA PNG 清除 RGB 各通道不高于 40/255、通道差不高于 10/255 的近黑中性不透明 matte，同时保留有色暗部；再以 Lanczos 缩放到 64×64，并从透明 `canvas:none` 合成目标格，不烘入棋盘格或旧图。

DDS 以 `ad3c4cc` 的 `Icons_ChaosOrigins.dds` 为字节基线。脚本先生成 10 级 mipmap 的 DXT5/BC3 临时目标图，仅把 12 个目标格在 mip0、mip1、mip2、mip3、mip4 的 4px 对齐 BC3 block 写回基线；mip5+、`COS_Identity` / `COS_Status` / `COS_Echo` 和所有未触及 block 保留基线原字节。运行：

```powershell
& .\artwork\icons-v2\rebuild-atlas.ps1
```
