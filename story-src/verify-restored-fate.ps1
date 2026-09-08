$ErrorActionPreference = 'Stop'
$goals = Join-Path $PSScriptRoot 'Mods/ChaosOriginsStory/Story/RawFiles/Goals'
$base = (Get-Content "$goals/COS_BaseAfterCreation.txt" -Raw).Replace("`r`n", "`n")
$config = Get-Content "$goals/COS_Config.txt" -Raw
$migration = @'
PROC_COS_SyncBaseAfterCreation((CHARACTER)_Character)
AND
HasPassive(_Character, "COS_ChaosOriginMarker", 1)
AND
HasPassive(_Character, "COS_FateRevision", 0)
THEN
DB_COS_CorePassive(1, "COS_FateRevision");
AddPassive(_Character, "COS_FateRevision");
'@
if (-not $base.Contains($migration.Replace("`r`n", "`n"))) { throw '删除改签版本的旧档必须显式恢复改签被动，不能仅依赖 INIT 数据' }
if ($config.Contains('PROC_COS_RetireFate')) { throw '不得在菜单同步时再次删除改签' }
Write-Host 'FATE_RESTORED_STATIC=PASS; IN_GAME=PENDING'
