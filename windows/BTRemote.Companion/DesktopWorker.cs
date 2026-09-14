using System.ComponentModel;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Threading.Channels;
using BTRemote.Companion.Core;
using Microsoft.Win32.SafeHandles;

namespace BTRemote.Companion;

internal sealed class DesktopWorker : ApplicationContext
{
    private readonly NamedPipeClientStream pipe;
    private readonly CancellationTokenSource shutdown = new();
    private readonly Channel<DesktopMessage> output = Channel.CreateBounded<DesktopMessage>(32);
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 1000 };
    private readonly RawWindow window;
    private readonly string address;
    private readonly int parent;
    private readonly EdgeDetector detector = new();
    private readonly HandoffSession handoff = new();
    private readonly Dictionary<IntPtr, bool> devices = [];
    private MonitorInfo[] monitors = [];
    private EdgeConfiguration? config;
    private byte blind = 4;
    private bool started;

    public DesktopWorker(string name, int parent, string address)
    {
        this.parent = parent;
        this.address = address;
        pipe = new NamedPipeClientStream(".", name, PipeDirection.InOut, PipeOptions.Asynchronous);
        window = new RawWindow(this);
        timer.Tick += (_, _) => Refresh();
        Application.Idle += Start;
    }

    private async void Start(object? sender, EventArgs args)
    {
        if (started) return;
        started = true;
        Application.Idle -= Start;
        try
        {
            await pipe.ConnectAsync(10000, shutdown.Token);
            if (!GetNamedPipeServerProcessId(pipe.SafePipeHandle, out var pid) || pid != parent)
                throw new InvalidDataException("Unexpected desktop pipe server");
            if (!DesktopNative.RegisterRawInputDevices([
                new() { Page = 1, Usage = 2, Flags = 0x2100, Target = window.Handle }
            ], 1, (uint)Marshal.SizeOf<DesktopNative.RawDevice>()))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            var writer = WriteAsync();
            Refresh();
            timer.Start();
            try
            {
                while (!shutdown.IsCancellationRequested) Handle(await DesktopPipe.Read(pipe, shutdown.Token));
            }
            finally { output.Writer.TryComplete(); await writer; }
        }
        catch (Exception error) when (error is IOException or OperationCanceledException or Win32Exception or System.Text.Json.JsonException) { }
        finally { ExitThread(); }
    }

    private async Task WriteAsync()
    {
        try { await foreach (var message in output.Reader.ReadAllAsync(shutdown.Token)) await DesktopPipe.Write(pipe, message, shutdown.Token); }
        catch { pipe.Dispose(); }
    }

    private void Send(DesktopMessage message)
    {
        if (!output.Writer.TryWrite(message)) pipe.Dispose();
    }

    private void Refresh()
    {
        var next = Screen.AllScreens.Select(screen => new MonitorInfo(screen.DeviceName,
            screen.Bounds.X, screen.Bounds.Y, screen.Bounds.Width, screen.Bounds.Height, DesktopNative.Dpi(screen.Bounds.X, screen.Bounds.Y), screen.Primary)).ToArray();
        if (!next.SequenceEqual(monitors))
        {
            handoff.Exit(); detector.Reset(); monitors = next;
            Send(new DesktopMessage("screens", Monitors: monitors));
        }
        uint count = 0;
        var size = (uint)Marshal.SizeOf<DesktopNative.DeviceEntry>();
        if (DesktopNative.GetRawInputDeviceList(null, ref count, size) != uint.MaxValue && count <= 1024)
        {
            var list = new DesktopNative.DeviceEntry[count];
            var read = DesktopNative.GetRawInputDeviceList(list, ref count, size);
            if (read != uint.MaxValue)
            {
                var present = list.Take((int)read).Where(item => item.Type == 0).Select(item => item.Handle).ToHashSet();
                foreach (var stale in devices.Keys.Where(key => !present.Contains(key)).ToArray()) devices.Remove(stale);
                foreach (var device in present)
                    if (!devices.ContainsKey(device)) devices[device] = DesktopNative.IsMacMouse(device, address);
            }
        }
        var mouse = devices.Values.Any(value => value);
        var state = DesktopNative.DesktopState();
        var accessible = state.Desktop == 0;
        blind = !accessible ? state.Blind : !mouse ? (byte)3 : (byte)0;
        if (blind != 0) { handoff.Exit(); detector.Reset(); }
        Send(new DesktopMessage("state", Blind: blind, Desktop: state.Desktop, MousePresent: mouse,
            Detail: !accessible ? "Secure desktop; use the Mac hotkey" : !mouse ?
                "Waiting for the selected Mac's HID mouse" : "Windows edge return ready"));
    }

    private void Handle(DesktopMessage message)
    {
        switch (message.Kind)
        {
            case "config":
                handoff.Exit(); detector.Reset();
                config = message.Config is { Edge: < 4, PushCounts: >= 0 and <= 1000 } ? message.Config : null;
                break;
            case "exit": handoff.Exit(); detector.Reset(); break;
            case "enter":
                handoff.Exit(); detector.Reset();
                var monitor = monitors.FirstOrDefault(item => item.Id == config?.Monitor);
                var ok = false;
                var position = new DesktopNative.Point();
                if (monitor is not null && message.Edge == config?.Edge && DesktopNative.IsDefaultDesktop())
                {
                    var point = monitor.Entry(message.Edge, message.Fraction);
                    ok = DesktopNative.SetCursorPos(point.X, point.Y) && DesktopNative.GetCursorPos(out position) &&
                        Math.Abs(position.X - point.X) <= 1 && Math.Abs(position.Y - point.Y) <= 1;
                    if (ok) handoff.Enter(message.SwitchId);
                }
                Send(new DesktopMessage("ack", SwitchId: message.SwitchId, Ok: ok,
                    X: position.X, Y: position.Y, Blind: ok ? blind : (byte)4));
                break;
        }
    }

    private void RawInput(IntPtr handle)
    {
        if (handoff.Active is not { } id || config is null || blind != 0) return;
        var headerSize = (uint)(8 + IntPtr.Size * 2);
        uint size = 0;
        if (DesktopNative.GetRawInputData(handle, 0x10000003, IntPtr.Zero, ref size, headerSize) == uint.MaxValue ||
            size < headerSize + 24 || size > 4096) return;
        var buffer = Marshal.AllocHGlobal((int)size);
        try
        {
            if (DesktopNative.GetRawInputData(handle, 0x10000003, buffer, ref size, headerSize) != size ||
                Marshal.ReadInt32(buffer) != 0) return;
            var device = Marshal.ReadIntPtr(buffer, 8);
            if (!devices.TryGetValue(device, out var selected) || !selected) return;
            var mouse = buffer + (int)headerSize;
            if ((Marshal.ReadInt16(mouse) & 1) != 0 || !DesktopNative.GetCursorPos(out var point)) return;
            var dx = Marshal.ReadInt32(mouse, 12);
            var dy = Marshal.ReadInt32(mouse, 16);
            if (dx == 0 && dy == 0) return;
            var monitor = monitors.FirstOrDefault(item => item.Id == config.Monitor);
            if (monitor is null) return;
            var held = new[] { 1, 2, 4, 5, 6 }.Any(key => DesktopNative.GetAsyncKeyState(key) < 0);
            var clipped = !DesktopNative.GetClipCursor(out var clip) || clip.Left > monitor.X || clip.Top > monitor.Y ||
                clip.Right < monitor.X + monitor.W || clip.Bottom < monitor.Y + monitor.H;
            if (detector.Observe(monitor, monitors, config, point.X, point.Y, dx, dy, held, clipped))
                Send(new DesktopMessage("leave", SwitchId: id, Edge: config.Edge,
                    Fraction: monitor.Fraction(config.Edge, point.X, point.Y)));
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            Application.Idle -= Start;
            shutdown.Cancel(); timer.Dispose(); pipe.Dispose(); window.DestroyHandle(); shutdown.Dispose();
        }
        base.Dispose(disposing);
    }

    private sealed class RawWindow : NativeWindow
    {
        private readonly DesktopWorker owner;
        public RawWindow(DesktopWorker owner)
        {
            this.owner = owner;
            CreateHandle(new CreateParams { Caption = "BTRemote desktop input", Parent = new IntPtr(-3) });
        }
        protected override void WndProc(ref System.Windows.Forms.Message message)
        {
            if (message.Msg == 0xFF) owner.RawInput(message.LParam);
            if (message.Msg == 0xFE) owner.devices.Clear(); // device handles can be reused after reconnect
            base.WndProc(ref message);
        }
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetNamedPipeServerProcessId(SafePipeHandle pipe, out uint pid);
}
