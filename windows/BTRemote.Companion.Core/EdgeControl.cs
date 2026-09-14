namespace BTRemote.Companion.Core;

public sealed record MonitorInfo(string Id, int X, int Y, int W, int H, int Dpi, bool Primary)
{
    public bool Contains(int x, int y) => x >= X && y >= Y && x < X + W && y < Y + H;
    public (int X, int Y) Entry(byte edge, ushort fraction)
    {
        var alongX = X + (int)Math.Round(fraction / 65535d * (W - 1));
        var alongY = Y + (int)Math.Round(fraction / 65535d * (H - 1));
        return edge switch
        {
            0 => (X + 2, Math.Clamp(alongY, Y + 2, Y + H - 3)),
            1 => (X + W - 3, Math.Clamp(alongY, Y + 2, Y + H - 3)),
            2 => (Math.Clamp(alongX, X + 2, X + W - 3), Y + 2),
            3 => (Math.Clamp(alongX, X + 2, X + W - 3), Y + H - 3),
            _ => throw new ArgumentOutOfRangeException(nameof(edge))
        };
    }
    public ushort Fraction(byte edge, int x, int y) => (ushort)Math.Round(65535 * Math.Clamp(
        edge < 2 ? (y - Y) / (double)(H - 1) : (x - X) / (double)(W - 1), 0, 1));
}

public sealed record EdgeConfiguration(byte Edge, string Monitor, int PushCounts = 12);
public sealed record DesktopMessage(string Kind, EdgeConfiguration? Config = null, byte SwitchId = 0,
    byte Edge = 0, ushort Fraction = 0, MonitorInfo[]? Monitors = null,
    byte Blind = 4, byte Desktop = 2, bool MousePresent = false, bool Ok = false, int X = 0, int Y = 0, string? Detail = null);

// Only fresh outward counts from the selected Mac mouse can trigger a return.
public sealed class EdgeDetector
{
    private long push;
    public void Reset() => push = 0;
    public bool Observe(MonitorInfo monitor, IReadOnlyList<MonitorInfo> monitors, EdgeConfiguration config,
        int x, int y, int dx, int dy, bool held, bool blocked)
    {
        var outward = config.Edge switch { 0 => -(long)dx, 1 => dx, 2 => -(long)dy, 3 => dy, _ => 0 };
        var pinned = monitor.Contains(x, y) && config.Edge switch
        {
            0 => x == monitor.X,
            1 => x == monitor.X + monitor.W - 1,
            2 => y == monitor.Y,
            3 => y == monitor.Y + monitor.H - 1,
            _ => false
        };
        var outside = config.Edge switch
        {
            0 => (x - 1, y),
            1 => (x + 1, y),
            2 => (x, y - 1),
            _ => (x, y + 1)
        };
        if (held || blocked || !pinned || outward <= 0 ||
            monitors.Any(other => other.Id != monitor.Id && other.Contains(outside.Item1, outside.Item2)))
        { Reset(); return false; }
        push += outward;
        if (push < Math.Max(1, config.PushCounts)) return false;
        Reset();
        return true;
    }
}

// A desktop restart/EXIT invalidates its previous handoff; later placement or edge messages cannot revive it.
public sealed class HandoffSession
{
    public byte? Active { get; private set; }
    public void Enter(byte id) => Active = id;
    public void Exit() => Active = null;
    public bool Accept(byte id) => Active == id;
}
