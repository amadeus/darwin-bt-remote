#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$admin = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $process = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath)
    )
    exit $process.ExitCode
}
try {
    $service = Get-Service BTRemoteCompanion -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -ne 'Stopped') {
            Stop-Service BTRemoteCompanion
            $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
        }
        & "$env:SystemRoot\System32\sc.exe" delete BTRemoteCompanion
        if ($LASTEXITCODE -ne 0) { throw 'Could not unregister the service.' }
    }
    $shortcut = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'BTRemote Companion.lnk'
    if (Test-Path -LiteralPath $shortcut) { Remove-Item -LiteralPath $shortcut }
    Write-Host 'Service removed. Pairing, saved configuration and diagnostics are retained.'
    Write-Host 'Quit Tray to close the optional UI. Installed files may then be removed from Program Files\BTRemote Companion.'
} catch { Write-Error $_; exit 1 }
Read-Host 'Press Enter to close'
