# ChaosOriginsStory Config Menu Performance and Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore every existing fine-grained configuration control, remove status-driven page reconstruction, and keep the category and preset features in a compact native menu.

**Architecture:** Flatten each category's existing child `DataTemplate` back into the page's static visual tree. Keep category values and preset behavior in Story, but stop using category actual-state statuses to create or hide controls. Preserve the old targeted child event handlers; reserve full synchronization for menu open, category changes, and preset application.

**Tech Stack:** BG3 native Osiris Story, Larian XAML overrides, PowerShell 7 contract tests, LSLib resource and PAK tools, Git.

---

## File map

| File | Responsibility |
|---|---|
| `story-src/verify-config-menu-performance.ps1` | Fail-first structural and event-path regression checks. |
| `story-src/verify.ps1` | Runs the focused verifier in the full suite. |
| `story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu.xaml` | Static keyboard/mouse configuration layout. |
| `story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu_c.xaml` | Matching controller layout and focus controls. |
| `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt` | Removes unnecessary diagnostic and category-actual refresh work from fine-grained click paths. |
| `story-src/docs/RELEASE-1.0.1.102.md` | Build, hash, install, and remaining game-test evidence. |

### Task 1: Add a fail-first performance and completeness verifier

**Files:**

- Create: `story-src/verify-config-menu-performance.ps1`
- Modify: `story-src/verify.ps1`

- [ ] Add a PowerShell verifier that parses both XAML files as XML and enforces these exact contracts:

```powershell
$categories = @('Core','Origin','RaceTags','Weapon','Armor','Racial','Convenience')
$pages = @(
    'Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu.xaml',
    'Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu_c.xaml'
)

foreach ($page in $pages) {
    $text = Get-Content -LiteralPath (Join-Path $PSScriptRoot $page) -Raw -Encoding UTF8
    [xml]$xml = $text
    foreach ($category in $categories) {
        Require ($text -notmatch "COSCategory${category}ChildMutation") "仍存在动态分类模板: $category"
        Require ($text -notmatch "COSCategory${category}PausedOverlay") "仍存在分类遮罩: $category"
        Require ($text -match "COSCategory${category}Section") "缺少分类区: $category"
        Require ($text -match "COSCategory${category}Toggle") "缺少分类总开关: $category"
    }
    Require ($text -notmatch 'COSRuntimeDiagnosticPanel') '主页面仍渲染大型运行诊断框'
    Require (([regex]::Matches($text, 'CurrentPlayer.SelectedCharacter.StatusEffects')).Count -le 2) '状态列表绑定仍会重建页面'
}
```

- [ ] Read the pre-category keyboard page from commit `54c1f8c^`, extract its unique `x:Name` set, and require every name to exist in both current pages. This locks the complete old selection surface without hard-coding only a sample.

- [ ] Parse TutorialEvent rules in `COS_Config.txt`. Require fine-grained mechanism, grant, racial, cost, carry, Volo-eye, tag-spell, and life-skill handlers not to call `PROC_COS_ConfigSyncCharacter`, `PROC_COS_ConfigSyncCategoryActual`, or `PROC_COS_RuntimeDiagnosticUpdate`. Require category toggle and preset apply to retain one unified sync call.

- [ ] Invoke the verifier from `verify.ps1` immediately after the category/preset verifier.

- [ ] Run the focused verifier against `.101`:

```powershell
pwsh -NoProfile -File .\verify-config-menu-performance.ps1
```

Expected: failure naming `COSCategory*ChildMutation`, the runtime diagnostic panel, or excessive status bindings.

- [ ] Commit the red test:

```powershell
git add story-src/verify-config-menu-performance.ps1 story-src/verify.ps1
git commit -m "test(ui): require static complete config layout"
```

### Task 2: Flatten the keyboard and controller category layouts

**Files:**

- Modify: `story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu.xaml`
- Modify: `story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu_c.xaml`

- [ ] For each of the seven category sections, clone the single root `StackPanel` from `COSCategory<Category>ChildTemplate` into `COSCategory<Category>Children`, then remove the `ChildMutation` ItemsControl and paused overlay.

- [ ] Remove each category's `Actual` ItemsControl and its 560-pixel actual-state column. Keep the total category switch, its fixed TutorialEvent UUID, and its passive mirror.

- [ ] Move the total switch and passive mirror into the existing centered decorative category header. Reuse the ordinary child checkbox template, keep an 80-pixel check target on the right, and remove the separate full-width category row. Give the resulting header the existing `COSCategory<Category>MasterRow` name so keyboard/controller parity and tests remain explicit.

- [ ] Remove `COSRuntimeDiagnosticPanel`. Keep Story diagnostic statuses and procedures unchanged so logs and future diagnostic pages retain the data.

- [ ] Keep `COSPresetPanel` above the categories, reduce excess vertical margins, and preserve all six preset button UUIDs.

- [ ] In the controller page, preserve `UIAccept` bindings and verify every visible category and preset control remains focusable with no dead end.

- [ ] Run the focused verifier:

```powershell
pwsh -NoProfile -File .\verify-config-menu-performance.ps1
```

Expected: `CONFIG_MENU_PERFORMANCE=PASS`.

- [ ] Compile GUI resources:

```powershell
pwsh -NoProfile -File .\compile-resources.ps1
```

Expected: both XAML pages compile without missing names, resources, or XML errors.

- [ ] Commit the layout fix:

```powershell
git add story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu.xaml story-src/Mods/ChaosOriginsStory/GUI/Pages/COS_ConfigMenu_c.xaml
git commit -m "fix(ui): restore static detailed configuration"
```

### Task 3: Remove heavy work from fine-grained click paths

**Files:**

- Modify: `story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt`
- Test: `story-src/verify-config-menu-performance.ps1`

- [ ] Trace every fine-grained TutorialEvent rule. Remove only redundant preset detection, category-actual synchronization, and runtime-diagnostic refresh calls that execute after the targeted mutation already updated its own mirror or resource.

- [ ] Keep these expensive operations at their required boundaries:

```text
menu open -> one unified sync, preset detection, diagnostic refresh
category toggle -> one unified sync, preset detection, diagnostic refresh
preset apply -> one unified sync, preset detection, validation, diagnostic refresh
level start/control/level-up/respec -> existing lifecycle sync
```

- [ ] Do not add a timer, retry, silent fallback, guessed value, or new saved database.

- [ ] Run the focused verifier and Story compiler:

```powershell
pwsh -NoProfile -File .\verify-config-menu-performance.ps1
pwsh -NoProfile -File .\compile-story.ps1
```

Expected: both exit `0`; Story still contains six Goals.

- [ ] Commit the click-path fix:

```powershell
git add story-src/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt story-src/verify-config-menu-performance.ps1
git commit -m "perf(story): keep option clicks targeted"
```

### Task 4: Update the existing category verifier for the static layout

**Files:**

- Modify: `story-src/verify-category-presets.ps1`
- Test: `story-src/verify-category-presets.ps1`
- Test: `story-src/verify-config-menu-performance.ps1`

- [ ] Replace assertions that require `ChildMutation` templates and paused overlays with assertions that require static child controls, persistent visible values, category total switches, and unchanged preset events.

- [ ] Keep all Story data, preset matrix, new/legacy initialization, ownership, combat lock, and package invariants unchanged.

- [ ] Run both focused verifiers:

```powershell
pwsh -NoProfile -File .\verify-category-presets.ps1
pwsh -NoProfile -File .\verify-config-menu-performance.ps1
```

Expected: both pass.

- [ ] Commit the contract update:

```powershell
git add story-src/verify-category-presets.ps1
git commit -m "test(ui): verify static category controls"
```

### Task 5: Run the full suite and build 1.0.1.102

**Files:**

- Modify automatically: `story-src/version.json`
- Modify automatically: `story-src/Mods/ChaosOriginsStory/meta.lsx`
- Create: `story-src/docs/RELEASE-1.0.1.102.md`
- Update: `dist/ChaosOriginsStory.pak`
- Update: `dist/build-manifest.json`

- [ ] Run formatting and full verification from `story-src`:

```powershell
git diff --check
pwsh -NoProfile -File .\verify.ps1
```

Expected: all contract, Story, Stats, localization, resource, package-path, and mutation checks pass.

- [ ] Confirm `version.json` still reports build `101`, then run `build.ps1` exactly once.

Expected: version `1.0.1.102`, Version64 incremented by one, 38 packaged files, and six Story Goals.

- [ ] Record the source commit, PAK SHA-256, reverse-unpack proof, and `GAMEPLAY=UNTESTED` in `story-src/docs/RELEASE-1.0.1.102.md`.

- [ ] Commit the release and push `codex/native-core-config` to the authorized GitHub remote. Verify local and remote hashes match.

### Task 6: Install the verified candidate

**Files:**

- Export: `C:\Users\ankerlcg\Desktop\博德之门3mod\ChaosOriginsStory-1.0.1.102.pak`
- Install: `%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods\ChaosOriginsStory.pak`
- Modify only this module entry: `%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\PlayerProfiles\Public\modsettings.lsx`

- [ ] Check for `bg3.exe` and `bg3_dx11.exe`. If running, close only the game before replacing the PAK.

- [ ] Copy the verified PAK to the export and install paths. Update only ChaosOriginsStory's Version64 in `modsettings.lsx`; preserve every other module and load-order entry.

- [ ] Verify source, export, and installed PAK hashes are identical and only one ChaosOriginsStory entry is active.

- [ ] Hand off these in-game checks: fine-grained choices are visible, ordinary option clicks respond promptly, category and preset buttons still work, saved selections survive category pause/re-enable, and keyboard/controller pages remain usable. Do not label gameplay as passed until the user reports it.
