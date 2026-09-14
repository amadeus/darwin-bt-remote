using System.Diagnostics;
using System.Security.Principal;
using System.ServiceProcess;
using System.Text;
using System.Text.Json;
using BTRemote.Companion.Core;

namespace BTRemote.Companion;

internal static class ServiceCommands
{
    public static int Execute(string[] args)
    {
        using var identity = WindowsIdentity.GetCurrent();
        if (!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
            throw new InvalidOperationException("This service operation requires administrator permission.");
        using var service = new ServiceController(Paths.ServiceName);
        switch (args)
        {
            case ["--start"]:
                if (service.Status == ServiceControllerStatus.Stopped) service.Start();
                service.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(15));
                break;
            case ["--stop"]:
                if (service.Status != ServiceControllerStatus.Stopped)
                {
                    service.Stop();
                    service.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(15));
                }
                break;
            case ["--startup", "auto" or "manual"]:
                RunSc("config", Paths.ServiceName, "start=", args[1] == "auto" ? "auto" : "demand");
                break;
            case ["--configure", var encoded]:
                if (encoded.Length > 16384) throw new ArgumentException("Device selection is too large.");
                var settings = JsonSerializer.Deserialize<CompanionSettings>(Convert.FromBase64String(encoded))
                    ?? throw new ArgumentException("Invalid device selection.");
                settings.Validate();
                if (!Directory.Exists(Paths.DataDirectory)) throw new InvalidOperationException("Install the service first.");
                JsonFiles.Write(Paths.Settings, settings);
                break;
            default:
                throw new ArgumentException("Unknown companion command.");
        }
        return 0;
    }

    public static async Task ElevateAsync(params string[] args)
    {
        if (!File.Exists(Paths.InstalledExe)) throw new InvalidOperationException("Run Install.cmd from the companion package first.");
        var start = new ProcessStartInfo(Paths.InstalledExe) { UseShellExecute = true, Verb = "runas" };
        foreach (var argument in args) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start service operation.");
        await process.WaitForExitAsync();
        if (process.ExitCode != 0) throw new InvalidOperationException("The service operation did not complete.");
    }

    public static string EncodeSettings(CompanionSettings settings) =>
        Convert.ToBase64String(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(settings)));

    private static void RunSc(params string[] args)
    {
        var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "sc.exe"))
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        foreach (var argument in args) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not open Service Control Manager.");
        var output = process.StandardOutput.ReadToEnd();
        var errors = process.StandardError.ReadToEnd();
        process.WaitForExit();
        if (process.ExitCode != 0) throw new InvalidOperationException($"Service configuration failed: {output} {errors}");
    }
}
