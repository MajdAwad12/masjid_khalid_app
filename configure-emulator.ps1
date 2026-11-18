$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $root 'firebase.json'
$rulesPath = Join-Path $root 'firestore.rules'

if (-not (Test-Path $configPath)) {
    throw 'firebase.json not found. Extract this ZIP into the Flutter project root.'
}
if (-not (Test-Path $rulesPath)) {
    throw 'firestore.rules not found.'
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
if ($config.PSObject.Properties.Name -contains 'firestore') {
    if ($config.firestore -is [array]) {
        throw 'firebase.json contains multiple Firestore databases. Configure the rules path manually.'
    }
    $config.firestore | Add-Member -NotePropertyName 'rules' -NotePropertyValue 'firestore.rules' -Force
} else {
    $config | Add-Member -NotePropertyName 'firestore' -NotePropertyValue ([pscustomobject]@{ rules = 'firestore.rules' })
}

$backupPath = "$configPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $configPath $backupPath
$json = $config | ConvertTo-Json -Depth 40
[System.IO.File]::WriteAllText($configPath, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
Write-Host 'DONE: linked firestore.rules in firebase.json' -ForegroundColor Green
Write-Host "Backup: $backupPath"
Write-Host 'Restart emulators to load the new rules.'
