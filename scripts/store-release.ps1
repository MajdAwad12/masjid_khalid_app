# PowerShell on Windows, or pwsh on a Mac with Xcode.
param(
  [Parameter(Mandatory)][ValidateSet('android','ios')][string]$Platform,
  [Parameter(Mandatory)][ValidateSet('Release','Patch')][string]$Action,
  [string]$ReleaseVersion
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
if ($Platform -eq 'ios' -and (-not $IsMacOS)) { throw 'iOS distribution requires macOS and Xcode.' }
if (-not (Test-Path 'store-config.json')) { throw 'Complete store-config.json as described in PRODUCTION.MD.' }
node scripts/prepare-store-site.cjs
if ($LASTEXITCODE -ne 0) { throw 'Invalid store configuration.' }
if (-not (Get-Command shorebird -ErrorAction SilentlyContinue)) { throw 'Install the Shorebird CLI and run shorebird login. See PRODUCTION.MD.' }
if (-not (Test-Path 'shorebird.yaml')) { throw 'Restore the registered shorebird.yaml from this project before building.' }
if ($Platform -eq 'android' -and (-not (Test-Path 'android/key.properties'))) { throw 'Configure the Android upload key in android/key.properties.' }
if ($Action -eq 'Release') {
  & shorebird release $Platform --flutter-version=3.50.0 --dart-define-from-file=store-config.json
} else {
  if ($ReleaseVersion -notmatch '^\d+\.\d+\.\d+\+\d+$') { throw 'Provide the exact installed base version, for example 1.0.0+1.' }
  & shorebird patch $Platform "--release-version=$ReleaseVersion" --track=staging --dart-define-from-file=store-config.json
}
if ($LASTEXITCODE -ne 0) { throw "Shorebird $Action failed." }
