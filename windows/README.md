# Windows companion: service reconnect checkpoint

This first M3 build tests automatic Bluetooth recovery under a Windows service
account. It includes the service, its isolated Bluetooth worker, an optional
tray/settings UI, and Start/Stop/automatic-start controls. Desktop edge return,
matching cursor placement, custom companion GATT traffic, and clipboard sync
are not implemented yet. The existing Mac edge switch and return hotkey still
provide control.

## Install and configure

1. Keep the existing Mac pairing and leave BTRemote advertising on the Mac.
2. Extract the entire ZIP on the PC. Run **Install.cmd** and approve the Windows
   administrator prompt. No .NET SDK or runtime installation is needed.
3. Open **BTRemote Companion** from the Windows Start menu. Select the paired Mac
   and click **Use selected Mac**; approve the configuration change.
4. Watch the Bluetooth status. `Discovered` means uncached GATT discovery found
   HID; it does **not** prove Windows subscribed to keyboard/mouse input. Check
   the Mac's Setup screen and try controlling Windows.

The service runs as LocalSystem, including before login and after sign-out. Its
BLE worker inherits that identity in Session 0 and uses a dedicated STA message
loop for WinRT. Whether Windows allows this account to restore HID is the live
checkpoint; it has not yet been verified on the PC. The worker is isolated so a
stalled Bluetooth API cannot prevent Stop from shutting down the service.

Windows may display its normal unsigned-app reputation prompt for this personal
build. The archive is built from this repository; no installer downloads or
third-party servers are used at runtime.

## Tray controls

- **Start Service:** start now.
- **Stop Service:** stop companion recovery now. Existing OS HID connections may
  remain active; this does not unpair or disable Bluetooth. Mac hotkey return
  remains available.
- **Start automatically with Windows:** checked by default. Changes Automatic
  versus Manual startup for future boots without starting/stopping it now. A
  manually started service survives logout in either mode. An intentional Stop
  is respected until Start or the next boot with automatic startup enabled.
- **Quit Tray:** close the optional UI, leaving the service running.

Service/configuration changes request administrator permission. Opening settings
and viewing status do not. The tray's automatic-start checkbox reads actual
Windows service configuration, not a separate app preference.

## First manual checkpoint

First verify reconnect while signed in: restart the Mac app, leave the pairing
intact, and confirm the service restores Mac HID subscriptions and control.
Then choose **Quit Tray**, sign out of Windows (not just lock), and restart the
Mac app again. Verify you can control the Windows sign-in screen and use the
Mac hotkey to return. Finally reboot the PC with automatic startup enabled and
try control before signing in. Confirm Stop stays stopped, including with
automatic startup checked.

After signing in again, use **Open diagnostics** in the tray. Send the status
from `status.json` and the relevant portion of `service.log` from
`C:\ProgramData\BTRemote`. Logs include discovery results, HRESULTs, the service
identity, and session transitions. They do not record keys, mouse movement,
clipboard contents, or passwords. Logs rotate at 2 MiB with one retained file.
Do not re-pair just to hide a service-account failure; report its HRESULT first.

If recovery fails in service context, stop here and report the output. The
working interactive PowerShell discovery script is still available in the repo;
native GATT recovery will be evaluated next if this service-context spike fails.

## Remove or update

Quit the tray before rerunning Install.cmd to update. Existing startup settings,
device selection and running/stopped state are preserved. Uninstall.cmd stops
and unregisters the service and removes its Start menu shortcut; pairing,
configuration, logs and installed files are retained.

## Build

Use .NET 10 SDK. Cross-build from macOS:

```sh
dotnet build windows/BTRemote.Companion.sln -c Release
dotnet test windows/BTRemote.Companion.Tests -c Release
./windows/publish.sh win-x64
```

Use `win-arm64` for an ARM Windows PC. `BTREMOTE_DOTNET` can point at an isolated
SDK. ZIPs are written to `.build/windows/`. Core tests run on macOS; service,
WinRT and tray execution must be verified on Windows.

References: [Microsoft GATT connection behavior](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/gatt-client),
[service isolation](https://learn.microsoft.com/en-us/windows/win32/services/interactive-services),
and [service access rights](https://learn.microsoft.com/en-us/windows/win32/services/service-security-and-access-rights).
