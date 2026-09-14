# Embedded in the EXE and passed to Windows PowerShell in memory; never installed as a script.
$ErrorActionPreference = 'Stop'
$cleanupLock = $null
$ownsCleanupLock = $false
try {
    try { $parentProcess = [Diagnostics.Process]::GetProcessById($removingProcess) }
    catch [ArgumentException] { $parentProcess = $null }
    if ($parentProcess) {
        try { if (-not $parentProcess.WaitForExit(60000)) { throw 'The removal process did not exit.' } }
        finally { $parentProcess.Dispose() }
    }
    $cleanupLock = [Threading.Mutex]::new($false, 'Global\BTRemoteCompanionInstall')
    try { $ownsCleanupLock = $cleanupLock.WaitOne(10000) }
    catch [Threading.AbandonedMutexException] { $ownsCleanupLock = $true }
    if (-not $ownsCleanupLock) { throw 'Another installation or removal is running.' }
    $cleanupPaths = @(ConvertFrom-Json ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedPaths))))
    foreach ($cleanupPath in $cleanupPaths) {
        # Never traverse a replaced/junctioned parent into somebody else's data.
        for ($ancestor = [IO.DirectoryInfo]::new($cleanupPath); $null -ne $ancestor; $ancestor = $ancestor.Parent) {
            if ($ancestor.Exists -and ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Cannot remove through a directory link: $($ancestor.FullName)"
            }
        }
        $lastFailure = $null
        for ($attempt = 0; $attempt -lt 40; $attempt++) {
            try {
                if ([IO.Directory]::Exists($cleanupPath)) {
                    if ($cleanupPath -eq $cleanupPaths[-1]) {
                        # Preserve the retry marker until all other installation files are gone.
                        foreach ($entry in [IO.Directory]::GetFileSystemEntries($cleanupPath)) {
                            if ([IO.Path]::GetFileName($entry) -eq 'removal-pending') { continue }
                            if ([IO.Directory]::Exists($entry)) { [IO.Directory]::Delete($entry, $true) }
                            else { [IO.File]::Delete($entry) }
                        }
                        [IO.File]::Delete([IO.Path]::Combine($cleanupPath, 'removal-pending'))
                        [IO.Directory]::Delete($cleanupPath, $false)
                    } else { [IO.Directory]::Delete($cleanupPath, $true) }
                }
                if ([IO.Directory]::Exists($cleanupPath)) { throw "Directory still exists: $cleanupPath" }
                $lastFailure = $null
                break
            } catch { $lastFailure = $_; Start-Sleep -Milliseconds 250 }
        }
        if ($lastFailure) { throw $lastFailure }
    }
    if ($showResult) {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show('BTRemote was removed. You can now delete the downloaded EXE and ZIP.', 'BTRemote removed')
    }
} catch {
    if ($showResult) {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show("Removal did not finish. Reopen the downloaded EXE to retry.`n`n$($_.Exception.Message)", 'BTRemote removal incomplete')
    } else { [Console]::Error.WriteLine($_.Exception.Message) }
    exit 1
} finally {
    if ($ownsCleanupLock) { $cleanupLock.ReleaseMutex() }
    if ($cleanupLock) { $cleanupLock.Dispose() }
}
