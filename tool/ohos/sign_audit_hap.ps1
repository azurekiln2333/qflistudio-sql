param(
    [Parameter(Mandatory = $true)][string]$DeviceUdid,
    [string]$BundleName = 'com.azurekiln.qfli.sqlab.audit',
    [string]$Sdk = 'D:/ProgramFiles/Huawei/DevEco Studio/sdk/default/openharmony',
    [string]$Jdk = 'D:/ProgramFiles/Huawei/DevEco Studio/jbr'
)
$ErrorActionPreference = 'Stop'
if ($BundleName -notmatch '^com\.azurekiln\.qfli\.sqlab\.[a-z][a-z0-9.]*$') {
    throw 'Only an independent SQL audit bundle may use the public SDK test identity.'
}
if ($DeviceUdid -notmatch '^[A-Fa-f0-9]{32,128}$') { throw 'Invalid device UDID.' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = Join-Path $repo 'build/ohos-audit'
$unsigned = Join-Path $output 'sql-audit-unsigned.hap'
$build = Get-Content -Raw -LiteralPath (Join-Path $output 'build.json') | ConvertFrom-Json
if ($build.bundleName -ne $BundleName) { throw 'Bundle does not match the audit build record.' }
if ($build.unsignedSha256 -ne (Get-FileHash -LiteralPath $unsigned).Hash) { throw 'Unsigned artifact changed.' }
$lib = Join-Path $Sdk 'toolchains/lib'
$java = Join-Path $Jdk 'bin/java.exe'
$keytool = Join-Path $Jdk 'bin/keytool.exe'
$store = Join-Path $lib 'OpenHarmony.p12'
$jar = Join-Path $lib 'hap-sign-tool.jar'
$profile = Get-Content -Raw -LiteralPath (Join-Path $lib 'UnsgnedDebugProfileTemplate.json') | ConvertFrom-Json
$profile.uuid = [Guid]::NewGuid().ToString()
$profile.validity.'not-before' = [DateTimeOffset]::UtcNow.AddMinutes(-10).ToUnixTimeSeconds()
$profile.validity.'not-after' = [DateTimeOffset]::UtcNow.AddDays(30).ToUnixTimeSeconds()
$profile.'bundle-info'.'bundle-name' = $BundleName
$profile.'debug-info'.'device-ids' = @($DeviceUdid)
$profilePath = Join-Path $output 'audit-profile.json'
[IO.File]::WriteAllText($profilePath, ($profile | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
$chain = $profile.'bundle-info'.'development-certificate'
if ($chain -notmatch '-----BEGIN CERTIFICATE-----') { throw 'SDK template has no application certificate.' }
$chain += "`n"
# The release key's store entry contains a self-signed certificate. The SDK
# profile template supplies the CA-issued certificate for that same public key.
# App signing verifies that certificate against the actual signing key.
foreach ($alias in 'openharmony application ca', 'openharmony application root ca') {
    # The SDK ships this public test store and its documented default password.
    # Export certificates only; no key is generated, exported or copied.
    $certificate = & $keytool -exportcert -rfc -alias $alias -keystore $store -storepass 123456 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to export public SDK certificate.' }
    $chain += ($certificate -join "`n") + "`n"
}
$chainPath = Join-Path $output 'sdk-app-chain.pem'
[IO.File]::WriteAllText($chainPath, $chain, [Text.UTF8Encoding]::new($false))
$signedProfile = Join-Path $output 'audit-profile.p7b'
& $java -jar $jar sign-profile -mode localSign -keyAlias 'openharmony application profile debug' `
    -keyPwd 123456 -profileCertFile (Join-Path $lib 'OpenHarmonyProfileDebug.pem') `
    -inFile $profilePath -signAlg SHA256withECDSA -keystoreFile $store -keystorePwd 123456 -outFile $signedProfile `
    *> (Join-Path $output 'sign-profile.log')
if ($LASTEXITCODE -ne 0) { throw 'Audit profile signing failed; inspect sign-profile.log.' }
$signed = Join-Path $output 'sql-audit-signed.hap'
& $java -jar $jar sign-app -mode localSign -keyAlias 'openharmony application release' `
    -keyPwd 123456 -appCertFile $chainPath -profileFile $signedProfile -inFile $unsigned `
    -signAlg SHA256withECDSA -keystoreFile $store -keystorePwd 123456 -outFile $signed -compatibleVersion 18 `
    *> (Join-Path $output 'sign-app.log')
if ($LASTEXITCODE -ne 0) { throw 'Audit HAP signing failed; inspect sign-app.log.' }
& $java -jar $jar verify-app -inFile $signed -outCertChain (Join-Path $output 'verified-chain.cer') `
    -outProfile (Join-Path $output 'verified-profile.p7b') *> (Join-Path $output 'verify-app.log')
if ($LASTEXITCODE -ne 0) { throw 'Signed audit HAP verification failed.' }
$build | Add-Member -NotePropertyName signed -NotePropertyValue $true -Force
$build | Add-Member -NotePropertyName signedSha256 -NotePropertyValue (Get-FileHash -LiteralPath $signed).Hash -Force
$build | Add-Member -NotePropertyName signingIdentity -NotePropertyValue 'OpenHarmony SDK public test identity' -Force
[IO.File]::WriteAllText((Join-Path $output 'build.json'), ($build | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
Write-Output "Signed independent audit HAP: $signed"
Write-Output "SHA256: $((Get-FileHash -LiteralPath $signed).Hash)"
Write-Output 'Device trust/install remains unverified. This script performs no device operation.'
