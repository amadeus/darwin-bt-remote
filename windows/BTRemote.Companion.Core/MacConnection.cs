namespace BTRemote.Companion.Core;

public enum MacTransport { LowEnergy, Classic }

public sealed record MacCandidate(string Id, string Name, string? Address, bool Paired, MacTransport Transport = MacTransport.LowEnergy)
{
    public override string ToString() => Paired ? $"{Name} (paired)" : Name;
}

public static class MacCandidates
{
    public static MacCandidate[] Visible(IEnumerable<MacCandidate> candidates) => candidates
        .Where(item => !string.IsNullOrWhiteSpace(item.Name))
        .GroupBy(item => string.IsNullOrWhiteSpace(item.Address) ? item.Id : item.Address.Replace(":", "").Replace("-", ""),
            StringComparer.OrdinalIgnoreCase)
        .Select(group => group.OrderByDescending(item => item.Paired)
            .ThenByDescending(item => item.Transport == MacTransport.Classic)
            .ThenBy(item => item.Id, StringComparer.Ordinal).First())
        .OrderByDescending(item => item.Paired).ThenBy(item => item.Name, StringComparer.OrdinalIgnoreCase).ToArray();
}

public interface IMacConnection
{
    Task<bool> Pair(); // true only when this attempt created the bond
    Task<CompanionSettings> Verify();
    Task Save(CompanionSettings settings);
    Task RollbackPairing();
}

public static class MacConnection
{
    public static async Task Connect(IMacConnection connection)
    {
        var created = await connection.Pair();
        try
        {
            var settings = await connection.Verify();
            settings.Validate();
            await connection.Save(settings);
        }
        catch (Exception primary)
        {
            if (created)
            {
                try { await connection.RollbackPairing(); }
                catch (Exception cleanup)
                {
                    throw new InvalidOperationException($"{primary.Message}\nThe new pairing could not be undone: {cleanup.Message}", primary);
                }
            }
            throw;
        }
    }
}
