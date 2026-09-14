using System.Runtime.InteropServices;

namespace BTRemote.Companion;

internal static class ConsoleSession
{
    public static (uint Id, string State) Read()
    {
        var id = WTSGetActiveConsoleSessionId();
        if (id == uint.MaxValue) return (id, "No console session");
        if (!WTSQuerySessionInformation(IntPtr.Zero, id, 5, out var buffer, out _))
            return (id, "Unknown");
        try
        {
            var user = Marshal.PtrToStringUni(buffer);
            // record presence only; service logs do not need the interactive user's name.
            return (id, string.IsNullOrEmpty(user) ? "Signed out" : "User session present");
        }
        finally { WTSFreeMemory(buffer); }
    }

    [DllImport("kernel32.dll")]
    private static extern uint WTSGetActiveConsoleSessionId();
    [DllImport("wtsapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "WTSQuerySessionInformationW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool WTSQuerySessionInformation(IntPtr server, uint sessionId, int infoClass,
        out IntPtr buffer, out uint bytes);
    [DllImport("wtsapi32.dll")]
    private static extern void WTSFreeMemory(IntPtr memory);
}
