param(
    [string]$Target = 'integration_test/sql_curriculum_ohos_audit.dart',
    [ValidateSet('ohos-x64', 'ohos-arm64')][string]$Architecture = 'ohos-x64',
    [string]$BundleName = 'com.azurekiln.qfli.sqlab.audit',
    [string[]]$DartDefines = @(),
    [string]$Flutter = 'D:/ProgramFiles/flutter_ohos/bin/flutter.bat',
    [string]$Json5Module = '',
    [string]$DevEcoHome = 'D:/ProgramFiles/Huawei/DevEco Studio'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if ($BundleName -notmatch '^com\.azurekiln\.qfli\.sqlab\.[a-z][a-z0-9.]*$') {
    throw 'Use a separate SQL audit bundle; the installed production bundle is preserved.'
}
if (-not (Test-Path -LiteralPath (Join-Path $repo $Target))) { throw 'Audit target does not exist.' }
if (-not (Test-Path -LiteralPath $Flutter -PathType Leaf)) { throw 'Explicit Flutter executable does not exist.' }
$Flutter = (Resolve-Path -LiteralPath $Flutter).Path
if (-not (Test-Path -LiteralPath $DevEcoHome -PathType Container)) { throw 'Explicit DevEco home does not exist.' }
$DevEcoHome = (Resolve-Path -LiteralPath $DevEcoHome).Path
$nodeHome = Join-Path $DevEcoHome 'tools/node'
$javaHome = Join-Path $DevEcoHome 'jbr'
$sdkRoot = Join-Path $DevEcoHome 'sdk'
$pathPrefix = @($nodeHome, (Join-Path $DevEcoHome 'tools/ohpm/bin'),
    (Join-Path $DevEcoHome 'tools/hvigor/bin'), (Join-Path $javaHome 'bin'),
    (Join-Path $sdkRoot 'default/openharmony/toolchains'))
foreach ($directory in $pathPrefix) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Selected toolchain directory does not exist: $directory" }
}
if (-not $Json5Module) { $Json5Module = Join-Path $DevEcoHome 'tools/hvigor/hvigor-ohos-plugin/node_modules/json5' }
if (-not (Test-Path -LiteralPath $Json5Module)) { throw 'Explicit JSON5 module does not exist.' }
$Json5Module = (Resolve-Path -LiteralPath $Json5Module).Path
$toolFiles = [ordered]@{
    flutter = $Flutter
    node = Join-Path $nodeHome 'node.exe'
    npm = Join-Path $nodeHome 'npm.cmd'
    npmCli = Join-Path $nodeHome 'node_modules/npm/bin/npm-cli.js'
    npmPrefix = Join-Path $nodeHome 'node_modules/npm/bin/npm-prefix.js'
    ohpm = Join-Path $DevEcoHome 'tools/ohpm/bin/ohpm.bat'
    ohpmCli = Join-Path $DevEcoHome 'tools/ohpm/bin/pm-cli.js'
    hvigor = Join-Path $DevEcoHome 'tools/hvigor/bin/hvigorw.bat'
    hvigorCli = Join-Path $DevEcoHome 'tools/hvigor/bin/hvigorw.js'
    java = Join-Path $javaHome 'bin/java.exe'
    sdkPackage = Join-Path $sdkRoot 'default/sdk-pkg.json'
}
if (Test-Path -LiteralPath $Json5Module -PathType Container) {
    # Node resolves package.json/main for directory modules. Bind the whole
    # selected parser package so its implementation cannot change unnoticed.
    $parserFiles = @(Get-ChildItem -LiteralPath $Json5Module -File -Recurse)
    if (-not $parserFiles.Count) { throw 'Explicit JSON5 module is empty.' }
    foreach ($file in $parserFiles) {
        $toolFiles['json5/' + [IO.Path]::GetRelativePath($Json5Module, $file.FullName)] = $file.FullName
    }
} else { $toolFiles['json5'] = $Json5Module }
$toolInputs = [ordered]@{}
foreach ($item in $toolFiles.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $item.Value -PathType Leaf)) { throw "Selected toolchain input does not exist: $($item.Key)" }
    $path = (Resolve-Path -LiteralPath $item.Value).Path
    $toolInputs[$item.Key] = @{ path = $path; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
}
if (Test-Path -LiteralPath (Join-Path $repo 'ohos/hvigorw.bat')) {
    throw 'Unbound project-local Hvigor wrapper would override the selected toolchain.'
}
# Flutter prefers this persistent setting over SDK environment variables. Read
# only its SDK selector, and never rewrite or print the rest of the settings.
$appData = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
# Flutter reads relative settings/SDK paths from its child CWD (the repo),
# and falls back to '.' when APPDATA is absent.
$settingsHome = if ($appData) { [IO.Path]::GetFullPath($appData, $repo) } else { $repo }
$settingsPath = Join-Path $settingsHome '.flutter_settings'
if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    $settings = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
    $sdkSetting = $settings.PSObject.Properties['ohos-sdk']
    if ($sdkSetting -and $null -ne $sdkSetting.Value) {
        if ($sdkSetting.Value -isnot [string] -or -not $sdkSetting.Value) {
            throw 'Persistent ohos-sdk conflicts with the selected DevEco SDK.'
        }
        $configuredSdk = [IO.Path]::GetFullPath($sdkSetting.Value, $repo)
        if (-not (Test-Path -LiteralPath $configuredSdk -PathType Container) -or
            -not [StringComparer]::OrdinalIgnoreCase.Equals((Resolve-Path -LiteralPath $configuredSdk).Path, $sdkRoot)) {
            throw 'Persistent ohos-sdk conflicts with the selected DevEco SDK.'
        }
    }
}
$environmentChanges = [ordered]@{
    NODE_HOME = $nodeHome; JAVA_HOME = $javaHome
    DEVECO_SDK_HOME = $sdkRoot; HOS_SDK_HOME = $sdkRoot
    npm_config_prefix = $nodeHome; OHOS_HOME = $null; OHOS_SDK_HOME = $null
    PATH = ($pathPrefix -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:PATH
}
$originalEnvironment = @{}
foreach ($name in $environmentChanges.Keys) { $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
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
    foreach ($name in $environmentChanges.Keys) { [Environment]::SetEnvironmentVariable($name, $environmentChanges[$name], 'Process') }
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
    $global:LASTEXITCODE = $null
    & $toolInputs.node.path -e $edit $Json5Module $profilePath $appPath $BundleName
    if ($null -eq $LASTEXITCODE -or $LASTEXITCODE -ne 0) { throw 'Unable to prepare isolated audit metadata.' }
    $temporaryProfile = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash
    $temporaryApp = (Get-FileHash -LiteralPath $appPath -Algorithm SHA256).Hash
    $arguments = @('build', 'hap', '--debug', '--target-platform', $Architecture,
        '--no-codesign', '--no-pub', '--target', $Target)
    foreach ($define in $DartDefines) { $arguments += "--dart-define=$define" }
    $global:LASTEXITCODE = $null
    & $Flutter @arguments *> (Join-Path $output 'build.log')
    if ($null -eq $LASTEXITCODE -or $LASTEXITCODE -ne 0) { throw 'Audit build failed; inspect build/ohos-audit/build.log.' }
    foreach ($item in $toolInputs.GetEnumerator()) {
        if ((Get-FileHash -LiteralPath $item.Value.path -Algorithm SHA256).Hash -ne $item.Value.sha256) {
            throw "Selected toolchain input changed during the build: $($item.Key)"
        }
    }
    $unsigned = Join-Path $repo 'ohos/entry/build/default/outputs/default/entry-default-unsigned.hap'
    $artifact = Join-Path $output 'sql-audit-unsigned.hap'
    Copy-Item -LiteralPath $unsigned -Destination $artifact
    $identity = @{
        bundleName = $BundleName; architecture = $Architecture; target = $Target
        dartDefines = $DartDefines; builtAt = [DateTime]::UtcNow.ToString('o')
        flutter = (Resolve-Path -LiteralPath $Flutter).Path
        flutterSha256 = (Get-FileHash -LiteralPath $Flutter -Algorithm SHA256).Hash
        toolchain = @{ devEcoHome = $DevEcoHome; sdkRoot = $sdkRoot; json5Module = $Json5Module
            pathPrefix = $pathPrefix; inputs = $toolInputs
            environment = @{ NODE_HOME = $nodeHome; JAVA_HOME = $javaHome
                DEVECO_SDK_HOME = $sdkRoot; HOS_SDK_HOME = $sdkRoot; npm_config_prefix = $nodeHome }
            clearedEnvironment = @('OHOS_HOME', 'OHOS_SDK_HOME') }
        unsignedSha256 = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
        signed = $false; deviceExecuted = $false
    }
    $identity | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'build.json') -Encoding utf8
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
        try {
            if ($locationPushed) { Pop-Location }
            $lock.Dispose()
            Remove-Item -LiteralPath $lockPath
        } finally {
            foreach ($name in $originalEnvironment.Keys) {
                [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process')
            }
        }
    }
    if ($restoreIssue) { throw $restoreIssue }
}
