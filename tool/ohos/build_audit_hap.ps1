param(
    [string]$Target = 'integration_test/sql_curriculum_ohos_audit.dart',
    [ValidateSet('ohos-x64', 'ohos-arm64')][string]$Architecture = 'ohos-x64',
    [string]$BundleName = 'com.azurekiln.qfli.sqlab.audit',
    [string[]]$DartDefines = @(),
    [string]$Json5Module = 'D:/ProgramFiles/Huawei/DevEco Studio/tools/hvigor/hvigor-ohos-plugin/node_modules/json5'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if ($BundleName -notmatch '^com\.azurekiln\.qfli\.sqlab\.[a-z][a-z0-9.]*$') {
    throw 'Use a separate SQL audit bundle; the installed production bundle is preserved.'
}
if (-not (Test-Path -LiteralPath (Join-Path $repo $Target))) { throw 'Audit target does not exist.' }
$output = Join-Path $repo 'build/ohos-audit'
[IO.Directory]::CreateDirectory($output) | Out-Null
$lockPath = Join-Path $output '.build-lock'
$lock = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
$profilePath = Join-Path $repo 'ohos/build-profile.json5'
$appPath = Join-Path $repo 'ohos/AppScope/app.json5'
$originalProfile = $null
$originalApp = $null
$mutated = $false
$locationPushed = $false
$temporaryProfile = $null
$temporaryApp = $null
try {
    $originalProfile = [IO.File]::ReadAllBytes($profilePath)
    $originalApp = [IO.File]::ReadAllBytes($appPath)
    Push-Location $repo
    $locationPushed = $true
    # Use Hvigor's own JSON5 parser. No signing material is printed or copied
    # into the audit artifact. The original files are restored byte for byte.
    $edit = @'
const fs = require('fs');
const json5 = require(process.argv[1]);
const profilePath = process.argv[2], appPath = process.argv[3];
const profile = json5.parse(fs.readFileSync(profilePath, 'utf8'));
profile.app.signingConfigs = [];
for (const product of profile.app.products) delete product.signingConfig;
const app = json5.parse(fs.readFileSync(appPath, 'utf8'));
app.app.bundleName = process.argv[4];
fs.writeFileSync(profilePath, JSON.stringify(profile, null, 2));
fs.writeFileSync(appPath, JSON.stringify(app, null, 2));
'@
    # Mark before invoking Node so a partial edit is also restored on failure.
    $mutated = $true
    & node -e $edit $Json5Module $profilePath $appPath $BundleName
    if ($LASTEXITCODE -ne 0) { throw 'Unable to prepare isolated audit metadata.' }
    $temporaryProfile = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash
    $temporaryApp = (Get-FileHash -LiteralPath $appPath -Algorithm SHA256).Hash
    $arguments = @('build', 'hap', '--debug', '--target-platform', $Architecture,
        '--no-codesign', '--no-pub', '--target', $Target)
    foreach ($define in $DartDefines) { $arguments += "--dart-define=$define" }
    & flutter @arguments *> (Join-Path $output 'build.log')
    if ($LASTEXITCODE -ne 0) { throw 'Audit build failed; inspect build/ohos-audit/build.log.' }
    $unsigned = Join-Path $repo 'ohos/entry/build/default/outputs/default/entry-default-unsigned.hap'
    $artifact = Join-Path $output 'sql-audit-unsigned.hap'
    Copy-Item -LiteralPath $unsigned -Destination $artifact
    $identity = @{
        bundleName = $BundleName; architecture = $Architecture; target = $Target
        dartDefines = $DartDefines; builtAt = [DateTime]::UtcNow.ToString('o')
        unsignedSha256 = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
        signed = $false; deviceExecuted = $false
    }
    $identity | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'build.json') -Encoding utf8
    Write-Output "Built independent audit HAP: $artifact"
} finally {
    $restoreIssue = $null
    try {
      if ($mutated) {
        # No other worker owns these two files during this build. Refuse to
        # overwrite unexpected edits, and retain exact backups for recovery.
        $changed = ($temporaryProfile -and (Get-FileHash -LiteralPath $profilePath).Hash -ne $temporaryProfile) -or
            ($temporaryApp -and (Get-FileHash -LiteralPath $appPath).Hash -ne $temporaryApp)
        if ($changed) {
            [IO.File]::WriteAllBytes((Join-Path $output 'build-profile.original'), $originalProfile)
            [IO.File]::WriteAllBytes((Join-Path $output 'app.original'), $originalApp)
            $restoreIssue = 'Concurrent metadata edit detected; exact original backups retained in ignored build output.'
        } else {
            [IO.File]::WriteAllBytes($profilePath, $originalProfile)
            [IO.File]::WriteAllBytes($appPath, $originalApp)
        }
      }
    } finally {
        if ($locationPushed) { Pop-Location }
        $lock.Dispose()
        Remove-Item -LiteralPath $lockPath
    }
    if ($restoreIssue) { throw $restoreIssue }
}
