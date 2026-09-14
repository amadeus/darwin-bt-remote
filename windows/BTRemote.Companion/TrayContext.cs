using System.ComponentModel;
using System.Diagnostics;
using System.ServiceProcess;
using BTRemote.Companion.Core;
using Windows.Devices.Bluetooth;
using Windows.Devices.Enumeration;

namespace BTRemote.Companion;

internal sealed class TrayContext : ApplicationContext
{
    private readonly NotifyIcon icon;
    private readonly ToolStripMenuItem statusItem = new("Checking service…") { Enabled = false };
    private readonly ToolStripMenuItem startItem = new("Start Service");
    private readonly ToolStripMenuItem stopItem = new("Stop Service");
    private readonly ToolStripMenuItem automaticItem = new("Start automatically with Windows");
    private readonly System.Windows.Forms.Timer refresh = new() { Interval = 2000 };
    private SettingsForm? settings;
    private bool busy;

    public TrayContext(EventWaitHandle showSettings)
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add(statusItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(startItem);
        menu.Items.Add(stopItem);
        menu.Items.Add(automaticItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Settings…", null, (_, _) => ShowSettings());
        menu.Items.Add("Open diagnostics", null, (_, _) => OpenDiagnostics());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit Tray", null, (_, _) => ExitThread());
        startItem.Click += async (_, _) => await ControlAsync("--start");
        stopItem.Click += async (_, _) => await ControlAsync("--stop");
        automaticItem.Click += async (_, _) => await ControlAsync("--startup", automaticItem.Checked ? "manual" : "auto");
        icon = new NotifyIcon { Icon = SystemIcons.Application, Text = "BTRemote Companion", ContextMenuStrip = menu, Visible = true };
        icon.DoubleClick += (_, _) => ShowSettings();
        refresh.Tick += (_, _) =>
        {
            if (showSettings.WaitOne(0)) ShowSettings();
            RefreshStatus();
        };
        refresh.Start();
        RefreshStatus();
        ShowSettings();
    }

    private async Task ControlAsync(params string[] args)
    {
        busy = true;
        RefreshStatus();
        try { await ServiceCommands.ElevateAsync(args); }
        catch (Win32Exception error) when (error.NativeErrorCode == 1223) { }
        catch (Exception error) { ShowError(error); }
        finally { busy = false; RefreshStatus(); }
    }

    private void RefreshStatus()
    {
        try
        {
            using var service = new ServiceController(Paths.ServiceName);
            var state = service.Status;
            statusItem.Text = $"Service: {state}";
            startItem.Enabled = !busy && state == ServiceControllerStatus.Stopped;
            stopItem.Enabled = !busy && state == ServiceControllerStatus.Running;
            automaticItem.Enabled = !busy;
            automaticItem.Checked = service.StartType == ServiceStartMode.Automatic;
            icon.Text = $"BTRemote: {state}";
            settings?.RefreshControls(state, automaticItem.Checked, busy);
            settings?.RefreshStatus(state.ToString());
        }
        catch (Exception error) when (error is InvalidOperationException or Win32Exception)
        {
            statusItem.Text = "Service unavailable — reopen BTRemote Companion to repair";
            startItem.Enabled = stopItem.Enabled = automaticItem.Enabled = false;
            settings?.RefreshControls(null, false, true);
            settings?.RefreshStatus("Not installed or inaccessible");
        }
    }

    private void ShowSettings()
    {
        if (settings is null || settings.IsDisposed) settings = new SettingsForm(ControlAsync);
        settings.Show();
        if (settings.WindowState == FormWindowState.Minimized) settings.WindowState = FormWindowState.Normal;
        settings.Activate();
        RefreshStatus();
    }

    private static void OpenDiagnostics()
    {
        try { Process.Start(new ProcessStartInfo(Paths.DataDirectory) { UseShellExecute = true }); }
        catch (Exception error) { ShowError(error); }
    }

    internal static void ShowError(Exception error) =>
        MessageBox.Show(error.Message, "BTRemote Companion", MessageBoxButtons.OK, MessageBoxIcon.Error);

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            refresh.Dispose();
            icon.Visible = false;
            icon.Dispose();
            settings?.Dispose();
        }
        base.Dispose(disposing);
    }
}

internal sealed class SettingsForm : Form
{
    private readonly ComboBox devices = new() { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
    private readonly Button reload = new() { Text = "Refresh devices", AutoSize = true };
    private readonly Button save = new() { Text = "Use selected Mac", AutoSize = true };
    private readonly Label selected = new() { AutoSize = true, MaximumSize = new Size(460, 0) };
    private readonly Label state = new() { AutoSize = true, MaximumSize = new Size(460, 0) };
    private readonly Label detail = new() { AutoSize = true, MaximumSize = new Size(460, 0) };
    private readonly Button startService = new() { Text = "Start Service", AutoSize = true };
    private readonly Button stopService = new() { Text = "Stop Service", AutoSize = true };
    private readonly CheckBox automatic = new() { Text = "Start automatically with Windows (even when signed out)", AutoSize = true };
    private bool loading;

    public SettingsForm(Func<string[], Task> control)
    {
        Text = "BTRemote Companion";
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(530, 460);
        MinimumSize = new Size(530, 460);
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(16), ColumnCount = 1, RowCount = 10, AutoScroll = true };
        layout.Controls.Add(new Label { Text = "Paired Mac", AutoSize = true });
        layout.Controls.Add(devices);
        var buttons = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill };
        buttons.Controls.Add(reload);
        buttons.Controls.Add(save);
        layout.Controls.Add(buttons);
        layout.Controls.Add(selected);
        layout.Controls.Add(state);
        layout.Controls.Add(detail);
        var serviceButtons = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, Margin = new Padding(0, 12, 0, 0) };
        serviceButtons.Controls.Add(startService);
        serviceButtons.Controls.Add(stopService);
        layout.Controls.Add(serviceButtons);
        layout.Controls.Add(automatic);
        startService.Click += async (_, _) => await control(["--start"]);
        stopService.Click += async (_, _) => await control(["--stop"]);
        // Click, rather than CheckedChanged: refreshing service state must not write it.
        automatic.Click += async (_, _) => await control(["--startup", automatic.Checked ? "auto" : "manual"]);
        layout.Controls.Add(new Label
        {
            Text = "Closing this window leaves the service running. Open BTRemote Companion again or use its tray icon to return here.",
            AutoSize = true,
            MaximumSize = new Size(460, 0),
            Margin = new Padding(0, 16, 0, 0)
        });
        Controls.Add(layout);
        reload.Click += async (_, _) => await LoadDevicesAsync();
        save.Click += async (_, _) => await SaveAsync();
        Shown += async (_, _) => await LoadDevicesAsync();
    }

    private async Task LoadDevicesAsync()
    {
        if (loading) return;
        loading = true;
        reload.Enabled = save.Enabled = false;
        try
        {
            var collection = await DeviceInformation.FindAllAsync(BluetoothLEDevice.GetDeviceSelectorFromPairingState(true),
                ["System.Devices.Aep.IsPaired"], DeviceInformationKind.AssociationEndpoint);
            if (IsDisposed) return;
            devices.Items.Clear();
            foreach (var device in collection)
                if (device.Pairing.IsPaired) devices.Items.Add(new DeviceChoice(device.Id, string.IsNullOrWhiteSpace(device.Name) ? "Unnamed BLE device" : device.Name));
            var existing = JsonFiles.Read<CompanionSettings>(Paths.Settings);
            devices.SelectedIndex = devices.Items.Cast<DeviceChoice>().ToList().FindIndex(item => item.Id == existing?.DeviceId);
            if (devices.SelectedIndex < 0 && devices.Items.Count == 1) devices.SelectedIndex = 0;
            if (devices.Items.Count == 0) detail.Text = "No paired BLE devices found. Pair the Mac in Windows Bluetooth Settings first.";
        }
        catch (Exception error) { TrayContext.ShowError(error); }
        finally { loading = false; if (!IsDisposed) { reload.Enabled = true; save.Enabled = devices.Items.Count > 0; } }
    }

    private async Task SaveAsync()
    {
        if (devices.SelectedItem is not DeviceChoice choice) return;
        save.Enabled = false;
        try
        {
            var value = new CompanionSettings(choice.Id, choice.Name);
            value.Validate();
            await ServiceCommands.ElevateAsync("--configure", ServiceCommands.EncodeSettings(value));
        }
        catch (Win32Exception error) when (error.NativeErrorCode == 1223) { }
        catch (Exception error) { TrayContext.ShowError(error); }
        finally { if (!IsDisposed) save.Enabled = true; }
    }

    public void RefreshControls(ServiceControllerStatus? serviceState, bool autoStart, bool busy)
    {
        startService.Enabled = !busy && serviceState == ServiceControllerStatus.Stopped;
        stopService.Enabled = !busy && serviceState == ServiceControllerStatus.Running;
        automatic.Enabled = !busy && serviceState is not null;
        automatic.Checked = autoStart;
    }

    public void RefreshStatus(string serviceState)
    {
        try
        {
            selected.Text = $"Selected Mac: {JsonFiles.Read<CompanionSettings>(Paths.Settings)?.DeviceName ?? "None"}";
            state.Text = $"Service: {serviceState}";
            var snapshot = JsonFiles.Read<ServiceSnapshot>(Paths.Status);
            if (serviceState != "Running" || snapshot is null) { detail.Text = "Bluetooth recovery is not running."; return; }
            if (!ServicePolicy.IsFresh(snapshot.UpdatedAt, DateTimeOffset.UtcNow)) { detail.Text = "Waiting for a fresh service status…"; return; }
            detail.Text = $"Bluetooth: {snapshot.Worker.State}\n{snapshot.Worker.Detail}";
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Text.Json.JsonException)
        { detail.Text = "Service status is temporarily unavailable."; }
    }

    private sealed record DeviceChoice(string Id, string Name)
    {
        public override string ToString() => Name;
    }
}
