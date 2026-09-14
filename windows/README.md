# Windows companion: edge-return checkpoint

This M3 build adds signed-in Windows edge return and proportional cursor
placement to the existing service reconnect support. The service owns the BLE
control channel and launches a worker in the active console user's desktop.
The optional tray configures the service; closing it does not stop switching.
Clipboard sync and Winlogon desktop switching are still pending.

## Install and configure

1. Keep the existing Mac pairing and leave BTRemote running on the Mac.
2. Extract the ZIP and open **BTRemote.Companion.exe**. Approve the Windows
   administrator prompt to install or update; the companion window opens
   automatically afterward. No scripts or .NET installation are needed.
3. On first setup, select the paired Mac and click **Use selected Mac**; approve
   the configuration change. Updates retain your existing selection.
4. Run the matching new Mac build. In **Layout → Windows**, wait for **Windows
   edge return ready**. Choose the PC display there if its primary display is
   not the one next to your Mac. The PC uses the edge opposite the Mac edge.
5. Cross the Mac edge; the Windows pointer should appear at the matching
   position along its edge. Move back to that Windows edge to return to
   the Mac. Release held keys/buttons before crossing back. The Mac hotkey still
   returns immediately after its own keys are released.

The service runs as LocalSystem, including before login and after sign-out. Its
BLE worker inherits that identity in Session 0 and uses a dedicated STA message
loop for WinRT. On 2026-09-13, Amadeus confirmed recovery across a Mac app
restart using the existing pairing while Windows was signed in. On 2026-09-14,
he confirmed mouse/keyboard control at the login screen after a Windows reboot
and successfully signed in. Restarting the Mac app while Windows remains signed
out still needs testing. The worker is isolated so a stalled Bluetooth API can
be terminated by the service.

Windows may display its normal unsigned-app reputation prompt for this personal
build. The archive is built from this repository; no installer downloads or
third-party servers are used at runtime.

## Window and tray controls

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

Keep the existing pairing and open the EXE from the new ZIP to update. The
update closes the old companion automatically. Leave the service running and test:

- Cross at roughly the top, middle and bottom of the Mac edge. Placement on the
  selected Windows display should match; return should preserve that fraction.
- Reach the corresponding Windows edge to return immediately; no dwell or
  extra push is required. A shared border with
  another Windows display is not an exit; use an exposed part of the edge.
- Hold a key or mouse button while pushing back: control must stay on Windows.
  Release it, then move into the edge again. No key or button should remain stuck.
- Return to the Mac: the Windows cursor should disappear. Move or click the
  PC's own mouse: it should reappear immediately, and the first click should
  reach the app underneath. Crossing back to Windows also shows the cursor.
  Stop the service while the cursor is hidden and check that ordinary PC mouse
  use resumes. The tray window can remain closed throughout.
- Return using the Mac hotkey, then move the PC's own mouse: no delayed switch
  should occur. Quit the tray and repeat edge switching; it should still work.
- Restart the Mac app and confirm both HID and companion reconnect without
  re-pairing. If the companion drops while remote, the Mac restores local input
  after its heartbeat expires.
- While controlling Windows, press Ctrl+Alt+Delete, then close the security
  screen and return through the Windows edge. Edge return resumes on the normal
  desktop without a hotkey round trip. While the security screen is open, use
  the Mac hotkey if needed; returning locally that way must prevent a stale
  Windows edge event from switching again after the security screen closes.

The service lifecycle remains available while signed out, but this desktop worker only
runs under a signed-in console user's token. UAC/lock/Winlogon placement and
edge return are not claimed by this checkpoint. The local Mac hotkey remains
available when edge return is unavailable or an application confines the PC
cursor.

## Login handoff checkpoint

With the updated companion and Mac app, reboot Windows, cross from the Mac at
the login screen and sign in. Once **Layout → Windows** on the Mac reports
**Windows edge return ready**, move back through the Windows edge. The current
handoff should continue without a hotkey round trip or another entry, and the
cursor should stay where you left it when the desktop worker becomes ready.
Also check that using the Mac hotkey before the worker is ready prevents a late
return event after login. These continuation checks still need live validation.

Login-screen edge return itself remains pending; use **⇧⌘Escape** there. Tray
auto-launch after login is deferred to final polish; the service and desktop
worker operate without the tray open.

Use **Open diagnostics** in the tray for `status.json` and `service.log` in
`C:\ProgramData\BTRemote`. Logs include discovery results, HRESULTs, desktop
readiness, service identity and session transitions. They do not record keys,
mouse movement, clipboard contents or passwords. Logs rotate at 2 MiB with one
retained file. If status remains **Waiting for the selected Mac's HID mouse**,
report that status; do not remove the pairing as a first troubleshooting step.

## Open or update

Use **BTRemote Companion** in the Start menu, or open the downloaded EXE again.
If the tray is already running, its window reopens. An identical EXE opens the
installed app without reinstalling. A different build updates the installation,
automatically closes the previous companion, then opens the new window.
Existing startup settings, device selection and running/stopped state are
preserved. First installation starts the service with automatic startup enabled.
The UI runs with the permissions of the user who opened it; only installation
and service changes request administrator permission.

The repository retains `windows/packaging/Uninstall.cmd` for removing the
service during development; it is not part of the end-user ZIP.

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

## Desktop-launch correction (2026-09-13)

The desktop worker now starts outside the BLE worker's Session 0 job, using
explicit breakaway and the console user's token. Its retained process handle
and background pipe-disconnect monitor preserve service-owned shutdown across
sessions. This fixes a launch path that could report "Access is denied" while
Bluetooth itself stayed connected. Startup failures now keep the operation and
Win32 error in status.json rather than replacing it with "Waiting for signed-in
console desktop". No Mac update or Bluetooth re-pairing is needed for this fix.

Windows job session constraint: [AssignProcessToJobObject](https://learn.microsoft.com/en-us/windows/win32/api/jobapi2/nf-jobapi2-assignprocesstojobobject).
