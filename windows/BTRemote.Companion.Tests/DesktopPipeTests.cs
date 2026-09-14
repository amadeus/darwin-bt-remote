using System.Threading.Channels;
using BTRemote.Companion.Core;
using Xunit;

namespace BTRemote.Companion.Tests;

public sealed class DesktopPipeTests
{
    [Fact]
    public async Task ParentDisconnectFinishesWithoutWaitingForDesktopDispatch()
    {
        using var stream = new MemoryStream();
        await DesktopPipe.Write(stream, new DesktopMessage("exit"), CancellationToken.None);
        stream.Position = 0;
        var pendingDesktop = new List<DesktopMessage>();
        var outgoing = Channel.CreateBounded<DesktopMessage>(32);
        // Queue the desktop message but never execute it, as if the UI were hung.
        // EOF must still stop the pump, including its otherwise idle writer.
        await Assert.ThrowsAsync<EndOfStreamException>(() =>
            Task.Run(() => DesktopPipe.Pump(stream, outgoing.Reader, pendingDesktop.Add, CancellationToken.None))
                .WaitAsync(TimeSpan.FromSeconds(2)));
        Assert.Single(pendingDesktop);
        Assert.Equal("exit", pendingDesktop[0].Kind);
    }

    [Fact]
    public async Task MaximumClipboardFitsInAuthenticatedDesktopMessage()
    {
        using var stream = new MemoryStream();
        var payload = Enumerable.Repeat((byte)255, ClipboardTransfer.MaximumBytes).ToArray();
        await DesktopPipe.Write(stream, new DesktopMessage("clipboard-copy", Epoch: 42, Revision: 7, Clipboard: payload), CancellationToken.None);
        stream.Position = 0;
        var read = await DesktopPipe.Read(stream, CancellationToken.None);
        Assert.Equal(payload, read.Clipboard);
        Assert.Equal(42u, read.Epoch);
        Assert.Equal(7u, read.Revision);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(DesktopPipe.MaximumMessageBytes + 1)]
    public async Task RejectsInvalidLengthBeforeReadingPayload(int length)
    {
        var header = new byte[4];
        System.Buffers.Binary.BinaryPrimitives.WriteInt32LittleEndian(header, length);
        using var stream = new MemoryStream(header);
        await Assert.ThrowsAsync<InvalidDataException>(() => DesktopPipe.Read(stream, CancellationToken.None));
    }
}
