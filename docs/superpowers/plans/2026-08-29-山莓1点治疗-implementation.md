# 山莓 1 点治疗 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将原版山莓的自定义治疗结算从无实机效果的 `RegainHitPoints(0)` 改为固定恢复 1 点，同时保留不消耗、治疗表现和神莓术边界，发布为 `1.0.1.60`。

**Architecture:** 继续由 `COS_Raspberry.lsf.lsx` 覆盖官方山莓和平使用动作并保持 `Consume=False`，继续向角色施加既有 `COS_RASPBERRY_ZERO_HEAL` 状态；唯一运行时变化是该状态的 `OnApplyFunctors` 固定为 `RegainHitPoints(1)`。`verify.ps1` 先锁定精确七行 Stats 契约并拒绝 0、其他数值、重复 Functor 与额外字段，再修改生产 Stats 使测试转绿。

**Tech Stack:** BG3 Stats、RootTemplate LSX、PowerShell 验证与构建脚本、LSLib、Git。

---

### Task 1: 用失败测试锁定固定恢复 1 点

**Files:**
- Modify: `story-src/verify.ps1:4228-4299`
- Test: `story-src/verify.ps1`

- [x] **Step 1: 将山莓验证目标改成 1 点**

把现有 `RegainHitPoints(0)` 精确契约改为：

```powershell
Require (Test-StatsField $raspberryStatusBlock 'OnApplyFunctors' 'RegainHitPoints(1)') `
    '山莓1点治疗状态必须唯一执行 RegainHitPoints(1)'
Require (-not ($raspberryStatusBlock -match 'RegainHitPoints\((?!1\))')) `
    '山莓1点治疗状态不得恢复 1 点以外的生命值'
$expectedRaspberryOneHealBlock = Normalize-LineEndings @'
new entry "COS_RASPBERRY_ZERO_HEAL"
type "StatusData"
data "StatusType" "BOOST"
using "FOOD"
data "Icon" "Spell_Transmutation_Goodberry"
data "StackId" "FOOD"
data "OnApplyFunctors" "RegainHitPoints(1)"
'@
function Test-RaspberryOneHealContract([string]$Block) {
    return (Normalize-LineEndings $Block).Trim() -ceq $expectedRaspberryOneHealBlock.Trim()
}
```

保留并改写现有重复 Functor、`OnRemoveFunctors` 和额外 `data` 变异探针；新增把唯一 Functor 替换为 `RegainHitPoints(0)` 的变异探针，要求精确契约拒绝它。

- [x] **Step 2: 运行验证并确认 RED**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify.ps1
```

Expected: 非零退出，并明确报告 `山莓1点治疗状态必须唯一执行 RegainHitPoints(1)`；失败来自生产 Stats 仍为 `RegainHitPoints(0)`，不是脚本语法错误。

### Task 2: 实施唯一运行时变化并转绿

**Files:**
- Modify: `story-src/Public/ChaosOriginsStory/Stats/Generated/Data/Status_BOOST.txt:45-51`
- Test: `story-src/verify.ps1`

- [x] **Step 1: 把生产 Functor 从 0 改为 1**

保持状态 ID、继承、图标和 StackId 不变，只替换最后一行：

```text
new entry "COS_RASPBERRY_ZERO_HEAL"
type "StatusData"
data "StatusType" "BOOST"
using "FOOD"
data "Icon" "Spell_Transmutation_Goodberry"
data "StackId" "FOOD"
data "OnApplyFunctors" "RegainHitPoints(1)"
```

不得修改 `COS_Raspberry.lsf.lsx` 的 `Consume=False`，不得修改 `CONS_Berry`、MapKey、`FOOD_FRUIT_GOODBERRY`、50 倍负重或其他混沌机制。

- [x] **Step 2: 运行完整验证并确认 GREEN**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify.ps1
git diff --check
```

Expected: 验证输出 `ChaosOriginsStory final native Story source verification: ok`，两个命令均以 0 退出。

- [ ] **Step 3: 提交功能修复**

```powershell
git add -- story-src/verify.ps1 story-src/Public/ChaosOriginsStory/Stats/Generated/Data/Status_BOOST.txt docs/superpowers/plans/2026-08-29-山莓1点治疗-implementation.md
git commit -m "fix(raspberry): restore one hit point"
```

### Task 3: 构建、目标安装并发布 1.0.1.60

**Files:**
- Modify by build: `story-src/version.json`
- Modify by build: `dist/build-manifest.json`
- Generate by build: `dist/ChaosOriginsStory.pak`
- Install: `C:/Users/ankerlcg/AppData/Local/Larian Studios/Baldur's Gate 3/Mods/ChaosOriginsStory.pak`

- [ ] **Step 1: 构建一次并确认版本只增加一次**

```powershell
pwsh -NoProfile -File .\story-src\build.ps1 -LslibPath 'C:\Users\ankerlcg\Desktop\BG3ModManager_Latest\_Lib\LSLib.dll'
```

Expected: 以 0 退出，`story-src/version.json` 的 `lastBuild` 从 `59` 变为 `60`，构建清单报告 38 个文件。

- [ ] **Step 2: 只安装目标 PAK**

先检查并只终止 `bg3`、`bg3_dx11`；备份当前已安装的 `ChaosOriginsStory.pak` 到 `dist/installed-backups`，复制新 PAK 后比较构建包与安装包 SHA-256。不得触碰其他 MOD。

- [ ] **Step 3: 提交构建产物并推送两个已授权分支**

```powershell
git add -- story-src/version.json dist/build-manifest.json dist/ChaosOriginsStory.pak
git commit -m "build(release): publish 1.0.1.60"
git push github codex/native-core-config
git push github HEAD:main
```

- [ ] **Step 4: 做发布后新鲜验证**

Run:

```powershell
pwsh -NoProfile -File .\story-src\verify.ps1
git status --short --branch
git ls-remote github refs/heads/main refs/heads/codex/native-core-config
```

Expected: 验证以 0 退出；工作树干净；两个远端引用都指向本地 `HEAD`。游戏内仍需单独验收山莓每次使用不消耗、播放治疗表现且实际恢复恰好 1 点。
