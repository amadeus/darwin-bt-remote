namespace BTRemote.Companion;

internal static class Paths
{
    // These installed identities stay stable across the DeusKVM rename so
    // updates reuse the existing service, startup command and saved pairing.
    public const string ServiceName = "BTRemoteCompanion";
    public static string DataDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BTRemote");
    public static string Settings => Path.Combine(DataDirectory, "settings.json");
    public static string Status => Path.Combine(DataDirectory, "status.json");
    public static string Log => Path.Combine(DataDirectory, "service.log");
    public static string InstallDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "BTRemote Companion");
    public static string Shortcut => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms), "DeusKVM Companion.lnk");
    public static string LegacyShortcut => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms), "BTRemote Companion.lnk");
    public static string RemovalMarker => Path.Combine(InstallDirectory, "removal-pending");
    public static string InstalledExe => Path.Combine(InstallDirectory, "BTRemote.Companion.exe");
}
