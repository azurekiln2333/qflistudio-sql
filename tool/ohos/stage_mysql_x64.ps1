param(
    [string]$Distribution = 'qfli-java-build',
    [string]$PortRoot = '/root/qfli-mysql-ohos-x64-1022'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if ($PortRoot -notmatch '^/root/[a-zA-Z0-9_-]+$') { throw 'Use an isolated absolute port root.' }
if ($Distribution -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid WSL distribution name.' }
$sourceRoot = "\\wsl.localhost\$Distribution" + $PortRoot.Replace('/', '\')
$report = Get-Content -Raw -LiteralPath (Join-Path $sourceRoot 'closure-report.json') | ConvertFrom-Json
if ($report.status -ne 'PASS' -or $report.resourceFiles -ne 70) { throw 'Candidate ELF closure/resource audit did not pass.' }
$destination = Join-Path $repo 'build/mysql-port/package/libs/x86_64'
[IO.Directory]::CreateDirectory($destination) | Out-Null
$libraries = @('libqfli_mysql.so', 'libqfli_mysql_server.so', 'libqfli_mysql_launcher.so', 'libqfli_mysql_server_proto.so')
function Assert-Candidate([string]$File, $Identity) {
    if ((Get-Item -LiteralPath $File).Length -ne $Identity.packagedBytes -or
        (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne $Identity.packagedSha256) {
        throw "Candidate hash/size differs from audited output: $File"
    }
    $stream = [IO.File]::OpenRead($File)
    try {
        $header = [byte[]]::new(20)
        if ($stream.Read($header, 0, 20) -ne 20 -or
            [BitConverter]::ToString($header, 0, 6) -ne '7F-45-4C-46-02-01' -or
            $header[18] -ne 62 -or $header[19] -ne 0) {
            throw "Expected a little-endian x86_64 ELF: $File"
        }
    } finally { $stream.Dispose() }
}
foreach ($library in $libraries) {
    $source = Join-Path $sourceRoot "package/libs/x86_64/$library"
    Assert-Candidate $source $report.artifacts.$library
}
foreach ($library in $libraries) {
    $source = Join-Path $sourceRoot "package/libs/x86_64/$library"
    $target = Join-Path $destination $library
    Copy-Item -LiteralPath $source -Destination $target
    Assert-Candidate $target $report.artifacts.$library
}
$record = @{
    stagedAt = [DateTime]::UtcNow.ToString('o'); source = $sourceRoot
    destination = $destination; artifacts = $report.artifacts
    runtimeVerified = $false; deviceVerified = $false
}
[IO.File]::WriteAllText((Join-Path $destination 'staging.json'), ($record | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
Write-Output 'Staged four exact audited real Oracle x86_64 libraries. ARM64 and shared resources were preserved.'
