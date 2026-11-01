# Complete, verified cold backup of the production MySQL directory.
# Enumerates every regular file (size + relative path), fetches each through the
# app-visible /data/storage/el2/base/haps/entry/files/mysql path via
# `hdc file recv -b`, and fails on any missing/truncated file. Never chmods.
$ErrorActionPreference = 'Stop'
$B = 'com.azurekiln.qfli.sqlab'
$T = '192.168.68.207:46551'
$APPBASE = "/data/app/el2/100/base/$B/haps/entry/files/mysql"
$VISIBLE = "/data/storage/el2/base/haps/entry/files/mysql"
$DIR = 'build/mysql-port/prod-cold-backup-20261009'
$DST = "$DIR/mysql"
$manifest = "$DIR/prod-file-sizes.txt"
New-Item -ItemType Directory -Force -Path $DST | Out-Null

$failures = New-Object System.Collections.Generic.List[string]
$ok = 0
$entries = Get-Content $manifest | Where-Object { $_ -match '^\d+ \./' }
Write-Host "manifest entries: $($entries.Count)"

foreach ($line in $entries) {
    if ($line -notmatch '^(\d+) \./(.+)$') { $failures.Add("unparsed: $line"); continue }
    $size = [int64]$Matches[1]
    $rel = $Matches[2]
    $local = Join-Path $DST ($rel -replace '/', '\')
    $localDir = Split-Path $local -Parent
    if (-not (Test-Path $localDir)) { New-Item -ItemType Directory -Force -Path $localDir | Out-Null }
    hdc -t $T file recv -b $B "$VISIBLE/$rel" "$local" *> $null
    if (-not (Test-Path $local)) { $failures.Add("MISSING $rel"); continue }
    $actual = (Get-Item $local).Length
    if ($actual -ne $size) { $failures.Add("TRUNCATED $rel expected=$size actual=$actual"); continue }
    $ok++
}

Write-Host "fetched+verified: $ok / $($entries.Count)"
if ($failures.Count -gt 0) {
    Write-Host "FAILURES ($($failures.Count)):"
    $failures | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" }
    $failures | Set-Content "$DIR/backup-failures.txt"
    exit 1
}
Write-Host "COLD BACKUP COMPLETE AND VERIFIED"
