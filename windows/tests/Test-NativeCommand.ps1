#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../packaging/NativeCommand.ps1')
$folder = Join-Path ([IO.Path]::GetTempPath()) ('btremote arguments ' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $folder | Out-Null
try {
    $echo = Join-Path $folder 'echo arguments.ps1'
    Set-Content -LiteralPath $echo -Value 'ConvertTo-Json -InputObject @($args) -Compress' -Encoding UTF8
    $hostExe = (Get-Process -Id $PID).Path
    $expected = @('config', 'BTRemoteCompanion', 'binPath=',
        '"C:\Program Files\BTRemote Companion\BTRemote.Companion.exe" --service',
        '', 'trailing\', 'embedded"quote', 'name with spaces')
    $result = Invoke-BTRemoteNative -FilePath $hostExe -Arguments (@('-NoProfile', '-File', $echo) + $expected)
    $actual = @($result | ConvertFrom-Json)
    if ($actual.Count -ne $expected.Count) { throw "Wrong argument count: $result" }
    for ($i = 0; $i -lt $expected.Count; $i++) {
        if ($actual[$i] -cne $expected[$i]) { throw "Argument $i changed: $result" }
    }
    foreach ($path in Get-ChildItem (Join-Path $PSScriptRoot '../packaging') -Filter '*.ps1') {
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($path.FullName, [ref] $tokens, [ref] $errors)
        if ($errors.Count -ne 0) { throw ($errors | Out-String) }
    }
    Write-Host 'Native argument round-trip and installer syntax checks passed.'
} finally { Remove-Item -LiteralPath $folder -Recurse -Force }
