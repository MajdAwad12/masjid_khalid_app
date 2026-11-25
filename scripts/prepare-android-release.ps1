# Run from the project root: powershell -ExecutionPolicy Bypass -File scripts/prepare-android-release.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
function Require-Env($Name) {
  $value = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($value)) { throw "Missing environment variable: $Name" }
  return $value.Trim()
}
$managerName = Require-Env 'SUPPORT_MANAGER_NAME'
$managerPhone = Require-Env 'SUPPORT_MANAGER_PHONE'
$privacyUrl = Require-Env 'PRIVACY_POLICY_URL'
if ($managerName.Contains('لاحقًا') -or $managerPhone.Contains('لاحقًا')) {
  throw 'Replace temporary support contacts with real contact details.'
}
if (($managerPhone -replace '\D','').Length -lt 8) {
  throw 'SUPPORT_MANAGER_PHONE must contain a valid telephone number.'
}
if ($privacyUrl -notmatch '^https://[^/]+') {
  throw 'PRIVACY_POLICY_URL must be a real HTTPS policy URL.'
}
if (-not (Test-Path 'android/key.properties')) {
  throw 'Create android/key.properties from android/key.properties.example with your real upload signing credentials.'
}
$signingText = Get-Content 'android/key.properties' -Raw
if ($signingText -match 'REPLACE_ME|YOUR_USER') { throw 'Set actual signing properties; placeholders are forbidden.' }
foreach ($field in @('storeFile', 'storePassword', 'keyAlias', 'keyPassword')) {
  if ($signingText -notmatch "(?m)^$field=.+") { throw "Missing signing property: $field" }
}
node scripts/release-smoke.cjs
if ($LASTEXITCODE -ne 0) { throw 'Preflight release smoke failed.' }
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed.' }
flutter test
if ($LASTEXITCODE -ne 0) { throw 'flutter test failed.' }
flutter build appbundle --release --dart-define="SUPPORT_MANAGER_NAME=$managerName" --dart-define="SUPPORT_MANAGER_PHONE=$managerPhone" --dart-define="PRIVACY_POLICY_URL=$privacyUrl"
if ($LASTEXITCODE -ne 0) { throw 'Android release build failed.' }
Write-Host 'Release AAB built. Check Google Play pre-launch tests and physical devices before submission.'
