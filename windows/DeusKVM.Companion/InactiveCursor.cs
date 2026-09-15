using System.Runtime.InteropServices;

namespace DeusKVM.Companion;

// A temporary, nonactivating surface under the pointer owns the invisible cursor.
// No system cursor scheme changes or shared ShowCursor counters survive this worker.
internal sealed class InactiveCursor : NativeWindow, IDisposable
{
    private readonly MouseHook mouseHook;
    private IntPtr hook;
    public bool Hidden { get; private set; }

    public InactiveCursor()
    {
        mouseHook = OnMouse;
        CreateHandle(new CreateParams
        {
            Caption = "DeusKVM inactive cursor",
            Style = unchecked((int)0x80000000), // WS_POPUP
            ExStyle = 0x08080088, // NOACTIVATE | LAYERED | TOOLWINDOW | TOPMOST
            Width = 1,
            Height = 1
        });
        // Nonzero alpha keeps the one-pixel surface hit-testable without a visible window.
        SetLayeredWindowAttributes(Handle, 0, 1, 2);
    }

    public void Hide()
    {
        if (Hidden || !DesktopNative.IsDefaultDesktop() || !DesktopNative.GetCursorPos(out var point)) return;
        // Reveal before a click is routed so the hider cannot eat the first click.
        // Raw Input supplies device-specific movement; this hook never consumes input.
        hook = SetWindowsHookEx(14, mouseHook, GetModuleHandle(null), 0); // WH_MOUSE_LL
        if (hook == IntPtr.Zero) return;
        Hidden = true;
        if (!SetWindowPos(Handle, new IntPtr(-1), point.X, point.Y, 1, 1, 0x50)) // NOACTIVATE | SHOWWINDOW
        { Reveal(); return; }
        SetCursor(IntPtr.Zero);
    }

    public void Reveal()
    {
        if (!Hidden) return;
        Hidden = false;
        if (hook != IntPtr.Zero) { UnhookWindowsHookEx(hook); hook = IntPtr.Zero; }
        SetWindowPos(Handle, IntPtr.Zero, 0, 0, 0, 0, 0x97); // HIDEWINDOW | NOACTIVATE | NOZORDER | NOMOVE | NOSIZE
        if (!DesktopNative.GetCursorPos(out var point)) return;
        // Ask the underlying app for its current cursor (I-beam, resize, etc.).
        // The fallback also restores visibility if that app cannot respond.
        SetCursor(LoadCursor(IntPtr.Zero, new IntPtr(32512))); // IDC_ARROW
        var target = WindowFromPoint(point);
        if (target != IntPtr.Zero)
            SendNotifyMessage(target, 0x20, target, new IntPtr(1)); // WM_SETCURSOR, HTCLIENT
    }

    private IntPtr OnMouse(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0 && Hidden && message.ToInt64() is 0x201 or 0x204 or 0x207 or 0x20B or 0x20A or 0x20E)
            Reveal();
        return CallNextHookEx(IntPtr.Zero, code, message, data);
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == 0x20 && Hidden) // WM_SETCURSOR
        {
            SetCursor(IntPtr.Zero);
            message.Result = new IntPtr(1);
            return;
        }
        if (message.Msg == 0x21) // WM_MOUSEACTIVATE: never take keyboard focus
        {
            message.Result = new IntPtr(3); // MA_NOACTIVATE (do not discard the click)
            return;
        }
        base.WndProc(ref message);
    }

    public void Dispose() { Reveal(); DestroyHandle(); }

    private delegate IntPtr MouseHook(int code, IntPtr message, IntPtr data);
    [DllImport("user32.dll")]
    private static extern IntPtr SetWindowsHookEx(int id, MouseHook callback, IntPtr module, uint thread);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? name);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetLayeredWindowAttributes(IntPtr window, uint color, byte alpha, uint flags);
    [DllImport("user32.dll")]
    private static extern IntPtr SetCursor(IntPtr cursor);
    [DllImport("user32.dll")]
    private static extern IntPtr LoadCursor(IntPtr instance, IntPtr name);
    [DllImport("user32.dll")]
    private static extern IntPtr WindowFromPoint(DesktopNative.Point point);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SendNotifyMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
}
