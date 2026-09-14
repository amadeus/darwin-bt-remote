using System.Buffers.Binary;
using System.Text.Json;
using BTRemote.Companion.Core;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Storage.Streams;

namespace BTRemote.Companion;

// Runs on the service's STA BLE worker. Desktop observations are requests; the Mac remains the routing authority.
internal sealed class BluetoothControl(Action<string> status) : IDisposable
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };
    private readonly SynchronizationContext context = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
    private readonly Queue<(GattCharacteristic Characteristic, byte[] Data, bool HelloEnd)> controls = new(), bulk = new();
    private readonly HandoffSession handoff = new();
    private Protocol.Encoder controlEncoder = new(), bulkEncoder = new();
    private Protocol.Decoder controlDecoder = new(), bulkDecoder = new();
    private GattCharacteristic? controlRead, controlWrite, bulkRead, bulkWrite;
    private DesktopHost? desktop;
    private MonitorInfo[] monitors = [];
    private EdgeConfiguration? config;
    private long lastSeen, connectedAt;
    private bool subscribing, ready, writing, helloSent;
    private int generation;
    private byte blind = 4;
    public bool NeedsReconnect { get; private set; }
    public bool Attached => controlRead is not null;
    public string Detail { get; private set; } = "Waiting for Mac control service";

    public async Task Attach(GattDeviceService service, CancellationToken stop)
    {
        ResetLink();
        var result = await service.GetCharacteristicsAsync(BluetoothCacheMode.Uncached).AsTask(stop);
        if (result.Status != GattCommunicationStatus.Success) throw new IOException("Control characteristic discovery: " + result.Status);
        GattCharacteristic Find(int id) => result.Characteristics.FirstOrDefault(item => item.Uuid == Protocol.Uuid(id))
            ?? throw new IOException("Missing companion characteristic " + id);
        controlRead = Find(2); controlWrite = Find(3); bulkRead = Find(4); bulkWrite = Find(5);
        foreach (var characteristic in new[] { controlRead, controlWrite, bulkRead, bulkWrite })
            characteristic.ProtectionLevel = GattProtectionLevel.EncryptionRequired;
        // Clear persisted CCCDs first so macOS starts a fresh per-connection handshake.
        foreach (var characteristic in new[] { controlRead, bulkRead })
        {
            var outcome = await characteristic.WriteClientCharacteristicConfigurationDescriptorAsync(
                GattClientCharacteristicConfigurationDescriptorValue.None).AsTask(stop);
            if (outcome != GattCommunicationStatus.Success) throw new IOException("Companion subscription reset: " + outcome);
        }
        controlRead.ValueChanged += Notification;
        bulkRead.ValueChanged += Notification;
        subscribing = true;
        connectedAt = Environment.TickCount64;
        foreach (var characteristic in new[] { controlRead, bulkRead })
        {
            var outcome = await characteristic.WriteClientCharacteristicConfigurationDescriptorAsync(
                GattClientCharacteristicConfigurationDescriptorValue.Notify).AsTask(stop);
            if (outcome != GattCommunicationStatus.Success) throw new IOException("Companion subscription: " + outcome);
        }
        subscribing = false;
        Drain();
    }

    public void Tick(string address)
    {
        desktop ??= new DesktopHost(DesktopEvent);
        try { desktop.Refresh(address); }
        catch (Exception error) { SetDetail("Desktop worker: " + error.Message); }
        if (!Attached) return;
        if ((!ready && Environment.TickCount64 - connectedAt > 10000) ||
            (ready && Environment.TickCount64 - lastSeen > 10000))
        { Fail("Companion heartbeat expired; reconnecting"); return; }
        if (ready)
        {
            var payload = new byte[4];
            BinaryPrimitives.WriteUInt32LittleEndian(payload, unchecked((uint)Environment.TickCount64));
            Send(Protocol.Message.Ping, payload);
            if (!desktop.Connected) { blind = 4; Send(Protocol.Message.State, [4, 2, 0]); SetDetail(desktop.Detail); }
        }
    }

    private void Notification(GattCharacteristic sender, GattValueChangedEventArgs args)
    {
        using var reader = DataReader.FromBuffer(args.CharacteristicValue);
        if (reader.UnconsumedBufferLength > Protocol.ChunkSize) { context.Post(_ => Fail("Oversized companion frame"), null); return; }
        var bytes = new byte[reader.UnconsumedBufferLength];
        reader.ReadBytes(bytes);
        context.Post(_ => Receive(sender, bytes), null);
    }

    private void Receive(GattCharacteristic source, byte[] frame)
    {
        if (NeedsReconnect || (source != controlRead && source != bulkRead)) return;
        try
        {
            var control = source == controlRead;
            var packet = (control ? controlDecoder : bulkDecoder).Receive(frame);
            if (packet is null) return;
            if (packet.Stream != (control ? 0 : 1)) throw new InvalidDataException("Wrong companion stream");
            var type = (Protocol.Message)packet.Type;
            if (type == Protocol.Message.Hello)
            {
                using var hello = JsonDocument.Parse(packet.Payload);
                if (ready || hello.RootElement.GetProperty("v").GetInt32() != 1 ||
                    hello.RootElement.GetProperty("role").GetString() != "mac" ||
                    hello.RootElement.GetProperty("chunk").GetInt32() < 20) throw new InvalidDataException("Invalid HELLO");
                ready = true;
                SendJson(Protocol.Message.Hello, new { v = 1, role = "pc", name = "BTRemote Companion", chunk = 20 });
                if (monitors.Length > 0) SendScreens();
                SetDetail("Companion connected; waiting for desktop status");
            }
            else
            {
                if (!ready) throw new InvalidDataException("Expected HELLO");
                Handle(type, packet.Payload);
            }
            lastSeen = Environment.TickCount64;
        }
        catch (Exception error) when (error is InvalidDataException or JsonException or InvalidOperationException or KeyNotFoundException)
        { Fail("Invalid companion message: " + error.Message); }
    }

    private void Handle(Protocol.Message type, byte[] payload)
    {
        switch (type)
        {
            case Protocol.Message.Ping when payload.Length == 4: Send(Protocol.Message.Pong, payload); break;
            case Protocol.Message.Pong when payload.Length == 4: break;
            case Protocol.Message.Config:
                var next = JsonSerializer.Deserialize<EdgeConfiguration>(payload, Json);
                if (next is not { Edge: < 4, PushCounts: >= 0 and <= 1000 } ||
                    !monitors.Any(item => item.Id == next.Monitor)) throw new InvalidDataException("Unknown Windows display");
                if (config != next)
                {
                    handoff.Exit(); config = next;
                    desktop?.Send(new DesktopMessage("config", Config: config));
                }
                break;
            case Protocol.Message.Enter when payload.Length == 4 && payload[1] < 4:
                handoff.Enter(payload[0]);
                if (desktop?.Connected == true && config is not null && config.Edge == payload[1])
                    desktop.Send(new DesktopMessage("enter", SwitchId: payload[0], Edge: payload[1],
                        Fraction: BinaryPrimitives.ReadUInt16LittleEndian(payload.AsSpan(2))));
                else Send(Protocol.Message.EnterAck, [payload[0], 0, 0, 0, 0, 0, 4]);
                break;
            case Protocol.Message.Exit when payload.Length == 1:
                if (handoff.Accept(payload[0])) { handoff.Exit(); desktop?.Send(new DesktopMessage("exit")); }
                break;
            default: throw new InvalidDataException("Unsupported companion message");
        }
    }

    private void DesktopEvent(DesktopMessage message)
    {
        switch (message.Kind)
        {
            case "connected":
            case "disconnected":
                handoff.Exit(); config = null; blind = 4;
                if (ready) Send(Protocol.Message.State, [4, 2, 0]);
                break;
            case "screens":
                if (message.Monitors is not { Length: > 0 and <= 32 } screens ||
                    screens.Any(item => item.W is < 5 or > 32768 || item.H is < 5 or > 32768 || item.Id.Length > 256)) return;
                handoff.Exit(); config = null; monitors = screens;
                if (ready) SendScreens();
                break;
            case "state":
                blind = message.Blind;
                if (ready) Send(Protocol.Message.State, [blind, message.Desktop, (byte)(message.MousePresent ? 1 : 0)]);
                SetDetail(message.Detail ?? "Desktop status received");
                break;
            case "ack" when handoff.Accept(message.SwitchId):
                var ack = new byte[7]; ack[0] = message.SwitchId; ack[1] = message.Ok ? (byte)1 : (byte)0;
                BinaryPrimitives.WriteInt16LittleEndian(ack.AsSpan(2), (short)Math.Clamp(message.X, short.MinValue, short.MaxValue));
                BinaryPrimitives.WriteInt16LittleEndian(ack.AsSpan(4), (short)Math.Clamp(message.Y, short.MinValue, short.MaxValue));
                ack[6] = message.Blind;
                Send(Protocol.Message.EnterAck, ack);
                break;
            case "leave" when handoff.Accept(message.SwitchId) && message.Edge == config?.Edge && blind == 0:
                Send(Protocol.Message.Leave, [message.SwitchId, message.Edge, (byte)message.Fraction, (byte)(message.Fraction >> 8)]);
                break;
        }
    }

    private void SendScreens() => SendJson(Protocol.Message.Screens, new { monitors });
    private void SendJson(Protocol.Message type, object value) => Enqueue(type, 1, JsonSerializer.SerializeToUtf8Bytes(value, Json));
    private void Send(Protocol.Message type, byte[] payload) { if (ready) Enqueue(type, 0, payload); }
    private void Enqueue(Protocol.Message type, byte stream, byte[] payload)
    {
        var characteristic = stream == 0 ? controlWrite : bulkWrite;
        if (characteristic is null || NeedsReconnect) return;
        var frames = (stream == 0 ? controlEncoder : bulkEncoder).Encode(new Protocol.Packet(stream, (byte)type, payload));
        if (controls.Count + bulk.Count + frames.Count > 512) { Fail("Companion queue full"); return; }
        for (var index = 0; index < frames.Count; index++)
            (stream == 0 ? controls : bulk).Enqueue((characteristic, frames[index],
                type == Protocol.Message.Hello && index == frames.Count - 1));
        Drain();
    }

    private async void Drain()
    {
        if (writing || subscribing || NeedsReconnect) return;
        writing = true;
        var epoch = generation;
        try
        {
            while (epoch == generation && !NeedsReconnect && (controls.Count > 0 || bulk.Count > 0))
            {
                // The peer must receive the whole HELLO before any control-stream messages.
                var queue = !helloSent ? bulk : controls.Count > 0 ? controls : bulk;
                if (queue.Count == 0) break;
                var item = queue.Dequeue();
                using var writer = new DataWriter(); writer.WriteBytes(item.Data);
                var result = await item.Characteristic.WriteValueAsync(writer.DetachBuffer(),
                    item.Characteristic == controlWrite ? GattWriteOption.WriteWithoutResponse : GattWriteOption.WriteWithResponse)
                    .AsTask().WaitAsync(TimeSpan.FromSeconds(8));
                if (result != GattCommunicationStatus.Success) throw new IOException("Companion write: " + result);
                if (epoch == generation && item.HelloEnd) helloSent = true;
            }
        }
        catch (Exception error) { if (epoch == generation) Fail(error.Message); }
        finally { writing = false; if (epoch != generation) Drain(); }
    }

    private void SetDetail(string value) { if (Detail != value) { Detail = value; status(value); } }
    private void Fail(string reason) { NeedsReconnect = true; ready = false; handoff.Exit(); desktop?.Send(new DesktopMessage("exit")); SetDetail(reason); }
    public void ResetLink()
    {
        generation++;
        if (controlRead is not null) controlRead.ValueChanged -= Notification;
        if (bulkRead is not null) bulkRead.ValueChanged -= Notification;
        controlRead = controlWrite = bulkRead = bulkWrite = null;
        controls.Clear(); bulk.Clear(); controlEncoder = new(); bulkEncoder = new(); controlDecoder = new(); bulkDecoder = new();
        ready = subscribing = NeedsReconnect = helloSent = false;
        config = null; handoff.Exit(); desktop?.Send(new DesktopMessage("exit"));
    }
    public void Dispose() { ResetLink(); desktop?.Dispose(); desktop = null; }
}
