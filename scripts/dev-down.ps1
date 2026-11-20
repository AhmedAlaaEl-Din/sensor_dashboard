<#
.SYNOPSIS
  Stops what scripts\dev-up.ps1 started (only those processes) and cleans up.

.PARAMETER Phone
  Also remove the phone's port forwards (adb reverse --remove-all) and turn off
  "stay awake while charging".
#>
param([switch]$Phone)

$root = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $root '.dev-pids.json'

if (Test-Path $pidFile) {
  $pids = Get-Content $pidFile -Raw | ConvertFrom-Json
  foreach ($name in 'api', 'broker') {
    $id = $pids.$name
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($p -and $p.ProcessName -eq 'node') {
      Stop-Process -Id $id -Force
      Write-Host "Stopped $name (PID $id)."
    } elseif ($p) {
      Write-Host "PID $id is now '$($p.ProcessName)', not ours. Left it alone." -ForegroundColor Yellow
    } else {
      Write-Host "$name was not running."
    }
  }
  Remove-Item $pidFile
} else {
  Write-Host 'Nothing to stop (no .dev-pids.json).'
}

if ($Phone -and (Get-Command adb -ErrorAction SilentlyContinue)) {
  adb reverse --remove-all 2>$null | Out-Null
  adb shell svc power stayon false 2>$null | Out-Null
  Write-Host 'Phone: port forwards removed, stay-awake off.'
}

foreach ($port in 1883, 3000) {
  $l = Get-NetTCPConnection -LocalPort $port -State Listen -LocalAddress 127.0.0.1 -ErrorAction SilentlyContinue
  if ($l) { Write-Host "Note: something still listens on 127.0.0.1:$port (PID $($l.OwningProcess))." -ForegroundColor Yellow }
}
