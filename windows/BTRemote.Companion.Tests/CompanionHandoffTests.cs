using BTRemote.Companion.Core;
using Xunit;

namespace BTRemote.Companion.Tests;

public sealed class CompanionHandoffTests
{
    [Fact]
    public void LoginRetainsPreLoginOwnershipWithoutReplayingPlacement()
    {
        var session = new CompanionHandoff();
        session.Enter(42, 1);
        Assert.Null(session.Resume(false));
        session.DesktopChanged();
        Assert.Null(session.Resume(true));
        session.Configure(new(1, "primary"));
        Assert.Equal(new DesktopMessage("resume", SwitchId: 42, Edge: 1), session.Resume(true));
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void LateHelloOwnershipAndConfigurationCanArriveInEitherOrder(bool controlFirst)
    {
        var session = new CompanionHandoff();
        if (controlFirst) session.Enter(7, 0);
        else session.Configure(new(0, "primary"));
        Assert.Null(session.Resume(true));
        if (controlFirst) session.Configure(new(0, "primary"));
        else session.Enter(7, 0);
        Assert.Equal(new DesktopMessage("resume", SwitchId: 7, Edge: 0), session.Resume(true));
        Assert.Null(session.Resume(false));
    }

    [Fact]
    public void WorkerRestartRequiresFreshConfigurationAndRetainsOwnership()
    {
        var session = new CompanionHandoff();
        session.Enter(255, 1);
        session.Configure(new(1, "old"));
        session.DesktopChanged();
        Assert.True(session.Accept(255));
        Assert.Null(session.Resume(true));
        Assert.True(session.Configure(new(1, "new")));
        Assert.False(session.Configure(new(1, "new")));
        Assert.NotNull(session.Resume(true));
    }

    [Fact]
    public void HotkeyExitBeforeLateConfigurationCannotReviveRemoteControl()
    {
        var session = new CompanionHandoff();
        session.Enter(42, 1);
        session.DesktopChanged();
        session.Exit();
        session.Configure(new(1, "primary"));
        Assert.False(session.Accept(42));
        Assert.Null(session.Resume(true));
    }

    [Fact]
    public void LinkResetClearsOwnershipAndConfiguration()
    {
        var session = new CompanionHandoff();
        session.Enter(42, 1);
        session.Configure(new(1, "primary"));
        session.Reset();
        Assert.Null(session.Configuration);
        session.Configure(new(1, "primary"));
        Assert.Null(session.Resume(true));
    }

    [Fact]
    public void ReplacementHandoffMustMatchTheConfiguredEdge()
    {
        var session = new CompanionHandoff();
        session.Enter(255, 1);
        session.Configure(new(1, "primary"));
        session.Enter(0, 0);
        Assert.False(session.Accept(255));
        Assert.True(session.Accept(0));
        Assert.Null(session.Resume(true));
        session.Configure(new(0, "primary"));
        Assert.Equal(new DesktopMessage("resume", SwitchId: 0, Edge: 0), session.Resume(true));
    }
}
