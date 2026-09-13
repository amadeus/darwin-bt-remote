# BTRemote for macOS

This personal fork keeps the existing Bluetooth LE HID remote-control backend
and adds Mac-to-PC edge switching. See [PLAN.md](PLAN.md) for milestones.
The iOS target and Bluetooth Classic backend have been removed. Pair the Mac
from Windows Bluetooth Settings and use the app's existing Direct Input mode.

The HID descriptor and BLE notification behavior are unchanged. No Windows
companion is needed for the upcoming edge-out / hotkey-back checkpoint.

## Build

Use Xcode and `xcodegen`, `swiftformat`, `swiftlint`, and `xcbeautify`.
Run `./build.sh` from this directory. Local development signing is configured
in `project.yml`.

## Upstream and license

Based on [jqssun/darwin-bt-remote](https://github.com/jqssun/darwin-bt-remote).
Licensed under [AGPL-3.0-only](LICENSE); preserve upstream license obligations.
