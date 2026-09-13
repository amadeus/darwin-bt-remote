# BTRemote → Synergy-style KVM: plan

Goal: keep the Mac as a Bluetooth LE HID keyboard/mouse for the Windows PC, but
make it behave like Across / Deskflow / Universal Control: push the Mac cursor
past a chosen display edge to control the PC, push the PC cursor against a
chosen edge to come back, share the clipboard. A small Windows companion app
handles the PC side (edge hits, cursor placement, clipboard, config).

Approach, in one paragraph: reuse the existing app's Bluetooth architecture as
it is; it already pairs, presents the Mac as a keyboard and mouse, and forwards
input. Remove what is not needed (Classic mode, the iOS target, the sandbox).
Add the interactions that are missing: pushing the cursor past a chosen Mac
edge switches to the PC, and a customizable hotkey toggles between machines.
Then add a small Windows companion, which is what makes the return trip by edge
possible (the Mac cannot see where the PC cursor is), places the PC cursor at
the matching spot on entry, and carries the clipboard.

**Implementation boundary.** Amadeus has tested the existing remote control
and found it works well. Preserve that working behavior. The first edge-switch
checkpoint adds Mac edge activation and a local return hotkey around the existing
capture and HID forwarding path. Do not proactively rewrite notification queues,
merge movement, change key mappings, tune scrolling, widen reports, or alter the
HID descriptor. Make only the ownership, tap-lifecycle and cursor changes needed
for those interactions. Changes to core input/Bluetooth behavior must address a
problem reproduced at a manual checkpoint, or a later explicitly requested
capability; document that reason and keep the change narrow. Source observations
below are not a backlog of fixes to implement automatically.

Everything below is based on reading the code plus a research pass whose briefs
are summarised in "Facts the design rests on". Items marked **unverified** need
the spike named next to them before anything is built on top of them.

---

## 0. How this project is run

**Working model.** The implementing agent does the work end to end: reads,
edits, builds, lints, tests, stages and commits on the `big-hacks` branch in
this worktree. Amadeus does not type code; he tests at the points marked
**manual checkpoint** below and answers nothing else unless a checkpoint fails.
No pull requests, no pushes unless asked.

**Commits.** One commit per task bullet (or smaller), short lowercase
imperative subject in the style of the existing history (`delete classic
backend`, `add companion service`), body only when the why is not obvious.
Commit only when the build is green; commit after each M0 step separately so
regressions bisect.

**Commands** (run from the worktree root; prefix every `xcodebuild` with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` until
`xcode-select` is switched):

```
xcodegen generate                                             # after any project.yml change
swiftformat --lint . && swiftlint lint --strict               # must be clean before commit
xcodebuild -project BTRemote.xcodeproj -scheme BTRemote -configuration Debug \
  -destination "platform=macOS" -derivedDataPath .build/DerivedData build
xcodebuild ... test                                           # once BTRemoteTests exists (M0)
open .build/DerivedData/Build/Products/Debug/BTRemote.app     # for manual checkpoints
```

**Signing.** Set `DEVELOPMENT_TEAM: UHD99KF9X7` and `CODE_SIGN_STYLE:
Automatic` in `project.yml` (identity "Apple Development: Amadeus Demarzi" is
already in the login keychain). Do **not** pass `CODE_SIGNING_ALLOWED=NO` for
builds that will be run: an ad-hoc signature changes every build and macOS
revokes the Accessibility grant each time.

**Rules the agent follows without asking.** §3.5 invariants; §3.3 is the only
source of protocol values; `HIDProfile.reportMapData` and the HID
characteristics remain unchanged unless checkpoint evidence or an explicitly
requested capability requires a scoped change; strings via `L10n` + `Localizable.xcstrings`
(manual/translated entries, new namespaces in new files, never `L10n.swift`);
settings keys in `AppSettings` as `"BTRemote.camelCase"`; Swift 6 strict
concurrency (`@MainActor` classes, `nonisolated static` C callbacks, no
main-actor hop on the tap hot path); lowercase comments, no `// MARK:`; unit
tests for anything pure (protocol framing against `docs/protocol-vectors.json`,
edge geometry, key map). When a spike or checkpoint contradicts this document,
update the document in the same commit.

**Tunables.** These numbers are placeholders to tune by feel in M2/M3, not
researched values: `pushCounts` 12, `switchDelayMs` 250, `doubleTapMs` 0 (off),
`cornerPx` 0 (off), heartbeat 3 s with 3 misses,
parking point = center of the configured display. Keep them in
`AppSettings` defaults so tuning is a one-line change.

---

## 1. What the app is today (verified by reading the code)

| Piece                     | Where                                                       | What matters for us                                                                                                                                                                                                                                                                                                                     |
| ------------------------- | ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BLE HID peripheral        | `BTRemote/LowEnergy/HIDPeripheral.swift`                    | Builds Battery → Device Info → HID services in `didAdd` chain, then advertises only the HID UUID. Report IDs: 1 mouse (buttons, int8 X/Y/wheel), 2 keyboard, 3 LEDs, 4 battery, 5 system, 6 consumer.                                                                                                                                   |
| Report map                | `BTRemote/LowEnergy/HIDProfile.swift`                       | 239 of 512 allowed bytes. Any change forces Windows users to unpair/re-pair.                                                                                                                                                                                                                                                            |
| Notification backpressure | `HIDPeripheral.updateValue` / `pendingBroadcast`            | One global latest-wins slot. A queued keyboard report can be overwritten by a mouse report, and mouse deltas are dropped (not summed) when the queue is full. Wrong for a byte stream.                                                                                                                                                  |
| Service Changed hack      | `HIDPeripheral.scheduleServiceChanged`                      | Adds/removes a throwaway service so a host with a stale GATT cache re-discovers. The code base already relies on bluetoothd emitting Service Changed.                                                                                                                                                                                   |
| Direct input              | `BTRemote/DirectInputController.swift` (macOS half)         | Active `CGEventTap` at session level swallowing all input, `NSCursor.hide()`, `CGAssociateMouseAndMouseCursorPosition(false)`, any Ctrl+Alt event releases (to be replaced, §3.2). Needs Accessibility. Owned by `ContentView` as a `@StateObject`; `SetupView.onDisappear` stops it. Shows its own red `NSStatusItem` while capturing. |
| Input mapping gaps        | `DirectInputController` key table                           | No left/right modifier distinction, KeypadEnter mapped to Return (0x4C → 0x28, should be 0x58), no nav cluster / keypad / F13-F20, no media keys, scroll clamps per event, no horizontal scroll (needs a report-map field).                                                                                                             |
| HID facade                | `BTRemote/HIDInput.swift`                                   | Value snapshot rebuilt on every `App` body evaluation. `isConnected` is true for _any_ connected central, not specifically the PC.                                                                                                                                                                                                      |
| App shell                 | `BTRemoteApp.swift`, `ContentView.swift`, `SetupView.swift` | One `WindowGroup`; backends start from the window's `.onAppear`; iOS and macOS share views behind `#if os(...)`.                                                                                                                                                                                                                        |
| Classic (HIDP) backend    | `BTRemote/Classic/`                                         | Cannot reach Windows at all (README, and confirmed in code: outbound only). To be deleted in M0.                                                                                                                                                                                                                                        |
| Build                     | `project.yml` (xcodegen), `build.sh`                        | Swift 6 strict concurrency, swiftformat + `swiftlint --strict`. Baseline (2026-09-13): unsigned Debug macOS build succeeds; lint fails only on `L10n.swift` being 607 lines (limit 600). No tests.                                                                                                                                      |

---

## 2. Facts the design rests on

### Verified (primary docs and, where marked, real-world reports)

1. **Windows can talk to a custom GATT service next to HID.** Windows enumerates
   each primary GATT service of a bonded LE device as its own device node; only
   the HID service (0x1812) returns `AccessDenied` to apps. An unpackaged .NET 8
   (`net8.0-windows10.0.19041.0`) or C++/WinRT app can find the already-paired
   Mac (`BluetoothLEDevice.GetDeviceSelectorFromPairingState(true)` →
   `FromIdAsync`), open the custom service, subscribe to notifications and
   write, with no manifest capability or consent prompt. Pairing itself must be
   done in Windows Settings (`PairAsync` is unsupported in desktop apps).
2. **Windows caches the GATT table of bonded devices**; the cache is invalidated
   only by a Service Changed indication or by unpairing.
   `BluetoothLEDevice.GattServicesChanged` fires on the companion side.
3. **Absolute-pointer HID is a dead end as the primary design.** Windows maps
   absolute mice to the primary monitor only (mouhid never sets
   `MOUSE_VIRTUAL_DESKTOP`; KB5003637 re-broke multi-head in 2021;
   PiKVM/NanoKVM/JetKVM/deskhop all fall back to relative). Across also confirms
   drag-back without a client only works in its absolute modes with manually
   entered resolution. Keep relative HID; optional single-monitor fallback
   later.
4. **Raw Input keeps delivering relative deltas while the Windows cursor is
   clamped at an edge**, unaffected by pointer speed (`MOUSE_MOVE_RELATIVE`
   only). Microsoft's DirectXTK, Chromium pointer lock and SDL rely on it.
   `WH_MOUSE_LL` coordinates are clamped-ish and unreliable as a push signal;
   Microsoft itself says prefer Raw Input.
5. **Blind states on Windows are real.** A medium-integrity companion gets no
   hook/raw-input while an elevated window is foreground (UIPI), and nothing on
   the secure desktop (UAC prompt, lock screen). `GetCursorPos`/`SetCursorPos`
   need the thread on the input desktop. BLE HID input itself still works there,
   so the Mac must keep two ways back that do not involve the companion: the
   automatic releases in §3.2 and an optional user-mapped toggle hotkey.
6. **Deskflow never detects edges on the controlled machine**: the server
   dead-reckons the remote cursor from the deltas it sends and places it with
   absolute coordinates. That model does not transfer to relative BLE HID with
   Windows pointer ballistics. Hence the companion owns edge detection on the
   PC.
7. **CoreBluetooth notification limits**: values are truncated to
   `CBCentral.maximumUpdateValueLength`; `updateValue` returns false when the
   queue is full and `peripheralManagerIsReady` is the only resume signal.
   Windows 11 requests ATT MTU 527; the negotiated value must be logged, expect
   20–512 bytes per notification and roughly 5–25 kB/s shared with HID traffic.
8. **LAN option, if ever needed**: on macOS 15+ _listening_ for inbound TCP
   needs no Local Network prompt (Bonjour and outgoing local connections do).
   With the App Sandbox dropped (M0) no entitlement is needed; if the sandbox
   were kept, only `com.apple.security.network.server` when the Mac listens and
   Windows connects out. TLS-PSK is not usable (Apple: TLS 1.2 only; .NET:
   none), so pin a self-signed cert instead.
9. **Prior-art UX to match** (Deskflow `Server::isSwitchOkay`, Across, Mouse
   Without Borders): 1-px jump zone, optional switch delay (250 ms), optional
   double tap, corner exclusion (mask + size), lock-to-screen toggle,
   jump/return hotkeys, entry point = proportional position along the shared
   edge (`mapToFraction`), inset 1–3 px so it does not immediately re-trigger,
   release all keys on leave, clipboard pushed on switch when dirty and
   immediately when the remote side is active, size cap.

### Unverified and load-bearing (spike before building on them)

- **U1 Hiding/freezing the Mac cursor while the app is _not_ frontmost.** Apple
  documents `CGDisplayHideCursor` and `CGAssociateMouseAndMouseCursorPosition`
  as foreground-only. Deskflow/Barrier solve it with the private
  `CGSSetConnectionProperty("SetsCursorInBackground")` before
  `CGDisplayHideCursor`. This is a personal build, so that trick is on the
  table and is the first thing to test; Apple DTS notes it is blocked while the
  Dock would own the cursor, and nobody has confirmed it on macOS 26. Public
  fallbacks suggested by DTS: a non-activating panel at `.screenSaver` window
  level plus `NSCursor.hide()` on a timer, or parking the cursor with
  `CGWarpMouseCursorPosition` on every swallowed event. Today the toggle is
  flipped inside the app window, so the app _is_ frontmost when capture starts;
  with edge switching it will not be.
- **U2 `kCGMouseEventDeltaX/Y` keep flowing while the cursor is pinned at an
  outer display edge** with association on. Inferred from the field semantics
  and Deskflow; not stated by Apple.
- **U3 bluetoothd sends Service Changed when an app adds a service, and Windows
  then discovers the new service without a re-pair.** Strongly implied by
  Apple's Accessory Design Guidelines and by the existing hack, but not traced.
  Fallback is a one-time re-pair.
- **U4 Report-map changes require a Windows re-pair.** Universal
  firmware-community practice, no Microsoft statement.
- **U5 `SetCursorPos` from a medium-integrity process while an elevated window
  is foreground.** `SendInput` is documented as UIPI-blocked; `SetCursorPos` is
  not documented either way.
- **U6 Exact `RIDI_DEVICENAME` string** for the Mac's HOGP mouse on Windows
  (expected to contain `{00001812-…}` and `VID&01ffff_PID&0001` from the PnP ID
  in `HIDProfile.pnpIDValue`).

---

## 3. Target architecture

### 3.1 Components

**Mac (existing app, macOS-only after M0)**

- `EdgeSwitchCoordinator` (`@MainActor final class … ObservableObject`, owned by
  `BTRemoteApp` as a `@StateObject`): the single source of truth for who has
  control. States: `local` (tap passes through), `remote` (tap swallows and
  forwards HID), `returning`. "Switch to remote" is what the Direct Input
  toggle does today; the edge trigger and the hotkey are new ways to invoke it,
  and the companion is only *told* about it. Each handoff gets a `switchId`
  (u8, incrementing); ACK/LEAVE carrying another id are ignored. Owns
  `InputTap`, `EdgeGeometry`, `CursorConcealer`, drives `DirectInputController`, talks
  to the companion link, runs the clipboard watcher.
- `InputTap`: **one** always-installed active session tap (`.defaultTap`, mask
  = the existing keyboard, mouse and scroll events), running on its own thread
  with its own `CFRunLoop` (Deskflow's model). While `local` the callback does
  the edge check inline and returns the event untouched; while `remote` it
  returns `nil`. The mode is one atomic flag flipped inside the callback, so no
  event can leak in the handoff, and the toggle hotkey is matched in the same
  place in both modes. The callback never hops to the main actor; it reads an
  immutable geometry snapshot and posts state changes out. (This replaces the
  earlier listen-only + active two-tap idea, which had a race window between
  the two taps.)
- `EdgeGeometry`: CG global space (`CGGetActiveDisplayList`,
  `CGDisplayBounds`); chosen display persisted as
  `CGDisplayCreateUUIDFromDisplayID` string; outer-edge segments recomputed on
  `CGDisplayRegisterReconfigurationCallback` and published to the tap as a new
  snapshot. Trigger = cursor on the last pixel column/row of the chosen edge
  **and** outward delta, then the gates from §2.9.
- `CursorConcealer`: hides the cursor **and guarantees it cannot hover
  anything** while remote. Fixed sequence on switch-out: (1) warp the cursor to
  a parking point (center of the configured display, away from Dock and menu
  bar); (2) order in a 1×1 non-activating `NSPanel` at `.screenSaver` level at
  that point, so the cursor is technically over our window and everything else
  gets one `mouseExited` and nothing more (Deskflow's Windows-side "hider
  window"); (3) freeze with `CGAssociateMouseAndMouseCursorPosition(false)` so
  the position never changes and no tracking-area, cursor-rect or hover logic
  anywhere can fire; (4) hide via the strategy chosen in S1: Deskflow's
  `CGSSetConnectionProperty("SetsCursorInBackground")` + `CGDisplayHideCursor`
  (private API, fine here) or `NSCursor.hide` with a re-hide timer; (5)
  belt-and-braces: on every swallowed motion event re-warp to the parking point
  with warp-delta compensation, so even if the freeze silently fails in the
  background the cursor snaps back before anything can react. Reverse order on
  switch-in.
- `DirectInputController` (existing): preserve its input translation and HID
  report generation. Adapt tap ownership/lifecycle only as needed for the single
  tap and coordinator; a separate `HIDForwarder` extraction is not required.
  Replace the hardcoded Ctrl+Alt release with the configurable toggle hotkey,
  and move its status indication into the app's menu-bar UI. Keep existing key
  mappings, modifier encoding, mouse clamping and scroll behavior for M2. The
  coordinator handles permission checks and the Secure Input release. The hotkey
  is checked locally in the same tap in both modes.
- `CompanionService` (`BTRemote/LowEnergy/CompanionService.swift`): one custom
  128-bit primary service added in `HIDPeripheral`'s `didAdd` for
  `HIDProfile.hidService`, **before** `startAdvertisingNow()`, never removed at
  runtime, never advertised. Characteristics, all encryption-required so the
  existing HID bond covers them: `ctrl` notify (Mac→PC, single-chunk hot path),
  `ctrlW` write-without-response (PC→Mac hot path), `bulk` notify and `bulkW`
  write (clipboard/config chunks), `status` read.
- `CompanionLink` (M3 onward): framing, reassembly, per-stream FIFO,
  HELLO/PING state, and the message types below. Add queueing for the new
  companion traffic, with ctrl ahead of bulk, while preserving existing HID
  report behavior. Integrate notification readiness narrowly: drain eligible
  companion chunks until empty or `updateValue` returns `false`, then resume
  from `peripheralManagerIsReady`. Test simultaneous HID and companion traffic
  at M3/M4. A HID queue rewrite or movement-merging policy is not part of M2;
  change the existing send path only if a reproduced issue requires it.
- `ClipboardWatcher`: polls `NSPasteboard.general.changeCount` (0.5 s while
  remote is active, 1–2 s otherwise), records its own writes' changeCount for
  echo suppression, skips `org.nspasteboard.TransientType` / `ConcealedType`
  items.
- App shell: a status-bar agent with no Dock icon. `LSUIElement = true` in
  `Info.plist` (never `LSBackgroundOnly`, which breaks active event taps on
  macOS 15+), a `MenuBarExtra` whose icon shows local/remote/blind and whose
  menu opens the `Settings` scene (both macOS 13+), optional
  `SMAppService.mainApp.register()` behind an explicit toggle. New
  `LayoutSettingsView` pane.

**Windows companion (`windows/` in the same repo, C# .NET 8, WinForms tray,
unpackaged)**

- `BTRemote.Companion.Core` (UI-free): `GattLink` (device picker from paired
  set, `GattSession`, characteristics, reconnect state machine driven by
  `ConnectionStatusChanged`/`SessionStatusChanged`/`PBT_APMRESUMEAUTOMATIC`,
  CCCD re-write after every reconnect, `GattServicesChanged` handler),
  `Protocol` (same framing as the Mac), `EdgeMonitor` (Raw Input on a
  message-only window, `RIDEV_INPUTSINK | RIDEV_DEVNOTIFY`, filter to the Mac's
  device, `GetCursorPos` pinned test, push accumulator, corner/button/ClipCursor
  gates, `EnumDisplayMonitors` topology, blind-state detection via input-desktop
  name and `SetWinEventHook(EVENT_SYSTEM_FOREGROUND)` + token integrity level),
  `CursorPlacer` (`OpenInputDesktop`/`SetThreadDesktop` then `SetCursorPos`,
  verify with `GetCursorPos`, `SendInput(MOUSEEVENTF_VIRTUALDESK)` fallback),
  `ClipboardWatcher` (`AddClipboardFormatListener`, `GetClipboardSequenceNumber`
  echo suppression, Win32 clipboard with retry, honours
  `ExcludeClipboardContentFromMonitorProcessing`, sets
  `CanUploadToCloudClipboard=0`), `Settings` (JSON in `%LOCALAPPDATA%`),
  `StartupRegistration` (HKCU Run key).
- `BTRemote.Companion.App`: `[STAThread]` single-instance `ApplicationContext`
  with `NotifyIcon`, `SettingsForm` (device picker, monitor/edge picker,
  thresholds, clipboard on/off, start at login),
  `ApplicationHighDpiMode=PerMonitorV2`, `asInvoker`. Published self-contained
  single-file (compressed, not trimmed; ~30 MB). Simplest is to build it on the
  PC itself with the .NET SDK; a GitHub Actions publish job is optional.
  Unsigned, so click through SmartScreen once.

### 3.2 Control flow

```
Mac local: tap passes events through; edge check inline
  cursor reaches configured edge + gates pass, in the tap callback:
    → precondition (existing state): the target central is subscribed to HID;
      otherwise nothing happens and the edge is inert
    → that event is swallowed, mode := remote, switchId += 1                (suppression starts here)
    → CursorConcealer parks, freezes, hides
    → first HID reports: keyboard and mouse all-up; normal handoffs only commit
      once physical keys, modifiers and mouse buttons are released
    → from now on every event is swallowed and forwarded to the PC as HID immediately
    → if a companion is present: send ENTER{switchId, edge, frac}, fire and forget
  ENTER_ACK{switchId, ok, x, y, blind}, if it ever arrives: companion did SetCursorPos;
    Mac only updates the blind indicator. Nothing waits on it.
Mac remote: companion sees the Mac's raw deltas pushing into the configured PC edge, gates pass
    → LEAVE{switchId, edge, frac}; Mac ignores it if switchId is stale or physical
      input is held; when blocked, a fresh edge request after release is required
    → Mac: mode := returning; all-keys-up + all-buttons-up reports; warp to mapped point 2 px inside
      the edge; associate(true); drop the next delta; un-conceal; mode := local (tap passes through)
Companion heartbeat STATE{blind, desktop, macMousePresent} every 3 s; menu bar shows blind state
```

**Handoff rules.**

- *Suppression begins when the handoff commits.* An eligible outward motion
  event is swallowed by the callback that commits the edge switch. If input is
  still held, control remains on the current machine and events keep their
  existing routing until released. The final release must reach that machine
  before the handoff commits; never swallow that release to trigger a switch.
- *Nothing waits on the companion.* The switch itself is the existing Direct
  Input behaviour and depends only on state `HIDPeripheral` already tracks
  (`subscribedCentrals`, notification readiness). ENTER is sent alongside if a
  companion is connected; its ACK only places the PC cursor and reports blind
  state. Motion sent before the ACK moves the PC cursor from wherever it was,
  then `SetCursorPos` places it once and deltas continue from there. A blind or
  absent companion therefore never blocks going to the PC (a UAC prompt or lock
  screen is exactly when you want to type there), and the return guarantees
  (§3.5) do not depend on it. A late ACK for an old `switchId` is ignored.
- *Release before switching.* Track physically held keys, modifiers and mouse
  buttons in the Mac tap in both modes, including keys with no HID mapping.
  Seed/check the held state when enabling capture so keys pressed before the
  watcher started are not missed. Caps/Num Lock's latched state is not a held
  modifier. Normal edge, hotkey and manual handoffs wait for all physical input
  to be released. While waiting, key-up, modifier changes, button-up and
  autorepeat continue to the current machine through the existing input path.
  Commit only after the final release has passed through locally or has been
  handed to the existing HID send path remotely. No synthetic key reconciliation
  or HID queue rewrite is required for this gate; verify release behavior at M2.
- *Pending requests.* A Mac edge request remains eligible only while the cursor
  stays at the configured edge and its gates remain valid; moving away cancels
  it. For PC edge-return, ignore LEAVE while physical input is held and require
  a fresh edge request afterward, rather than acting on a stale PC position.
  A hotkey/manual request latches one switch and commits after release without
  requiring an edge. Consume the toggle key's down, repeats and matching up
  locally; continue routing modifier releases to the current machine. Holding
  the shortcut must never toggle repeatedly. Clear pending requests on return,
  link loss, or configuration changes that invalidate them.
- *Automatic releases bypass the held-input gate.* Link loss, tap disable,
  Secure Input and normal quit still restore the Mac without waiting for key-up
  events that may no longer arrive. All-up reports remain best-effort on these
  failure paths. Hotkey return waits only for the user's physical releases,
  never for a PC or companion response.

**Return paths.** Edge detection on the PC is the normal path. The toggle
hotkey is the escape hatch when something on the PC prevents edge-return
(for example, a UAC prompt, lock screen, or an unavailable companion).

1. Companion `LEAVE` (normal path).
2. **Toggle hotkey**: one combination that focuses the other machine.
   In `local` it hands control to the PC (ENTER with the PC's remembered exit
   position, or its current position when there is none); in `remote` it hands
   control back and warps the Mac cursor to where it was when control left,
   not to an edge (Deskflow's jump-cursor-pos behaviour). Fully user-mapped in
   Layout settings (any key with any modifiers, or disabled). Default:
   Fn/Globe + Escape, because the Fn key has no HID usage and is never
   forwarded, so the default cannot collide with a Windows shortcut. Matched
   locally on the Mac on `keyDown` of the full combination, before HID
   forwarding. Latch the request on key-down and switch after the shortcut
   and other held input are released; returning never needs a response from
   the PC or companion.
3. Automatic release: BLE link to the PC drops or the PC unsubscribes; an
   established companion heartbeat is missed 3 times (9 s) *and* the user is
   still moving the mouse; the active tap is disabled by the system; display
   configuration changes remove the configured edge; or the app quits
   normally. Each path restores local input and best-effort sends all-keys-up
   and all-buttons-up reports. No companion heartbeat is expected in M2 or
   when no companion session has been established.

Entry-point mapping both directions = Deskflow's:
`t = (pos - edgeStart + 0.5) / edgeLength` on the departing edge, mapped through
the configured span onto the arriving edge, inset 1–3 px.

### 3.3 Wire protocol (BLE-first; the same messages ride TCP later with a length prefix)

**Source of truth.** `BTRemote/Companion/CompanionProtocol.swift` (pure Swift,
no AppKit, unit-tested) defines every constant, enum and encoder below.
`windows/BTRemote.Companion.Core/Protocol.cs` mirrors it by hand. Both test
suites decode the same golden vectors in `docs/protocol-vectors.json`
(hex-encoded frames with their decoded meaning); a change to one side that
breaks the vectors fails the other side's tests. All integers little-endian.
Protocol version `1`; either side rejects a HELLO with a different major.

**GATT identifiers.** Base UUID `d5dfc674-fd35-4b5c-8fc9-39dd1c43cb1d`; the
third and fourth hex digits of the first group carry a short id, Nordic-UART
style, so `d5df0001-…` is the service and `d5df000N-…` the characteristics.

| Short id | Role                                          | Properties                                  |
| -------- | --------------------------------------------- | ------------------------------------------- |
| `0001`   | Companion service (primary, never advertised) |                                             |
| `0002`   | `ctrl` Mac→PC, single-chunk hot path          | notify, encryption required                 |
| `0003`   | `ctrlW` PC→Mac, single-chunk hot path         | write without response, encryption required |
| `0004`   | `bulk` Mac→PC, chunked streams                | notify, encryption required                 |
| `0005`   | `bulkW` PC→Mac, chunked streams               | write (with response), encryption required  |
| `0006`   | `status` snapshot for debugging               | read, encryption required                   |

**Chunk framing** (one notification or write; `chunkSize = min(maximumUpdateValueLength, MaxPduSize−3, 244)`, floor 20):

```
byte 0   seq      u8, independent per characteristic and direction, wraps at 255
byte 1   flags    bit0 FIRST, bit1 LAST, bit2 ACK_REQ (reserved, never set in v1), bits4–7 stream
                  stream 0 = ctrl (always FIRST|LAST, fixed binary, ≤ 13 payload bytes)
                  stream 1 = meta (JSON: HELLO, SCREEN_INFO, CONFIG)
                  stream 2 = clip
                  stream 3 = file (v2)
FIRST:   byte 2   msgType u8; bytes 3–6 total payload length u32   (7-byte header → 13 payload bytes at chunk 20)
payload
LAST of a multi-chunk message: CRC-32C (Castagnoli) of the reassembled payload, u32
```

Bootstrap: until both HELLOs have been exchanged every chunk is 20 bytes (the
floor), which is why HELLO rides the meta stream as a multi-chunk message.
After HELLO each side uses `min(own chunk, peer chunk)`.

**Message types and fixed-binary payloads** (ctrl stream unless noted):

| Type   | Name        | Direction | Payload                                                                                  |
| ------ | ----------- | --------- | ---------------------------------------------------------------------------------------- |
| `0x01` | HELLO       | both      | meta stream, JSON, see below                                                             |
| `0x02` | PING        | both      | `ms u32` sender monotonic clock                                                          |
| `0x03` | PONG        | both      | `ms u32` echoed                                                                          |
| `0x04` | SCREEN_INFO | PC→Mac    | meta stream, JSON                                                                        |
| `0x05` | CONFIG      | Mac→PC    | meta stream, JSON                                                                        |
| `0x11` | ENTER       | Mac→PC    | `switchId u8, edge u8, frac u16`                                                         |
| `0x12` | ENTER_ACK   | PC→Mac    | `switchId u8, ok u8, x i16, y i16, blind u8` (x,y = physical px where the cursor landed) |
| `0x13` | LEAVE       | PC→Mac    | `switchId u8, edge u8, frac u16` (id of the ENTER being returned from)                   |
| `0x14` | STATE       | PC→Mac    | `blind u8, desktop u8, macMousePresent u8` every 3 s                                     |
| `0x20` | CLIP_GRAB   | both      | `seq u32, formats u16, bytes u32` (announce: my clipboard changed)                       |
| `0x21` | CLIP_GET    | both      | `seq u32, formats u16` (send me that clipboard in these formats)                         |
| `0x22` | CLIP_DATA   | both      | clip stream: `seq u32, format u16` then raw bytes                                        |
| `0x7E` | ACK         | both      | `stream u8, seq u8` (only in reply to ACK_REQ; unused in v1)                             |
| `0x7F` | NACK        | both      | `stream u8, expectedSeq u8` (drop partial, resend from FIRST)                            |

**Enumerations and scales.**

| Field     | Values                                                                                                                                                              |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `edge`    | `0` left, `1` right, `2` top, `3` bottom. v1 has exactly one link, so the edge identifies the side; the monitor comes from CONFIG.                                  |
| `frac`    | `0…65535` = position along the edge as a fraction: from the top for left/right edges, from the left for top/bottom. `round((pos − start + 0.5) / length × 65535)`.  |
| `ok`      | `0` failed (cursor not moved), `1` placed                                                                                                                           |
| `blind`   | `0` none, `1` secure desktop (UAC / lock / Ctrl+Alt+Del), `2` elevated window in foreground, `3` Mac mouse not present in Raw Input, `4` input desktop inaccessible |
| `desktop` | `0` Default, `1` Winlogon, `2` other                                                                                                                                |
| `formats` | bitmask: `0x0001` UTF-8 text, `0x0002` HTML, `0x0004` RTF, `0x0008` PNG, `0x0010` file list. v1 uses `0x0001` only.                                                 |
| `format`  | one bit of `formats`                                                                                                                                                |
| `stream`  | as in the flags nibble                                                                                                                                              |

**JSON shapes** (meta stream; unknown keys ignored, missing keys take the default shown).

```json
HELLO        {"v":1,"role":"mac"|"pc","name":"Mac Studio","chunk":244}
SCREEN_INFO  {"monitors":[{"id":"\\\\.\\DISPLAY1","x":0,"y":0,"w":2560,"h":1440,"dpi":96,"primary":true}]}
CONFIG       {"edge":1,"monitor":"\\\\.\\DISPLAY1","span":[0.0,1.0],"pushCounts":12,
              "switchDelayMs":250,"doubleTapMs":0,"cornerPx":0,"clipboard":true,"heartbeatS":3}
```

- Each side sends HELLO once after the PC subscribes to `ctrl` and `bulk`;
  nothing else is sent until both HELLOs are in. `chunk` is what the sender can
  receive per chunk (Mac: `maximumUpdateValueLength`; PC: `MaxPduSize − 3`,
  capped at 244); each side then uses `min(own, peer)`.
- `SCREEN_INFO` is sent after HELLO and again on `WM_DISPLAYCHANGE`. `monitor`
  in CONFIG is the `id` from SCREEN_INFO (`MONITORINFOEX.szDevice`).
- `span` is the fraction range of the PC edge that maps onto the Mac edge
  (Deskflow link interval); v1 UI exposes `[0,1]` only.
- `pushCounts` is the summed raw-input delta into the edge required before
  LEAVE fires (device counts, so independent of Windows pointer speed); `0`
  means fire on arrival.

**Flow control.** Mac→PC companion traffic: FIFO with ctrl before bulk (§3.1),
drained until empty or `updateValue` returns `false`. Preserve the existing HID
send behavior; validate coexistence at the companion checkpoints. PC→Mac: `ctrlW` chunks
are write-without-response (one chunk, fire and forget); `bulkW` chunks are
write-with-response, so ATT itself paces them and no credit scheme is needed.
Reassembly: one partial message per stream per direction; a seq gap or a FIRST
while a message is partial drops the partial and sends NACK{stream,
expectedSeq}; the sender restarts that message from FIRST.

**Which central is the PC.** In M2 (no companion yet) the target is the single
active central subscribed to the HID report characteristics; if more than one
is subscribed the user picks it in Layout settings (the existing active/inactive
toggle per device). From M3 on, a central that subscribes to `ctrl` and
completes HELLO becomes the target and enables cursor placement and
edge-return; the HID subscription alone still suffices to arm edge switching
(§3.5 rule 8). The target's identifier, not `HIDInput.isConnected`, drives
`EdgeSwitchCoordinator`. HID reports keep going to all active centrals as
today.

### 3.4 Clipboard policy

- v1: UTF-8 text only, LF on the wire, cap 64 KiB over BLE. Grab → `CLIP_GRAB`
  marks the other side dirty; data moves on the next switch, or immediately if
  the other side is currently active. Sequence numbers drop stale data. Echo
  suppression on both sides.
- v2: hybrid transport. Mac sends `LAN_OFFER{addrs, port, secret, certSha256}`
  over BLE; Mac only _listens_ (`NWListener`, add
  `com.apple.security.network.server`; no Bonjour so no Local Network prompt on
  macOS 15+); Windows only connects out (no firewall prompt); TLS 1.3 with the
  offered fingerprint pinned plus an HMAC hello. Formats: text, HTML (CF_HTML ↔
  public.html), RTF, PNG/DIB, later file lists. BLE stays the fallback for text.

### 3.5 Invariants (an implementing agent must not violate these)

1. **No hidden-cursor side effects on the Mac while remote.** The cursor is
   parked over our 1×1 panel and frozen before it is hidden; every input event
   is swallowed; motion events re-warp to the parking point. Nothing else on
   the Mac may receive an event or observe cursor movement between switch-out
   and switch-in.
2. **Returning is a local operation.** `returnLocal()` is idempotent and
   restores cursor association, balances the selected cursor-hiding strategy,
   removes the parking panel, restores the cursor position, and resumes tap
   pass-through. AppKit cleanup runs on the main actor. Sending all-keys-up /
   all-buttons-up to the PC is best-effort and never delays local restoration.
   Every return path uses this same operation.
3. **The toggle hotkey is the first check in the tap callback**, in both modes.
   It latches one toggle request before HID forwarding, consumes the toggle
   key down/repeats/up, and commits after physical input is released (§3.2).
   Modifier releases keep their existing routing. PC cursor position, desktop
   state, companion availability, and Bluetooth responses cannot prevent a
   hotkey return after the user releases the held input.
4. **The system disabling the tap is a release.** On `tapDisabledByTimeout` /
   `tapDisabledByUserInput` while remote: request `returnLocal()` and restore
   the cursor before resuming edge detection.
5. **Secure Input is a release.** Poll `IsSecureEventInputEnabled()` at 1 Hz
   while remote; if it turns on, request `returnLocal()` and show a menu-bar
   warning. With Secure Input on, keyboard events can bypass the tap and
   prevent it from receiving the hotkey.
6. **Link loss is a release.** PC central unsubscribes or disconnects, or an
   established companion heartbeat is missed three times while the user keeps
   moving the mouse → `returnLocal()`. An absent companion does not start a
   heartbeat timeout.
7. **The hotkey is the escape hatch for PC-side failures.** This design does
   not add a watchdog process, launchd recovery helper, or crash-signal recovery
   machinery. Normal app termination restores local input through
   `returnLocal()`.
8. **Never arm edge switching without a PC to receive input.** Edge detection
   is enabled only while the target central (§3.3) is subscribed to the HID
   report characteristics, so the Mac can never hand control to nothing. The
   companion is *not* required to arm (M2 works without it); it adds cursor
   placement and edge-return. Without a companion the menu bar shows "return:
   hotkey only".
9. **Preserve the working HID behavior.** The HID report map, characteristics
   and their order stay byte-identical through M2. M3 adds a separate companion
   service while retaining the existing HID tree. Descriptor, encoding, mapping
   and queue changes require a reproduced checkpoint issue or an explicitly
   requested capability; no milestone schedules them as speculative cleanup.

---

## 4. Milestones

Each milestone ends in something you can use.

### M0 — Toolchain and hygiene

Do these in order, building (and from step 2 on, committing) after each step:
toolchain → iOS removal → Classic removal → sandbox drop → lint fix → test
target → signing → CI. iOS first because it turns the Classic deletion in
`SetupView` into plain code removal.

- Install the build tools the repo expects but this Mac lacks:
  `brew install xcodegen swiftlint swiftformat xcbeautify` (the Xcode project is
  generated from `project.yml`; `build.sh` gates on swiftformat and swiftlint).
- Point the CLI at Xcode instead of the Command Line Tools:
  `sudo xcode-select -s /Applications/Xcode.app`, or prefix builds with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Fetch the two gitignored bundle resources
  `BTRemote/Resources/company_ids.json` and `service_uuids.json` (Bluetooth SIG
  company and service name tables from Nordic's bluetooth-numbers-database;
  `BluetoothNumbers.swift` uses them to label devices).
  `ci_scripts/ci_post_clone.sh` downloads them and runs `xcodegen generate`;
  already done in this worktree.
- Fix the lint gate: move a namespace out of `L10n.swift` into a new
  `L10n+Layout.swift` (new strings go there anyway).
- Delete the Classic backend: remove `BTRemote/Classic/`, `TransportMode` and
  the `classic` state object and mode switch in `BTRemoteApp.swift`, the
  Classic branch of `HIDInput.make` (one LE-only `make`), the transport
  picker / paired-devices section / Classic status rows in `SetupView.swift`,
  `GuideView`'s `.classic` case, the `HIDClassicDevice()` in the `#Preview`
  blocks of `ContentView`/`SetupView`/`SettingsView`, and the now-dead
  `L10n.TransportMode`, `L10n.Classic`, `L10n.ErrorMessage` namespaces plus
  their `Localizable.xcstrings` keys. Update the README.
- Drop the iOS target: `project.yml` → `supportedDestinations: [macOS]`,
  remove the iOS deployment target, `IPHONEOS_DEPLOYMENT_TARGET` and
  `TARGETED_DEVICE_FAMILY`; delete `TouchpadView.swift` and the iOS half of
  `DirectInputController.swift` (GameController + `PointerLockHost`); strip the
  `#if os(iOS)` branches from the 14 files that have them (`BTRemoteApp`,
  `ContentView`, `SetupView`, `SettingsView`, `HIDInput`, `KeyboardView`,
  `TrackpadPanel`, `RemoteTabView`, `GuideView`, `DeviceListView`,
  `DeviceInfoView`, `HIDCentral`, …) and then the now-pointless `#if os(macOS)`
  wrappers, keeping the macOS branch (`NavigationStack`, `.formStyle(.grouped)`);
  drop the iOS keys from `Info.plist` (`UIBackgroundModes`,
  `UISupportedInterfaceOrientations`, `UILaunchScreen`,
  `UIApplicationSceneManifest`); delete the iOS section of `build.sh`, the
  `ios` entry in the workflow matrix and release step, the `ios` fastlane lane
  and `fastlane/metadata|screenshots/ios`.
- Drop the App Sandbox: this is a personal build, so the sandbox buys nothing
  and costs entitlement and TCC friction. Set `com.apple.security.app-sandbox`
  to false (or delete `entitlements.plist` and the `--entitlements` argument in
  `build.sh`). Note UserDefaults move out of the container path, so settings
  start fresh once.
- Add `BTRemoteTests` (unit-test bundle, `test:` in the scheme) so protocol
  framing, edge geometry and key mapping get tests from day one.
- Add `.github/workflows/ci.yml` (push/PR, unsigned build + lint on
  `BTRemote/**`; dotnet build/test on `windows/**`). Leave the tag-triggered
  release workflow alone.
- Signing: `DEVELOPMENT_TEAM: UHD99KF9X7`, `CODE_SIGN_STYLE: Automatic` in
  `project.yml` (see §0), so the Accessibility grant survives rebuilds.
- **Manual checkpoint M0:** launch the app, grant Bluetooth and Accessibility
  once, confirm the existing Direct Input toggle still controls the PC exactly
  as before. Nothing new yet; this is the regression baseline.

### M1 — Spikes with pass/fail gates

| Spike         | What to build                                                                                                                                                                                                                                                                                                                                          | Pass                                                                                                                                                                                                                                                                                                                                      |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| S1 (U1)       | Tiny unsandboxed app, another app frontmost: first Deskflow's `CGSSetConnectionProperty("SetsCursorInBackground")` + `CGDisplayHideCursor` + `CGAssociate(false)`; then the public fallbacks (`NSCursor.hide()` alone, `.screenSaver` non-activating `NSPanel` + re-hide timer, warp-parking). Test over the Dock and a full-screen Space on macOS 26. | At least one strategy hides and freezes the cursor reliably; record which, it becomes the default in `CursorConcealer`. Also: confirm the local return hotkey restores the cursor and association while another app is frontmost; confirm Fn+Escape arrives in the tap as `keyDown` keycode 53 with `.maskSecondaryFn` (else pick another default). |
| S2 (U2)       | 20-line listen-only tap logging location + deltas while pushing against an outer edge.                                                                                                                                                                                                                                                                 | Deltas keep arriving while pinned. If not: trigger on arrival + switch delay only (Deskflow behaviour).                                                                                                                                                                                                                                   |
| S3 (U3, MTU)  | Add the custom service after HID in `HIDPeripheral`. On a PC that bonded _before_: does Settings/Device Manager show the new "Bluetooth LE Generic Attribute Service" node without re-pairing? .NET console app: open service, subscribe, write, log `GattSession.MaxPduSize`; Mac logs `maximumUpdateValueLength` in `didSubscribeTo`.                | Companion can subscribe and write while HID keeps working. Record whether existing bonds need a re-pair.                                                                                                                                                                                                                                  |
| S4 (U6, §2.4) | Console app with Raw Input + `GetCursorPos`, driven by the Mac's HID mouse: confirm deltas at the clamped edge, coalescing rate, `RIDI_DEVICENAME` string.                                                                                                                                                                                             | Pinned-plus-push condition is detectable; device string known.                                                                                                                                                                                                                                                                            |
| S5 (U5)       | `SetCursorPos` from the console app while Task Manager is foreground; and while locked.                                                                                                                                                                                                                                                                | Know which blind states need reporting.                                                                                                                                                                                                                                                                                                   |

S1 and S2 the agent builds and runs alone on this Mac. S3, S4 and S5 are
**manual checkpoints**: the agent writes the spike code (Swift changes and a
.NET console app), Amadeus runs them with the PC and reports what Device
Manager, the console output and the cursor did. M2 depends only on S1 and S2,
so it starts while S3–S5 wait for PC time. S3 also tells us whether adding the
service alone forces a re-pair. Do not change the HID report map just because
adding the companion service might require re-pairing.

### M2 — Mac-side edge switch out, hotkey back — first daily-usable build

M2 deliberately works with no companion installed: the edge hands control to
the PC over HID alone, the PC cursor stays wherever it was (no placement until
M3), and the way back is the toggle hotkey or an automatic release. Rule 8 in
§3.5 is written to allow this.

- `EdgeSwitchCoordinator` + `InputTap` (single always-on active tap on its own
  thread) + `EdgeGeometry` + `CursorConcealer` (parking panel + freeze + hide
  strategy from S1), owned by `BTRemoteApp`. Implement the §3.5 invariants
  here, including `returnLocal()`, the local toggle hotkey, and tap-disabled
  and Secure Input releases.
- Move `DirectInputController` ownership to the app/coordinator instead of
  `ContentView`; delete `SetupView.onDisappear { directInput.stop() }`. Keep
  its existing translation and forwarding logic. The manual Direct Input
  toggle calls the coordinator, as do edge activation and the return hotkey.
  Adapt tap ownership only as needed; remove the controller's own status item.
- Move backend start-up out of the window's `.onAppear` into `init()`/app
  delegate so it runs with no window open.
- `MenuBarExtra` (icon reflects local/remote/blind), `Settings` scene hosting
  the existing tabs plus a first `LayoutSettingsView`: pick display
  (`NSScreen.screens`, persisted by display UUID), pick edge, enable toggle,
  switch delay, return hotkey. `AppSettings` keys: `edgeSwitchEnabled`,
  `edgeDisplayUUID`, `edgeSide`, `switchDelayMs`, `switchDoubleTap`,
  `cornerSizePx`, `toggleHotkey`, `clipboardSync`.
- Switch gates: arrival + outward delta, switch delay, corner exclusion, no
  switch while any physical key, modifier or mouse button is down,
  lock-to-screen toggle. Apply the release-before-switch rules from §3.2 to
  edge, hotkey and manual handoffs; preserve the existing HID translation.
- Toggle hotkey (default Fn+Escape, user-mappable or disabled): local → remote
  starts capture; remote → local restores the Mac cursor to its remembered
  position. Plus the automatic releases from §3.2, which warp 2 px inside the
  configured edge. Every return re-associates the cursor and drops one delta.
  The old Ctrl+Alt behaviour is removed.
- Preserve existing key mapping, mouse/scroll encoding, report descriptors
  and HID notification queue. Record any actual input problems at the manual
  checkpoint and fix only those reproduced problems before retesting.
- Exit: push past edge → PC controlled, cursor hidden; toggle hotkey flips
  focus either way with the cursor where you expect; pulling the PC's Bluetooth
  or quitting the app also gives the Mac back.
- **M2 is an iteration loop, not a gate to rush through.** Expect several
  rounds of checkpoint → bug fix or tunable change → rebuild → checkpoint
  before M3 starts. Functional bugs and feel problems found here (push
  threshold, switch delay, hotkey choice, what happens at corners, how the
  cursor lands on return) are cheapest to fix now, and M3 only adds the PC-side
  half on top of this behaviour.
- **Manual checkpoint M2:** (a) push past the edge, drive the PC, confirm no
  hover/highlight changes anywhere on the Mac while you do; (b) toggle hotkey
  both ways; (c) turn the PC's Bluetooth off mid-session → Mac comes back by
  itself; (d) quit the app mid-session → cursor comes back; (e) focus a
  password field on the Mac before switching → switch is refused or released
  with the Secure Input warning; (f) hold a letter until it repeats, or hold
  Shift/Ctrl, then request a switch: input stays on the current machine until
  release, with no stuck key/modifier afterward; test both directions and
  holding the toggle shortcut to confirm it switches only once.

### M3 — Companion v1: edge return and cursor placement

- Windows reconnect: retain the selected paired BLE endpoint and initiate
  connection/service rediscovery when the Mac returns. One-shot uncached GATT
  discovery has restored HID control without re-pairing in the live M2 test;
  verify automatic recovery across normal Mac quit/relaunch and PC sleep/radio
  cycles. See docs/BLUETOOTH-RECONNECT.md.
- Mac: `CompanionService`, `CompanionLink` framing and companion send queue,
  HELLO/PING/STATE handling, `ENTER`/`ENTER_ACK`/`LEAVE`, secure-input warning.
- Mac: retain the existing HID descriptor and report encoding. If S3 shows
  the companion service requires re-pairing, remove the PC bond and pair again;
  otherwise retain it. Do not bundle unrelated HID changes into this milestone.
- Windows: `windows/` solution as in §3.1, tray app, device picker,
  `EdgeMonitor` from S4, `CursorPlacer` from S5, blind-state reporting, HKCU Run
  key, GitHub Actions publish job.
- Mac Layout pane gains the PC side: monitor list from `SCREEN_INFO`, edge
  picker, push threshold, and the pairing status of the companion.
- Exit: both directions by mouse alone; the toggle hotkey and automatic
  releases still work; menu bar shows "PC detector blind" during UAC/elevated
  apps.
- **Manual checkpoint M3:** re-pair only if needed; both directions by mouse with
  the cursor landing at the matching height; open Task Manager and a UAC prompt
  on the PC and confirm the menu bar shows blind and the toggle hotkey still
  returns; stop the Windows companion while controlling the PC and confirm
  the hotkey still returns immediately; sleep and wake the PC and confirm the
  companion reconnects.

### M4 — Clipboard v1, text over BLE

- `ClipboardWatcher` on both sides, `CLIP_GRAB`/`CLIP_GET`/bulk stream, echo
  suppression, transient/concealed skipping, 64 KiB cap, sequence numbers.
- Exit: copy on either machine, paste on the other, no ping-pong loops, secrets
  from password managers not synced.
- **Manual checkpoint M4:** copy/paste text both ways, including a 20 KB block;
  copy from a password manager and confirm it does not cross.

### M5 — Feel and polish

- Input feel: address only problems reported at checkpoints. Horizontal
  scrolling, alternate scroll accumulation, wider movement reports, added key
  mappings and media keys are candidates if requested or needed for a reproduced
  issue, not automatic changes to the working input path. Any descriptor change
  includes a focused validation and re-pair checkpoint.
- Double tap, per-edge spans (percent range like Deskflow links),
  lock-to-screen, remembered exit points on both machines (used by the toggle
  hotkey and by hotkey re-entry), wake PC display on
  enter (consumer report), toggle-key (Caps/Num) sync using the LED output
  report, first-run flow (Accessibility → pair in Windows Settings → install
  companion → pick edges), launch at login (`SMAppService`, opt-in), companion
  tray states, README rewrite.

### M6 — Later

- Clipboard v2 over the hybrid LAN channel (HTML/RTF/PNG/files).
- Optional uiAccess/elevated install of the companion for edge-return while
  elevated apps are focused.
- Optional single-monitor "no companion" fallback with an absolute-pointer
  collection (Report ID 7). Rejected for now (§6); would cost another re-pair
  and needs a game-mode toggle back to relative.

---

## 5. Concrete touch points in the existing code

| File                                                                  | Change                                                                                                                                                                                                                                                                                                                                                                                                     |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BTRemoteApp.swift`                                                   | Own `EdgeSwitchCoordinator` (which owns `InputTap`, `DirectInputController`, `CursorConcealer`) as a `@StateObject`; `MenuBarExtra` + `Settings` scenes; start backends without a window; factor the environment-injection chain into a `ViewModifier`; `LSUIElement` in `Info.plist`.                                                                                                                              |
| `ContentView.swift`                                                   | Drop the macOS `@StateObject directInput` and the connect/accessibility auto-prompts (coordinator handles them).                                                                                                                                                                                                                                                                                           |
| `SetupView.swift`                                                     | Delete `.onDisappear { directInput.stop() }`; keep manual toggle; remove the Classic transport picker, paired-devices section and status rows.                                                                                                                                                                                                                                                             |
| `DirectInputController.swift` | Preserve translation and forwarding; adapt ownership/tap lifecycle for edge activation and the local toggle hotkey; move status indication to the app. No speculative key-map, delta or scroll changes. |
| `LowEnergy/HIDPeripheral.swift` | Preserve the existing HID send path through M2. M3 adds the companion service and narrowly integrates its queue/readiness handling; validate simultaneous traffic before changing existing HID behavior. |
| `LowEnergy/HIDProfile.swift` | Add companion UUIDs in M3; retain the HID report map unless a reproduced issue or requested capability requires a change. |
| `LowEnergy/HIDReports.swift` | Preserve existing report layouts and key definitions; change only for reproduced checkpoint issues or explicitly requested capabilities. |
| `HIDInput.swift`                                                      | `isConnected` for a _specific_ central; optional `sendSystemControl`.                                                                                                                                                                                                                                                                                                                                      |
| `AppSettings.swift`, new `L10n+Layout.swift`, `Localizable.xcstrings` | Keys and strings per convention (`"BTRemote.camelCase"`, `layout.snake_case`, manual/translated entries).                                                                                                                                                                                                                                                                                                  |
| `project.yml`, `.swiftlint.yml`, `.swiftformat`, `.gitignore`         | Test target; include tests in lint; exclude `windows/`; ignore `windows/**/bin`, `obj`, `.vs`.                                                                                                                                                                                                                                                                                                             |
| New                                                                   | `EdgeSwitchCoordinator.swift`, `InputTap.swift`, `EdgeGeometry.swift`, `CursorConcealer.swift`, `LayoutSettingsView.swift`, `ClipboardWatcher.swift`, `LowEnergy/CompanionService.swift`, `CompanionLink.swift`, `Companion/CompanionProtocol.swift` (AppKit-free source of truth, §3.3), `docs/protocol-vectors.json`, `windows/…` with `Protocol.cs` mirroring it |

Conventions to respect: Swift 6 strict concurrency (`@MainActor` classes,
`nonisolated static` C callbacks hopping via `Task { @MainActor in }`),
140-column swiftformat, private helpers prefixed `_`, lowercase comments, no
`// MARK:`, strings via `L10n`.

---

## 6. Decisions

### Decided

- **Personal build only, no App Store.** Consequences applied above: private
  API (Deskflow's CGS cursor trick) is allowed, the App Sandbox goes (M0), no
  review constraints on launch-at-login or an always-on agent, and the Windows
  companion can stay unsigned.
- **Low Energy only; Classic is deleted in M0.** Classic cannot reach Windows
  at all on macOS, and HID over GATT is what every modern Bluetooth mouse uses,
  so there is nothing to lose for a Mac Studio → PC setup.
- **Reuse the tested remote-control core.** Existing remote control worked
  well in Amadeus's testing. M2 adds edge activation and the local return hotkey
  with the minimum necessary ownership/tap/cursor changes. Preserve input
  translation, notification queue behavior, report formats and the HID
  descriptor. Revisit them only for a reproduced checkpoint issue or a later
  explicitly requested capability. M3's new companion service does not itself
  justify a HID rewrite or descriptor change; re-pair only if needed.
- **Drop the iOS target (M0).** Not wanted here. Removing it deletes the
  iOS-only code, all `#if os(iOS)` / `#if os(macOS)` conditionals, and the iOS
  build/CI/fastlane paths, so every later change is simpler.
- **Status-bar agent, no Dock icon.** Both apps live as status/tray icons that
  open a settings window: `LSUIElement` + `MenuBarExtra` + `Settings` scene on
  the Mac, `NotifyIcon` + settings form on Windows. The Remote/Keyboard views
  stay reachable from the status menu.
- **Edge detection is the switching mechanism; the Ctrl+Alt chord goes.** The
  only keyboard shortcut is an optional, fully user-mappable **toggle hotkey**
  that focuses whichever machine is not focused (default Fn+Escape, can be
  disabled). The hotkey is the escape hatch when a PC-side condition prevents
  edge-return; it is handled locally and never waits on the PC. Automatic
  releases in §3.2 also restore local input on link loss and tap disable.
- **Companion in C# .NET 8 WinForms.** Fastest to build and iterate on; ~30 MB
  self-contained single-file exe is fine for personal use. Rust only if size
  ever matters.

- **M2 works without the companion.** Arming requires only a PC subscribed to
  HID, not a companion handshake; the companion adds placement and
  edge-return in M3. (Reviewer alternative, not taken: pull the minimal
  companion handshake into M2. Rejected because it makes the first usable
  build wait on the Windows side.)
- **Nothing waits on the companion.** Switching to the PC is the existing
  Direct Input behaviour, gated only on state the app already tracks; ENTER is
  fire-and-forget and its ACK only places the PC cursor. `switchId` makes late
  ACK/LEAVE harmless. (Reviewer alternative, not taken: stay local when ENTER
  is not acknowledged. Rejected because it would block going to a PC sitting
  at a UAC prompt or lock screen, and the return paths do not need the
  companion.)
- **Agent-driven.** The agent implements, builds, tests, stages and commits;
  Amadeus tests only at the manual checkpoints (§0, M0–M4, S3–S5).

Nothing else is open; the rest is engineering.

---

## 7. Risks

| Risk                                                                                   | Mitigation                                                                                                                                                                                                                                        |
| -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cursor cannot be hidden from the background on macOS 26                                | S1 first; Deskflow's CGS trick is allowed in a personal build; warp-parking is the public fallback that always works.                                                                                                                             |
| Existing Windows bond does not see the new service                                     | S3; one-time re-pair; keep the Service Changed hack as a fallback with logging.                                                                                                                                                                   |
| BLE throughput too low for clipboard                                                   | Text only in v1 with a cap; LAN hybrid in v2.                                                                                                                                                                                                     |
| Companion blind during UAC / elevated apps / lock                                      | STATE heartbeat, menu-bar indicator, toggle hotkey, optional uiAccess install later.                                                                                                                                                              |
| Two menu-bar icons / capture dying when the window closes                              | Ownership move to the App and removal of `onDisappear` stop (M2).                                                                                                                                                                                 |
| Stuck with a hidden cursor and input going to the PC                                   | Local toggle hotkey returns without a PC or companion response; system tap-disable, Secure Input and link loss also restore local input (§3.5). |
| Lint gate already red                                                                  | Fix in M0 before any PR.                                                                                                                                                                                                                          |
| Swift 6 concurrency friction with new callbacks (display reconfiguration, tap, timers) | Follow the `DirectInputController` pattern (Unmanaged refcon + MainActor hop).                                                                                                                                                                    |

## Implementation progress

- Toolchain installed; baseline unsigned macOS Debug build succeeded.
- M0: moved the existing DirectInput localization namespace out of L10n.swift
  alongside iOS removal to make the first commit pass the existing lint gate.
  SwiftLint also needs DEVELOPER_DIR set on this Mac. Disabled the formatter's
  new environment-entry migration and single-line if expansion to preserve the
  existing conventions and HID code.
- The requested stopping point is the M2 manual checkpoint; M0's manual PC
  regression check will be included there rather than interrupting implementation.

- M0: Classic removed; kept L10n.ErrorMessage because HIDCentral still uses it.

- Signing correction: the installed certificate has OU/team UHD99KF9X7;
  J972UZ26TC in its display name is not the development team. Use the actual
  certificate team and explicit Apple Development identity.

- M0 complete: macOS-only app, Classic removal, sandbox removal, localization
  lint repair, standalone unit tests, verified development signing, and macOS CI.
- M2 implementation: app-owned coordinator, single dedicated-thread tap,
  exposed-edge geometry, release-before-switch gate, local configurable toggle,
  background cursor panel, settings, and persistent menu-bar controls. The
  existing input translation, HID reports, descriptor and peripheral send path
  are preserved. Setup/verification steps are in docs/M2-CHECKPOINT.md.
- Eight focused tests and signed Debug build pass; formatter and strict lint
  pass. Both `build test` actions are needed because the unit-test target is
  standalone. S3–S5 and Windows companion implementation remain for M3.
- S1 preliminary diagnostic: the private background property resolves and
  hide/show calls return success, but disassociation alone did not keep the
  background cursor parked. The implementation therefore uses the planned
  active-tap suppression plus per-motion parking path. Live validation of that
  combined path and S2 physical edge deltas remains part of this checkpoint.
  Until pinned deltas are verified, edge detection also supports arrival plus
  dwell, as permitted by S2's fallback.
- Accessibility: TCC logs confirm the old grant belongs to the upstream signing
  identity, while this worktree uses Amadeus's development identity. The exact
  built app must be added in Accessibility before live capture can be verified.
- Handoff detail: the dwell timer commits only after the final input-release
  callback has returned, so that release is routed to the old machine. The tap
  makes the suppression decision synchronously; ordered main-queue messages
  perform AppKit cursor setup and the unchanged report translation. Normal
  returns use the local hotkey; no recovery helper process is installed.

- M2 live checkpoint: user confirmed control is working after fixing stale
  Shift/Command tracking. Modifier transitions now use the event flags instead
  of querying global key state inside the callback; two regression tests cover
  modifier release and preserving ordinary held keys (ten tests total).
  Preference loading also suppresses writes until all saved values are restored.
- Next requested behavior: proportional Windows cursor placement on edge entry,
  already specified in M3. The current relative HID reports cannot set a screen
  coordinate; the planned companion's ENTER handler supplies that placement.
- Reconnect checkpoint: normal Mac quit/relaunch loses automatic Windows HID
  reconnection. Uncached discovery from Windows restored the existing pairing's
  HID subscriptions, and the user confirmed control still worked after the
  diagnostic exited. Use scripts/Test-BTRemoteConnection.ps1 as the verified
  manual workaround; automate recovery in M3. Peripheral state restoration did
  not fix normal quit and was reverted. See docs/BLUETOOTH-RECONNECT.md.
- Mac-only reconnect follow-up: while the PC remained connected over Classic
  AVRCP, native HID subscriber arrays were empty. A targeted Mac GATT connect
  attempt reported Classic GATT unsupported and remained pending over BLE;
  startup Service Changed and short-form HID advertising did not recover it.
  Temporary probes were removed. Windows discovery remains the only verified
  recovery, although these tests do not prove all Mac-only solutions impossible.
