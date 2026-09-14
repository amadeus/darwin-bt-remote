namespace BTRemote.Companion;

internal static class Paths
{
    public const string ServiceName = "BTRemoteCompanion";
    public static string DataDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BTRemote");
    public static string Settings => Path.Combine(DataDirectory, "settings.json");
    public static string Status => Path.Combine(DataDirectory, "status.json");
    public static string Log => Path.Combine(DataDirectory, "service.log");
    public static string InstallDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "BTRemote Companion");
    public static string InstalledExe => Path.Combine(InstallDirectory, "BTRemote.Companion.exe");
}
