# ChaosOrigins icon set v2

12 枚图标是使用内置 imagegen 生成的原创技能符号。提示方向为：参考 BG3 本体的魔法技能图标视觉语言，但不复制现有符号；每枚只有一个居中大符号，高对比元素辉光，在 64px 下仍可辨认，无文字、无外框、transparent 背景。

图集行映射（保留旧图集中的 `COS_Identity` / `COS_Status` / `COS_Echo` 格）：

- row0: `COS_Identity`, `COS_Status`, `COS_Lost`, `COS_Power`
- row1: `COS_AllIn`, `COS_Echo`, `COS_Strike`, `COS_Genesis`
- row2: `COS_Finisher`, `COS_Wound`, `COS_Duality`, `COS_FateRevision`
- row3: `COS_Mastery`, `COS_MasteryTune`, `COS_MasteryCorrect`

`preview-64px.png` 按展示顺序排列：Power / Lost / Wound / Duality，AllIn / FateRevision / Genesis / Strike，Mastery / MasteryTune / MasteryCorrect / Finisher。

后处理：保留 256×256 RGBA PNG 作为源，缩放到 64×64 后合入 512×512 图集；不烘入棋盘格，保留 alpha，最终编码为 DXT5/BC3 DDS 并保留 10 级 mipmap。
