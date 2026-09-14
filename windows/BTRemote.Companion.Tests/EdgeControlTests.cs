using System.Text.Json;
using BTRemote.Companion.Core;
using Xunit;

namespace BTRemote.Companion.Tests;

public sealed class EdgeControlTests
{
    private static readonly MonitorInfo Monitor = new("left", -1920, -200, 1920, 1080, 144, false);
    [Theory]
    [InlineData(0, -1918, 340)]
    [InlineData(1, -3, 340)]
    [InlineData(2, -960, -198)]
    [InlineData(3, -960, 877)]
    public void EntryUsesPhysicalCoordinatesAndMatchingFraction(byte edge, int x, int y)
    {
        Assert.Equal((x, y), Monitor.Entry(edge, 32768));
        Assert.InRange(Math.Abs(Monitor.Fraction(edge, x, y) - 32768), 0, 40);
    }
    [Theory]
    [InlineData(0, -1920, 300, -1, 0)]
    [InlineData(1, -1, 300, 1, 0)]
    [InlineData(2, -900, -200, 0, -1)]
    [InlineData(3, -900, 879, 0, 1)]
    public void FirstOutwardCountAtAnyEdgeReturnsImmediately(byte edge, int x, int y, int dx, int dy)
    {
        // Legacy Mac settings must not restore a threshold or dwell on Windows.
        var config = JsonSerializer.Deserialize<EdgeConfiguration>(
            $$"""{"edge":{{edge}},"monitor":"left","pushCounts":12,"switchDelayMs":250}""",
            new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
        bool Move(int moveX, int moveY, bool held = false, bool blocked = false) =>
            EdgeDetector.Observe(Monitor, [Monitor], config, x, y, moveX, moveY, held, blocked);
        Assert.True(Move(dx, dy));
        Assert.False(Move(dx, dy, held: true));
        Assert.True(Move(dx, dy));
        Assert.False(Move(dx, dy, blocked: true));
        Assert.False(Move(-dx, -dy));
        Assert.False(Move(0, 0));
        Assert.True(Move(dx, dy));
        Assert.False(EdgeDetector.Observe(Monitor, [Monitor], config, -900, 300, dx, dy, false, false));
    }
    [Fact]
    public void SharedMonitorBorderCannotReturn()
    {
        var other = new MonitorInfo("right", 0, 0, 1920, 1080, 96, true);
        Assert.False(EdgeDetector.Observe(Monitor, [Monitor, other], new(1, Monitor.Id), -1, 300, 40, 0, false, false));
        Assert.True(EdgeDetector.Observe(Monitor, [Monitor, other], new(1, Monitor.Id), -1, -100, 40, 0, false, false));
    }
    [Fact]
    public void ExitAndReplacementInvalidateOldHandoff()
    {
        var session = new HandoffSession();
        Assert.False(session.Accept(1));
        session.Enter(1); Assert.True(session.Accept(1));
        session.Enter(2); Assert.False(session.Accept(1));
        session.Exit(); Assert.False(session.Accept(2));
        session.Enter(255); session.Enter(0); Assert.False(session.Accept(255)); Assert.True(session.Accept(0));
    }
    [Fact]
    public void SecureDesktopSuspendsAndResumesTheSameHandoff()
    {
        var session = new HandoffSession();
        session.Enter(42);
        Assert.True(session.CanReturn);
        session.SetAvailable(false);
        Assert.False(session.CanReturn);
        Assert.True(session.Accept(42));
        session.SetAvailable(true);
        Assert.True(session.CanReturn);
        Assert.True(session.Accept(42));
        Assert.True(EdgeDetector.Observe(Monitor, [Monitor], new(1, Monitor.Id), -1, 300, 1, 0, false, false));
    }
    [Fact]
    public void HotkeyExitWhileSecureCannotBeRevivedByDesktopRecovery()
    {
        var session = new HandoffSession();
        session.Enter(42);
        session.SetAvailable(false);
        session.Exit();
        session.SetAvailable(true);
        Assert.False(session.CanReturn);
        Assert.False(session.Accept(42));
    }
    [Fact]
    public void EntryDuringSecureDesktopBecomesReturnableWhenDesktopRecovers()
    {
        var session = new HandoffSession();
        session.SetAvailable(false);
        session.Enter(43);
        Assert.False(session.CanReturn);
        session.SetAvailable(true);
        Assert.True(session.CanReturn);
        Assert.True(session.Accept(43));
    }

}
