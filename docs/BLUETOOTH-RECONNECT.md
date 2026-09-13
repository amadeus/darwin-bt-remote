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
powershell.exe -NoProfile -File .\Test-BTRemoteConnection.ps1
```

If local script policy prevents running the file, open it in a text editor and
paste its contents into Windows PowerShell. No policy change is needed.

It selects the paired device named BTRemote, or asks the user to select the
paired Mac if that name is not unique/present. It prints cached and uncached
service-discovery status and holds the device references for twenty seconds
to allow checking edge switching. It does not pair, unpair, write reports or
install anything. Its Windows Runtime calls cannot be executed on this Mac;
Windows results and whether HID input recovers remain unverified.

References:

- [Apple: restored peripheral services](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanagerrestoredstateserviceskey)
- [Microsoft: Bluetooth GATT client connection behavior](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/gatt-client)
- [Microsoft: Bluetooth service cache](https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.bluetoothcachemode)
