# Plain-text clipboard sharing

Clipboard sharing is enabled by default in **Mac Settings → Share text clipboard
with Windows**. The toggle controls both directions. Both machines need this
build; the Windows service and signed-in desktop worker handle sharing even
when the tray window is closed. Keep the existing Bluetooth pairing.

## Morning test

1. Extract `.build/windows/BTRemote-Companion-win-x64.zip` on Windows and open
   `BTRemote.Companion.exe`. Its existing update flow replaces the service and
   desktop worker and preserves settings. No separate stop/start script is needed.
2. Quit the running Mac app and reopen
   `.build/DerivedData/Build/Products/Debug/BTRemote.app` from this checkout.
3. Copy a sentence on the Mac, cross to Windows and paste into Notepad. Copy a
   different sentence in Notepad, return to the Mac and paste into a text editor.
4. Repeat with emoji, accented characters, multiple lines and approximately
   20 KB of text. Check that typing and edge return stay responsive during
   transfer. BLE transfer time needs measurement on the actual hardware.
5. Make several successive copies in both directions. A newer local copy must
   not be replaced by an older transfer, and switching back and forth without
   copying must not cause clipboard feedback loops.
6. Disable sharing and copy fresh text; it must stay local. Re-enable and copy
   again. Test reconnect and lock/unlock with new text. The clipboard must not
   synchronize on the login/security screen.
7. Using disposable test text, check a password manager that marks its clipboard
   private. Confirm that private text, images/files and text over 64 KiB do not
   replace the other machine's clipboard.

Neither app was launched/restarted during the overnight implementation, and no
system clipboard or computer-use interaction was used. Native clipboard reads,
writes, privacy markers and Bluetooth timing await these checks. Automated
unit tests do not establish live integration behavior.

## Behavior and limits

- Only plain Unicode text crosses, up to **65,536 UTF-8 bytes after newline
  normalization**. Rich copies may supply their plain-text representation;
  formatting, files and images are not transferred. File-list clipboards are
  excluded even if they also contain a text representation.
- New copies are offered to the other machine. The destination fetches them
  when it is active, or at the next handoff. The initial clipboard snapshot is
  offered only when leaving that machine, preventing connection alone from
  replacing the active machine's clipboard with old text.
- Transfers run asynchronously; switching does not wait for the clipboard.
  Polling is every 200 ms while sharing is available. A large copy may take
  time before a paste sees it. Text over the cap is skipped rather than truncated.
- Empty text is supported. Embedded NUL and malformed Unicode are rejected.
  Newlines are LF on the wire and CRLF when written to Windows.
- Imported revisions are recorded and marked so they are not echoed back. A
  fresh local clipboard change cancels a pending import. A busy clipboard write
  is retried for up to two seconds; a newer local revision takes precedence.
- Only the Mac's selected, allowed PC can exchange clipboard messages. Sharing
  pauses on Windows lock/secure desktop/logout, Mac sleep/session deactivation
  or secure input, and when the user disables it. Old-session pending payloads
  are discarded. Copy again after reconnect/unlock to establish a fresh offer.
- Known private, transient and generated clipboard markers are inspected before
  reading text. This is metadata filtering, not content classification:
  **unmarked password text cannot be distinguished from ordinary text**.
- BTRemote does not log or persist clipboard contents. Windows imports also
  opt out of cloud clipboard upload. The OS and other installed clipboard tools
  still govern their own history behavior.

## Implementation

`ClipboardTransfer.swift` and `ClipboardTransfer.cs` implement matching pure
state machines. HELLO's optional `clipboard:1` capability gates the extension;
older companions still switch normally without clipboard sharing.

The Windows service owns an epoch and advertises availability with CLIP_STATE.
The Mac acknowledges only after priming its local snapshot and checking its
sharing preference/session. Windows then primes its desktop snapshot before
handling a pending remote offer. This ordering prevents a first snapshot from
cancelling an import that started during connection setup.

All integers below are little-endian. Control messages fit one 20-byte frame.

| Message | Stream | Payload |
| --- | --- | --- |
| CLIP_GRAB (0x20) | 0 | epoch u32, copy sequence u32, byte count u32; 0xffffffff withdraws |
| CLIP_GET (0x21) | 0 | epoch u32, copy sequence u32, byte offset u32 |
| CLIP_DATA (0x22) | 1 | epoch u32, copy sequence u32, byte offset u32, 0–1024 bytes |
| CLIP_STATE (0x23) | 0 | epoch u32, availability/enabled u8 |

The receiver requests one 1 KiB block at a time; multi-frame blocks use the
existing CRC-32C framing. A missing block request retries after five seconds,
up to three times. Control traffic retains priority over bulk. No HID descriptor,
mouse/keyboard report logic, third stream or pairing change is involved.

The Windows BLE worker coordinates the transfer but does not access the
Session 0 clipboard. `DesktopClipboard` uses a dedicated STA thread within the
signed-in desktop worker, isolated from the Raw Input STA. `ClipboardPasteboard`
uses a dedicated Mac queue, isolated from the main/input run loops. Native
revision checks protect a newer local copy even if it happens before polling
notices it. Clipboard owners can delay rendering; these reads cannot stall the
input loop. The Mac pasteboard API does not provide an atomic compare-and-write,
so an external write exactly between its final revision check and replacement
remains a native API race.

Tests cover shared wire fixtures, Unicode/newline/empty payloads, block boundaries,
20 KB/64 KiB transfers, caps, corruption/malformed input, stale epochs, local-copy
cancellation, duplicate offers, retries, echo suppression, revision tracking,
privacy policy and the bounded desktop pipe envelope. They do not read either
machine's actual clipboard.

Privacy conventions: [NSPasteboard community types](https://nspasteboard.org/),
[Windows clipboard formats](https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-formats).
Native memory ownership follows
[SetClipboardData](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setclipboarddata).
