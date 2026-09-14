using BTRemote.Companion.Core;
using Xunit;

namespace BTRemote.Companion.Tests;

public sealed class ClipboardPolicyTests
{
    [Fact]
    public void ImportedWritesKeepTheLocalTokenButExternalCopiesCancelIt()
    {
        var revisions = new ClipboardRevision();
        Assert.False(revisions.CanApply(0, 0));
        revisions.Capture(10);
        Assert.True(revisions.CanApply(10, 10));
        revisions.Imported(11); Assert.True(revisions.CanApply(10, 11));
        revisions.Imported(12); Assert.True(revisions.CanApply(10, 12));
        Assert.False(revisions.CanApply(10, 13));
        revisions.Capture(13);
        Assert.False(revisions.CanApply(10, 13));
        Assert.True(revisions.CanApply(13, 13));
        revisions.Reset(); Assert.False(revisions.CanApply(13, 13));
    }
    [Fact]
    public void PrivateMarkersAndOptOutFlagsAreRespected()
    {
        Assert.Contains("ExcludeClipboardContentFromMonitorProcessing", ClipboardPrivacy.ExcludedFormats);
        Assert.Contains("Clipboard Viewer Ignore", ClipboardPrivacy.ExcludedFormats);
        Assert.Contains("BTRemote.Clipboard", ClipboardPrivacy.ExcludedFormats);
        Assert.Contains("CanUploadToCloudClipboard", ClipboardPrivacy.PermissionFormats);
        Assert.True(ClipboardPrivacy.BlocksSharing(0));
        Assert.True(ClipboardPrivacy.BlocksSharing(null));
        Assert.True(ClipboardPrivacy.BlocksSharing(2));
        Assert.False(ClipboardPrivacy.BlocksSharing(1));
    }
}
