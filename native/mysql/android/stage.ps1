param(
    [Parameter(Mandatory)][ValidateSet('arm64-v8a','x86_64')][string]$Abi,
    [Parameter(Mandatory)][string]$Runtime,
    [Parameter(Mandatory)][string]$ReadElf
)
$ErrorActionPreference = 'Stop'
$Runtime = (Resolve-Path -LiteralPath $Runtime).ProviderPath
$ReadElf = (Resolve-Path -LiteralPath $ReadElf).ProviderPath
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).ProviderPath
$required = @('bin/mysqld','bin/qfli_mysql_launcher','lib/libqfli_mysql_bridge.so',
    'lib/libc++_shared.so','share/english/errmsg.sys','share/charsets/Index.xml','share/icu/icudt77l/unames.icu',
    'licenses/mysql-LICENSE','licenses/openssl-LICENSE.txt','licenses/android-ndk-NOTICE','PROVENANCE.txt')
foreach ($name in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $Runtime $name) -PathType Leaf)) {
        throw "Incomplete Android Oracle runtime: $name"
    }
}
$nativeNames = @{
    'bin/mysqld' = 'libqfli_mysqld_exec.so'
    'bin/qfli_mysql_launcher' = 'libqfli_mysql_launcher_exec.so'
    'lib/libqfli_mysql_bridge.so' = 'libqfli_mysql_bridge.so'
    'lib/libc++_shared.so' = 'libc++_shared.so'
}
$out = Join-Path $repo 'native/build/mysql-android'
$native = Join-Path $out "jniLibs/$Abi"
$assets = Join-Path $out 'assets'
New-Item -ItemType Directory -Force -Path $native,$assets | Out-Null
$data = [Collections.Generic.List[IO.FileInfo]]::new()
$digests = [Collections.Generic.List[string]]::new()
$publicLibraries = @('libc.so','libm.so','libdl.so','liblog.so','libc++_shared.so')
foreach ($file in Get-ChildItem -LiteralPath $Runtime -Recurse -File | Sort-Object FullName) {
    $relative = [IO.Path]::GetRelativePath($Runtime,$file.FullName).Replace('\','/')
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $isElf = $bytes.Length -ge 64 -and $bytes[0] -eq 127 -and $bytes[1] -eq 69 -and $bytes[2] -eq 76 -and $bytes[3] -eq 70
    if ($nativeNames.ContainsKey($relative) -and -not $isElf) { throw "Oracle native input is not ELF: $relative" }
    if ($isElf) {
        if (-not $nativeNames.ContainsKey($relative)) { throw "Unexpected Android Oracle native file: $relative" }
        $expected = if ($Abi -eq 'x86_64') { 62 } else { 183 }
        if ($bytes[4] -ne 2 -or $bytes[5] -ne 1 -or [BitConverter]::ToUInt16($bytes,18) -ne $expected -or [BitConverter]::ToUInt16($bytes,16) -ne 3) {
            throw "Oracle native input must be a matching ELF64 PIE/shared object: $relative"
        }
        $table = [BitConverter]::ToUInt64($bytes,32)
        $size = [BitConverter]::ToUInt16($bytes,54)
        $count = [BitConverter]::ToUInt16($bytes,56)
        $hasInterpreter = $false
        for ($index = 0; $index -lt $count; $index++) {
            $entry = [int]($table + $index * $size)
            $type = [BitConverter]::ToUInt32($bytes,$entry)
            if ($type -eq 3) {
                $hasInterpreter = $true
                $start = [int][BitConverter]::ToUInt64($bytes,$entry + 8)
                $length = [int][BitConverter]::ToUInt64($bytes,$entry + 32)
                if ([Text.Encoding]::ASCII.GetString($bytes,$start,$length).TrimEnd([char]0) -ne '/system/bin/linker64') {
                    throw "Oracle input has a non-Android interpreter: $relative"
                }
            }
            if ($type -ne 1) { continue }
            $alignment = [BitConverter]::ToUInt64($bytes,$entry + 48)
            $offset = [BitConverter]::ToUInt64($bytes,$entry + 8)
            $address = [BitConverter]::ToUInt64($bytes,$entry + 16)
            if ($alignment -lt 16384 -or $offset % 16384 -ne $address % 16384) {
                throw "Oracle input lacks 16 KiB LOAD compatibility: $relative"
            }
        }
        if ($relative.StartsWith('bin/') -and -not $hasInterpreter) { throw "Oracle executable lacks Android interpreter: $relative" }
        $dynamic = (& $ReadElf --dynamic $file.FullName 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw "Cannot inspect ELF dependencies: $relative" }
        foreach ($match in [regex]::Matches($dynamic,'\(NEEDED\).*?\[([^\]]+)\]')) {
            if ($match.Groups[1].Value -notin $publicLibraries) {
                throw "Unpackaged or private Android dependency $($match.Groups[1].Value): $relative"
            }
        }
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $native $nativeNames[$relative]) -Force
    } else {
        $data.Add($file)
    }
    $digests.Add($relative + ':' + (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant())
}
$id = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($digests -join "`n"))).ToLowerInvariant()
$manifest = @{
    version = 1
    id = "$Abi-$id"
    serverVersion = '8.4.6'
    api = 28
    sourceSha256 = 'a1e523dc8be96d18a5ade106998661285ca01b6f5b46c08b2654110e40df2fb7'
    opensslSha256 = 'c9489d2abcf943cdc8329a57092331c598a402938054dc3a22218aea8a8ec3bf'
    inputs = @($digests.ToArray())
} | ConvertTo-Json -Depth 4 -Compress
[IO.File]::WriteAllText((Join-Path $assets "mysql-$Abi.json"),$manifest,[Text.UTF8Encoding]::new($false))
$zipPath = Join-Path $assets "mysql-$Abi.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath }
$zip = [IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $data) {
        $relative = [IO.Path]::GetRelativePath($Runtime,$file.FullName).Replace('\','/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.FullName,$relative) | Out-Null
    }
} finally { $zip.Dispose() }
Write-Output "Android Oracle ${Abi}: $($nativeNames.Count) native files, $($data.Count) resource files; $zipPath"
