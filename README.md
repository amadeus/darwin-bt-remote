# DeusKVM

Use your Mac's keyboard, mouse, and trackpad to control a Windows PC over
Bluetooth. Move through a configured screen edge to switch computers, or use a
hotkey. A Windows companion service handles reconnecting, cursor placement,
edge return, and plain-text clipboard sharing, including input control at the
Windows login screen.

DeusKVM is a personal fork of
[BTRemote](https://github.com/jqssun/darwin-bt-remote). Keyboard and mouse input
use Bluetooth LE HID; the companion control and clipboard channel also uses
BLE. No LAN connection is required.

## Setup

1. Open **DeusKVM.app** on the Mac. Allow Bluetooth, then enable DeusKVM in
   **System Settings → Privacy & Security → Accessibility** and **Input
   Monitoring**. If Accessibility does not list it, add the app with **+**.
   Reopen the app after granting Input Monitoring.
2. On Windows, extract **DeusKVM-Companion-win-x64.zip** and open
   **DeusKVM.Companion.exe**. Approve the administrator prompt. The EXE installs
   or updates the service and opens its settings; no scripts or separate .NET
   installation are required.
3. For first-time pairing, leave **System Settings → Bluetooth** open on the
   Mac. Choose **Connect a Mac…** in the Windows companion and approve the
   pairing prompts. Choose your Mac's computer name. If it is missing, try
   **Show all devices**. Windows Bluetooth Settings is not needed for this flow.
4. In the Mac's **Setup** tab, turn on **Enable control** for your PC. Advertising
   stops when an allowed PC is ready and resumes when none is available.
5. In **Layout**, choose the Mac display and exit edge, enable edge switching,
   and select the Windows display. Wait for **Windows edge return ready**.
   Return through the opposite edge on Windows.

## Everyday use

- Edge crossings place the cursor at the corresponding position on the other
  display. Release held keys and mouse buttons before switching.
- **Switch to PC**, including the hotkey, centers the pointer on the selected
  Windows display. The default toggle is **Fn + Escape**; record your own in
  **Layout**. The Mac hotkey remains the way back if Windows cannot return.
- **Settings → Share text clipboard with Windows** shares plain text in both
  directions, up to **64 KiB of UTF-8** per copy. Clipboard sharing pauses while
  locked or signed out and skips recognized private clipboard markers. See
  [clipboard behavior and limits](docs/CLIPBOARD.md).
- Vertical and horizontal scrolling can be inverted independently in Settings.
- **Disable DeusKVM** in Settings or the menu bar restores local input and
  stops advertising, input capture, and clipboard exchange. Enabling reuses
  saved devices. The menu icon shows searching, connecting, ready, or disabled.
- Mac launch-at-login is optional. On Windows, **Start automatically with
  Windows** controls the service; **Show tray icon at sign-in** controls the
  settings UI separately. Closing either settings window leaves control running.

The Windows service supports control at the login screen and across sign-in.
Clipboard access remains limited to the signed-in desktop. See the
[Windows guide](windows/README.md) for service controls and diagnostics.

## Update or remove

Quit the old Mac app and open the new **DeusKVM.app**. Keep the app in a stable
location if using launch-at-login. On Windows, open the new downloaded EXE;
it updates the installation and closes the old companion automatically.
Existing Bluetooth pairings and preferences are retained.

When upgrading from BTRemote, internal bundle, preference, protocol, and Windows
service identities remain stable. Windows' Start menu and service display name
become **DeusKVM Companion**. Compatibility paths and removal behavior are
listed in the [Windows guide](windows/README.md#updating-from-btremote).

To remove the Windows installation, choose **Remove DeusKVM from this PC…**.
It removes the service, startup entries, installed files, settings/logs, and the
selected Mac's Windows pairing. Wait for the completion message, then delete
the downloaded EXE/ZIP. Other Bluetooth pairings are untouched.

## Build

The source project names remain `BTRemote` for compatibility; build products use
DeusKVM. For macOS, install Xcode (26 or later for the current UI), `xcodegen`,
`swiftformat`, `swiftlint`, and `xcbeautify`, then run:

```sh
./build.sh
open .build/DerivedData/Build/Products/Debug/DeusKVM.app
```

`project.yml` contains the development signing team; use your own signing
configuration when building on another Mac. The deployment target is macOS 13.

The Windows companion requires the .NET 10 SDK to build. It can be cross-built
on macOS:

```sh
dotnet build windows/BTRemote.Companion.sln -c Release
dotnet test windows/BTRemote.Companion.Tests -c Release
./windows/publish.sh win-x64
```

Use `win-arm64` for Windows on ARM. The ZIP is written to `.build/windows/`.
The companion targets Windows 10 version 2004 or later. Native Windows
installation and desktop behavior are checked separately from the portable
policy tests. [PLAN.md](PLAN.md) records implementation scope and validation.

## License

Based on the upstream BTRemote project. Licensed under
[AGPL-3.0-only](LICENSE); preserve upstream license obligations.
