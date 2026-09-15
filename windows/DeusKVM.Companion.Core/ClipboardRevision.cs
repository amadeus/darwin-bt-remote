namespace DeusKVM.Companion.Core;

// Writes imported from the peer must not look like a new local copy. The local
// token stays valid across imports, but any external clipboard change cancels it.
public sealed class ClipboardRevision
{
    public uint? Observed { get; private set; }
    public uint Local { get; private set; }
    public void Reset() { Observed = null; Local = 0; }
    public void Capture(uint value) { Observed = value; Local = value; }
    public void Imported(uint value) => Observed = value;
    public bool CanApply(uint expectedLocal, uint current) => Local == expectedLocal && Observed == current;
}

public static class ClipboardPrivacy
{
    public static readonly string[] ExcludedFormats = [
        "ExcludeClipboardContentFromMonitorProcessing", "Clipboard Viewer Ignore",
        "com.agilebits.onepassword", "DeusKVM.Clipboard"
    ];
    public static readonly string[] PermissionFormats = ["CanIncludeInClipboardHistory", "CanUploadToCloudClipboard"];
    public static bool BlocksSharing(uint? flag) => flag != 1;
}
