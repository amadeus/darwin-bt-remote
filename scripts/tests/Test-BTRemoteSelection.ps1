# Portable regression checks for the diagnostic's PowerShell selection logic.
$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'Test-BTRemoteConnection.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref] $tokens, [ref] $parseErrors)
if ($parseErrors.Count -ne 0) { throw ($parseErrors | Out-String) }

# Load only the actual collection helper; Windows Runtime is unavailable on macOS.
$helper = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'ConvertTo-DeviceList'
}, $true)
if ($null -eq $helper) { throw 'Device-list helper not found.' }
. ([scriptblock]::Create($helper.Extent.Text))
$statusHelper = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Show-DiscoveryStatus'
}, $true)
if ($null -eq $statusHelper) { throw 'Discovery-status helper not found.' }
. ([scriptblock]::Create($statusHelper.Extent.Text))

Add-Type @'
using System.Collections;

public sealed class EnumerationOnlyDevices : IEnumerable {
    private readonly object[] items;
    public EnumerationOnlyDevices(object[] items) { this.items = items; }
    public int Count { get { return items.Length; } }
    // Reproduce PowerShell binding to a public overload instead of IEnumerable.
    public IEnumerator GetEnumerator(int unused) {
        throw new System.NotSupportedException("Use the IEnumerable interface.");
    }
    IEnumerator IEnumerable.GetEnumerator() { return items.GetEnumerator(); }
}

public sealed class UnprojectedServiceResult {
    public string Status { get { return "Success"; } }
    public object ProtocolError { get { return null; } }
    public object Services {
        get { throw new System.NotSupportedException("The service vector must not be inspected."); }
    }
}
'@

$expected = @(
    [pscustomobject] @{ Name = 'Mac Studio'; Id = 'mac' }
    [pscustomobject] @{ Name = 'ALU40'; Id = 'keyboard1' }
    [pscustomobject] @{ Name = 'ALU40'; Id = 'keyboard2' }
    [pscustomobject] @{ Name = 'Xbox Wireless Controller'; Id = 'controller' }
)
$rows = ConvertTo-DeviceList ([EnumerationOnlyDevices]::new($expected))
if ($rows -isnot [System.Collections.IList] -or $rows.Count -ne 4) { throw 'Expected four indexable rows.' }
for ($i = 0; $i -lt $expected.Count; $i++) {
    if ($rows[$i].Id -cne $expected[$i].Id -or $rows[$i].Name -cne $expected[$i].Name) {
        throw "Selection $i does not resolve to exactly one expected device."
    }
}
$matching = @($rows | Where-Object { $_.Name -eq 'Mac Studio' })
if ($matching.Count -ne 1 -or $matching[0].Id -cne 'mac') { throw 'Named selection failed.' }
$single = ConvertTo-DeviceList ([EnumerationOnlyDevices]::new(@($expected[0])))
if ($single.Count -ne 1 -or $single[0].Id -cne 'mac') { throw 'Single-device selection failed.' }
$empty = ConvertTo-DeviceList ([EnumerationOnlyDevices]::new(@()))
if ($null -eq $empty -or $empty.Count -ne 0) { throw 'Empty collection was not preserved.' }
Show-DiscoveryStatus 'Cached' ([UnprojectedServiceResult]::new()) 6>$null
Show-DiscoveryStatus 'Uncached' ([UnprojectedServiceResult]::new()) 6>$null
Write-Host 'PASS: script syntax, device selection, empty/single collections, and status reporting without accessing service vectors.'
