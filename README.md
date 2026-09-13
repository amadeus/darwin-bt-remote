# BTRemote for macOS

This personal fork adds **Mac edge → Windows control → local hotkey return** to
[jqssun/darwin-bt-remote](https://github.com/jqssun/darwin-bt-remote). It uses the
existing Bluetooth LE HID backend and report format. No Windows companion is
needed for this checkpoint; PC-side edge return and clipboard sharing come later.

## Build and try

Install Xcode and `xcodegen`, `swiftformat`, `swiftlint`, and `xcbeautify`, then run:

```sh
./build.sh
open .build/DerivedData/Build/Products/Debug/BTRemote.app
```

Allow Bluetooth and Accessibility, pair from Windows Bluetooth Settings, then
choose the Mac display/edge in **Layout** and enable edge switching. Use
**Fn + Escape**, or record another toggle shortcut, to return. Normal switches
wait for held keys and buttons to be released. The controls remain available
from the menu-bar icon after the window closes.

See [the checkpoint guide](docs/M2-CHECKPOINT.md) for setup and testing, and
[PLAN.md](PLAN.md) for the implementation scope and later milestones.

The iOS target and Bluetooth Classic backend have been removed. The BLE
peripheral, HID descriptor, and report encoding are preserved; core changes are
driven by problems found during testing.

## License

Based on the upstream BTRemote project. Licensed under
[AGPL-3.0-only](LICENSE); preserve upstream license obligations.
