#Requires -Version 5.1
<#
Run in Windows PowerShell 5.1 with BTRemote advertising on the Mac.
Select the existing paired Mac/BTRemote entry. This requests GATT discovery;
it does not pair, unpair, write HID reports, or install anything.
#>
[CmdletBinding()]
param(
    [string] $DeviceName = 'BTRemote',
    [ValidateRange(0, 60)]
    [int] $HoldSeconds = 20
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Use Windows PowerShell 5.1 (powershell.exe), not PowerShell 7 (pwsh.exe).'
}

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType = WindowsRuntime]
$null = [Windows.Devices.Enumeration.DeviceInformationCollection, Windows.Devices.Enumeration, ContentType = WindowsRuntime]
$null = [Windows.Devices.Bluetooth.BluetoothLEDevice, Windows.Devices.Bluetooth, ContentType = WindowsRuntime]
$null = [Windows.Devices.Bluetooth.BluetoothCacheMode, Windows.Devices.Bluetooth, ContentType = WindowsRuntime]
$null = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattDeviceServicesResult, Windows.Devices.Bluetooth, ContentType = WindowsRuntime]

$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and
    $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
if ($null -eq $asTask) { throw 'The Windows Runtime async adapter is unavailable.' }

function Wait-WinRT {
    param($Operation, [Type] $ResultType)
    $task = $asTask.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    if (-not $task.Wait(45000)) {
        throw 'Windows did not finish the Bluetooth request within 45 seconds.'
    }
    # Keep a DeviceInformationCollection as one result rather than unrolling it.
    return ,($task.GetAwaiter().GetResult())
}

function Show-Services {
    param([string] $Label, $Result)
    Write-Host "$Label discovery: $($Result.Status)"
    if ($null -ne $Result.ProtocolError) {
        Write-Host "ATT protocol error: $($Result.ProtocolError)"
    }
    foreach ($service in $Result.Services) {
        Write-Host "  $($service.Uuid)"
    }
}

$selector = [Windows.Devices.Bluetooth.BluetoothLEDevice]::GetDeviceSelectorFromPairingState($true)
$devices = Wait-WinRT ([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($selector)) `
    ([Windows.Devices.Enumeration.DeviceInformationCollection])
if ($devices.Count -eq 0) {
    throw 'Windows reports no paired BLE devices. The existing Mac entry may only be a Classic Bluetooth pairing.'
}

$matchesByName = @($devices | Where-Object { $_.Name -eq $DeviceName })
if ($matchesByName.Count -eq 1) {
    $selected = $matchesByName[0]
} else {
    Write-Host 'Select the paired Mac/BTRemote entry:'
    for ($i = 0; $i -lt $devices.Count; $i++) {
        Write-Host "  [$i] $($devices[$i].Name)"
    }
    $selectionText = Read-Host 'Device number (blank cancels)'
    $selectionIndex = 0
    if (-not [int]::TryParse($selectionText, [ref] $selectionIndex) -or
        $selectionIndex -lt 0 -or $selectionIndex -ge $devices.Count) {
        throw 'No valid device selected; nothing was connected.'
    }
    $selected = $devices[$selectionIndex]
}

$device = $null
$cached = $null
$fresh = $null
try {
    Write-Host "Selected: $($selected.Name); paired: $($selected.Pairing.IsPaired)"
    $device = Wait-WinRT ([Windows.Devices.Bluetooth.BluetoothLEDevice]::FromIdAsync($selected.Id)) `
        ([Windows.Devices.Bluetooth.BluetoothLEDevice])
    if ($null -eq $device) { throw 'Windows could not open the selected BLE device.' }
    Write-Host "Connection before discovery: $($device.ConnectionStatus)"

    $cached = Wait-WinRT ($device.GetGattServicesAsync([Windows.Devices.Bluetooth.BluetoothCacheMode]::Cached)) `
        ([Windows.Devices.Bluetooth.GenericAttributeProfile.GattDeviceServicesResult])
    Show-Services 'Cached' $cached

    Write-Host 'Requesting fresh services from the Mac...'
    $fresh = Wait-WinRT ($device.GetGattServicesAsync([Windows.Devices.Bluetooth.BluetoothCacheMode]::Uncached)) `
        ([Windows.Devices.Bluetooth.GenericAttributeProfile.GattDeviceServicesResult])
    Show-Services 'Uncached' $fresh
    Write-Host "Connection after discovery: $($device.ConnectionStatus)"
    Write-Host "Keeping these references open for $HoldSeconds seconds; try edge switching on the Mac now."
    Start-Sleep -Seconds $HoldSeconds
    Write-Host "Connection at end: $($device.ConnectionStatus)"
    Write-Host 'Done. Copy the output and report whether Mac edge switching worked.'
} finally {
    foreach ($result in @($cached, $fresh)) {
        if ($null -ne $result) {
            foreach ($service in $result.Services) { $service.Dispose() }
        }
    }
    if ($null -ne $device) { $device.Dispose() }
}
