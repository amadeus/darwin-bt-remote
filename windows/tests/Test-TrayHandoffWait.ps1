#Requires -Version 5.1
# Exercise the lifecycle test's process polling without launching an app or service.
$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'Test-ExecutableInstall.ps1'
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$helper = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Wait-SingleCompanionTray'
}, $true)
if ($null -eq $helper) { throw 'Missing tray handoff helper.' }
. ([scriptblock]::Create($helper.Extent.Text))

$binary = '/installed/DeusKVM.Companion.exe'
function Get-Process {
    param($Name, $ErrorAction)
    $index = [Math]::Min($script:polls, $script:snapshots.Count - 1)
    $script:polls++
    foreach ($id in $script:snapshots[$index]) {
        $process = [pscustomobject]@{ Id = $id; Path = $binary; Disposed = $false }
        $process | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
        $script:observed.Add($process)
        $process
    }
    # A downloaded launcher must not count as an installed tray.
    $other = [pscustomobject]@{ Id = 99; Path = '/download/DeusKVM.Companion.exe'; Disposed = $false }
    $other | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
    $script:observed.Add($other)
    $other
}
function Start-Sleep { param($Milliseconds) $script:sleeps++ }
function Reset-Scenario {
    $script:polls = 0
    $script:sleeps = 0
    $script:observed = [Collections.Generic.List[object]]::new()
}

Reset-Scenario
$script:snapshots = @(@(41, 42), @(41))
$tray = Wait-SingleCompanionTray -ExpectedId 41
if ($tray.Id -ne 41 -or $tray.Disposed -or $script:polls -ne 2 -or $script:sleeps -ne 1) {
    throw 'Did not wait for the temporary handoff process to exit.'
}
if (@($script:observed | Where-Object { -not $_.Disposed }).Count -ne 1) {
    throw 'Polling leaked a process snapshot.'
}
$tray.Dispose()
Write-Host 'Transient second process settles to the original tray.'

Reset-Scenario
$script:snapshots = ,@(41)
$tray = Wait-SingleCompanionTray -ExpectedId 41
if ($script:sleeps -ne 0) { throw 'Already settled handoff should not wait.' }
$tray.Dispose()
Write-Host 'Already settled handoff returns immediately.'

foreach ($scenario in @(
    @{ Name = 'persistent duplicate'; Ids = @(41, 42) },
    @{ Name = 'replacement tray'; Ids = @(42) },
    @{ Name = 'missing tray'; Ids = @() }
)) {
    Reset-Scenario
    $script:snapshots = ,$scenario.Ids
    $caught = $null
    try { $null = Wait-SingleCompanionTray -ExpectedId 41 -TimeoutMilliseconds 0 } catch { $caught = $_ }
    if ($null -eq $caught -or $caught.ToString() -notlike 'Expected only the original installed tray*') {
        throw "Did not reject $($scenario.Name): $caught"
    }
    if (@($script:observed | Where-Object { -not $_.Disposed }).Count -ne 0) {
        throw "Failed handoff leaked process snapshots: $($scenario.Name)"
    }
    Write-Host "Rejected $($scenario.Name)."
}
Write-Host 'All five tray handoff checks passed.'
