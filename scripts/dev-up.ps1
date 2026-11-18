<#
.SYNOPSIS
  Starts the local demo stack: MQTT broker + simulator (broker/) and the API (api/).
  Everything listens on 127.0.0.1 only.

.PARAMETER Phone
  Also forward the phone's ports 1883 and 3000 to this computer over USB (adb reverse).

.PARAMETER NoRandomSpikes
  Calm, predictable data (good for recordings). Spikes can still be triggered with
  `npm run spike -- <device>` in broker/.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\dev-up.ps1 -Phone
#>
param(
  [switch]$Phone,
  [switch]$NoRandomSpikes
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $root '.dev-pids.json'
$logDir = Join-Path $root 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null

function Get-Listener([int]$port) {
  Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
}

# Already running?
if (Test-Path $pidFile) {
  $old = Get-Content $pidFile -Raw | ConvertFrom-Json
  $alive = @($old.broker, $old.api) | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }
  if ($alive) {
    Write-Host "Already running (PIDs $($alive -join ', ')). Run scripts\dev-down.ps1 first." -ForegroundColor Yellow
    exit 0
  }
  Remove-Item $pidFile
}

# Port checks.
foreach ($port in 1883, 3000) {
  foreach ($l in @(Get-Listener $port)) {
    $name = (Get-Process -Id $l.OwningProcess -ErrorAction SilentlyContinue).ProcessName
    if ($l.LocalAddress -eq '127.0.0.1') {
      Write-Host "Port $port on 127.0.0.1 is already used by '$name' (PID $($l.OwningProcess)). Stop it first." -ForegroundColor Red
      exit 1
    }
    $msg = ("WARNING: '{0}' (PID {1}) also listens on {2}:{3}. That is NOT part of this project and is " +
      "reachable from your network. Our services bind 127.0.0.1 and take precedence locally, but if ours " +
      "stop, local clients will connect to '{0}' instead.") -f $name, $l.OwningProcess, $l.LocalAddress, $port
    Write-Host $msg -ForegroundColor Yellow
  }
}

# Dependencies.
foreach ($dir in 'broker', 'api') {
  if (-not (Test-Path (Join-Path $root "$dir\node_modules"))) {
    Write-Host "Installing $dir dependencies..."
    Push-Location (Join-Path $root $dir); npm install --no-fund --no-audit | Out-Null; Pop-Location
  }
}

$node = (Get-Command node).Source
$simArgs = @('src/dev.js')
if ($NoRandomSpikes) { $simArgs += '--no-random-spikes' }

$broker = Start-Process -FilePath $node -ArgumentList $simArgs -WorkingDirectory (Join-Path $root 'broker') `
  -RedirectStandardOutput (Join-Path $logDir 'broker.log') -RedirectStandardError (Join-Path $logDir 'broker.err.log') `
  -WindowStyle Hidden -PassThru
Start-Sleep -Milliseconds 800
$api = Start-Process -FilePath $node -ArgumentList 'src/server.js' -WorkingDirectory (Join-Path $root 'api') `
  -RedirectStandardOutput (Join-Path $logDir 'api.log') -RedirectStandardError (Join-Path $logDir 'api.err.log') `
  -WindowStyle Hidden -PassThru

@{ broker = $broker.Id; api = $api.Id; started = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content $pidFile

# Wait for both to listen on loopback.
$deadline = (Get-Date).AddSeconds(20)
$ready = @{ 1883 = $false; 3000 = $false }
while ((Get-Date) -lt $deadline -and ($ready.Values -contains $false)) {
  foreach ($port in 1883, 3000) {
    $want = if ($port -eq 1883) { $broker.Id } else { $api.Id }
    if (@(Get-Listener $port) | Where-Object { $_.OwningProcess -eq $want -and $_.LocalAddress -eq '127.0.0.1' }) {
      $ready[$port] = $true
    }
  }
  Start-Sleep -Milliseconds 300
}
if ($ready.Values -contains $false) {
  Write-Host 'Startup failed. See logs\broker*.log and logs\api*.log. Stopping what was started.' -ForegroundColor Red
  & (Join-Path $PSScriptRoot 'dev-down.ps1')
  exit 1
}

Write-Host "Broker + simulator: mqtt://127.0.0.1:1883   (PID $($broker.Id))" -ForegroundColor Green
Write-Host "API:                http://127.0.0.1:3000   (PID $($api.Id))" -ForegroundColor Green
Write-Host "Logs:               $logDir"

if ($Phone) {
  $devices = (adb devices) -match "`tdevice$"
  if (-not $devices) {
    Write-Host 'No authorized phone found (adb devices). Skipping adb reverse.' -ForegroundColor Yellow
  } else {
    adb reverse tcp:1883 tcp:1883 | Out-Null
    adb reverse tcp:3000 tcp:3000 | Out-Null
    Write-Host 'Phone: adb reverse tcp:1883 and tcp:3000 active (over USB, not the network).' -ForegroundColor Green
  }
}
Write-Host 'Stop everything with: scripts\dev-down.ps1'
