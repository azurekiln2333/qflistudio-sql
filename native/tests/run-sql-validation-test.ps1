param(
    [string]$BuildDirectory = '',
    [string]$CMakeExecutable = '',
    [string]$CCompiler = '',
    [string]$CxxCompiler = '',
    [string]$NinjaExecutable = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Find-Tool([string]$Explicit, [string]$Name, [string[]]$Candidates) {
    if ($Explicit) { return (Resolve-Path -LiteralPath $Explicit).Path }
    $found = Get-Command $Name -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    foreach ($candidate in $Candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw "Missing $Name. Pass its explicit executable path; this gate cannot silently skip."
}

$sdkTools = 'D:\ProgramFiles\Huawei\DevEco Studio\sdk\default\openharmony\native\build-tools\cmake\bin'
$cmake = Find-Tool $CMakeExecutable 'cmake' @("$sdkTools\cmake.exe")
$ninja = Find-Tool $NinjaExecutable 'ninja' @("$sdkTools\ninja.exe")
$cc = Find-Tool $CCompiler 'gcc' @('D:\ProgramFiles\Dev-Cpp\MinGW64\bin\gcc.exe')
$cxx = Find-Tool $CxxCompiler 'g++' @('D:\ProgramFiles\Dev-Cpp\MinGW64\bin\g++.exe')
if (-not $BuildDirectory) {
    $BuildDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("qfli-sql-validation-" + [guid]::NewGuid())
}
$priorPath = $env:PATH
try {
    $env:PATH = (Split-Path -Parent $cc) + ';' + $priorPath
    & $cmake -S (Join-Path $PSScriptRoot 'sql_validation') -B $BuildDirectory -G Ninja `
        "-DCMAKE_MAKE_PROGRAM=$($ninja.Replace('\', '/'))" `
        "-DCMAKE_C_COMPILER=$($cc.Replace('\', '/'))" `
        "-DCMAKE_CXX_COMPILER=$($cxx.Replace('\', '/'))"
    if ($LASTEXITCODE -ne 0) { throw 'Native validation test configure failed.' }
    & $cmake --build $BuildDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Native validation test build failed.' }
    & (Join-Path (Split-Path -Parent $cmake) 'ctest.exe') --test-dir $BuildDirectory --output-on-failure
    if ($LASTEXITCODE -ne 0) { throw 'Native validation real-engine behavior tests failed.' }
    Write-Output "PASS: production core real-engine tests; build directory: $BuildDirectory"
} finally {
    $env:PATH = $priorPath
}
