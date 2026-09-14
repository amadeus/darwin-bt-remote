# Windows companion

The service owns Bluetooth recovery, switching and plain-text clipboard
coordination. It launches the desktop worker; the optional tray configures the
service. Closing the tray leaves switching and clipboard sharing running.

This build adds in-app Mac pairing, complete removal and tray startup at login.
It also supports centered hotkey/button entry with the matching Mac build.
Text clipboard sharing works in both directions, up to 64 KiB per copy.
Update both apps; keep the existing pairing unless testing removal.
Clipboard sharing pauses while locked or signed out. Login control remains
independent of the clipboard feature.

## Install and configure

1. Keep the existing Mac pairing and leave BTRemote running on the Mac.
2. Extract the ZIP and open **BTRemote.Companion.exe**. Approve the Windows
   administrator prompt to install or update; the companion window opens
   automatically afterward. No scripts or .NET installation are needed.
3. On first setup, click **Connect a Mac…**, choose your Mac and approve any
   Windows/Mac pairing prompts. Keep BTRemote enabled on the Mac; it advertises
   when no allowed PC is ready. The companion verifies BTRemote before saving.
   Allow input for this PC on the Mac if needed. Updates retain your selection;
   use **Change Mac…** to select a different Mac or reuse an existing pairing.
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
- **Show tray icon at sign-in:** open only the optional tray after users sign
  in. Enabled once on this upgrade, then preserved across updates. Independent
  of the service-startup checkbox; it does not start a stopped service.
- **Remove BTRemote from this PC…:** complete removal, including the selected
  Mac pairing, service/workers, startup entry, shortcut, settings/logs and
  installed files. Wait for the final result message. If it fails, reopen the
  downloaded EXE to retry. Other pairings and Windows execution history remain.
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

The clipboard worker runs only in the signed-in console user session and
accesses the clipboard only on the Default desktop. The local Mac hotkey
remains available when an application confines the PC cursor.

## Login handoff checkpoint

With the updated companion and Mac app, reboot Windows, cross from the Mac at
the login screen and sign in. Once **Layout → Windows** on the Mac reports
**Windows edge return ready**, move back through the Windows edge. The current
handoff should continue without a hotkey round trip or another entry, and the
cursor should stay where you left it when the desktop worker becomes ready.
Also check that using the Mac hotkey before the worker is ready prevents a late
return event after login. Amadeus confirmed login behavior works; this checklist remains useful for regressions.

The tray can now auto-launch after login; the service and desktop worker still
operate without it. Login launch does not open a settings window.

Use **Open diagnostics** in the tray for `status.json` and `service.log` in
`C:\ProgramData\BTRemote`. Logs include discovery results, HRESULTs, desktop
readiness, service identity and session transitions. They do not record keys,
mouse movement, clipboard contents or passwords. Logs rotate at 2 MiB with one
retained file. If status remains **Waiting for the selected Mac's HID mouse**,
report that status; do not remove the pairing as a first troubleshooting step.

## Text clipboard checkpoint

1. Open the EXE from the new ZIP to update Windows. Quit and reopen the newly
   built Mac app. Keep **Settings → Share text clipboard with Windows** enabled.
2. Copy text on the Mac, cross to Windows and paste. Copy different text on
   Windows, return to the Mac and paste. Repeat a few times with Unicode,
   multiple lines and a 20 KB block. Large BLE transfers can take longer.
3. Check that edge switching and typing stay responsive during the large copy.
   Paste again after several round trips: imported text should not bounce back
   and replace a newer local copy.
4. Turn sharing off in Mac Settings and confirm new copies no longer cross.
   Turn it on, make a fresh copy and repeat. Lock/unlock and reconnect, then
   repeat with fresh text; clipboard sharing must stay off on the login screen.

Only plain text crosses; no files, images or rich formatting. Known private
clipboard markers are respected, but unmarked password text is indistinguishable
from ordinary text. Test privacy with disposable text, not real credentials.
Full behavior, limits and development checks are in [docs/CLIPBOARD.md](../docs/CLIPBOARD.md).
Native clipboard behavior and BLE transfer timing still need the manual test.

## Open or update

Use **BTRemote Companion** in the Start menu, or open the downloaded EXE again.
If the tray is already running, its window reopens. An identical EXE opens the
installed app without reinstalling. A different build updates the installation,
automatically closes the previous companion, then opens the new window.
Existing startup settings, device selection and running/stopped state are
preserved. First installation starts the service with automatic startup enabled.
The UI runs with the permissions of the user who opened it; only installation
and service changes request administrator permission.

Use the **Remove BTRemote from this PC…** button/menu for removal. No separate
uninstall script is needed. It deliberately removes the selected Windows pairing;
the Mac's allow list and downloaded EXE/ZIP remain unchanged.

## New Mac controls

The configured hotkey and **Switch to PC** button center the Windows pointer on
the selected display. Edge crossings retain proportional placement. Both builds
are required; existing pairings and the HID descriptor are unchanged.

Mac Settings and its menu now share **Disable BTRemote / Enable BTRemote**.
Disabling restores local control, stops advertising/input capture/clipboard
sharing, and changes the menu icon to a pause symbol. This state survives app
restart. Enable to reconnect using the saved pairing. Mac Settings also offers
an opt-in **Launch BTRemote at login** control.

For the complete test sequence, see `docs/POLISH.md` in the repository. Test
removal last because it intentionally removes the selected Mac pairing.

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
