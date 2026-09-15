using DeusKVM.Companion.Core;
using Microsoft.Win32;

namespace DeusKVM.Companion;

internal static class TrayStartup
{
    internal const string RunKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
    internal const string ValueName = "DeusKVMCompanion";
    private static string Preference => Path.Combine(Paths.DataDirectory, "tray-startup.json");
    private static string Command => $"\"{Paths.InstalledExe}\" --tray";
    internal static bool Enabled
    {
        get
        {
            using var root = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            using var key = root.OpenSubKey(RunKey);
            return string.Equals(key?.GetValue(ValueName) as string, Command, StringComparison.OrdinalIgnoreCase);
        }
    }
    internal static void InstallDefault()
    {
        // Enable on first installation; subsequent updates preserve the user's choice.
        if (!File.Exists(Preference)) SetEnabled(true);
    }
    internal static void SetEnabled(bool enabled)
    {
        using var root = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
        using var key = root.CreateSubKey(RunKey, true);
        var previous = key.GetValue(ValueName);
        var kind = previous is null ? RegistryValueKind.String : key.GetValueKind(ValueName);
        try
        {
            if (enabled) key.SetValue(ValueName, Command, RegistryValueKind.String);
            else key.DeleteValue(ValueName, false);
            JsonFiles.Write(Preference, new PreferenceValue(enabled));
        }
        catch
        {
            if (previous is null) key.DeleteValue(ValueName, false);
            else key.SetValue(ValueName, previous, kind);
            throw;
        }
    }
    internal static void Remove()
    {
        using var root = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
        using var key = root.OpenSubKey(RunKey, true);
        key?.DeleteValue(ValueName, false);
    }
    private sealed record PreferenceValue(bool Enabled);
}
