# Fate log and synchronization

Approved scope: attack-level Fate records and bidirectional menu/passive synchronization. Settings persistence is confirmed working by the user; do not replace it.

- [x] Add failing native Story contract tests for synchronization, notification and per-action deduplication.
- [x] Preserve six mutually exclusive damage routes; append observations only. Keep one last record per character and deduplicate repeated damage events by StoryActionID. Success reports roll count, selected base Duality percentage and actual cost; skipped paths report their actual reason. Do not call a zero-damage event a confirmed miss; omit those intermediate events from result notifications.
- [x] Synchronize the saved Fate switch to its passive using TogglePassive only when the observed status differs. Guard programmatic grant/sync; passive status events update the saved value and menu mirror only outside that guard.
- [x] Validate lifecycle hooks for load, level, respec, control and menu. Preserve existing choices.
- [x] Run updated semantic/mutation checks, full verification, native compile and package reverse checks. Export the next version and back up to GitHub. In-game acceptance remains pending.
