#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$admin = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $process = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath)
    )
    exit $process.ExitCode
}

. (Join-Path $PSScriptRoot 'NativeCommand.ps1')
function Invoke-ServiceCommand {
    param([string[]] $Arguments)
    Invoke-BTRemoteNative -FilePath "$env:SystemRoot\System32\sc.exe" -Arguments $Arguments
}
function Protect-Directory {
    param([string] $Path)
    if (Test-Path -LiteralPath $Path) {
        if ((Get-Item -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing to install through a directory link: $Path"
        }
        $owner = (Get-Acl -LiteralPath $Path).GetOwner([Security.Principal.SecurityIdentifier]).Value
        if ($owner -notin @('S-1-5-18', 'S-1-5-32-544')) {
            throw "Existing directory is not owned by SYSTEM or Administrators: $Path"
        }
    } else { New-Item -ItemType Directory -Path $Path | Out-Null }
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $admins = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $acl.SetOwner($admins)
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.SecurityIdentifier]::new($sid), 'FullControl',
            'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        [Security.Principal.SecurityIdentifier]::new('S-1-5-11'), 'ReadAndExecute',
        'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    Set-Acl -LiteralPath $Path -AclObject $acl
}

try {
    $source = Join-Path $PSScriptRoot 'BTRemote.Companion.exe'
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Extract the entire companion ZIP before installing.' }
    $install = Join-Path $env:ProgramFiles 'BTRemote Companion'
    $data = Join-Path $env:ProgramData 'BTRemote'
    $binary = Join-Path $install 'BTRemote.Companion.exe'
    $existing = Get-Service -Name BTRemoteCompanion -ErrorAction SilentlyContinue
    $startAfterInstall = $null -eq $existing -or $existing.Status -eq 'Running'
    if ($existing -and $existing.Status -ne 'Stopped') {
        Stop-Service BTRemoteCompanion
        $existing.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
    }
    $tray = Get-Process -Name 'BTRemote.Companion' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $binary }
    if ($tray) { throw 'Choose Quit Tray in BTRemote, then run Install.cmd again.' }
    Protect-Directory $install
    Protect-Directory $data
    # never overwrite a redirected target in the privileged installation directory.
    if ((Test-Path -LiteralPath $binary) -and ((Get-Item -LiteralPath $binary).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The installed executable is a link; installation stopped.'
    }
    Copy-Item -LiteralPath $source -Destination $binary -Force
    $imagePath = '"{0}" --service' -f $binary
    if ($existing) {
        Invoke-ServiceCommand -Arguments @('config', 'BTRemoteCompanion', 'binPath=', $imagePath, 'obj=', 'LocalSystem')
    } else {
        Invoke-ServiceCommand -Arguments @('create', 'BTRemoteCompanion', 'binPath=', $imagePath,
            'start=', 'auto', 'obj=', 'LocalSystem', 'DisplayName=', 'BTRemote Companion')
    }
    Invoke-ServiceCommand -Arguments @('description', 'BTRemoteCompanion', 'Maintains the paired Mac Bluetooth connection independently of user login.')
    Invoke-ServiceCommand -Arguments @('failure', 'BTRemoteCompanion', 'reset=', '86400', 'actions=', 'restart/5000/restart/15000/restart/60000')
    Invoke-ServiceCommand -Arguments @('failureflag', 'BTRemoteCompanion', '0')
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'BTRemote Companion.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $binary
    $shortcut.WorkingDirectory = $install
    $shortcut.Save()
    if ($startAfterInstall) { Start-Service BTRemoteCompanion }
    Write-Host 'Installed. Open BTRemote Companion from the Start menu and select your paired Mac.'
    Write-Host "Diagnostics: $data"
    Write-Host 'The service starts at boot and survives logout. The tray is optional.'
} catch {
    Write-Error $_
    exit 1
}
Read-Host 'Press Enter to close'
