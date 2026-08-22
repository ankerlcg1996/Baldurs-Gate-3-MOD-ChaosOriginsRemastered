# Racial Passive Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task.

**Goal:** 保留全部种族身份标签与 29 项种族主动技能/法术，同时停止并清理本 MOD 额外授予的 20 项种族被动。

**Architecture:** 保留审核后的 `RaceCatalog` 作为官方数据来源和旧存档清理清单。`RaceFeatures.Sync` 继续同步种族标签，并只授予三个 `COR_RacialSpells_Level*` 隐藏解锁被动；旧版本记录在 `RaceGranted.Passives` 账本中的额外种族被动会沿用现有差集清理逻辑精确移除，角色原生种族能力不受影响。

**Tech Stack:** BG3 Script Extender Lua、BG3 Stats/Localization XML、PowerShell 校验与打包脚本、Git。

---

### Task 1: 为新授予策略添加静态回归校验

**Files:**
- Modify: `verify.ps1`

**Step 1: 添加失败校验**

提取 `RaceFeatures.Sync` 函数体，要求它仍然授予等级解锁被动，并禁止在同步函数中读取 `features.Passives`：

```powershell
$raceSyncBlock = [regex]::Match(
    $raceFeaturesLua,
    '(?ms)^function M\.Sync\(character, record\)(.*?)^end\r?\n\r?\nreturn M'
).Groups[1].Value
Require ($raceSyncBlock.Contains(
    'desiredPassives[Catalog.RacialSpellPassives[unlockLevel]] = true'
)) 'RaceFeatures.Sync no longer grants racial spell unlock passives.'
Require (-not $raceSyncBlock.Contains('features.Passives')) `
    'RaceFeatures.Sync still grants audited racial passives.'
```

**Step 2: 运行校验并确认失败原因**

Run: `powershell -ExecutionPolicy Bypass -File .\verify.ps1`

Expected: FAIL，且失败信息明确指出 `RaceFeatures.Sync still grants audited racial passives.`

### Task 2: 停止额外种族被动授予并保留种族技能

**Files:**
- Modify: `source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/RaceFeatures.lua`

**Step 1: 修改运行时同步逻辑**

删除 `Sync` 中把 `features.Passives` 加入 `desiredPassives` 的循环，只保留：

```lua
-- 仅保留解锁主动种族技能的隐藏被动；官方种族被动清单只用于审核和旧账本清理。
desiredPassives[Catalog.RacialSpellPassives[unlockLevel]] = true
```

现有账本差集清理会移除旧版本曾由 MOD 授予、但现在不再期望存在的 20 项被动。

**Step 2: 运行完整静态校验**

Run: `powershell -ExecutionPolicy Bypass -File .\verify.ps1`

Expected: PASS；39 个种族、32 个标签、29 项主动技能/法术及三个隐藏解锁被动仍通过审核。

**Step 3: 提交功能修改**

```powershell
git add verify.ps1 source/Mods/ChaosOriginsRemastered/ScriptExtender/Lua/RaceFeatures.lua
git commit -m "balance: remove extra racial passives"
```

### Task 3: 同步玩家说明与元数据

**Files:**
- Modify: `README.md`
- Modify: `source/Mods/ChaosOriginsRemastered/meta.lsx`
- Modify: `source/Mods/ChaosOriginsRemastered/Localization/Chinese/ChaosOriginsRemastered_Chinese.xml`
- Modify: `source/Mods/ChaosOriginsRemastered/Localization/English/ChaosOriginsRemastered_English.xml`
- Modify: `source/Mods/ChaosOriginsRemastered/Localization/Japanese/ChaosOriginsRemastered_Japanese.xml`
- Modify: `source/Mods/ChaosOriginsRemastered/Localization/Korean/ChaosOriginsRemastered_Korean.xml`

**Step 1: 更新功能说明**

明确说明全部种族身份标签仍保留、不会额外授予 20 项种族被动、29 项主动种族技能/法术仍按等级解锁。不得修改起源身份、七个初始法术、技能精通、混沌轮盘或测试经验说明。

**Step 2: 运行完整校验**

Run: `powershell -ExecutionPolicy Bypass -File .\verify.ps1`

Expected: PASS。

**Step 3: 提交说明修改**

```powershell
git add README.md source/Mods/ChaosOriginsRemastered/meta.lsx source/Mods/ChaosOriginsRemastered/Localization
git commit -m "docs: describe racial identities and skills only"
```

### Task 4: 构建、反向校验并安装 v1.0.21

**Files:**
- Modify: `source/Mods/ChaosOriginsRemastered/meta.lsx`（构建脚本更新版本）
- Modify: `version.json`
- Create: `dist/ChaosOriginsRemastered-v1.0.21.pak`

**Step 1: 构建发布包**

Run:

```powershell
.\build.ps1 -LslibPath 'C:\Users\ankerlcg\Desktop\BG3ModManager_Latest\_Lib\LSLib.dll'
```

Expected: 版本递增为 `1.0.21`，打包校验和反向解包校验全部通过。

**Step 2: 提交版本文件**

```powershell
git add version.json source/Mods/ChaosOriginsRemastered/meta.lsx
git commit -m "chore: release version 1.0.21"
git push origin main
```

**Step 3: 确认游戏已关闭并备份安装包**

检查 `bg3.exe` 与 `bg3_dx11.exe` 均未运行。将当前安装包复制为 `backups/ChaosOriginsRemastered-before-1.0.21-<timestamp>.pak`，不得覆盖旧备份。

**Step 4: 安装并核对哈希**

把 `dist/ChaosOriginsRemastered-v1.0.21.pak` 复制到 BG3 Mods 目录，比较构建包与安装包 SHA256，要求完全一致。

**Step 5: 游戏内验收边界**

载入旧存档与新建角色分别确认：全部种族身份标签存在；额外种族被动已消失；种族主动技能仍存在且按等级解锁；角色原生种族能力未被删除。静态校验与安装成功不能替代本步骤。
