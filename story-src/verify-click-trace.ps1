$ErrorActionPreference = 'Stop'
$source = Get-Content "$PSScriptRoot/Mods/ChaosOriginsStory/Story/RawFiles/Goals/COS_Config.txt" -Raw
foreach ($pattern in @(
    'TutorialEvent\(_Character, _Event\)\s*AND\s*DB_COS_GrantEvent\(_Event, _Key\)\s*THEN\s*DB_COS_ConfigClickTrace\(_Character, _Key, "Received"\);',
    'TutorialEvent\(_Character, \(TUTORIALEVENT\)COS_CFG_VOLO_EYE_77000000-0000-4000-8000-000000000001\)\s*THEN\s*DB_COS_ConfigClickTrace\(_Character, "VoloEye", "Received"\);',
    'DB_COS_GrantSetting\(_Character, _Key, _Next\);\s*PROC_COS_ApplyGrantOptions\(_Character\);\s*DB_COS_ConfigClickTrace\(_Character, _Key, "Applied"\);',
    'TogglePassive\(_Character, _Passive\);\s*PROC_COS_SyncOriginGrantMirrors\(_Character\);\s*DB_COS_ConfigClickTrace\(_Character, _Key, "Applied"\);',
    'DB_COS_VoloEyeSetting\(_Character, _Next\);\s*PROC_COS_SyncVoloEye\(_Character\);\s*DB_COS_ConfigClickTrace\(_Character, "VoloEye", "Applied"\);'
)) { if ($source -notmatch $pattern) { throw "Missing click boundary: $pattern" } }
'CLICK_TRACE_STATIC=PASS; RUNTIME=PENDING'
