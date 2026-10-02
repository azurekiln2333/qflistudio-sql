param(
  [Parameter(Mandatory = $true)][string]$Archive,
  [string]$Destination = (Join-Path $PSScriptRoot '../../build/mysql/windows')
)
$ErrorActionPreference = 'Stop'
$expected = 'b6c152f9f3aaa7294eb47db698e47974d37b261bf3cab4f90dc1243bb5ecd204'
if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
  throw 'Oracle MySQL 8.4.6 Windows archive does not match the pinned SHA256.'
}
$root = Join-Path $Destination 'mysql-8.4.6-winx64'
if (Test-Path -LiteralPath $root) { throw "Use a fresh staging destination: $Destination" }
Expand-Archive -LiteralPath $Archive -DestinationPath $Destination
foreach ($relative in @('bin/mysqld.exe', 'lib/libmysql.dll', 'include/mysql.h', 'share/english/errmsg.sys', 'LICENSE')) {
  if (-not (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) {
    throw "Incomplete official MySQL distribution: $relative"
  }
}
$manifest = [ordered]@{ format = 1; engine = 'Oracle MySQL'; version = '8.4.6'; platform = 'windows-x64'; archiveSha256 = $expected }
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'runtime.json') -Encoding utf8
Write-Output "Verified Oracle SDK: $root"
