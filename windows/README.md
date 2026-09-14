# Windows companion: edge-return checkpoint

This M3 build adds signed-in Windows edge return and proportional cursor
placement to the existing service reconnect support. The service owns the BLE
control channel and launches a worker in the active console user's desktop.
The optional tray configures the service; closing it does not stop switching.
Clipboard sync and Winlogon desktop switching are still pending.

## Install and configure

1. Keep the existing Mac pairing and leave BTRemote advertising on the Mac.
2. Extract the entire ZIP on the PC. Run **Install.cmd** and approve the Windows
   administrator prompt. No .NET SDK or runtime installation is needed.
3. Open **BTRemote Companion** from the Windows Start menu. Select the paired Mac
   and click **Use selected Mac**; approve the configuration change.
4. Run the matching new Mac build. In **Layout → Windows**, wait for **Windows
   edge return ready**. Choose the PC display there if its primary display is
   not the one next to your Mac. The PC uses the edge opposite the Mac edge.
5. Cross the Mac edge; the Windows pointer should appear at the matching
   position along its edge. Push back against that Windows edge to return to
   the Mac. Release held keys/buttons before pushing back. The Mac hotkey still
   returns immediately after its own keys are released.

The service runs as LocalSystem, including before login and after sign-out. Its
BLE worker inherits that identity in Session 0 and uses a dedicated STA message
loop for WinRT. On 2026-09-13, Amadeus confirmed recovery across a Mac app
restart using the existing pairing while Windows was signed in. Recovery while
signed out and before the first login after boot remains unverified. The worker
is isolated so a stalled Bluetooth API can be terminated by the service.

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

## Signed-in edge checkpoint

Keep the existing pairing; quit the tray and run Install.cmd from this new ZIP
to update the service. Leave the service running and test:

- Cross at roughly the top, middle and bottom of the Mac edge. Placement on the
  selected Windows display should match; return should preserve that fraction.
- Push against the corresponding Windows edge to return. A shared border with
  another Windows display is not an exit; use an exposed part of the edge.
- Hold a key or mouse button while pushing back: control must stay on Windows.
  Release it, then push again. No key or button should remain stuck.
- Return using the Mac hotkey, then move the PC's own mouse: no delayed switch
  should occur. Quit the tray and repeat edge switching; it should still work.
- Restart the Mac app and confirm both HID and companion reconnect without
  re-pairing. If the companion drops while remote, the Mac restores local input
  after its heartbeat expires. A desktop change disarms the current return;
  use the hotkey and cross again after returning to the normal desktop.

Signed-out/pre-login testing is deferred at Amadeus's request. The service
lifecycle remains available while signed out, but this desktop worker only
runs under a signed-in console user's token. UAC/lock/Winlogon placement and
edge return are not claimed by this checkpoint. The local Mac hotkey remains
available when edge return is unavailable or an application confines the PC
cursor. Native Raw Input device matching and pinned-edge deltas still need
confirmation on the actual Windows machine.

Use **Open diagnostics** in the tray for `status.json` and `service.log` in
`C:\ProgramData\BTRemote`. Logs include discovery results, HRESULTs, desktop
readiness, service identity and session transitions. They do not record keys,
mouse movement, clipboard contents or passwords. Logs rotate at 2 MiB with one
retained file. If status remains **Waiting for the selected Mac's HID mouse**,
report that status; do not remove the pairing as a first troubleshooting step.

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
WinRT, desktop workers, Raw Input and tray execution must be verified on Windows.

References: [Microsoft GATT connection behavior](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/gatt-client),
[service isolation](https://learn.microsoft.com/en-us/windows/win32/services/interactive-services),
and [service access rights](https://learn.microsoft.com/en-us/windows/win32/services/service-security-and-access-rights).

Desktop worker API references: [CreateProcessAsUser](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessasuserw) and [Microsoft device instance property definitions](https://github.com/microsoft/win32metadata/blob/main/generation/WinSDK/RecompiledIdlHeaders/shared/devpkey.h).
