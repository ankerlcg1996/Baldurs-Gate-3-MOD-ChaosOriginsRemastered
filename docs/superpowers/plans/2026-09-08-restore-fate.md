# Restore Fate Implementation Plan

**Goal:** Restore the previously approved attack-triggered Fate Revision in 1.0.1.94 and install it.

**Architecture:** Restore only Fate changes from the parent of e116398. Preserve newer carry mirroring, negative protection and overview improvements. Keep both independent costs in the core section.

**Tech Stack:** Native Osiris Story, BG3 Stats, XAML, PowerShell, LSLib.

- [x] Restore Fate assertions in story-src/verify.ps1 and verify-power-costs.ps1; replace retirement checks with restoration checks. Run verification and confirm the removed passive is rejected.
- [x] Restore Fate blocks in COS_ChaosMechanics.txt, COS_Config.txt, COS_BaseAfterCreation.txt and Passive.txt from e116398's parent, without reverting unrelated changes.
- [x] Restore Fate checkbox and cost controls to both XAML pages, directly before Genesis. Preserve the Genesis cost position.
- [x] Restore Fate descriptions affected by retirement; keep overview probability calculations intact.
- [x] Run full source checks and story-src/build.ps1; expect version 1.0.1.94 and validated package.
- [ ] Record project summary and acceptance limits. Back up source and PAK to the verified GitHub branch.
- [ ] Stop only BG3 processes; replace only ChaosOriginsStory.pak and its module Version64 in modsettings.lsx. Verify matching hashes and unchanged other configuration.
