namespace DeusKVM.Companion;

internal static class AppIcon
{
    // Shared for the UI process lifetime, like SystemIcons.Application.
    public static Icon Image { get; } = Load();

    private static Icon Load()
    {
        using var stream = typeof(AppIcon).Assembly.GetManifestResourceStream("DeusKVM.Companion.AppIcon.ico")
            ?? throw new InvalidOperationException("The application icon is missing.");
        using var icon = new Icon(stream);
        return (Icon)icon.Clone();
    }
}
