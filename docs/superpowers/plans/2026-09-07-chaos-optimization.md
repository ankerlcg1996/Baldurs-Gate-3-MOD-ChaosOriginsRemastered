# Chaos optimization implementation plan

> **For agentic workers:** Use subagent-driven-development for bounded implementation and review, with TDD and explicit in-game acceptance boundaries.

**Goal:** Implement the approved overview, log, negative-protection, convenience and equipment changes without reintroducing Fate.

**Architecture:** Reuse the six native Story goals and existing XAML mirrors. Separate read-only displays from gameplay state; retain old identifiers needed by saves.

**Tech Stack:** Osiris Story, Stats, XAML, localization XML, PowerShell validation.

## Execution checkpoint: first candidate 1.0.1.92

- [x] Menu separation, read-only status overview and remaining point display.
- [x] Exact half-weight protection with explicit skipped-application log; RED/GREEN checks and separate spec/quality reviews.
- [x] Independent carry setting, preserved default scope and old-save setting; static checks and reviews.
- [x] Full native verify/build/reverse check passed: 6 goals, 1478 nodes, 672 constants, 38 package files.
- [ ] Numeric combat-log integration: native parameterized log API not verified; no notification substitute shipped.
- [ ] Equipment qualification: exact original entries audited, disguise overlap and OnCreate refresh still require validation; no unsafe overrides shipped.
- [ ] Per-ability actual unlock list and one-time bag handled-state mirror; current list explicitly shows enabled settings, not unlock status.
- [ ] In-game acceptance and installation.

Detailed evidence and remaining limits: `docs/optimization-phase1.md`. Items below describe the full target, not a claim that all five requested features are complete.

## 1. Menu separation

- [ ] Add `verify-optimization-menu.ps1`: require `COSConfigConvenienceHeader` after `COSConfigRowMastery` and before `COSConfigRowTagSpells` and `COSConfigLifeRow` on both pages. Run it and observe failure.
- [ ] Move the existing tag-spell row and its explanation into a new extra-convenience section before life skills. Preserve tutorial UUIDs, mirror names and handlers. Keep Genesis cost immediately after Genesis.
- [ ] Add a localized header; update controller traversal expectations and localization count. Run the new check and `verify.ps1`.

## 2. Strong negative protection

- [ ] Inspect `COS_ChaosMechanics.txt` outcome mappings and `ChaosDamage.txt` StackId groups; record the strongest tier for each group.
- [ ] Add `verify-negative-protection.ps1` checks for exact 2w/w weights, no repeated ApplyStatus, no changed category thresholds; observe RED.
- [ ] Use native HasActiveStatus checks to derive per-draw protected groups. Preserve integer weights: normal 2w, affected w. Keep weaker tiers from replacing or refreshing an active strongest tier. Record skipped application explicitly.
- [ ] Run the focused test, Story compile and full validation. Review old-save initialization: mapping must be seeded at runtime where new INIT rows would not load.

## 3. Read-only overview and logs

- [ ] Audit Stats bindings and Story text parameter APIs in local extracted reference data. Confirm types before coding.
- [ ] Extend the existing overview with remaining mastery points and an enabled-extras list, using current character data and no writeback handlers.
- [ ] Record actual adopted results only; distinguish queued and applied delayed damage. Add verification preventing RNG, resource writes or damage calls in display code.
- [ ] If native parameterized log output cannot be verified, report the exact limitation instead of emitting invented damage values.

## 4. Convenience controls and equipment eligibility

- [ ] Audit local original equipment condition sources and preserve an exact override list; independently verify genuine race, selected tag and toggle truth table.
- [ ] Follow existing TutorialEvent/mirror contracts for a default-off equipment switch. Never clear genuine tags to disable bonuses.
- [ ] Make 50x carry benefit independently switchable without altering other passive sources; expose starting-bag one-time handled state without refill or removal.
- [ ] Add old-save, true-race and toggled-tag regression checks before implementation. Block unsupported original condition rewrites rather than guessing.

## 5. Delivery

- [ ] Run `pwsh -NoProfile -File story-src/verify.ps1`, then `build.ps1`; confirm PAK reverse validation and SHA256.
- [ ] Review changes against the approved spec and perform code-quality review separately. Resolve findings before release.
- [ ] Export incremented version to Desktop/博德之门3mod, commit and verify GitHub remote HEAD. Do not install or stop the game in this development step.
- [ ] Report implemented scope and any evidence-backed limitations, with in-game checks explicitly pending.
