using System.ComponentModel;
using System.Diagnostics;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Threading.Channels;
using BTRemote.Companion.Core;
using Microsoft.Win32.SafeHandles;

namespace BTRemote.Companion;

// Service-owned worker in the console user's Default desktop. The tray is not involved.
internal sealed class DesktopHost(Action<DesktopMessage> receive) : IDisposable
{
    private Process? process;
    private WorkerJob? job;
    private NamedPipeServerStream? pipe;
    private CancellationTokenSource? lifetime;
    private Channel<DesktopMessage>? outgoing;
    private uint sessionId = uint.MaxValue;
    private string? userSid;
    private long lastMessage;
    public bool Connected { get; private set; }
    public string Detail { get; private set; } = "Waiting for signed-in console desktop";

    public void Refresh(string address)
    {
        var console = ConsoleSession.Read();
        if (!WTSQueryUserToken(console.Id, out var token)) { Stop(); return; }
        using (token)
        {
            using var identity = new WindowsIdentity(token.DangerousGetHandle());
            var sid = identity.User ?? throw new InvalidOperationException("Console token has no user SID");
            if (process is not null && !process.HasExited && sessionId == console.Id && userSid == sid.Value &&
                Environment.TickCount64 - lastMessage < 15000) return;
            Stop();
            sessionId = console.Id;
            userSid = sid.Value;
            var name = "BTRemote.Desktop." + Guid.NewGuid().ToString("N");
            var security = new PipeSecurity();
            security.SetAccessRuleProtection(true, false);
            security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid, null),
                PipeAccessRights.FullControl, AccessControlType.Deny));
            security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
                PipeAccessRights.FullControl, AccessControlType.Allow));
            security.AddAccessRule(new PipeAccessRule(sid, PipeAccessRights.ReadWrite, AccessControlType.Allow));
            pipe = NamedPipeServerStreamAcl.Create(name, PipeDirection.InOut, 1, PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous, 16384, 16384, security);
            try
            {
                process = Launch(token, name, address);
                job = new WorkerJob();
                job.Add(process);
                lifetime = new CancellationTokenSource();
                outgoing = Channel.CreateBounded<DesktopMessage>(32);
                lastMessage = Environment.TickCount64;
                Detail = "Connecting console desktop worker";
                _ = RunAsync(pipe, process.Id, outgoing, lifetime.Token);
            }
            catch { Stop(); throw; }
        }
    }

    public void Send(DesktopMessage message)
    {
        if (Connected && outgoing?.Writer.TryWrite(message) != true) Stop();
    }

    private async Task RunAsync(NamedPipeServerStream connection, int pid, Channel<DesktopMessage> queue, CancellationToken stop)
    {
        try
        {
            await connection.WaitForConnectionAsync(stop).WaitAsync(TimeSpan.FromSeconds(10), stop);
            if (!GetNamedPipeClientProcessId(connection.SafePipeHandle, out var peer) || peer != pid)
                throw new InvalidDataException("Unexpected desktop pipe client");
            Connected = true;
            Detail = "Console desktop connected";
            receive(new DesktopMessage("connected"));
            var writer = WriteAsync();
            try
            {
                while (!stop.IsCancellationRequested)
                {
                    var message = await DesktopPipe.Read(connection, stop);
                    lastMessage = Environment.TickCount64;
                    if (message.Detail is not null) Detail = message.Detail;
                    receive(message);
                }
            }
            finally { queue.Writer.TryComplete(); await writer; }
        }
        catch (Exception error) when (error is IOException or OperationCanceledException or TimeoutException or JsonException)
        {
            if (!stop.IsCancellationRequested)
            {
                Detail = "Desktop worker disconnected: " + error.Message;
                Stop();
            }
        }

        async Task WriteAsync()
        {
            try { await foreach (var message in queue.Reader.ReadAllAsync(stop)) await DesktopPipe.Write(connection, message, stop); }
            catch { connection.Dispose(); }
        }
    }

    private void Stop()
    {
        var wasConnected = Connected;
        Connected = false;
        lifetime?.Cancel(); lifetime?.Dispose(); lifetime = null;
        outgoing?.Writer.TryComplete(); outgoing = null;
        pipe?.Dispose(); pipe = null;
        job?.Dispose(); job = null;
        if (process is not null) { if (!process.HasExited) process.Kill(); process.Dispose(); process = null; }
        if (wasConnected) receive(new DesktopMessage("disconnected"));
    }

    public void Dispose() => Stop();

    private static Process Launch(SafeAccessTokenHandle token, string pipeName, string address)
    {
        var exe = Environment.ProcessPath!;
        var command = new StringBuilder($"\"{exe}\" --desktop-worker {pipeName} {Environment.ProcessId} {address}");
        var startup = new StartupInfo { Size = Marshal.SizeOf<StartupInfo>(), Desktop = @"winsta0\default" };
        if (!CreateEnvironmentBlock(out var environment, token, false)) throw new Win32Exception(Marshal.GetLastWin32Error());
        try
        {
            if (!CreateProcessAsUser(token, exe, command, IntPtr.Zero, IntPtr.Zero, false, 0x400,
                environment, AppContext.BaseDirectory, ref startup, out var result))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            try { return Process.GetProcessById((int)result.ProcessId); }
            finally { CloseHandle(result.Process); CloseHandle(result.Thread); }
        }
        finally { DestroyEnvironmentBlock(environment); }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StartupInfo
    {
        public int Size; public string? Reserved, Desktop, Title;
        public uint X, Y, Width, Height, XChars, YChars, Fill, Flags;
        public ushort Show, ReservedSize; public IntPtr ReservedPointer, Input, Output, Error;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInfo { public IntPtr Process, Thread; public uint ProcessId, ThreadId; }
    [DllImport("wtsapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool WTSQueryUserToken(uint session, out SafeAccessTokenHandle token);
    [DllImport("userenv.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreateEnvironmentBlock(out IntPtr block, SafeAccessTokenHandle token, [MarshalAs(UnmanagedType.Bool)] bool inherit);
    [DllImport("userenv.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyEnvironmentBlock(IntPtr block);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "CreateProcessAsUserW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreateProcessAsUser(SafeAccessTokenHandle token, string app, StringBuilder command,
        IntPtr processAttributes, IntPtr threadAttributes, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint flags,
        IntPtr environment, string directory, ref StartupInfo startup, out ProcessInfo process);
    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetNamedPipeClientProcessId(SafePipeHandle pipe, out uint pid);
}

internal static class DesktopPipe
{
    public static async Task<DesktopMessage> Read(Stream pipe, CancellationToken stop)
    {
        var header = new byte[4];
        await pipe.ReadExactlyAsync(header, stop);
        var size = System.Buffers.Binary.BinaryPrimitives.ReadInt32LittleEndian(header);
        if (size is < 1 or > 16384) throw new InvalidDataException("Invalid desktop message size");
        var data = new byte[size];
        await pipe.ReadExactlyAsync(data, stop);
        return JsonSerializer.Deserialize<DesktopMessage>(data) ?? throw new InvalidDataException("Empty desktop message");
    }
    public static async Task Write(Stream pipe, DesktopMessage message, CancellationToken stop)
    {
        var data = JsonSerializer.SerializeToUtf8Bytes(message);
        if (data.Length > 16384) throw new InvalidDataException("Desktop message too large");
        var header = new byte[4];
        System.Buffers.Binary.BinaryPrimitives.WriteInt32LittleEndian(header, data.Length);
        await pipe.WriteAsync(header, stop);
        await pipe.WriteAsync(data, stop);
        await pipe.FlushAsync(stop);
    }
}
