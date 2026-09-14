#Requires -Version 5.1
#Requires -RunAsAdministrator
# Run only on a disposable Windows CI machine: exercises real SCM and EXE updates.
param([Parameter(Mandatory = $true)][string] $Executable)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $Executable).Path
$install = Join-Path $env:ProgramFiles 'BTRemote Companion'
$binary = Join-Path $install 'BTRemote.Companion.exe'
$data = Join-Path $env:ProgramData 'BTRemote'
$shortcut = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'BTRemote Companion.lnk'
if ((Get-Service BTRemoteCompanion -ErrorAction SilentlyContinue) -or
    (Test-Path -LiteralPath $install) -or (Test-Path -LiteralPath $data) -or
    (Test-Path -LiteralPath $shortcut)) {
    throw 'This test requires a clean machine without an existing BTRemote installation.'
}
function Start-CompanionProcess {
    param([string] $Path, [string[]] $Command = @())
    # Retain the native process handle, including for short-lived commands.
    # Windows PowerShell's Start-Process -PassThru can lose their exit code.
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Path
    $start.UseShellExecute = $false
    # All test arguments are fixed switches or the literal "manual".
    if ($Command | Where-Object { $_ -notmatch '^[a-z-]+$' }) { throw 'Unexpected test argument.' }
    $start.Arguments = $Command -join ' '
    return [Diagnostics.Process]::Start($start)
}
function Stop-CompanionProcess {
    param([Diagnostics.Process] $Process)
    if (-not $Process.HasExited) { $Process.Kill() }
    if (-not $Process.WaitForExit(10000)) { throw "Process $($Process.Id) did not exit." }
}
function Invoke-Companion {
    param([string] $Path, [string[]] $Command)
    Write-Host "Running companion: $Command"
    $process = Start-CompanionProcess $Path $Command
    try {
        if (-not $process.WaitForExit(60000)) {
            Stop-CompanionProcess $process
            throw "Companion timed out: $Command"
        }
        if ($process.ExitCode -ne 0) { throw "Companion failed ($($process.ExitCode)): $Command" }
        Write-Host "Completed companion: $Command"
    } finally { $process.Dispose() }
}
function Assert-Service {
    param([string] $State, [string] $Startup)
    $service = Get-Service BTRemoteCompanion
    try {
        if ($service.Status.ToString() -ne $State -or $service.StartType.ToString() -ne $Startup) {
            throw "Expected $State/$Startup, got $($service.Status)/$($service.StartType)"
        }
    } finally { $service.Dispose() }
}
$failure = $null
$cleanupErrors = [Collections.Generic.List[string]]::new()
try {
    Invoke-Companion $source @('--install')
    Assert-Service 'Running' 'Automatic'
    if (-not (Test-Path -LiteralPath $shortcut)) { throw 'Missing Start menu shortcut.' }
    foreach ($directory in @($install, $data)) {
        $acl = Get-Acl -LiteralPath $directory
        if (-not $acl.AreAccessRulesProtected) { throw "Unprotected directory: $directory" }
        if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne 'S-1-5-32-544') {
            throw "Incorrect directory owner: $directory"
        }
        $users = @($acl.Access | Where-Object {
            $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-11'
        })
        if ($users.Count -ne 1 -or ($users[0].FileSystemRights -band [Security.AccessControl.FileSystemRights]::Write)) {
            throw "Ordinary users can modify the installation: $directory"
        }
    }
    Invoke-Companion $binary @('--stop')
    Invoke-Companion $binary @('--startup', 'manual')
    # Preserve machine configuration byte-for-byte, independently of Bluetooth hardware.
    $settings = Join-Path $data 'settings.json'
    [IO.File]::WriteAllText($settings, '{"DeviceId":"test-selected-mac","DeviceName":"Keep this Mac"}')
    $before = (Get-FileHash -LiteralPath $settings).Hash
    Write-Host 'Checking update with the installed tray open.'
    $tray = Start-CompanionProcess $binary
    try {
        if (-not $tray.WaitForInputIdle(10000)) { throw 'Installed EXE did not open its UI.' }
        Invoke-Companion $source @('--install')
        if (-not $tray.WaitForExit(10000)) { throw 'Update did not close the previous tray.' }
    } finally { $tray.Dispose() }
    Assert-Service 'Stopped' 'Manual'
    if ((Get-FileHash -LiteralPath $settings).Hash -ne $before) { throw 'Update changed the selected Mac.' }
    if ((Get-FileHash -LiteralPath $binary).Hash -ne (Get-FileHash -LiteralPath $source).Hash) { throw 'Wrong installed EXE.' }
    Remove-Item -LiteralPath $settings
    Invoke-Companion $binary @('--start')
    Invoke-Companion $source @('--install')
    Assert-Service 'Running' 'Manual'
    Invoke-Companion $binary @('--stop')
    # An identical downloaded EXE should just open the installed window; no install.
    Write-Host 'Checking downloaded EXE handoff and settings reopening.'
    $launcher = Start-CompanionProcess $source
    try {
        if (-not $launcher.WaitForExit(15000) -or $launcher.ExitCode -ne 0) { throw 'Downloaded EXE did not hand off to installed UI.' }
    } finally { $launcher.Dispose() }
    Assert-Service 'Stopped' 'Manual'
    $tray = @(Get-Process -Name 'BTRemote.Companion' | Where-Object { $_.Path -eq $binary })
    if ($tray.Count -ne 1 -or -not $tray[0].WaitForInputIdle(10000)) { throw 'Expected one installed UI.' }
    try {
        if (-not $tray[0].CloseMainWindow()) { throw 'Could not close settings to test reopening.' }
        Start-Sleep -Milliseconds 500
        $again = Start-CompanionProcess $source
        try {
            if (-not $again.WaitForExit(15000) -or $again.ExitCode -ne 0) { throw 'Could not reopen companion.' }
        } finally { $again.Dispose() }
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        do {
            Start-Sleep -Milliseconds 100
            $tray[0].Refresh()
        } while ($tray[0].MainWindowHandle -eq 0 -and [DateTime]::UtcNow -lt $deadline)
        if ($tray[0].MainWindowHandle -eq 0 -or $tray[0].HasExited) { throw 'Existing tray did not reopen settings.' }
    } finally { $tray[0].Dispose() }
    Write-Host 'EXE installation, update, state preservation, permissions and service controls passed.'
} catch {
    $failure = $_
    Write-Host "Lifecycle test failed before cleanup: $($_ | Out-String)"
    foreach ($name in @('status.json', 'service.log')) {
        $path = Join-Path $data $name
        if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Tail 30 -ErrorAction Continue | Out-Host }
    }
} finally {
    # Cleanup must finish process termination before deleting mapped EXEs, and
    # must not replace the original assertion with a secondary cleanup error.
    try {
        $service = Get-Service BTRemoteCompanion -ErrorAction SilentlyContinue
        if ($service) {
            try {
                if ($service.Status -ne 'Stopped') { $service.Stop(); $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30)) }
                & "$env:SystemRoot\System32\sc.exe" delete BTRemoteCompanion
                if ($LASTEXITCODE -ne 0) { throw "Service deletion failed: $LASTEXITCODE" }
            } finally { $service.Dispose() }
        }
    } catch { $cleanupErrors.Add($_.ToString()) }
    foreach ($process in @(Get-Process -Name 'BTRemote.Companion' -ErrorAction SilentlyContinue)) {
        try {
            if ($process.Path -eq $binary -or $process.Path -eq $source) { Stop-CompanionProcess $process }
        } catch { $cleanupErrors.Add($_.ToString()) }
        finally { $process.Dispose() }
    }
    foreach ($path in @($shortcut, $install, $data)) {
        try {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
        } catch { $cleanupErrors.Add($_.ToString()) }
    }
}
foreach ($message in $cleanupErrors) { Write-Warning "Cleanup failed: $message" }
if ($failure) { throw $failure }
if ($cleanupErrors.Count -ne 0) { throw 'Lifecycle test cleanup failed; see warnings above.' }
