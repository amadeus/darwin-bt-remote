using System.Diagnostics;
using System.Security.Principal;
using System.Text.Json;
using BTRemote.Companion.Core;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;

namespace BTRemote.Companion;

internal sealed class BluetoothWorker : ApplicationContext
{
    private static readonly Guid HidUuid = new("00001812-0000-1000-8000-00805f9b34fb");
    private readonly CancellationTokenSource shutdown = new();
    private readonly StreamWriter output = new(Console.OpenStandardOutput()) { AutoFlush = true };
    private readonly System.Windows.Forms.Timer heartbeat = new() { Interval = 10000 };
    private WorkerStatus status = new("Starting", "Starting service-account Bluetooth worker", DateTimeOffset.UtcNow);
    private BluetoothLEDevice? device;
    private GattSession? session;
    private readonly List<GattDeviceService> services = [];
    private volatile bool changed = true;
    private bool started;
    private BluetoothControl? control;
    public int ExitCode { get; private set; }

    public BluetoothWorker()
    {
        heartbeat.Tick += (_, _) => Emit(status with { At = DateTimeOffset.UtcNow });
        heartbeat.Start();
        Application.Idle += Start;
    }

    private async void Start(object? sender, EventArgs args)
    {
        if (started) return;
        started = true;
        Application.Idle -= Start;
        try { await RunAsync(shutdown.Token); }
        catch (OperationCanceledException) when (shutdown.IsCancellationRequested) { }
        catch (Exception error)
        {
            Emit(status with { State = "Error", Detail = Describe(error), At = DateTimeOffset.UtcNow });
            ExitCode = 1;
        }
        finally { ExitThread(); }
    }

    private async Task RunAsync(CancellationToken stop)
    {
        var settings = JsonFiles.Read<CompanionSettings>(Paths.Settings)
            ?? throw new InvalidOperationException("No paired Mac selected.");
        settings.Validate();
        control = new BluetoothControl(detail => Emit(status with { State = "Connected", Detail = detail }));
        var failures = 0;
        while (!stop.IsCancellationRequested)
        {
            try
            {
                if (device is null)
                {
                    Emit(status with { State = "Opening", Detail = "Opening saved paired endpoint", DeviceName = settings.DeviceName });
                    var info = await DeviceInformation.CreateFromIdAsync(settings.DeviceId,
                        ["System.Devices.Aep.IsPaired"], DeviceInformationKind.AssociationEndpoint).AsTask(stop);
                    if (!info.Pairing.IsPaired)
                        throw new InvalidOperationException("The saved endpoint is no longer paired. Select the paired Mac again.");
                    // executed on the STA message-loop thread, never Task.Run.
                    device = await BluetoothLEDevice.FromIdAsync(settings.DeviceId).AsTask(stop)
                        ?? throw new InvalidOperationException("Windows denied service-account access to this BLE endpoint.");
                    device.ConnectionStatusChanged += ConnectionChanged;
                    device.GattServicesChanged += ServicesChanged;
                    session = await GattSession.FromDeviceIdAsync(device.BluetoothDeviceId).AsTask(stop);
                    if (session is not null && session.CanMaintainConnection) session.MaintainConnection = true;
                    changed = true;
                }

                if (changed || control.NeedsReconnect || device.ConnectionStatus != BluetoothConnectionStatus.Connected || !control.Attached)
                {
                    changed = false;
                    Emit(status with { State = "Discovering", Detail = "Requesting uncached GATT services under the service account" });
                    control.ResetLink();
                    foreach (var service in services) service.Dispose();
                    services.Clear();
                    var result = await device.GetGattServicesAsync(BluetoothCacheMode.Uncached).AsTask(stop);
                    if (result.Status != GattCommunicationStatus.Success)
                    {
                        foreach (var service in result.Services) service.Dispose();
                        throw new InvalidOperationException($"Uncached discovery: {result.Status}; ATT error: {result.ProtocolError}");
                    }
                    services.AddRange(result.Services);
                    var hasHid = services.Any(service => service.Uuid == HidUuid);
                    Emit(status with
                    {
                        State = hasHid ? "Discovered" : "HID missing",
                        Detail = $"Uncached discovery succeeded; BLE {device.ConnectionStatus}. " +
                            "Mac HID subscription/control must be checked on the Mac.",
                        LastDiscovery = DateTimeOffset.UtcNow,
                        ServiceCount = services.Count,
                        HidServiceFound = hasHid
                    });
                    if (!hasHid) throw new InvalidOperationException("Discovery succeeded but the Mac HID service was absent.");
                    var companion = services.FirstOrDefault(service => service.Uuid == Protocol.Uuid(1));
                    if (companion is not null) await control.Attach(companion, stop);
                    failures = 0;
                }
                control.Tick(device.BluetoothAddress.ToString("X12"));
                await Task.Delay(TimeSpan.FromSeconds(3), stop);
            }
            catch (OperationCanceledException) when (stop.IsCancellationRequested) { throw; }
            catch (Exception error)
            {
                CloseDevice();
                var delay = ServicePolicy.RetryDelay(++failures);
                Emit(status with { State = "Retrying", Detail = $"{Describe(error)} Retrying in {delay.TotalSeconds:0}s." });
                await Task.Delay(delay, stop);
            }
        }
    }

    private void ConnectionChanged(BluetoothLEDevice sender, object args) => changed = true;
    private void ServicesChanged(BluetoothLEDevice sender, object args) => changed = true;

    private void Emit(WorkerStatus next)
    {
        status = next with
        {
            At = DateTimeOffset.UtcNow,
            Identity = WindowsIdentity.GetCurrent().Name,
            ProcessSession = Process.GetCurrentProcess().SessionId
        };
        output.WriteLine(JsonSerializer.Serialize(status));
    }

    private static string Describe(Exception error) => $"{error.Message} (HRESULT 0x{error.HResult:X8}).";

    private void CloseDevice()
    {
        control?.ResetLink();
        foreach (var service in services) service.Dispose();
        services.Clear();
        if (session is not null) { session.MaintainConnection = false; session.Dispose(); session = null; }
        if (device is not null)
        {
            device.ConnectionStatusChanged -= ConnectionChanged;
            device.GattServicesChanged -= ServicesChanged;
            device.Dispose();
            device = null;
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            shutdown.Cancel();
            heartbeat.Dispose();
            CloseDevice();
            control?.Dispose();
            output.Dispose();
            shutdown.Dispose();
        }
        base.Dispose(disposing);
    }
}
