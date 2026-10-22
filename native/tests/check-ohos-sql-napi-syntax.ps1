# Compile-verifies the OHOS SQLite NAPI bridge against a real DevEco SDK and
# includes the production isolated-validation core. Runtime behavior is checked
# separately by run-sql-validation-test.ps1 against the real bundled SQLite.
#
# This is a syntax/typing gate only: it does not run a device, install a HAP,
# or write shared build output. When no SDK is present it prints SKIP and
# exits 0, because a compile check is not runtime acceptance.
$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$source = Join-Path $repo 'ohos\entry\src\main\cpp\qfli_sql_napi.cpp'
$validation = Join-Path $repo 'ohos\entry\src\main\cpp\qfli_sql_validation.cpp'

function Find-Sdk {
    $candidates = @()
    if ($env:DEVECO_SDK_HOME) {
        $candidates += (Join-Path $env:DEVECO_SDK_HOME 'native')
        $candidates += (Join-Path $env:DEVECO_SDK_HOME 'openharmony\native')
    }
    if ($env:OHOS_NDK_HOME) { $candidates += $env:OHOS_NDK_HOME }
    $candidates += 'D:\ProgramFiles\Huawei\DevEco Studio\sdk\default\openharmony\native'
    $candidates += 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native'
    $candidates += (Join-Path $env:LOCALAPPDATA 'Huawei\DevEco Studio\sdk\default\openharmony\native')
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path (Join-Path $candidate 'llvm\bin\clang++.exe'))) {
            return (Resolve-Path $candidate).Path
        }
    }
    return $null
}

$sdk = Find-Sdk
if (-not $sdk) {
    Write-Output 'SKIP: no DevEco/OpenHarmony native SDK found (set DEVECO_SDK_HOME).'
    Write-Output '      A compile check is not runtime acceptance either way.'
    exit 0
}

$clang = Join-Path $sdk 'llvm\bin\clang++.exe'
$includes = @(
    "--sysroot=$sdk\sysroot",
    "-I$sdk\sysroot\usr\include".Replace('\', '/'),
    "-I$(Join-Path $repo 'native\third_party\sqlite')".Replace('\', '/'),
    "-I$(Join-Path $repo 'native\src')".Replace('\', '/')
)

$status = 0
foreach ($target in 'aarch64-linux-ohos', 'x86_64-linux-ohos') {
    $output = & $clang -fsyntax-only -std=c++17 -Wall -Wextra -Werror `
        -target $target @includes $source $validation 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Output "PASS: $target -Werror syntax check for NAPI and isolated validation core"
    } else {
        Write-Output "FAIL: $target syntax check for NAPI and isolated validation core"
        $output | ForEach-Object { Write-Output "  $_" }
        $status = 1
    }
}

exit $status
