# Bluetooth reconnect investigation

Observed on 2026-09-13 with the signed macOS Debug build and the Windows
Maingear host. Input works after pairing, but a normal BTRemote quit/relaunch
loses the HID connection. Removing and pairing again restores it.

## Confirmed observations

- Before quit, Windows subscribes to the battery and four HID input reports;
  Setup shows one subscribed host.
- On quit, `bluetoothd` removes all services belonging to BTRemote. It sends
  GATT change indications, which Windows acknowledges, then disconnects the
  encrypted BLE link as locally initiated because it is no longer used.
- Relaunch installs the services and advertises successfully, but no host
  subscription or incoming BLE connection follows during the observation.
- A manual reconnect attempt reached the Mac's ordinary Bluetooth Classic
  connection (AVRCP), without establishing the BLE HID connection.
- Toggling the existing Force Service Changed setting while disconnected did
  not recover the host; changing the database cannot notify a disconnected
  Windows client.
- Cycling Bluetooth off/on in Windows while retaining the pairing did not
  reconnect automatically. BTRemote still showed zero subscriptions afterward.

## Experiment that did not fix normal quit

Added a stable `CBPeripheralManagerOptionRestoreIdentifierKey` and a handler
that reused restored services, report references and subscribed centrals.
The daemon confirmed `persistence: on`. After a fresh working pairing, normal
quit still removed the services and disconnected the host; relaunch never
called `willRestoreState`. The experiment was removed from the source rather
than retained as a reconnect fix. The original input implementation builds
and its ten tests pass.

## Current interpretation and next check

This is a BLE service-lifetime/reconnection problem, not merely a missing
device row or the edge-switch gate. Windows may update its service cache when
the HID service disappears and subsequently stop requesting that connection.
That Windows-side explanation remains an inference; the Mac log does not
expose Windows' cache or driver state.

The next targeted test is uncached GATT discovery from Windows. Microsoft
documents that uncached discovery or `GattSession.MaintainConnection` can initiate a BLE connection.
The planned Windows companion can use that mechanism, but reconnect behavior
must be verified independently of cursor placement.

`scripts/Test-BTRemoteConnection.ps1` performs this diagnostic in Windows
PowerShell 5.1. Keep BTRemote advertising on the Mac, copy the script to the PC,
and run it from Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-BTRemoteConnection.ps1
```

The execution-policy override applies only to this PowerShell process; it does
not change the saved user or machine policy.

It selects the paired device named BTRemote, or asks the user to select the
paired Mac if that name is not unique/present. It prints cached and uncached
service-discovery status and holds the device references for twenty seconds
to allow checking edge switching. It does not pair, unpair, write reports or
install anything. Its Windows Runtime calls cannot be executed on this Mac;
fresh-discovery results and whether HID input recovers remain unverified.
Run it as the separate process shown above so process exit releases all its
temporary native device/service handles.

The first Windows run exposed a diagnostic bug: its WinRT collection printed
all device names in row zero and passed multiple IDs to `FromIdAsync`. That
failure does not establish a Bluetooth connection or bond failure. Selection
now copies the collection through its enumerator into a managed list, queries
association endpoints explicitly, and validates that the selected value is one
device. Async failures include the underlying message and HRESULT.

The second Windows run failed when PowerShell bound `GetEnumerator` on the
WinRT collection. A local fixture exposing a conflicting public overload
reproduced the exact zero-argument method error. Device collection copying now
uses a compiled C# helper calling `IEnumerable` directly. That same regression
passes with the helper. Neither failed
Windows run reached a valid service-discovery result.

The third run selected the correct Mac and reported `paired: True`,
`Connection before discovery: Disconnected`, and `Cached discovery: Success`.
It then failed converting the optional service vector (`System.__ComObject`)
to `IEnumerable`, before uncached discovery. No Mac-side HID interaction was
logged during that attempt. Service-vector enumeration has been removed from
both reporting and cleanup: only discovery status, protocol errors, and
connection state are needed for this test. This result confirms Windows has
a saved BLE pairing, but does not yet validate a live encrypted connection.

`scripts/tests/Test-BTRemoteSelection.ps1` checks the script syntax and the
actual selection helper with an enumeration-only collection, including four
separate devices, name selection, one device, and no devices. It passes under
portable PowerShell 7.6.6 on macOS, including the conflicting-enumerator
regression and status reporting with a service-vector property that throws on
access; the Windows PowerShell 5.1/WinRT retry is still required.

References:

- [Apple: restored peripheral services](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanagerrestoredstateserviceskey)
- [Microsoft: Bluetooth GATT client connection behavior](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/gatt-client)
- [Microsoft: Bluetooth service cache](https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.bluetoothcachemode)
