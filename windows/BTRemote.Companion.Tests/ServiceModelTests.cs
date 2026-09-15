using BTRemote.Companion.Core;
using Xunit;

namespace BTRemote.Companion.Tests;

public sealed class ServiceModelTests
{
    [Theory]
    [InlineData(1, 2)]
    [InlineData(2, 5)]
    [InlineData(3, 10)]
    [InlineData(4, 20)]
    [InlineData(100, 30)]
    public void ReconnectBackoffIsBounded(int failures, int seconds) =>
        Assert.Equal(TimeSpan.FromSeconds(seconds), ServicePolicy.RetryDelay(failures));

    [Fact]
    public void StaleStatusCannotLookLikeAWorkingConnection()
    {
        var now = DateTimeOffset.UtcNow;
        Assert.True(ServicePolicy.IsFresh(now.AddSeconds(-10), now));
        Assert.False(ServicePolicy.IsFresh(now.AddMinutes(-1), now));
        Assert.False(ServicePolicy.IsFresh(now.AddHours(1), now));
    }

    [Theory]
    [InlineData("", "Mac")]
    [InlineData("device\nother", "Mac")]
    [InlineData("endpoint", "")]
    public void InvalidDeviceSelectionIsRejected(string id, string name) =>
        Assert.Throws<ArgumentException>(() => new CompanionSettings(id, name).Validate());

    [Fact]
    public void ConfigurationRoundTripPreservesWindowsEndpointAndUnicodeName()
    {
        var folder = Path.Combine(Path.GetTempPath(), "btremote-test-" + Guid.NewGuid());
        Directory.CreateDirectory(folder);
        try
        {
            var path = Path.Combine(folder, "settings.json");
            var value = new CompanionSettings(@"BluetoothLE#BluetoothLE00:11:22:33:44:55-66:77:88:99:aa:bb", "Amadeus’s Mac")
            { PairingDeviceId = "classic-pairing-endpoint" };
            value.Validate();
            JsonFiles.Write(path, value);
            Assert.Equal(value, JsonFiles.Read<CompanionSettings>(path));
            var updated = value with { DeviceName = "Renamed Mac" };
            JsonFiles.Write(path, updated);
            Assert.Equal(updated, JsonFiles.Read<CompanionSettings>(path));
            Assert.False(File.Exists(path + ".new"));
        }
        finally { Directory.Delete(folder, recursive: true); }
    }
    [Fact]
    public void OlderSavedMacWithoutSeparatePairingEndpointRemainsValid()
    {
        var settings = System.Text.Json.JsonSerializer.Deserialize<CompanionSettings>(
            "{\"DeviceId\":\"existing-le-endpoint\",\"DeviceName\":\"Mac\"}")!;
        settings.Validate();
        Assert.Null(settings.PairingDeviceId);
        Assert.Equal("existing-le-endpoint", settings.DeviceId);
    }
    [Theory]
    [InlineData("")] [InlineData("\n")]
    public void InvalidSeparatePairingEndpointIsRejected(string id) =>
        Assert.Throws<ArgumentException>(() => new CompanionSettings("le", "Mac") { PairingDeviceId = id }.Validate());
}
