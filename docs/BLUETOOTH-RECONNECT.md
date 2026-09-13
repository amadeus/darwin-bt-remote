# Bluetooth reconnect investigation

## Verified result

On 2026-09-13, Windows uncached GATT discovery restored the existing Maingear
connection to the signed macOS BTRemote build without removing or re-pairing
the device. Windows reported `paired: True`, then `Uncached discovery: Success`
and a transition from `Disconnected` to `Connected`. The Mac log recorded the
host reading the rebuilt HID services and subscribing to the battery and all
four HID input reports. Amadeus confirmed edge switching/control worked both
during the diagnostic and after its process exited.

The saved pairing remains usable. Automatic reconnect/service rediscovery is
the failing path. The exact Windows cache/driver decision remains an inference;
the Mac log does not expose Windows' internal state.

## Reproduction and evidence

1. Pair from Windows: HID control works and Setup shows one subscribed host.
2. Quit BTRemote normally: `bluetoothd` removes its published HID services,
   sends service-change indications that Windows acknowledges, then locally
   disconnects the encrypted BLE link as unused.
3. Relaunch: services install and advertising starts, but Windows does not
   automatically reconnect or subscribe. A manual ordinary Bluetooth reconnect
   reached Classic AVRCP rather than BLE HID. Cycling Bluetooth off/on in
   Windows did not restore HID either.
4. Run uncached discovery from Windows with the existing pairing: BLE connects,
   the Mac's existing Service Changed workaround runs, Windows subscribes again,
   and control remains usable after the diagnostic exits.

Toggling Force Service Changed on the Mac while disconnected did not recover
Windows. It can help rediscovery once a BLE connection exists, but cannot
notify a disconnected client.

## State restoration experiment

A stable `CBPeripheralManagerOptionRestoreIdentifierKey` and a handler that
reused restored services/subscriptions did not fix normal quit. The daemon
reported `persistence: on` but still removed the services and disconnected the
host; relaunch did not call `willRestoreState`. That experiment was removed.
The original input implementation builds and its ten tests pass.

## Current workaround

Keep BTRemote advertising on the Mac. Copy
`scripts/Test-BTRemoteConnection.ps1` to the PC and run it in a separate Windows
PowerShell 5.1 process:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-BTRemoteConnection.ps1
```

The execution-policy override applies only to this process, without changing
saved user/machine policy. Select the existing paired Mac entry. The script
prints cached/fresh discovery results and holds its references for twenty
seconds; process exit releases its temporary handles. It does not pair,
unpair, write HID reports or install anything. Successful recovery has been
verified in one live run; it is not yet automatic.

Device enumeration needs a compiled C# `IEnumerable` bridge because Windows
PowerShell's WinRT collection indexing/method binding is unreliable here.
Optional service-vector printing is omitted because Windows exposes that
vector as an unprojected COM object. Local syntax/selection/status regressions
pass with `scripts/tests/Test-BTRemoteSelection.ps1` under portable PowerShell
7.6.6 on macOS; the complete script has now also run successfully on Windows.

## Planned automatic recovery

Include reconnect/service rediscovery in M3's Windows companion. Retain the
chosen paired BLE endpoint, request a connection when the Mac is available,
and refresh services when needed. Microsoft's documented options include
uncached discovery and `GattSession.MaintainConnection`. Validate ordinary Mac
quit/relaunch and Windows sleep/radio cycles before claiming automatic recovery.
Keep the working HID descriptor, report encoding and input path unchanged.

References:

- [Apple: restored peripheral services](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanagerrestoredstateserviceskey)
- [Microsoft: Bluetooth GATT client connection behavior](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/gatt-client)
- [Microsoft: Bluetooth service cache](https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.bluetoothcachemode)
